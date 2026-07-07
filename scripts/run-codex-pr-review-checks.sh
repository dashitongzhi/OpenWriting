#!/bin/sh
if [ -z "${ZSH_VERSION:-}" ]; then
  exec /bin/zsh -f "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Checking Codex PR review quota signals"
node "$REPO_ROOT/scripts/validate-codex-quota-signals.mjs"
node "$REPO_ROOT/scripts/test-codex-pr-review-quota-fallback.js"

echo "Checking Codex review bundle run selection"
node "$REPO_ROOT/scripts/test-codex-review-bundle-run-selection.js"

echo "Codex PR review checks passed"
