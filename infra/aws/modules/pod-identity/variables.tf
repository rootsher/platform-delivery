variable "name" {
  description = "Name of the IAM role."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "namespace" {
  description = "Namespace of the service account."
  type        = string
}

variable "service_account" {
  description = "Name of the service account that assumes the role."
  type        = string
}

variable "policy_json" {
  description = "Inline policy for the role."
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = "AWS managed policies to attach."
  type        = list(string)
  default     = []
}

variable "create_association" {
  description = "Create the Pod Identity association. Off for EKS add-ons, which bind the role themselves."
  type        = bool
  default     = true
}
