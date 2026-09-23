variable "team_name" {
  description = "Team identifier used in bucket names and tags. Prefer terraform.workspace at the root."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$", var.team_name))
    error_message = "team_name must be lowercase alphanumeric with hyphens, 1-32 chars."
  }
}

variable "name_prefix" {
  description = "Org/environment prefix for globally unique bucket names."
  type        = string
  default     = "sumup"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,20}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric with hyphens."
  }
}

variable "buckets" {
  description = "Map of logical bucket name to config. visibility is required with no default."
  type = map(object({
    visibility = string
  }))

  validation {
    condition = alltrue([
      for _, cfg in var.buckets :
      contains(["public", "private"], cfg.visibility)
    ])
    error_message = "Each bucket.visibility must be exactly \"public\" or \"private\"."
  }

  validation {
    condition = alltrue([
      for name, _ in var.buckets :
      can(regex("^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$", name))
    ])
    error_message = "Bucket keys must be lowercase alphanumeric with hyphens."
  }
}

variable "tags" {
  description = "Tags merged onto every bucket for ownership and cost allocation."
  type        = map(string)
  default     = {}
}
