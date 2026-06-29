#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenWritingChecksDerivedData}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
HOST_ARCH="$(uname -m)"
MACOS_DESTINATION="platform=macOS,arch=$HOST_ARCH"
XCTEST_CLASS_PATTERN='^[[:space:]]*(final[[:space:]]+)?class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[^{]*XCTestCase'

discover_hosted_test_classes() {
  rg --no-filename "$XCTEST_CLASS_PATTERN" "$REPO_ROOT/Tests/OpenWritingTests" -g '*Tests.swift' \
    | sed -E 's/^[[:space:]]*(final[[:space:]]+)?class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
    | sort -u
}

TEST_CLASSES=("${(@f)$(discover_hosted_test_classes)}")

export DEVELOPER_DIR
export DERIVED_DATA_PATH

if (( ${#TEST_CLASSES[@]} == 0 )); then
  echo "error: no hosted OpenWritingTests classes discovered" >&2
  exit 1
fi

echo "Checking diff whitespace"
git -C "$REPO_ROOT" diff --check
git -C "$REPO_ROOT" diff --cached --check

echo "Running smoke checks"
zsh "$SCRIPT_DIR/run-smoke-checks.sh"

echo "Running Debug build"
zsh "$SCRIPT_DIR/build-debug.sh"

echo "Running hosted Xcode tests"
rm -rf "$DERIVED_DATA_PATH"
for test_class in "${TEST_CLASSES[@]}"; do
  echo "Running OpenWritingTests/$test_class"
  "$XCODEBUILD" \
    test \
    -project "$REPO_ROOT/OpenWriting.xcodeproj" \
    -scheme OpenWriting \
    -destination "$MACOS_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "-only-testing:OpenWritingTests/$test_class" \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_DEBUG_DYLIB=NO
done

echo "All checks passed"
