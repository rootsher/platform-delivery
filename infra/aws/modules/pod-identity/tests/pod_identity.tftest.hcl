mock_provider "aws" {}

variables {
  name            = "test-external-secrets"
  cluster_name    = "test"
  namespace       = "external-secrets"
  service_account = "external-secrets"
  policy_json     = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
}

run "only_pod_identity_can_assume_the_role" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "The role must be assumable by EKS Pod Identity and nothing else."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) == 1
    error_message = "The trust policy must have exactly one statement."
  }
}

run "binds_one_service_account" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.this[0].namespace == "external-secrets" && aws_eks_pod_identity_association.this[0].service_account == "external-secrets"
    error_message = "The association must bind exactly the given namespace and service account."
  }
}

run "add_ons_bind_the_role_themselves" {
  command = plan

  variables {
    create_association = false
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.this) == 0
    error_message = "With create_association = false no association should be created."
  }
}
