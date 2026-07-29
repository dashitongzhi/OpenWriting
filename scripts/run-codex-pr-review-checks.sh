#!/bin/zsh -f

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "error: required command 'node' was not found" >&2
    exit 1
fi

echo "Checking Codex PR review quota signals"
node "$REPO_ROOT/scripts/validate-codex-quota-signals.mjs"
node "$REPO_ROOT/scripts/test-codex-pr-review-quota-fallback.js"

echo "Checking Codex review bundle run selection"
node "$REPO_ROOT/scripts/test-codex-review-bundle-run-selection.js"

echo "Codex PR review checks passed"
