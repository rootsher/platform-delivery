mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  name            = "test-terraform"
  repository      = "rootsher/platform-delivery"
  environment     = "staging"
  state_bucket    = "test-tfstate"
  state_key_alias = "alias/test-tfstate"
}

# The trust policies reference the OIDC provider ARN, which is only known
# after apply. With the mocked provider an apply creates nothing.
run "pull_requests_can_only_plan" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role.this["plan"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:rootsher/platform-delivery:pull_request"
    error_message = "The plan role must be assumable from pull requests of this repository only."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:rootsher/platform-delivery:environment:staging"
    error_message = "The apply role must be assumable from the GitHub environment of the same name only."
  }

  assert {
    condition     = alltrue([for r in aws_iam_role.this : jsondecode(r.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"])
    error_message = "Both roles must check the token audience."
  }
}

run "plans_read_no_data_but_the_state" {
  command = plan

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.plan.policy).Statement : s.NotResource if s.Sid == "NoDataOutsideTheState"]) == "arn:aws:s3:::test-tfstate/*"
    error_message = "The plan role must not read objects outside the state bucket."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.plan.policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "The plan role must stay read only."
  }
}
