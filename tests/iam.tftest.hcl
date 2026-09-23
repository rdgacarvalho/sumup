mock_provider "aws" {}

run "requires_at_least_one_bucket_arn" {
  command = plan

  module {
    source = "./modules/iam"
  }

  variables {
    team_name   = "payments"
    bucket_arns = []
    trusted_principals = {
      type        = "AWS"
      identifiers = ["arn:aws:iam::123456789012:root"]
    }
  }

  override_data {
    target = data.aws_iam_policy_document.assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.s3
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  expect_failures = [var.bucket_arns]
}

run "scopes_role_to_provided_buckets" {
  command = plan

  module {
    source = "./modules/iam"
  }

  variables {
    team_name = "payments"
    bucket_arns = [
      "arn:aws:s3:::sumup-payments-artifacts",
    ]
    trusted_principals = {
      type        = "AWS"
      identifiers = ["arn:aws:iam::123456789012:root"]
    }
  }

  override_data {
    target = data.aws_iam_policy_document.assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.s3
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  assert {
    condition     = output.role_name == "payments-s3"
    error_message = "Role name should be <team>-s3."
  }
}
