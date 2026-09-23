output "role_name" {
  description = "Name of the team IAM role."
  value       = aws_iam_role.team.name
}

output "role_arn" {
  description = "ARN of the team IAM role."
  value       = aws_iam_role.team.arn
}
