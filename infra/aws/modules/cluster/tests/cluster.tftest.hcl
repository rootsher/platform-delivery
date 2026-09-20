mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }
}

variables {
  name                = "test"
  kubernetes_version  = "1.37"
  subnet_ids          = ["subnet-a", "subnet-b", "subnet-c"]
  node_instance_types = ["m7i.large"]
  node_count          = { min = 2, desired = 3, max = 5 }
  admin_role_arns     = ["arn:aws:iam::111111111111:role/platform-admin"]
}

run "api_endpoint_is_private_by_default" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "Without public_access_cidrs the API must only be reachable from inside the VPC."
  }
}

run "access_is_managed_by_access_entries_only" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "The aws-auth ConfigMap must not be used."
  }

  assert {
    condition     = !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "Whoever runs terraform apply must not become a hidden cluster admin."
  }

  assert {
    condition     = length(aws_eks_access_policy_association.admin) == 1
    error_message = "Every admin role should get one cluster admin association."
  }
}

run "secrets_are_encrypted_and_control_plane_logged" {
  command = plan

  assert {
    condition     = contains(aws_eks_cluster.this.encryption_config[0].resources, "secrets")
    error_message = "Kubernetes Secrets must be envelope encrypted with KMS."
  }

  assert {
    condition     = contains(aws_eks_cluster.this.enabled_cluster_log_types, "audit")
    error_message = "The audit log must be enabled."
  }
}

run "nodes_do_not_carry_cni_permissions" {
  command = plan

  assert {
    condition     = !contains(keys(aws_iam_role_policy_attachment.node), "AmazonEKS_CNI_Policy")
    error_message = "The CNI policy belongs to the vpc-cni add-on through Pod Identity, not to the node role."
  }
}

run "rejects_an_api_open_to_the_internet" {
  command = plan

  variables {
    public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "control_plane_logs_can_use_the_key" {
  command = plan

  assert {
    condition = anytrue([
      for st in jsondecode(aws_kms_key.cluster.policy).Statement :
      try(st.Principal.Service, "") == "logs.eu-central-1.amazonaws.com"
    ])
    error_message = "CloudWatch Logs must be allowed to use the key, or the encrypted log group cannot be created."
  }
}
