#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_deps

# Ensure we're running against the user's fork, not the upstream repo
GH_USER=$(gh api user -q '.login')
UPSTREAM=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
REPO_NAME="${UPSTREAM#*/}"

if [[ "$UPSTREAM" == "${GH_USER}/"* ]]; then
  OWNER_REPO="$UPSTREAM"
else
  log "Forking ${UPSTREAM}..."
  gh repo fork --remote=false 2>/dev/null || true
  OWNER_REPO="${GH_USER}/${REPO_NAME}"
  for i in $(seq 1 30); do
    if gh api "repos/${OWNER_REPO}" &>/dev/null; then
      break
    fi
    sleep 2
  done
fi

log "Using repo: ${OWNER_REPO}"

start_runner "$OWNER_REPO"
trigger_workflow "$OWNER_REPO" "demo.yml"
stream_and_summarize
