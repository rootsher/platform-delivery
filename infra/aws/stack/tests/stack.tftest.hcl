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
  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
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

run "telemetry_buckets_are_private_and_encrypted" {
  command = plan

  assert {
    condition     = alltrue([for b in aws_s3_bucket_public_access_block.telemetry : b.block_public_acls && b.restrict_public_buckets])
    error_message = "Log and trace buckets must block every kind of public access."
  }

  assert {
    condition     = alltrue([for c in aws_s3_bucket_server_side_encryption_configuration.telemetry : one(c.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"])
    error_message = "Log and trace buckets must be encrypted with the KMS key."
  }
}
