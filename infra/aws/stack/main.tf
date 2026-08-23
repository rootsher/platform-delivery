# One environment in AWS: network, cluster, the IAM roles the platform
# components need, and the DNS zone. The same code builds staging and prod;
# env/<environment>.tfvars holds everything that differs, which is size.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "platform-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  external_secrets_secret_arns = "arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:${var.environment}/*"
}

# Encrypts the VPC flow logs. CloudWatch Logs needs to be allowed to use the
# key explicitly, and only for log groups of this environment.
resource "aws_kms_key" "logs" {
  description         = "${local.name}: log groups"
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
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/vpc/${local.name}/*"
          }
        }
      },
    ]
  })
}

module "network" {
  source = "../modules/network"

  name               = local.name
  cidr               = var.vpc_cidr
  azs                = var.azs
  single_nat_gateway = var.single_nat_gateway
  log_kms_key_arn    = aws_kms_key.logs.arn
}

module "cluster" {
  source = "../modules/cluster"

  name                = local.name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = module.network.private_subnet_ids
  public_access_cidrs = var.api_public_access_cidrs
  admin_role_arns     = var.admin_role_arns
  node_instance_types = var.node_instance_types
  node_count          = var.node_count
}

# external-secrets reads the secrets of this environment and nothing else.
# The prefix is what keeps staging from ever reading a prod secret.
module "external_secrets_identity" {
  source = "../modules/pod-identity"

  name            = "${local.name}-external-secrets"
  cluster_name    = module.cluster.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = local.external_secrets_secret_arns
    }]
  })
}

# Creates the network load balancer in front of Envoy. The policy is the one
# published with the controller, kept as a file so upgrades are a diff.
module "load_balancer_controller_identity" {
  source = "../modules/pod-identity"

  name            = "${local.name}-aws-load-balancer-controller"
  cluster_name    = module.cluster.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  policy_json     = file("${path.module}/../policies/aws-load-balancer-controller.json")
}

# The zone for this environment's hostnames, delegated from the parent domain
# by NS records at the registrar.
resource "aws_route53_zone" "this" {
  name = var.dns_zone
}

# Object storage for Loki and Tempo. Encrypted, private, and expired after the
# retention the charts are configured with, so the bucket never outgrows what
# anyone can query.
locals {
  telemetry_stores = {
    loki  = { service_account = "loki", retention_days = var.log_retention_days }
    tempo = { service_account = "tempo", retention_days = var.trace_retention_days }
  }
}

resource "aws_kms_key" "telemetry" {
  description         = "${local.name}: log and trace storage"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "telemetry" {
  for_each = local.telemetry_stores
  bucket   = "rootsher-${local.name}-${each.key}"
}

resource "aws_s3_bucket_public_access_block" "telemetry" {
  for_each                = aws_s3_bucket.telemetry
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "telemetry" {
  for_each = aws_s3_bucket.telemetry
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.telemetry.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "telemetry" {
  for_each = aws_s3_bucket.telemetry
  bucket   = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "telemetry" {
  for_each = aws_s3_bucket.telemetry
  bucket   = each.value.id

  rule {
    id     = "retention"
    status = "Enabled"
    filter {}

    expiration {
      days = local.telemetry_stores[each.key].retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

module "telemetry_identity" {
  source   = "../modules/pod-identity"
  for_each = local.telemetry_stores

  name            = "${local.name}-${each.key}"
  cluster_name    = module.cluster.name
  namespace       = "monitoring"
  service_account = each.value.service_account
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.telemetry[each.key].arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.telemetry[each.key].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.telemetry.arn
      },
    ]
  })
}
