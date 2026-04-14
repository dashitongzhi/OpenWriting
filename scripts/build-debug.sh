#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROJECT_PATH="$REPO_ROOT/OpenWriting.xcodeproj"
SCHEME="${SCHEME:-OpenWriting}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenWritingDerivedData}"

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

exec "$DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build
