#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ORIGINAL_HOME="${HOME:-$ROOT_DIR}"
ORIGINAL_XDG_CACHE_HOME="${XDG_CACHE_HOME:-}"
ORIGINAL_CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-}"
ORIGINAL_TMPDIR="${TMPDIR:-}"
ORIGINAL_DEVELOPER_DIR="${DEVELOPER_DIR:-}"
BUILD_HOME="$ROOT_DIR/.build/home"
CACHE_HOME="$BUILD_HOME/.cache"
MODULE_CACHE="$ROOT_DIR/.build/clang-module-cache"
TMP_DIR="$ROOT_DIR/.build/tmp"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
APP_STAGING_DIR="/tmp/OpenReading-preview"
APP_BUNDLE="$APP_STAGING_DIR/OpenReading.app"
EXECUTABLE="$BUILD_DIR/OpenReading"
RESOURCE_BUNDLE="$BUILD_DIR/OpenReading_OpenReading.bundle"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
LAUNCH_LOG="$ROOT_DIR/.build/openreading-launch.log"
APP_EXECUTABLE="$MACOS_DIR/OpenReading"

mkdir -p "$BUILD_HOME" "$CACHE_HOME" "$MODULE_CACHE" "$TMP_DIR"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export HOME="$BUILD_HOME"
export XDG_CACHE_HOME="$CACHE_HOME"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export TMPDIR="$TMP_DIR/"

xcrun swift build --disable-sandbox

rm -rf "$APP_STAGING_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$APP_EXECUTABLE"
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/OpenReading_OpenReading.bundle"

cat > "$INFO_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>OpenReading</string>
    <key>CFBundleIdentifier</key>
    <string>com.openreading.dev</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OpenReading</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x "$APP_EXECUTABLE"
codesign --force --deep -s - "$APP_BUNDLE"

export HOME="$ORIGINAL_HOME"

if [[ -n "$ORIGINAL_XDG_CACHE_HOME" ]]; then
    export XDG_CACHE_HOME="$ORIGINAL_XDG_CACHE_HOME"
else
    unset XDG_CACHE_HOME
fi

if [[ -n "$ORIGINAL_CLANG_MODULE_CACHE_PATH" ]]; then
    export CLANG_MODULE_CACHE_PATH="$ORIGINAL_CLANG_MODULE_CACHE_PATH"
else
    unset CLANG_MODULE_CACHE_PATH
fi

if [[ -n "$ORIGINAL_TMPDIR" ]]; then
    export TMPDIR="$ORIGINAL_TMPDIR"
else
    unset TMPDIR
fi

if [[ -n "$ORIGINAL_DEVELOPER_DIR" ]]; then
    export DEVELOPER_DIR="$ORIGINAL_DEVELOPER_DIR"
else
    unset DEVELOPER_DIR
fi

printf '%s\n' "$APP_BUNDLE"
