variable "aws_region" {
  description = "AWS region for the team's resources."
  type        = string
  default     = "eu-central-1"
}

variable "name_prefix" {
  description = "Prefix applied by the S3 module to all bucket names."
  type        = string
  default     = "sumup"
}

variable "emulator_endpoint" {
  description = "Single endpoint URL for the emulator provider. Set to empty to use real AWS credentials from the environment."
  type        = string
  default     = "http://localhost:4566"
}

variable "teams" {
  description = "Team declarations keyed by Terraform workspace name. Select a workspace to apply that team's map entry."
  type = map(object({
    cost_center = string
    buckets = map(object({
      visibility = string
    }))
    trusted_principals = object({
      type        = string
      identifiers = list(string)
    })
  }))

  default = {
    payments = {
      cost_center = "fintech-payments"
      buckets = {
        artifacts = { visibility = "private" }
        assets    = { visibility = "public" }
      }
      trusted_principals = {
        type        = "AWS"
        identifiers = ["arn:aws:iam::123456789012:root"]
      }
    }
    checkout = {
      cost_center = "fintech-checkout"
      buckets = {
        receipts = { visibility = "private" }
      }
      trusted_principals = {
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }
    }
  }
}
