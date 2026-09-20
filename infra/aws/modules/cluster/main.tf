# An EKS cluster with a private API endpoint, envelope encryption of Secrets,
# access managed through access entries (no aws-auth ConfigMap), and one
# managed node group on Bottlerocket in the private subnets.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  policy     = "arn:${local.partition}:iam::aws:policy"
}

# EKS uses the key through the cluster role's grants. CloudWatch Logs has no
# such grant and needs the key policy to allow it, limited to this cluster's
# log group; with the default policy creating the log group fails.
resource "aws_kms_key" "cluster" {
  description         = "${var.name}: EKS secrets and control plane logs"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "ControlPlaneLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/eks/${var.name}/cluster"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "cluster" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.cluster.key_id
}

resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy}/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "cluster" {
  # EKS writes to this exact name; creating it here sets retention and
  # encryption instead of taking the defaults.
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.cluster.arn
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = length(var.public_access_cidrs) > 0
    public_access_cidrs     = length(var.public_access_cidrs) > 0 ? var.public_access_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.cluster.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# Cluster admins are IAM roles (assumed through SSO), never users, and never
# the identity that happened to run terraform apply.
resource "aws_eks_access_entry" "admin" {
  for_each      = toset(var.admin_role_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  # The admission policies recognise cluster admins by this group.
  kubernetes_groups = ["platform:admins"]
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = toset(var.admin_role_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

resource "aws_iam_role" "node" {
  name = "${var.name}-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# The node role gets only what the kubelet needs. The CNI permissions go to
# the vpc-cni add-on through Pod Identity instead, so pods on the node cannot
# borrow them.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy}/${each.value}"
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  ami_type        = "BOTTLEROCKET_x86_64"
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"

  scaling_config {
    min_size     = var.node_count.min
    desired_size = var.node_count.desired
    max_size     = var.node_count.max
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    # Changed by hand or by an autoscaler during incidents; terraform should
    # not scale the group back on the next apply. min and max stay managed.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# Add-ons that need AWS permissions get them through Pod Identity, which needs
# its own agent running first.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
}

module "vpc_cni_identity" {
  source              = "../pod-identity"
  name                = "${var.name}-vpc-cni"
  cluster_name        = aws_eks_cluster.this.name
  namespace           = "kube-system"
  service_account     = "aws-node"
  managed_policy_arns = ["${local.policy}/AmazonEKS_CNI_Policy"]
  create_association  = false
}

module "ebs_csi_identity" {
  source              = "../pod-identity"
  name                = "${var.name}-ebs-csi"
  cluster_name        = aws_eks_cluster.this.name
  namespace           = "kube-system"
  service_account     = "ebs-csi-controller-sa"
  managed_policy_arns = ["${local.policy}/service-role/AmazonEBSCSIDriverPolicyV2"]
  create_association  = false
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  pod_identity_association {
    service_account = "aws-node"
    role_arn        = module.vpc_cni_identity.role_arn
  }

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    service_account = "ebs-csi-controller-sa"
    role_arn        = module.ebs_csi_identity.role_arn
  }

  depends_on = [aws_eks_addon.pod_identity_agent, aws_eks_node_group.default]
}

resource "aws_eks_addon" "core" {
  for_each     = toset(["coredns", "kube-proxy"])
  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.value

  depends_on = [aws_eks_node_group.default]
}
