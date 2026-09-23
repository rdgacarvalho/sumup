provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "platform-self-service"
      Team       = terraform.workspace
      ManagedBy  = "terraform"
      CostCenter = try(var.teams[terraform.workspace].cost_center, "unmapped")
    }
  }
}

provider "aws" {
  alias = "ministack"

  region = "us-east-1"

  access_key                  = var.emulator_endpoint == "" ? null : "test"
  secret_key                  = var.emulator_endpoint == "" ? null : "test"
  s3_use_path_style           = var.emulator_endpoint == ""
  skip_credentials_validation = var.emulator_endpoint != ""
  skip_metadata_api_check     = var.emulator_endpoint != ""
  skip_requesting_account_id  = var.emulator_endpoint != ""

  dynamic "endpoints" {
    for_each = var.emulator_endpoint == "" ? [] : [var.emulator_endpoint]

    content {
      s3             = endpoints.value
      sqs            = endpoints.value
      sns            = endpoints.value
      lambda         = endpoints.value
      iam            = endpoints.value
      ec2            = endpoints.value
      ecs            = endpoints.value
      cloudformation = endpoints.value
      route53        = endpoints.value
      cloudwatch     = endpoints.value
      secretsmanager = endpoints.value
      ssm            = endpoints.value
      kms            = endpoints.value
      rds            = endpoints.value
      sts            = endpoints.value
    }
  }
}