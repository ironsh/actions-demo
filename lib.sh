#!/usr/bin/env bash
# Shared functions for run-demo.sh and audit.sh

log() { echo "> $*"; }

check_deps() {
  for cmd in jq gh docker; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: $cmd is required but not installed." >&2
      exit 1
    fi
  done
}

start_runner() {
  local owner_repo="$1"
  local repo_url="https://github.com/${owner_repo}"

  log "Fetching runner registration token..."
  RUNNER_TOKEN=$(gh api "repos/${owner_repo}/actions/runners/registration-token" --method POST --jq '.token')

  log "Generating CA (if needed)..."
  ./generate-ca.sh

  log "Cleaning up previous run..."
  docker compose down 2>/dev/null || true

  log "Starting containers..."
  RUNNER_TOKEN="$RUNNER_TOKEN" RUNNER_REPO="$repo_url" docker compose up --build -d

  log "Waiting for runner to start..."
  local session_warning_shown=false
  while true; do
    line=$(docker compose logs runner --tail 5 2>/dev/null)
    if echo "$line" | grep -q "Listening for Jobs"; then
      log "Runner is online."
      break
    fi
    if [[ "$session_warning_shown" == false ]] && echo "$line" | grep -q "A session for this runner already exists"; then
      log "Stale session detected — the runner is reconnecting. This can take a few minutes."
      session_warning_shown=true
    fi
    sleep 1
  done
}

trigger_workflow() {
  local owner_repo="$1"
  local workflow="$2"

  log "Triggering ${workflow}..."
  gh workflow run "$workflow" --repo "$owner_repo"
  sleep 2
  RUN_URL=$(gh run list --repo "$owner_repo" --workflow "$workflow" --limit 1 --json url -q '.[0].url')
  log "Follow this job on GitHub: ${RUN_URL}"
}

stream_and_summarize() {
  echo ""
  log "Streaming egress logs..."
  echo ""

  set -m
  (docker compose logs proxy --follow --no-log-prefix 2>&1 | \
    grep --line-buffered '^{' | \
    jq -r --unbuffered '
      select(.audit != null) |
      (.time | split(".")[0] | sub("T"; " ")) as $ts |
      ([.request_transforms[]? | select(.annotations.swapped) | .annotations.swapped[].secret] | join(",")) as $swapped |
      (if ($swapped | length) > 0 then " \u001b[35m[swap: \($swapped)]\u001b[0m" else "" end) as $swap_tag |
      .audit |
      (.method | . + (" " * (4 - length))[0:4-length]) as $method |
      (if .action == "allow" then "\u001b[32mALLOW\u001b[0m"
       elif .action == "reject" then "\u001b[31mDENY \u001b[0m"
       else "\u001b[33m\(.action | ascii_upcase)\u001b[0m" end) as $action |
      "\($ts) \(.status_code // "---") \($action) \($method)" as $prefix |
      "https://\(.host)\(.path)" as $url |
      (96 - ($prefix | length) + 9) as $max_url |
      (if ($url | length) > $max_url then
        $prefix + " " + $url[:($max_url - 3)] + "..."
      else
        $prefix + " " + $url
      end) + $swap_tag
    ') &
  LOG_PID=$!

  # Wait for the runner to finish (ephemeral — exits after one job)
  docker compose wait runner 2>/dev/null || docker wait "$(docker compose ps -q runner)" 2>/dev/null || true
  sleep 2
  kill %1 2>/dev/null || true
  wait "$LOG_PID" 2>/dev/null || true

  # Print summary
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  docker compose logs proxy --no-log-prefix 2>&1 | \
    grep '^{' | \
    jq -rs '
      [.[] | select(.audit != null)] as $all |
      [$all[] | select(.audit.action == "reject")] as $denied |
      [$all[] | select(.audit.action == "allow")] as $allowed |
      [$all[] | select(.request_transforms[]?.annotations.swapped)] as $swapped |

      "\u001b[31mDenied requests: \($denied | length)\u001b[0m",
      ($denied | map("  \(.audit.method) https://\(.audit.host)\(.audit.path)") | unique | .[]),
      "",
      "\u001b[35mSecret swaps: \($swapped | length)\u001b[0m",
      ($swapped | map(
        . as $entry |
        [.request_transforms[]? | select(.annotations.swapped) | .annotations.swapped[]] |
        map("  \(.secret) → \(.locations | join(", ")) (\($entry.audit.method) \($entry.audit.host)\($entry.audit.path))") | .[]
      ) | unique | .[]),
      "",
      "\u001b[32mAllowed requests: \($allowed | length)\u001b[0m",
      ($allowed | group_by(.audit.host) | map(
        "  \(.[0].audit.host) (\(length) requests)"
      ) | sort | .[])
    '

  echo ""
  log "Review the job output on GitHub: ${RUN_URL}"
  echo ""
  docker compose down 2>/dev/null || true
}
