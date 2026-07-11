variable "name" {
  description = "Prefix for every resource, usually the cluster name."
  type        = string
}

variable "cidr" {
  description = "CIDR block of the VPC."
  type        = string

  validation {
    condition     = tonumber(split("/", var.cidr)[1]) <= 16
    error_message = "The VPC needs at least a /16: the VPC CNI takes one address per pod."
  }
}

variable "azs" {
  description = "Availability zones, one private and one public subnet in each."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Use two or three availability zones."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all zones instead of one per zone. Cheaper, but a zone failure cuts every zone off from the internet."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the VPC flow logs."
  type        = number
  default     = 90
}

variable "log_kms_key_arn" {
  description = "KMS key that encrypts the flow logs."
  type        = string
}
