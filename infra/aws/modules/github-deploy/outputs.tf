output "plan_role_arn" {
  description = "Role for plans on pull requests."
  value       = aws_iam_role.this["plan"].arn
}

output "apply_role_arn" {
  description = "Role for applies from the GitHub environment."
  value       = aws_iam_role.this["apply"].arn
}
