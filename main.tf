locals {
  team_name = terraform.workspace
  team      = var.teams[local.team_name]

  common_tags = {
    Team       = local.team_name
    CostCenter = local.team.cost_center
  }
}

# Add workspace constraints
check "forbid_default_workspace" {
  assert {
    condition     = terraform.workspace != "default"
    error_message = "Do not apply from the default workspace. Create a workspace named after the team."
  }
}
# Add teams constraints
check "workspace_has_team_config" {
  assert {
    condition     = contains(keys(var.teams), local.team_name)
    error_message = "No team config mapped for workspace \"${local.team_name}\". Add an entry to var.teams keyed by the workspace name."
  }
}

# Dedicated reusable s3 module across orgs and teams
module "s3" {
  source = "./modules/s3"

  providers = {
    aws = aws.ministack
  }

  team_name   = local.team_name
  name_prefix = var.name_prefix
  buckets     = local.team.buckets
  tags        = local.common_tags
}

# Dedicated reusable s3 module across teams bonded to above s3 module
module "iam" {
  source = "./modules/iam"

  providers = {
    aws = aws.ministack
  }

  team_name          = local.team_name
  bucket_arns        = values(module.s3.bucket_arns)
  trusted_principals = local.team.trusted_principals
  tags               = local.common_tags
}
