# The two roles the infra workflow assumes through GitHub OIDC, so there are
# no AWS keys in the repository. The GitHub subject claim decides which one a
# job gets: a pull request can only plan, and only a job running in the
# GitHub environment of the same name can apply.

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
  issuer    = "token.actions.githubusercontent.com"
  policy    = "arn:${local.partition}:iam::aws:policy"

  trust = {
    plan  = "repo:${var.repository}:pull_request"
    apply = "repo:${var.repository}:environment:${var.environment}"
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "this" {
  for_each = local.trust

  name = "${var.name}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.issuer}:aud" = "sts.amazonaws.com"
          "${local.issuer}:sub" = each.value
        }
      }
    }]
  })
}

# Planning needs to read every resource the stack manages, which is close to
# ReadOnlyAccess. What that policy allows beyond it is data: objects in the
# log and trace buckets and secret values. Those are denied, except for the
# state itself.
resource "aws_iam_role_policy_attachment" "plan" {
  role       = aws_iam_role.this["plan"].name
  policy_arn = "${local.policy}/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan" {
  name = "state"
  role = aws_iam_role.this["plan"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid         = "NoDataOutsideTheState"
        Effect      = "Deny"
        Action      = ["s3:GetObject", "s3:GetObjectVersion"]
        NotResource = "arn:${local.partition}:s3:::${var.state_bucket}/*"
      },
      {
        Sid      = "NoSecretValues"
        Effect   = "Deny"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "*"
      },
      {
        Sid      = "DecryptTheState"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "arn:${local.partition}:kms:*:*:key/*"
        Condition = {
          "ForAnyValue:StringEquals" = { "kms:ResourceAliases" = var.state_key_alias }
        }
      },
    ]
  })
}

# Applying creates IAM roles, KMS keys and the cluster itself, so it needs
# administrator access. What limits it is who can assume it: the trust policy
# above and the reviewers on the GitHub environment.
resource "aws_iam_role_policy_attachment" "apply" {
  role       = aws_iam_role.this["apply"].name
  policy_arn = "${local.policy}/AdministratorAccess"
}
