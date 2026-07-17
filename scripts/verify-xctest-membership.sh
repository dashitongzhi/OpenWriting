#!/bin/sh
if [ -z "${ZSH_VERSION:-}" ]; then
  exec /bin/zsh -f "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$REPO_ROOT/Tests/OpenWritingTests"
PROJECT_FILE="$REPO_ROOT/OpenWriting.xcodeproj/project.pbxproj"
errors=()

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
    source_membership_count="$(rg -Fc "$build_file_id /* $file_name in Sources */" "$PROJECT_FILE")"
    if (( source_membership_count < 2 )); then
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
