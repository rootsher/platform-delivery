output "name" {
  description = "Name of the cluster."
  value       = aws_eks_cluster.this.name
}

output "endpoint" {
  description = "API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "kms_key_arn" {
  description = "KMS key that encrypts Secrets and control plane logs."
  value       = aws_kms_key.cluster.arn
}

output "node_role_arn" {
  description = "IAM role of the default node group."
  value       = aws_iam_role.node.arn
}
