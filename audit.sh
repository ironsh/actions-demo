#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_deps

if [[ -z "${1:-}" || -z "${2:-}" ]]; then
  echo "Usage: $0 <owner/repo> <workflow-file>" >&2
  echo "  e.g. $0 myorg/myapp ci.yml" >&2
  exit 1
fi

OWNER_REPO="$1"
WORKFLOW="$2"

echo ""
echo "Before running, make sure:"
echo ""
echo "  1. You have push access to ${OWNER_REPO}"
echo "  2. ${WORKFLOW} has 'workflow_dispatch:' as a trigger"
echo "  3. The job you want to test has 'runs-on: self-hosted'"
echo ""
read -rp "Ready? (y/n) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborting."
  exit 0
fi

echo ""
log "Using repo: ${OWNER_REPO}"
log "Using workflow: ${WORKFLOW}"

start_runner "$OWNER_REPO"
trigger_workflow "$OWNER_REPO" "$WORKFLOW"
stream_and_summarize
