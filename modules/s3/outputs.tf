output "bucket_ids" {
  description = "Logical name to bucket id (physical name)."
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "bucket_arns" {
  description = "Logical name to bucket ARN. Pass values into the IAM module."
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "bucket_names" {
  description = "Enforced physical names keyed by logical bucket name."
  value       = local.bucket_names
}
