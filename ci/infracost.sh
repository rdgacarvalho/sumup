#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-breakdown}"
# Team list: TF_TEAMS wins, otherwise derive from var.teams (ci/teams.sh),
# falling back to the classic pair for local convenience.
TEAMS="${TF_TEAMS:-$(./ci/teams.sh list 2>/dev/null || true)}"
if [[ -z "$TEAMS" ]]; then
  TEAMS="payments checkout"
fi

skip_notice() {
  echo "INFRACOST_API_KEY not set; skipping infracost step (set the secret to enable cost estimates)."
}

require_key_and_bin() {
  if [[ -z "${INFRACOST_API_KEY:-}" ]]; then
    skip_notice
    exit 0
  fi
  if ! command -v infracost >/dev/null 2>&1; then
    echo "infracost binary not found; skipping cost estimate." >&2
    exit 0
  fi
}

breakdown_run() {
  require_key_and_bin

  rm -f .infracost-*.json infracost-output.json
  for team in $TEAMS; do
    plan="tfplan-$team"
    if [[ ! -f "$plan" ]]; then
      echo "plan file '$plan' missing; run ci/terraform.sh plan first." >&2
      exit 1
    fi
    echo "==> estimating costs for $team"
    infracost breakdown \
      --path "tfplan-$team.json" \
      --project-name "$team" \
      --format json \
      --out-file ".infracost-$team.json"
  done

  echo "==> combined cost estimate"
  infracost output --path ".infracost-*.json" --format table

  infracost output --path ".infracost-*.json" --format json > infracost-output.json
  echo "combined JSON written to infracost-output.json"
}

comment_run() {
  local platform="${1:-github}" repo="${2:-}" pr="${3:-}" token="${4:-}"
  if [[ -z "$repo" || -z "$pr" ]]; then
    echo "PR context missing (owner/repo or pull-request id empty); skipping cost comment."
    exit 0
  fi

  require_key_and_bin

  if [[ ! -f infracost-output.json ]]; then
    echo "infracost-output.json missing; run '${0} breakdown' first." >&2
    exit 1
  fi

  case "$platform" in
    github)
      if [[ -z "$token" ]]; then
        echo "GitHub token missing; skipping cost comment." >&2
        exit 0
      fi
      args=(comment github
        --path infracost-output.json
        --repo "$repo"
        --pull-request "$pr"
        --github-token "$token"
        --behavior update)
      if [[ -n "${INFRACOST_GITHUB_API_URL:-}" ]]; then
        args+=(--github-api-url "$INFRACOST_GITHUB_API_URL")
        echo "using GitHub-compatible API URL: $INFRACOST_GITHUB_API_URL"
      fi
      ;;
    *)
      echo "unsupported comment platform '$platform' (only github is supported; Gitea uses it with INFRACOST_GITHUB_API_URL)." >&2
      exit 2
      ;;
  esac

  infracost "${args[@]}"
  echo "infracost comment posted/updated on pull request $pr."
}

case "$ACTION" in
  breakdown) breakdown_run ;;
  comment) comment_run "$2" "$3" "$4" "$5" ;;
  *)
    echo "usage: $0 [breakdown] [comment <platform> <owner/repo> <pull-request-id> <token>]" >&2
    exit 2
    ;;
esac