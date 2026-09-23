mock_provider "aws" {}

run "enforces_naming_convention" {
  command = plan

  module {
    source = "./modules/s3"
  }

  variables {
    team_name = "payments"
    buckets = {
      data = { visibility = "private" }
    }
  }

  assert {
    condition     = length(output.bucket_names) == 1
    error_message = "Expected one bucket name."
  }

  assert {
    condition     = output.bucket_names["data"] == "sumup-payments-data"
    error_message = "Naming convention drifted."
  }
}

run "rejects_invalid_visibility" {
  command = plan

  module {
    source = "./modules/s3"
  }

  variables {
    team_name = "payments"
    buckets = {
      data = { visibility = "internal" }
    }
  }

  expect_failures = [var.buckets]
}
