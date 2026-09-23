output "team_name" {
  description = "Active Terraform workspace, used as the team identifier."
  value       = local.team_name
}

output "bucket_names" {
  description = "Logical bucket name to enforced physical name."
  value       = module.s3.bucket_names
}

output "bucket_arns" {
  description = "Logical bucket name to ARN."
  value       = module.s3.bucket_arns
}

output "role_arn" {
  description = "IAM role ARN scoped to this team's buckets."
  value       = module.iam.role_arn
}
