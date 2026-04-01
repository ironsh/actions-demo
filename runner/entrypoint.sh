#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RUNNER_TOKEN:-}" ]]; then
  echo "RUNNER_TOKEN is required" >&2
  exit 1
fi

if [[ -z "${RUNNER_REPO:-}" ]]; then
  echo "RUNNER_REPO is required (e.g. https://github.com/org/repo)" >&2
  exit 1
fi

./config.sh --unattended \
  --url "$RUNNER_REPO" \
  --token "$RUNNER_TOKEN" \
  --name "${RUNNER_NAME:-actions-demo-runner}" \
  --replace

exec ./run.sh
