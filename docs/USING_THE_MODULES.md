# Using the S3 and IAM platform modules

This repository is the platform team's self-service layer. Product teams do **not**
edit `modules/`. The root `main.tf` maps the current Terraform workspace name to a
team entry and passes those values into `modules/s3` and `modules/iam`.

Terraform **workspaces** isolate state: one workspace per team, same root module.

## How workspace mapping works

```hcl
locals {
  team_name = terraform.workspace
  team      = var.teams[local.team_name]
}

module "s3" {
  source      = "./modules/s3"
  team_name   = local.team_name
  buckets     = local.team.buckets
  # ...
}

module "iam" {
  source             = "./modules/iam"
  team_name          = local.team_name
  bucket_arns        = values(module.s3.bucket_arns)
  trusted_principals = local.team.trusted_principals
}
```

| Workspace | Mapped config |
|---|---|
| `payments` | `var.teams["payments"]` — private `artifacts`, public `assets` |
| `checkout` | `var.teams["checkout"]` — private `receipts` |
| `default` | Rejected by a `check` block |

No `-var-file` is required for the built-in teams. Selecting a workspace selects the map key.

## Prerequisites

- Terraform >= 1.11
- AWS credentials with rights to IAM and S3 (or a local emulator for experiments)
- A remote state bucket before any shared use (see `backend.tf`); locking uses the S3
  native lockfile (`use_lockfile = true`), no DynamoDB table required

## How state isolation works

| Mechanism | What it isolates | What it does not isolate |
|---|---|---|
| `terraform workspace` | State file per team | Module version, backend bucket, AWS account |
| `var.teams[<workspace>]` | Resource declaration for that team | Platform module code |

With the S3 backend enabled, state lands at:

`s3://<bucket>/env:/<workspace>/platform/team.tfstate`

and locking uses the native lockfile (`s3://<bucket>/env:/<workspace>/platform/team.tfstate.tflock`),
written via S3 conditional writes — no DynamoDB table.

Example: workspace `payments` → `.../env:/payments/platform/team.tfstate`

With the local backend (default while `backend.tf` is commented out):

`terraform.tfstate.d/<workspace>/terraform.tfstate`

The `default` workspace is forbidden (`check` block in `main.tf`).

## Daily workflow (platform engineer or future CI)

From the repository root:

```bash
terraform init

# First time for a team
terraform workspace new payments

# Every subsequent run
terraform workspace select payments
terraform plan
terraform apply
```

Convenience:

```bash
TEAM=payments
terraform workspace select "$TEAM" || terraform workspace new "$TEAM"
terraform apply
```

## Onboard a new team

1. Add a key to `var.teams` (override via a `.tfvars` file, or extend the default in `variables.tf`). The key **must** match the workspace name: lowercase, digits, hyphens only.
2. Declare **every** bucket's `visibility` as `"public"` or `"private"`. No default.
3. Set `trusted_principals` to who may assume the team role.
4. Create the workspace and apply (commands above).

Example override file `teams.tfvars`:

```hcl
teams = {
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
  newteam = {
    cost_center = "fintech-newteam"
    buckets = {
      data   = { visibility = "private" }
      public = { visibility = "public" }
    }
    trusted_principals = {
      type        = "AWS"
      identifiers = ["arn:aws:iam::<account-id>:role/newteam-runtime"]
    }
  }
}
```

If you replace the whole `teams` map, include existing teams or they disappear from configuration.

Bucket physical names are enforced as:

`<name_prefix>-<team>-<logical-key>` → `sumup-newteam-data`

## What each module does

### `modules/s3`

- Creates one bucket per map entry (`for_each`).
- Versioning and SSE-S3 on all buckets.
- ACLs disabled (`BucketOwnerEnforced`).
- **Private:** Block Public Access fully on; no public policy.
- **Public:** only `s3:GetObject` for `Principal *`. List and write remain private.
- Tags: `Team`, `Visibility`, `ManagedBy`, plus caller tags.

### `modules/iam`

- One role: `<team>-s3`.
- Inline policy limited to the ARNs returned by the S3 module (bucket and `/*`).
- No `s3:*` and no `Resource = "*"`.
- Trust policy is an input so teams can use an account, EC2, or later IRSA/OIDC.

The root module always passes `values(module.s3.bucket_arns)` into IAM so the
role cannot outlive or exceed the team's buckets.

## Offboard a team

```bash
TEAM=payments
terraform workspace select "$TEAM"
terraform destroy
terraform workspace select default
terraform workspace delete "$TEAM"
```

Then remove that key from `var.teams`. Destroy **before** deleting the workspace, or you orphan AWS resources with no state.

Public buckets may still have objects; `force_destroy` is off on purpose. Empty
the bucket (or get a platform-approved destroy exception) first.

## Security notes

- Visibility has **no default**. Invalid values fail `terraform plan`.
- Public means **read objects only**, not list, write, or delete.
- Account-level S3 Block Public Access, if enabled in the org, will block public
  buckets. That is expected; the team must request an exception or stay private.
- IAM cannot touch another team's buckets because those ARNs are not in this
  workspace's state.

## Testing modules without applying to AWS

From the repository root (`rdgacarvalho/sumup-rdgacarvalho`, GitHub):

```bash
terraform -chdir=modules/s3 init -backend=false
terraform -chdir=modules/s3 validate

terraform -chdir=modules/iam init -backend=false
terraform -chdir=modules/iam validate

terraform test
```

`terraform test` uses `command = plan` and `mock_provider` so CI does not need
credentials. Add `tflint` and `checkov` when the pipeline exists.

## CI/CD (deferred)

When a team's config changes, the pipeline should:

1. Detect a change to `var.teams` / tfvars (or a new workspace).
2. `terraform workspace select <team>` (create if new).
3. `terraform plan` (workspace already selects the map entry).
4. Apply on merge to main; the S3 backend locks state with the native lockfile
   (`use_lockfile = true`), no DynamoDB table required.

Do not run a single apply across all workspaces on every commit; that does not
scale to 300 teams and mixes blast radius.

## Why workspaces (and when you would not)

**Why:** one root module, onboarding is a map key plus workspace, state keys are
isolated, and CI maps workspace name to `var.teams[workspace]` with no extra files.

**When not:** if teams needed different backends, accounts, or module versions,
use one directory (or Terragrunt) per team instead of workspaces. That is a
stronger isolation boundary and a larger ops surface.
