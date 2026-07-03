#!/bin/sh
if [ -z "${ZSH_VERSION:-}" ]; then
    exec /bin/zsh -f "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROJECT_PATH="$REPO_ROOT/OpenWriting.xcodeproj"
SCHEME="${SCHEME:-OpenWriting}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenWritingHostedXCTestGuardDerivedData}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
HOST_ARCH="$(uname -m)"
MACOS_DESTINATION="platform=macOS,arch=$HOST_ARCH"
ONLY_TESTING="OpenWritingTests/HostedXCTestLaunchGuardTests/testOpenWritingTestsLaunchInsideAppHost"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "error: Xcode developer directory not found: $DEVELOPER_DIR" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "error: project not found: $PROJECT_PATH" >&2
    exit 1
fi

echo "Running hosted XCTest launch guard"
echo "Project: $PROJECT_PATH"
echo "Developer dir: $DEVELOPER_DIR"
echo "DerivedData: $DERIVED_DATA_PATH"
echo "Destination: $MACOS_DESTINATION"
echo "Only testing: $ONLY_TESTING"

exec "$XCODEBUILD" \
    test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$MACOS_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -parallel-testing-enabled NO \
    "-only-testing:$ONLY_TESTING" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS= \
    REGISTER_APP_GROUPS=NO \
    ENABLE_DEBUG_DYLIB=NO
