# An IAM role that only EKS Pod Identity can assume, bound to one service
# account in one namespace. No OIDC provider, no annotations on the service
# account, no static keys.

resource "aws_iam_role" "this" {
  name = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.managed_policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count  = var.policy_json == null ? 0 : 1
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

# Add-ons take the role through their own pod_identity_association block, so
# for them the association is not created here.
resource "aws_eks_pod_identity_association" "this" {
  count           = var.create_association ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn
}
