#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
TEAM="${2:-}"
TEAMS="${TF_TEAMS:-}"
REGION="${AWS_REGION:-eu-west-1}"
STATE_KEY="platform/team.tfstate"
PARALLELISM="${CI_PARALLELISM:-10}"

ensure_team_list() {
  if [[ -n "$TEAMS" ]]; then
    return
  fi
  TEAMS="$(./ci/teams.sh list 2>/dev/null || true)"
  if [[ -z "$TEAMS" ]]; then
    TEAMS="payments checkout"
  fi
}

# Creates a temporary backend on demand for Ministack
enable_backend() {
  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    cat > backend_ci.tf <<EOF
terraform {
  backend "s3" {
    bucket       = "${TF_STATE_BUCKET}"
    key          = "${STATE_KEY}"
    region       = "${REGION}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
    init_once "$(cksum backend_ci.tf | cut -d' ' -f1)" terraform init -input=false
  else
    rm -f backend_ci.tf
    init_once "local" terraform init -input=false
  fi
}

init_once() {
  local expected="$1"
  shift
  if [[ "$(cat .terraform/.ci-init 2>/dev/null)" != "$expected" ]]; then
    "$@"
    printf '%s' "$expected" > .terraform/.ci-init
  fi
}

ensure_workspace() {
  local team="$1"
  # TF_WORKSPACE is authoritative when set (used by per-workspace workers).
  if [[ -n "${TF_WORKSPACE:-}" ]]; then
    if [[ "$TF_WORKSPACE" != "$team" ]]; then
      echo "error: TF_WORKSPACE=$TF_WORKSPACE but requested team is $team" >&2
      exit 1
    fi
    return
  fi
  if terraform workspace list | sed 's/^[* ]*//' | grep -Fxq "$team"; then
    terraform workspace select "$team" >/dev/null
  else
    terraform workspace new "$team" >/dev/null
  fi
}

# Workspaces are the source of truth at runtime: var.teams only seeds workspaces
# that do not exist yet (onboarding). Everything after that iterates the actual
# workspace list, so the pipeline scales with workspaces, not with a team list.
seed_workspaces() {
  ensure_team_list
  local team
  for team in $TEAMS; do
    ensure_workspace "$team"
  done
}

workspace_names() {
  terraform workspace list | sed 's/^[* ]*//' | grep -v '^default$' | grep -v '^[[:space:]]*$'
}

for_workspace() {
  # First arg is the per-workspace function; second seeds missing workspaces.
  local fn="$1"
  local seed="$2"
  if [[ "$seed" == "1" ]]; then
    seed_workspaces
  fi
  local ws
  local -a ws_list=()
  while read -r ws; do
    [[ -n "$ws" ]] && ws_list+=("$ws")
  done < <(workspace_names)
  if [[ ${#ws_list[@]} -eq 0 ]]; then
    echo "no workspaces to run $fn on"
    return
  fi
  # Each workspace runs in its own process with TF_WORKSPACE pinned, so a broken
  # workspace only fails its own slice and concurrency stays bounded.
  printf '%s\n' "${ws_list[@]}" | xargs -P "$PARALLELISM" -I '{}' "$0" "worker:$fn" '{}'
}

run_for() {
  # First arg is the per-team function; remaining are teams.
  local fn="$1"
  shift
  local team
  for team in "$@"; do
    ensure_workspace "$team"
    $fn "$team"
  done
}

plan_team() {
  terraform plan -input=false -out="tfplan-$1"
  terraform show -json "tfplan-$1" > "tfplan-$1.json"
}

apply_team() {
  terraform apply -input=false -auto-approve "tfplan-$1"
}

destroy_team() {
  terraform destroy -input=false -auto-approve
}

verify_team() {
  local output role
  output="$(terraform output -json bucket_names 2>/dev/null || true)"
  role="$(terraform output -raw role_arn 2>/dev/null || true)"
  if [[ -z "$output" || "$output" == "{}" ]]; then
    echo "verification failed for $1: no buckets found in state" >&2
    exit 1
  fi
  if [[ ! "$output" == *"$1"* ]]; then
    echo "verification failed for $1: ${output}" >&2
    exit 1
  fi
  if [[ -z "$role" ]]; then
    echo "verification failed for $1: no role in state" >&2
    exit 1
  fi
  echo "verified $1: ${output}"
}

case "$ACTION" in
  fmt)
    terraform fmt -check -recursive
    ;;
  validate)
    init_once "local" terraform init -input=false -backend=false
    terraform validate
    ;;
  test)
    init_once "local" terraform init -input=false -backend=false
    terraform test
    ;;
  plan)
    enable_backend
    if [[ -n "$TEAM" ]]; then run_for plan_team "$TEAM"; else for_workspace plan_team 1; fi
    ;;
  apply)
    enable_backend
    if [[ -n "$TEAM" ]]; then run_for apply_team "$TEAM"; else for_workspace apply_team 1; fi
    ;;
  verify)
    if [[ -n "$TEAM" ]]; then run_for verify_team "$TEAM"; else for_workspace verify_team 0; fi
    ;;
  destroy)
    enable_backend
    if [[ -n "$TEAM" ]]; then run_for destroy_team "$TEAM"; else for_workspace destroy_team 0; fi
    ;;
  worker:*)
    # Re-entered per workspace with TF_WORKSPACE pinned (exported so terraform
    # actually sees it); the parent already enabled the backend, so this slice
    # only runs the per-workspace function.
    export TF_WORKSPACE="$TEAM"
    "${ACTION#worker:}" "$TEAM"
    ;;
  list-teams)
    ensure_team_list
    printf '%s\n' $TEAMS
    ;;
  list-workspaces)
    workspace_names
    ;;
  *)
    echo "usage: $0 [fmt|validate|test|plan|apply|verify|destroy|list-teams|list-workspaces] [team]" >&2
    exit 2
    ;;
esac