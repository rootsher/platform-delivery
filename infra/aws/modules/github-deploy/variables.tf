variable "name" {
  description = "Prefix of the role names; the roles are <name>-plan and <name>-apply."
  type        = string
}

variable "repository" {
  description = "GitHub repository allowed to assume the roles, as owner/name."
  type        = string
}

variable "environment" {
  description = "GitHub environment whose jobs may assume the apply role."
  type        = string
}

variable "state_bucket" {
  description = "Bucket holding the Terraform state, the only one the plan role can read objects from."
  type        = string
}

variable "state_key_alias" {
  description = "Alias of the KMS key the state is encrypted with."
  type        = string
}
