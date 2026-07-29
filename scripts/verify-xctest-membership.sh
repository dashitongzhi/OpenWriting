#!/bin/zsh -f

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$REPO_ROOT/Tests/OpenWritingTests"
PROJECT_FILE="$REPO_ROOT/OpenWriting.xcodeproj/project.pbxproj"
errors=()

if ! command -v rg >/dev/null 2>&1; then
    echo "error: required command 'rg' was not found" >&2
    exit 1
fi

test_sources_phase_id="$(
    awk '
        /\/\* OpenWritingTests \*\/ = \{/ { in_test_target = 1 }
        in_test_target && /\/\* Sources \*\// {
            print $1
            exit
        }
    ' "$PROJECT_FILE"
)"

if [[ -z "$test_sources_phase_id" ]]; then
    echo "error: could not identify the OpenWritingTests sources build phase" >&2
    exit 1
fi

test_sources_phase_block="$(
    awk -v phase_id="$test_sources_phase_id" '
        $1 == phase_id && /\/\* Sources \*\/ = \{/ { in_sources_phase = 1 }
        in_sources_phase { print }
        in_sources_phase && /^[[:space:]]*};[[:space:]]*$/ { exit }
    ' "$PROJECT_FILE"
)"

if [[ -z "$test_sources_phase_block" ]]; then
    echo "error: could not read the OpenWritingTests sources build phase" >&2
    exit 1
fi

while IFS= read -r test_file; do
    file_name="${test_file:t}"
    relative_path="OpenWritingTests/$file_name"
    file_reference_line="$(rg -m 1 "path = ${relative_path//./\\.};" "$PROJECT_FILE" || true)"
    if [[ -z "$file_reference_line" ]]; then
        errors+=("disk file is missing PBXFileReference: $relative_path")
        continue
    fi

    file_reference_id="$(print -r -- "$file_reference_line" | sed -E 's/^[[:space:]]*([A-Za-z0-9]+).*/\1/')"
    build_file_line="$(rg -m 1 "fileRef = $file_reference_id /\\* ${file_name//./\\.} \\*/" "$PROJECT_FILE" || true)"
    if [[ -z "$build_file_line" ]]; then
        errors+=("disk file is missing PBXBuildFile: $relative_path")
        continue
    fi

    build_file_id="$(print -r -- "$build_file_line" | sed -E 's/^[[:space:]]*([A-Za-z0-9]+).*/\1/')"
    if ! print -r -- "$test_sources_phase_block" \
        | rg -Fq "$build_file_id /* $file_name in Sources */"; then
        errors+=("disk file is missing from OpenWritingTests PBXSourcesBuildPhase: $relative_path")
    fi
done < <(find "$TEST_DIR" -maxdepth 1 -type f -name '*.swift' | sort)

while IFS= read -r relative_path; do
    if [[ ! -f "$REPO_ROOT/Tests/$relative_path" ]]; then
        errors+=("project references a missing test file: Tests/$relative_path")
    fi
done < <(rg -o 'path = OpenWritingTests/[^;]+\.swift' "$PROJECT_FILE" | sed 's/^path = //' | sort -u)

if (( ${#errors[@]} > 0 )); then
    echo "error: OpenWritingTests target membership is inconsistent:" >&2
    printf '  - %s\n' "${errors[@]}" >&2
    exit 1
fi

echo "OpenWritingTests target membership is consistent"
