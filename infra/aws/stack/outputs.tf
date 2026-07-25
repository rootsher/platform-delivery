output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.cluster.name
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = module.cluster.endpoint
}

output "vpc_id" {
  description = "Needed by the AWS Load Balancer Controller values."
  value       = module.network.vpc_id
}

output "dns_name_servers" {
  description = "Delegate the zone to these from the parent domain."
  value       = aws_route53_zone.this.name_servers
}
