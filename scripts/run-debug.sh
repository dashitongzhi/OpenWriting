#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCHEME="${SCHEME:-OpenWriting}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenWritingDerivedData}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$SCHEME.app"

"$SCRIPT_DIR/build-debug.sh"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: built app not found: $APP_PATH" >&2
    exit 1
fi

echo "Launching $APP_PATH"
open -n "$APP_PATH"
