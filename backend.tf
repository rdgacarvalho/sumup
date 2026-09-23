# Remote state is isolated per Terraform workspace:
#   s3://<bucket>/env:/<workspace>/platform/team.tfstate
#
# Locking uses the S3 native lockfile (use_lockfile = true, Terraform >= 1.11);
# no DynamoDB table is required.
#
# Uncomment and replace placeholders before shared/CI use.
# Leave commented for local workspaces (state under terraform.tfstate.d/<workspace>/).

# terraform {
#   backend "s3" {
#     bucket       = "YOUR-TFSTATE-BUCKET"
#     key          = "platform/team.tfstate"
#     region       = "eu-west-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
