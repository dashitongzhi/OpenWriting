#!/bin/sh
if [ -z "${ZSH_VERSION:-}" ]; then
  exec /bin/zsh -f "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenWritingTestsDerivedData-${USER:-user}-$$}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
HOST_ARCH="$(uname -m)"
DESTINATION="platform=macOS,arch=$HOST_ARCH"
XCTEST_CLASS_PATTERN='^[[:space:]]*(final[[:space:]]+)?class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[^{]*XCTestCase'

export DEVELOPER_DIR

zsh -f "$SCRIPT_DIR/verify-xctest-membership.sh"

test_classes=("${(@f)$(rg --no-filename "$XCTEST_CLASS_PATTERN" "$REPO_ROOT/Tests/OpenWritingTests" -g '*Tests.swift' \
    | sed -E 's/^[[:space:]]*(final[[:space:]]+)?class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
    | sort -u)}")

if (( ${#test_classes[@]} == 0 )); then
    echo "error: no OpenWriting XCTest classes discovered" >&2
    exit 1
fi

"$XCODEBUILD" \
    build-for-testing \
    -project "$REPO_ROOT/OpenWriting.xcodeproj" \
    -scheme OpenWriting \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO

for test_class in "${test_classes[@]}"; do
    echo "Running OpenWritingTests/$test_class"
    "$XCODEBUILD" \
        test-without-building \
        -project "$REPO_ROOT/OpenWriting.xcodeproj" \
        -scheme OpenWriting \
        -configuration Debug \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -parallel-testing-enabled NO \
        "-only-testing:OpenWritingTests/$test_class" \
        CODE_SIGNING_ALLOWED=NO
done

echo "All OpenWriting tests passed"
