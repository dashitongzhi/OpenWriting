#!/bin/zsh -f

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INDEX_FILE="$REPO_ROOT/INDEX.md"
missing=()

if ! command -v rg >/dev/null 2>&1; then
    echo "error: required command 'rg' was not found" >&2
    exit 1
fi

while IFS= read -r source_file; do
    relative_path="${source_file#$REPO_ROOT/}"
    if ! rg -Fq "\`$relative_path\`" "$INDEX_FILE"; then
        missing+=("$relative_path")
    fi
done < <(find "$REPO_ROOT/OpenWriting" -type f -name '*.swift' | sort)

if (( ${#missing[@]} > 0 )); then
    echo "error: INDEX.md is missing Swift source entries:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
fi

echo "INDEX.md covers all OpenWriting Swift sources"
