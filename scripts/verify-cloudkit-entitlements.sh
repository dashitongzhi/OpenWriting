#!/bin/zsh -f

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROJECT_PATH="$REPO_ROOT/OpenWriting.xcodeproj"
ENTITLEMENTS_PATH="$REPO_ROOT/OpenWriting/OpenWriting.entitlements"
SCHEME="${SCHEME:-OpenWriting}"
HOST_ARCH="$(uname -m)"

fail() {
    echo "error: $1" >&2
    exit 1
}

entitlement_template="$(
    /usr/libexec/PlistBuddy \
        -c "Print :com.apple.developer.icloud-container-environment" \
        "$ENTITLEMENTS_PATH"
)" || fail "CloudKit environment entitlement is missing"

[[ "$entitlement_template" == '$(ICLOUD_CONTAINER_ENVIRONMENT)' ]] ||
    fail "CloudKit environment entitlement must use ICLOUD_CONTAINER_ENVIRONMENT"

build_setting() {
    local configuration="$1"
    local output_file
    output_file="$(mktemp)"

    "$DEVELOPER_DIR/usr/bin/xcodebuild" \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$configuration" \
        -destination "platform=macOS,arch=$HOST_ARCH" \
        -showBuildSettings >"$output_file"

    awk -F ' = ' \
        '$1 ~ /^[[:space:]]*ICLOUD_CONTAINER_ENVIRONMENT$/ { print $2; exit }' \
        "$output_file"
    rm -f "$output_file"
}

debug_environment="$(build_setting Debug)"
release_environment="$(build_setting Release)"

[[ "$debug_environment" == "Development" ]] ||
    fail "Debug CloudKit environment must be Development (found: $debug_environment)"
[[ "$release_environment" == "Production" ]] ||
    fail "Release CloudKit environment must be Production (found: $release_environment)"

if [[ $# -gt 0 ]]; then
    signed_app="$1"
    expected_environment="${2:-Development}"
    extracted_entitlements="$(mktemp)"
    trap 'rm -f "$extracted_entitlements"' EXIT

    [[ -d "$signed_app" ]] || fail "signed app not found: $signed_app"
    codesign --verify --deep --strict "$signed_app"
    codesign -d --entitlements :- "$signed_app" >"$extracted_entitlements" 2>/dev/null
    signed_environment="$(
        /usr/libexec/PlistBuddy \
            -c "Print :com.apple.developer.icloud-container-environment" \
            "$extracted_entitlements"
    )" || fail "signed app is missing the CloudKit environment entitlement"
    [[ "$signed_environment" == "$expected_environment" ]] ||
        fail "signed app CloudKit environment must be $expected_environment (found: $signed_environment)"
fi

echo "CloudKit entitlement checks passed"
