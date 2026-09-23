# CI/CD

Deploys are triggered by a **push/merge to `master`**. On every merge the pipeline:

1. Notifies Slack that a deploy started.
2. Runs static checks (`terraform fmt`, `terraform validate`) — no credentials needed.
3. Validates `var.teams` (`ci/teams.sh validate` checks names and required
   team config in `variables.tf`).
4. Runs `terraform test` (mock provider, no credentials).
5. **Ministack stage**: plans, applies, verifies and destroys the module against a
   local Ministack emulator. This is the gate before anything touches real AWS.
6. **Plans on AWS**: `deploy-plan` runs one job across **all workspaces** —
   `ci/terraform.sh` seeds any workspace declared in `var.teams` (onboarding) and
   plans every existing workspace in one job with bounded parallelism
   (`CI_PARALLELISM=10`).
7. **Cost estimation**: Infracost reports the projected AWS cost of each plan.
8. **Approval gate**: `deploy-apply` is bound to the `aws-apply` environment and waits
   for manual approval (GitHub required reviewers / Gitea environment approvals)
   before it re-plans and applies every workspace.
9. Notifies Slack with the merge result.

On **pull requests** the same pipeline runs the static checks, the `var.teams` check and
the **Ministack stage** (plan on Ministack with dummy credentials) and, when the keys
are configured, posts the cost estimate (**Infracost**) as a comment on the PR. **Real
AWS deployment is only ever performed from `master`**: the `deploy-plan`/`deploy-apply`
jobs are scope-gated to `push` events on `master`, and apply additionally requires
approval.

- **GitHub/Gitea Actions**: PR pushes run the `ministack` job and the `infracost` job,
  which comments on the PR through the GitHub-compatible APIs. `deploy-apply` waits on
  the `aws-apply` environment and then applies **per workspace** in a single job, so
  adding a team never requires editing a workflow.

The Ministack stage aborts the pipeline if the module does not apply cleanly or the
expected resources are not created, so a broken `var.teams`/module change never reaches
the real AWS account.

## Teams, workspaces and scaling

The Terraform configuration is the **single source of truth** for teams: `variables.tf`
→ `var.teams` maps each workspace (`payments`, `checkout`, …) to that team's buckets and
IAM trust policy. Nothing else declares the team list — there is no separate registry
file to keep in sync.

At runtime, **the workspaces are the source of truth**. `var.teams` is only used to
*seed* workspaces that do not exist yet (onboarding), because `terraform workspace list`
cannot name a workspace that has never been created. After seeding, `ci/terraform.sh`
iterates the actual workspace list, so CI scales with workspaces — not with a team list
or a build matrix.

`ci/teams.sh` derives the declared list from `var.teams` with `terraform console`
(`jsonencode([for k in keys(var.teams) : k])`):
- `list` prints the declared team names (used only to seed new workspaces);
- `validate` fails when `var.teams` is empty, has an invalid team name, or a team is
  missing required config (`buckets`, `cost_center`, `trusted_principals`).

`ci/terraform.sh` in batch mode (no `<team>` argument) runs `enable_backend`, seeds
missing workspaces, then executes the action over `terraform workspace list` with
`xargs -P CI_PARALLELISM`, one process per workspace with `TF_WORKSPACE` pinned (it is
authoritative and mismatches are fatal, so a slice can never touch the wrong
workspace's state). A single `<team>` argument still runs just that workspace, and
`TF_TEAMS` overrides the derived seed list for special cases.

### Approval gate before AWS apply

`deploy-apply` is bound to `environment: aws-apply`. Until that environment is
approved, the job stays queued and **nothing touches real AWS**. Configure it once:

- **GitHub**: Settings → Environments → `aws-apply` → required reviewers (at least one
  approver). Env `secrets.AWS_*` are not passed inside `deploy-apply` unless the
  environment has access to them, so leave repo-secret access on.
- **Gitea** (>= 1.22): Settings → Environments → `aws-apply` with required approvals.

`deploy-apply` re-plans inside the job (`plan -out=tfplan-<ws>`, then applies that exact
plan) because the plan files do not survive between jobs — the **approved** plan is the
one that runs, so plan/apply drift is impossible.

### Onboarding a team (scale to hundreds)

1. Add the team key + config to `var.teams` in `variables.tf` (or a per-team tfvars file).
2. The `checks` job validates the entry; on the next master push `deploy-plan` seeds the
   new workspace automatically. No workflow or registry edits required.

Because there is **no `strategy.matrix`**, GitHub's 256-job cap does not apply: a single
deploy job plans and applies any number of workspaces. Run the fan-out elsewhere if you
ever want per-workspace job visibility. At very large scale reconsider the single S3
backend bucket's request limits and one AWS account per environment.

## Ministack stage

[Ministack](https://ministack.org) is a free, open-source, Terraform-compatible AWS
emulator (`ministackorg/ministack`, port 4566). Each pipeline runs it as an ephemeral
container, points `providers.tf` at it with dummy credentials, and executes the same
`ci/terraform.sh` sequence used for real AWS:

```text
terraform workspace select <team> || terraform workspace new <team>   # per team
terraform plan  -out=tfplan-<team>
terraform apply -auto-approve tfplan-<team>
terraform output → ci/terraform.sh verify   # fails if buckets/role missing
terraform destroy -auto-approve            # leave the emulator empty
```

Configuration that differs from the real AWS run:

| Setting | Ministack | Real AWS |
|---|---|---|
| `TF_VAR_emulator_endpoint` | `http://ministack:4566` | `""` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | `test` / `test` (dummy) | real credentials secret |
| state backend | local (ephemeral per runner) | S3 + native lockfile |
| destroy | yes, after verification | never |

It runs in the same job/runner network as the terraform steps:

- **GitHub/Gitea Actions**: a `services.ministack` service container, reached at
  `http://ministack:4566`.

## Cost estimation (Infracost)

Every pipeline estimates the monthly AWS cost of the plan and prints the breakdown in
the build log. On **pull requests** the estimate is also posted as a comment on the
GitHub PR through the GitHub API — both Actions pipelines call `ci/infracost.sh comment
github` (GitHub against `api.github.com`, Gitea via the `INFRACOST_GITHUB_API_URL`
GitHub-compatible base URL).

- The estimate is produced from the Terraform **plan JSON**
  (`ci/terraform.sh plan` runs `terraform show -json`), never from live infrastructure,
  so it works without AWS credentials and even against the Ministack plan.
- `ci/infracost.sh breakdown` runs `infracost breakdown` per team workspace, prints a
  combined table, and writes `infracost-output.json`.`ci/infracost.sh comment github
  <owner/repo> <pr-id> <token>` posts/updates the PR comment (`--behavior=update` keeps
  a single comment) and is used by every pipeline. Set `INFRACOST_GITHUB_API_URL` to a
  GitHub-compatible API base URL (Gitea, GitHub Enterprise); the default is
  `https://api.github.com`.
- **Credentials guard**: if `INFRACOST_API_KEY` is not set, `ci/infracost.sh` prints a
  notice and exits 0, and the comment step is skipped early when the repo/PR context is
  missing or the GitHub token is absent. GitHub/Gitea also skip the whole `infracost`
  job (`if: ... && secrets.INFRACOST_API_KEY != ''`). A missing key never fails a workflow.
- In GitHub/Gitea the report steps are `continue-on-error: true`, so cost reporting
  never blocks a deploy.

## Pipeline files

| File | Runtime |
|---|---|
| `.github/workflows/terraform-deploy.yml` | GitHub Actions. |
| `.gitea/workflows/terraform-deploy.yml` | Gitea Actions (GitHub-compatible). |
| `ci/teams.sh` | Derives the team list from `var.teams`: `list` / `validate`. |
| `ci/terraform.sh` | Shared commands used by every pipeline (per team or whole team list). |
| `ci/infracost.sh` | Shared Infracost cost estimation / PR-comment helper (GitHub API, GitHub-compatible for Gitea). |

This project lives at `rdgacarvalho/sumup-rdgacarvalho` (GitHub). GitHub Actions and
Gitea Actions read their workflow files from `.github/workflows/` and
`.gitea/workflows/` respectively.

## Secrets

Required secrets in the Actions repositories (names used by the pipelines):

| Secret | Purpose |
|---|---|
| `aws_access_key_id` | AWS credentials for real deploys (`TF_VAR_emulator_endpoint=""`). |
| `aws_secret_access_key` | AWS credentials for real deploys. |
| `tf_state_bucket` | S3 backend bucket for remote state (per-workspace `env:/` keys). Locking uses the S3 native lockfile (`use_lockfile`), no DynamoDB required. |
| `slack_webhook` | Slack Incoming Webhook URL. |
| `infracost_api_key` | Infracost API key (free tier). Needed for cost estimates; the pipeline skips cost reporting when it is absent. |

GitHub/Gitea Actions use the uppercase names `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `TF_STATE_BUCKET`, `SLACK_WEBHOOK` and `INFRACOST_API_KEY`,
plus the optional `INFRACOST_GITHUB_API_URL` variable for Gitea instances. They post PR
comments natively.

When `tf_state_bucket` is empty the pipeline falls back to local state and **only local
locking**; enable the S3 backend before shared use (see `backend.tf`). The S3 backend
locks state with the native lockfile (`use_lockfile = true`, Terraform >= 1.11).

## Commands

`ci/terraform.sh <action> [team]` supports `fmt`, `validate`, `test`, `plan`, `apply`,
`verify`, `destroy`, `list-teams` and `list-workspaces`. Without a team argument the
action runs in **batch/workspace mode**: it enables the backend, seeds missing
workspaces from the `var.teams`-derived list, then fans out one process per discovered
workspace bounded by `CI_PARALLELISM` (default 10). With a single `<team>` argument only
that workspace runs. It mirrors the workflow in `docs/USING_THE_MODULES.md` (workspace
per team, apply only after a merge). `init` is only rerun when the backend signature
changes (local state vs S3 backend), so the Ministack/real-AWS steps share one directory
without redundant re-initializations. `plan` also emits `tfplan-<team>.json` (via
`terraform show -json`) for Infracost. The temporary `backend_ci.tf` (written only when
`TF_STATE_BUCKET` is set) is gitignored.

`ci/teams.sh <action>` derives the declared team list from `var.teams`: `list` (team
names, used to seed new workspaces) and `validate` (fails when `var.teams` is empty, has
an invalid team name, or a team is missing required config). The `checks` job runs
`validate` on every pipeline.

`ci/infracost.sh <action>` supports `breakdown` (default; prints the table and writes
`infracost-output.json`) and `comment github <owner/repo> <pr-id> <token>` (posts the
PR comment; GitHub-compatible API base via `INFRACOST_GITHUB_API_URL`). Both are no-ops
when `INFRACOST_API_KEY` is unset.

## Deploy target

`ci/terraform.sh` runs against the repo-root workspace mapping. In batch mode the
workspaces are the source of truth: it seeds any missing from `var.teams`, then loops
over `terraform workspace list` with `xargs -P $CI_PARALLELISM` — one process per
workspace, `TF_WORKSPACE` pinned so a process can never touch another workspace's state.
This is a **single workflow job** for plan and a **single gated job** for apply, so
there is **no `strategy.matrix` and no 256-job cap**; a 300+ workspace platform plans
and applies in one run. Each workspace gets:

```text
terraform workspace new <team>   # only on first run (seeded from var.teams)
terraform plan  -out=tfplan-<workspace>
terraform apply -auto-approve tfplan-<workspace>   # deploy-apply, after approval
```

`TF_VAR_emulator_endpoint=""` makes `providers.tf` use real AWS credentials from the
environment instead of the local `localhost:1705` mock. Leave it unset (or set to the
mock URL) to deploy against the local emulator.

## Slack on PR merge

A PR merge produces a `push` event to `master`, which triggers the pipeline.
The final step posts a success/failure message to Slack.

## GitHub Actions

Create the same secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`TF_STATE_BUCKET`, `SLACK_WEBHOOK`, `INFRACOST_API_KEY`) in the repository Settings →
Secrets and variables → Actions. The workflow:

- on **push to `master`**: runs `checks` (includes the `ci/teams.sh validate` `var.teams`
  check) + `ministack` (plan/apply/verify/destroy against a `ministack` service
  container), then `deploy-plan` (plan all workspaces + Infracost cost report in a
  single workspace-driven job) and, after the **`aws-apply` environment approval**,
  `deploy-apply` (re-plan + apply per workspace) — then notifies Slack on start, success
  (merge) and failure;
- on **pull requests**: runs `checks` and the `ministack` job, then the `infracost` job
  plans on Ministack and comments the cost estimate on the PR
  (`INFRACOST_GITHUB_API_URL` is supported for GitHub Enterprise). The comment is
  skipped when the key is not configured.

## Gitea Actions

Gitea Actions uses identical workflow YAML, stored under `.gitea/workflows/`. Runner
setup:

1. In `app.ini`, the Gitea instance needs `[actions] ENABLED = true`.
2. Run the runner as a container and register it:
   `docker run -dit gitea/act_runner` (or `docker run -e GITEA_INSTANCE_URL=<url> -e GITEA_RUNNER_REGISTRATION_TOKEN=<token> gitea/act_runner`), then create a label mapping so `runs-on: ubuntu-latest` maps to a Docker image, e.g.
   `ubuntu-latest:docker://gitea/runner-images:latest`.
3. Add the same secrets in the repository Settings → Actions → Secrets, plus the
   optional `INFRACOST_GITHUB_API_URL` variable (the Gitea API base URL, e.g.
   `https://gitea.example.com/api/v1`) so the cost-estimate comment is posted to the PR.

Because Gitea emulates the GitHub `github.*` context, the workflow references
`github.ref`, `github.sha`, `github.actor`, `secrets.*`, `actions/checkout@v4` and
`hashicorp/setup-terraform@v3` work unchanged. The runner fetches those actions from
GitHub by default; point `[actions]` at a mirror if the instance has no direct access
to github.com.