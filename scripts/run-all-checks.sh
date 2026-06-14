#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"

echo "Checking diff whitespace"
git -C "$REPO_ROOT" diff --check
git -C "$REPO_ROOT" diff --cached --check

echo "Running smoke checks"
zsh "$SCRIPT_DIR/run-smoke-checks.sh"

echo "Running Swift typecheck"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
swift_files=("${(@f)$(rg --files "$REPO_ROOT/OpenWriting" -g '*.swift' | rg -v 'OpenWriting/(GenreTemplateBrowserView|QualityReviewDashboardView)\.swift$')}")
xcrun swiftc -typecheck -parse-as-library -sdk "$SDK_PATH" "$swift_files[@]"

echo "Running Debug build"
zsh "$SCRIPT_DIR/build-debug.sh"

echo "Building OpenWritingTests target"
"$XCODEBUILD" \
  -project "$REPO_ROOT/OpenWriting.xcodeproj" \
  -target OpenWritingTests \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Building OpenWritingTests for testing"
"$XCODEBUILD" \
  build-for-testing \
  -project "$REPO_ROOT/OpenWriting.xcodeproj" \
  -scheme OpenWriting \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO

if [[ "${RUN_HOSTED_XCTEST:-0}" == "1" ]]; then
  echo "Running hosted Xcode tests"
  "$XCODEBUILD" \
    test-without-building \
    -project "$REPO_ROOT/OpenWriting.xcodeproj" \
    -scheme OpenWriting \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_DEBUG_DYLIB=NO
fi

echo "All checks passed"
