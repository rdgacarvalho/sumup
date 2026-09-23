#!/usr/bin/env bash
set -euo pipefail

# The Terraform configuration is the single source of truth for the team list:
# variables.tf -> var.teams (workspace -> team config). This script derives the
# list from it with `terraform console`, so adding a team is ONE edit (a new key
# in var.teams) and the pipeline never drifts from the module. TF_TEAMS overrides
# the derived list for special cases. Batch mode in ci/terraform.sh only uses the
# list to SEED new workspaces; after that it iterates the actual workspaces.
#
# Needs a successful `terraform init` in the working directory (the checks job
# runs init before calling this script).

console_value() {
  local expr="$1"
  echo "$expr" \
    | terraform console 2>/dev/null \
    | perl -CS -pe 's/\e\[[0-9;]*m//g' \
    | grep -v '^Warning' \
    | tail -n 1 \
    | tr -d '\n'
}

ensure_init() {
  [[ -d .terraform ]] && return 0
  terraform init -input=false -backend=false >/dev/null 2>&1 || true
}

teams_from_hcl() {
  local raw list
  raw="$(console_value 'jsonencode([for k in keys(var.teams) : k])')"
  [[ -z "$raw" ]] && return 1
  list="$(jq -r '. | fromjson | .[]' <<<"$raw" 2>/dev/null)"
  [[ -z "$list" ]] && return 1
  printf '%s\n' "$list"
}

resolve_teams() {
  if [[ -n "${TF_TEAMS:-}" ]]; then
    printf '%s\n' $TF_TEAMS
    return 0
  fi
  ensure_init
  teams_from_hcl || {
    echo "could not derive the team list from var.teams; run \`terraform init\` first or set TF_TEAMS" >&2
    exit 1
  }
}

list() { resolve_teams; }

bool_check() {
  local out
  out="$(console_value "$1" | grep -oE '\b(true|false)\b' | tail -n 1)"
  [[ "$out" == "true" ]]
}

validate() {
  ensure_init
  if ! bool_check 'length(keys(var.teams)) > 0'; then
    echo "variables.tf: var.teams must define at least one team" >&2
    exit 1
  fi
  if ! bool_check 'alltrue([for k in keys(var.teams) : can(regex("^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$", k))])'; then
    echo "variables.tf: every var.teams key must be a valid team name (lowercase alphanumeric with hyphens)" >&2
    exit 1
  fi
  if ! bool_check 'alltrue([for k, v in var.teams : length(v.buckets) > 0 && v.cost_center != "" && v.trusted_principals != null])'; then
    echo "variables.tf: every team in var.teams requires at least one bucket, a cost_center and trusted_principals" >&2
    exit 1
  fi
  echo "team registry validated: team list derives from var.teams in variables.tf"
}

case "${1:-}" in
  list) list ;;
  validate) validate ;;
  *)
    echo "usage: $0 [list|validate]" >&2
    exit 2
    ;;
esac