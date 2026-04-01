#!/usr/bin/env bash
set -euo pipefail

# Ensure we're running against the user's fork, not the upstream repo
GH_USER=$(gh api user -q '.login')
UPSTREAM=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
REPO_NAME="${UPSTREAM#*/}"

if [[ "$UPSTREAM" == "${GH_USER}/"* ]]; then
  OWNER_REPO="$UPSTREAM"
else
  echo "Forking ${UPSTREAM}..."
  gh repo fork --remote=false 2>/dev/null || true
  OWNER_REPO="${GH_USER}/${REPO_NAME}"
  # Wait for the fork to be ready
  for i in $(seq 1 30); do
    if gh api "repos/${OWNER_REPO}" &>/dev/null; then
      break
    fi
    sleep 2
  done
fi

REPO_URL="https://github.com/${OWNER_REPO}"
echo "Using repo: ${OWNER_REPO}"

echo "Fetching runner registration token..."
RUNNER_TOKEN=$(gh api "repos/${OWNER_REPO}/actions/runners/registration-token" --method POST --jq '.token')

echo "Generating CA (if needed)..."
./generate-ca.sh

echo "Cleaning up previous run..."
docker compose down 2>/dev/null || true

echo "Starting containers..."
RUNNER_TOKEN="$RUNNER_TOKEN" RUNNER_REPO="$REPO_URL" docker compose up --build -d

# Wait for the runner to come online
echo "Waiting for runner to start..."
SESSION_WARNING_SHOWN=false
while true; do
  line=$(docker compose logs runner --tail 5 2>/dev/null)
  if echo "$line" | grep -q "Listening for Jobs"; then
    echo "Runner is online."
    break
  fi
  if [[ "$SESSION_WARNING_SHOWN" == false ]] && echo "$line" | grep -q "A session for this runner already exists"; then
    echo "Stale session detected — the runner is reconnecting. This can take a few minutes."
    SESSION_WARNING_SHOWN=true
  fi
  sleep 1
done

# Kick off the demo workflow
echo "Triggering demo workflow..."
gh workflow run demo.yml --repo "$OWNER_REPO"
sleep 2
RUN_URL=$(gh run list --repo "$OWNER_REPO" --workflow demo.yml --limit 1 --json url -q '.[0].url')
echo "See this run on GitHub: ${RUN_URL}"

# Stream proxy egress logs, formatted as: ALLOW GET https://host/path
echo ""
echo "Streaming egress logs..."
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
      [.request_transforms[]? | select(.annotations.swapped) | .annotations.swapped[]] |
      map("  \(.secret) → \(.locations | join(", "))") | .[]
    ) | unique | .[]),
    "",
    "\u001b[32mAllowed requests: \($allowed | length)\u001b[0m",
    ($allowed | group_by(.audit.host) | map(
      "  \(.[0].audit.host) (\(length) requests)"
    ) | sort | .[])
  '

echo ""
docker compose down 2>/dev/null || true
