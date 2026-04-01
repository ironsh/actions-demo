#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <repo-url>" >&2
  echo "  e.g. $0 https://github.com/ironsh/actions-demo" >&2
  exit 1
fi

REPO_URL="$1"
OWNER_REPO="${REPO_URL#https://github.com/}"

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
while true; do
  line=$(docker compose logs runner --tail 1 2>/dev/null)
  if echo "$line" | grep -q "Listening for Jobs"; then
    echo "Runner is online."
    break
  fi
  sleep 1
done

# Stream proxy egress logs, formatted as: ALLOW GET https://host/path
echo ""
echo "Streaming egress logs..."
echo ""
docker compose logs proxy -f 2>&1 | \
  while IFS= read -r line; do
    # Strip the docker compose prefix (everything up to the JSON object)
    json="${line#*\{}"
    if [[ -n "$json" ]]; then
      json="{$json"
      echo "$json" | jq -r '
        select(.host != null) |
        "\(.action | ascii_upcase) \(.method) https://\(.host)\(.path) \(.status_code // "")"
      ' 2>/dev/null
    fi
  done
