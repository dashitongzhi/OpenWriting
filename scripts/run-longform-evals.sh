#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

chapters=30
mode="mock"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chapters)
            chapters="$2"
            shift 2
            ;;
        --mode)
            mode="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument $1" >&2
            exit 2
            ;;
    esac
done

python3 "$REPO_ROOT/LongformEvals/run_mock_eval.py" \
    --chapters "$chapters" \
    --mode "$mode" \
    --seeds "$REPO_ROOT/LongformEvals/seeds.json" \
    --output "$REPO_ROOT/LongformEvals/runs"
