variable "environment" {
  description = "staging or prod. Also the prefix of the secrets this environment may read."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "AWS region of the environment."
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC, distinct per environment so they can be peered later."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets and nodes over."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway between zones. Acceptable for staging, not for prod."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Kubernetes minor version of the cluster."
  type        = string
}

variable "api_public_access_cidrs" {
  description = "Where the API endpoint may be reached from outside the VPC, for example the office or VPN egress."
  type        = list(string)
  default     = []
}

variable "admin_role_arns" {
  description = "IAM roles that get cluster admin through access entries."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "Instance types for the default node group, more than one to survive capacity shortages."
  type        = list(string)
}

variable "node_count" {
  description = "Size of the default node group."
  type = object({
    min     = number
    desired = number
    max     = number
  })
}

variable "dns_zone" {
  description = "Hosted zone for this environment's hostnames."
  type        = string
}
