variable "name" {
  description = "Cluster name, also the prefix for its IAM roles and keys."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version of the control plane."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs and the nodes."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Empty keeps the endpoint private only."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "The API endpoint must not be open to the whole internet."
  }
}

variable "admin_role_arns" {
  description = "IAM roles that get cluster admin through access entries."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "Instance types for the default node group."
  type        = list(string)
}

variable "node_count" {
  description = "Size of the default node group."
  type = object({
    min     = number
    desired = number
    max     = number
  })

  validation {
    condition     = var.node_count.min <= var.node_count.desired && var.node_count.desired <= var.node_count.max
    error_message = "node_count must satisfy min <= desired <= max."
  }
}

variable "log_retention_days" {
  description = "Retention of the control plane logs."
  type        = number
  default     = 90
}
