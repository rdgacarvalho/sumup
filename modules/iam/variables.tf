variable "team_name" {
  description = "Team identifier used in the role name and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$", var.team_name))
    error_message = "team_name must be lowercase alphanumeric with hyphens, 1-32 chars."
  }
}

variable "bucket_arns" {
  description = "ARNs of buckets this role may access. Typically values of module.s3.bucket_arns."
  type        = list(string)

  validation {
    condition     = length(var.bucket_arns) > 0
    error_message = "At least one bucket ARN is required."
  }
}

variable "trusted_principals" {
  description = "Who may assume the role (account, role, or service)."
  type = object({
    type        = string
    identifiers = list(string)
  })
}

variable "tags" {
  description = "Tags merged onto the IAM role."
  type        = map(string)
  default     = {}
}
