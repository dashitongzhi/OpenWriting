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
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenWritingDerivedData}"
HOST_ARCH="$(uname -m)"
MACOS_DESTINATION="platform=macOS,arch=$HOST_ARCH"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "error: Xcode developer directory not found: $DEVELOPER_DIR" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "error: project not found: $PROJECT_PATH" >&2
    exit 1
fi

echo "Building $SCHEME ($CONFIGURATION)"
echo "Project: $PROJECT_PATH"
echo "Developer dir: $DEVELOPER_DIR"
echo "DerivedData: $DERIVED_DATA_PATH"
echo "Destination: $MACOS_DESTINATION"

exec "$DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$MACOS_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build
