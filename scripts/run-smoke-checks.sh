#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Running build check"
"$SCRIPT_DIR/build-debug.sh"

echo "Checking diff whitespace"
git -C "$REPO_ROOT" diff --check
git -C "$REPO_ROOT" diff --cached --check

echo "Checking longform quality gates"
"$SCRIPT_DIR/run-longform-quality-checks.sh"

echo "Checking docs for removed polish flow"
if rg -n "润色" "$REPO_ROOT/README.md" "$REPO_ROOT/INDEX.md"; then
    echo "error: documentation still mentions the removed polish flow" >&2
    exit 1
fi

echo "Checking docs for chapter tree coverage"
if ! rg -q "章节树工作区" "$REPO_ROOT/README.md"; then
    echo "error: README is missing chapter tree workspace coverage" >&2
    exit 1
fi

echo "Smoke checks passed"
