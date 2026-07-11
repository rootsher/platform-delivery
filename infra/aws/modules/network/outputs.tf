output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnets, one per zone."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnets, one per zone."
  value       = aws_subnet.public[*].id
}
