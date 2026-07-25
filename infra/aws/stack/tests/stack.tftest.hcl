# Runs against both environments' tfvars:
#   terraform test -var-file=env/staging.tfvars
#   terraform test -var-file=env/prod.tfvars
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

run "plans_the_whole_environment" {
  command = plan

  assert {
    condition     = length(module.network.private_subnet_ids) == length(var.azs)
    error_message = "Every zone should get a private subnet."
  }
}

run "external_secrets_reads_only_its_own_environment" {
  command = plan

  assert {
    condition     = endswith(local.external_secrets_secret_arns, ":secret:${var.environment}/*")
    error_message = "external-secrets must be limited to secrets under the environment prefix."
  }
}
