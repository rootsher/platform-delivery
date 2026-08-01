terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.57"
    }
  }

  # Bucket and key come from env/<environment>.s3.tfbackend. State locking
  # uses S3 conditional writes, so there is no DynamoDB table.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      environment = var.environment
      repository  = "rootsher/platform-delivery"
      managed-by  = "terraform"
    }
  }
}
