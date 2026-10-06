[![.github/workflows/terraform-deploy.yml](https://github.com/rdgacarvalho/sumup-rdgacarvalho/actions/workflows/terraform-deploy.yml/badge.svg)](https://github.com/rdgacarvalho/sumup-rdgacarvalho/actions/workflows/terraform-deploy.yml)

# Platform self-service: S3 buckets and IAM roles per team

Terraform modules and a workspace-based root module for the SumUp Cloud Infrastructure take-home.

The root `main.tf` maps `terraform.workspace` to an entry in `var.teams` and passes that team's buckets and IAM trust policy into `modules/s3` and `modules/iam`. Each team uses a Terraform workspace so state is **fully** isolated from each other.

## Tech Stack

* Terraform - (https://developer.hashicorp.com/terraform)
* Docker - (https://docs.docker.com/get-started/)
* Ministack - (https://ministack.org)
* Infracost - (https://www.infracost.io)
* Github Actions - (https://docs.github.com/en/actions)
* Gitea - (open-source alternative for GHA) - (https://docs.gitea.com)
* tfenv - (https://github.com/tfutils/tfenv)
* Slack Notifications 
* Shell script

## Constraints this repo implements

- One IAM role and one or more S3 buckets per team
- Each bucket must set `visibility` to `public` or `private` (no default)
- Bucket names follow `<prefix>-<team>-<logical-key>` inside the S3 module
- The IAM role can only access that team's bucket ARNs
- Adding a team is a new key in `var.teams` — it is the single source of truth for
  seeding workspaces; the pipelines run **workspace-driven** (one job over
  `terraform workspace list`, no build-matrix cap)
- CI/CD: GitHub Actions (`.github/workflows/terraform-deploy.yml`) and Gitea Actions (`.gitea/workflows/terraform-deploy.yml`) deploy only on merge to `master`; on **pull requests** the Ministack stage always runs and **Infracost** comments the cost estimate on the PR natively. Real-AWS **applies require manual approval** (the `aws-apply` environment). Changes are first applied, verified and torn down against a **Ministack** AWS emulator before anything touches real AWS; see [docs/CI_CD.md](docs/CI_CD.md)

## Layout

```text
main.tf        Maps workspace name to team config; calls s3 and iam modules
variables.tf   teams map keyed by workspace (payments, checkout by default)
ci/teams.sh    Derives the declared team list from var.teams (list/validate)
modules/s3     Reusable S3 buckets (naming, encryption, public/private)
modules/iam    Reusable IAM role scoped to provided bucket ARNs
tests/         terraform test (plan + mock provider)
ci/            Shared CI/CD commands used by the pipelines
docs/          How to use the modules, CI/CD setup
```

## Quick start

See [docs/USING_THE_MODULES.md](docs/USING_THE_MODULES.md) for onboarding, apply, offboarding, security, and testing.
See [docs/CI_CD.md](docs/CI_CD.md) for the deployment pipelines.

> Validate locally via terraform cli

```bash
terraform init
terraform workspace new payments
terraform plan
```

Workspace `payments` uses `var.teams["payments"]`; workspace `checkout` uses `var.teams["checkout"]`. Do not apply from the `default` workspace.
