#!/bin/zsh -f

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenWritingTestsDerivedData-${USER:-user}-$$}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
HOST_ARCH="$(uname -m)"
DESTINATION="platform=macOS,arch=$HOST_ARCH"
EXPECTED_MACOSX_DEPLOYMENT_TARGET="14.0"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$EXPECTED_MACOSX_DEPLOYMENT_TARGET}"

export DEVELOPER_DIR

if [[ "$MACOSX_DEPLOYMENT_TARGET" != "$EXPECTED_MACOSX_DEPLOYMENT_TARGET" ]]; then
    echo "error: MACOSX_DEPLOYMENT_TARGET must be $EXPECTED_MACOSX_DEPLOYMENT_TARGET, got $MACOSX_DEPLOYMENT_TARGET" >&2
    exit 1
fi

zsh -f "$SCRIPT_DIR/verify-xctest-membership.sh"

"$XCODEBUILD" \
    build-for-testing \
    -project "$REPO_ROOT/OpenWriting.xcodeproj" \
    -scheme OpenWriting \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    CODE_SIGNING_ALLOWED=NO

"$XCODEBUILD" \
    test-without-building \
    -project "$REPO_ROOT/OpenWriting.xcodeproj" \
    -scheme OpenWriting \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -parallel-testing-enabled NO \
    MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    CODE_SIGNING_ALLOWED=NO

echo "All OpenWriting tests passed"
