#!/bin/sh
if [ -z "${ZSH_VERSION:-}" ]; then
  exec /bin/zsh -f "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -z "${DERIVED_DATA_PATH:-}" ]]; then
  DERIVED_DATA_PATH="/tmp/OpenWritingChecksDerivedData-${USER:-user}-$$"
fi

export DEVELOPER_DIR
export DERIVED_DATA_PATH

echo "Running git preflight"
bash "$SCRIPT_DIR/git-preflight.sh"
export OPENWRITING_GIT_PREFLIGHT_ALREADY_RAN=1

echo "Checking diff whitespace"
git -C "$REPO_ROOT" diff --check
git -C "$REPO_ROOT" diff --cached --check

echo "Checking architecture indexes and test target membership"
zsh -f "$SCRIPT_DIR/check-index-coverage.sh"
zsh -f "$SCRIPT_DIR/verify-xctest-membership.sh"

echo "Running Codex PR review checks"
zsh -f "$SCRIPT_DIR/run-codex-pr-review-checks.sh"

echo "Running smoke checks"
zsh -f "$SCRIPT_DIR/run-smoke-checks.sh"

echo "Running Swift typecheck"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
swift_files=(
  "$REPO_ROOT/OpenWriting/SidebarItem.swift"
  "$REPO_ROOT/OpenWriting/DomainModels.swift"
  "$REPO_ROOT/OpenWriting/LongformStorySystem.swift"
  "$REPO_ROOT/OpenWriting/KeywordMemoryExtractor.swift"
  "$REPO_ROOT/OpenWriting/ChapterCommitUseCase.swift"
  "$REPO_ROOT/OpenWriting/ChapterTreeRefresh.swift"
  "$REPO_ROOT/OpenWriting/StrandWeaveTracker.swift"
  "$REPO_ROOT/OpenWriting/WritingMemoryBuckets.swift"
  "$REPO_ROOT/OpenWriting/MemoryExtractionService.swift"
  "$REPO_ROOT/OpenWriting/NovelProject+WebnovelIntegration.swift"
  "$REPO_ROOT/OpenWriting/PrewriteValidator.swift"
  "$REPO_ROOT/OpenWriting/ContextRanker.swift"
  "$REPO_ROOT/OpenWriting/GenreTemplateData.swift"
  "$REPO_ROOT/OpenWriting/GenreTemplateEngine.swift"
  "$REPO_ROOT/OpenWriting/GenreTemplates.swift"
  "$REPO_ROOT/OpenWriting/AIWritingService.swift"
  "$REPO_ROOT/OpenWriting/AIWritingService+Enhanced.swift"
  "$REPO_ROOT/OpenWriting/AIWritingService+Prompts.swift"
  "$REPO_ROOT/OpenWriting/AIWritingServicing.swift"
  "$REPO_ROOT/OpenWriting/ChapterQualityReviewer.swift"
  "$REPO_ROOT/OpenWriting/QualityReviewService.swift"
  "$REPO_ROOT/OpenWriting/ProjectFileStore.swift"
  "$REPO_ROOT/OpenWriting/ProjectExportService.swift"
  "$REPO_ROOT/OpenWriting/TextFileDecoding.swift"
  "$REPO_ROOT/OpenWriting/DateFormatting.swift"
  "$REPO_ROOT/OpenWriting/CommerceEntitlements.swift"
  "$REPO_ROOT/OpenWriting/ModelConnectionConfigurationStore.swift"
  "$REPO_ROOT/OpenWriting/AccountSync.swift"
  "$REPO_ROOT/OpenWriting/AppLogger.swift"
  "$REPO_ROOT/OpenWriting/UserFacingError.swift"
)
xcrun swiftc -typecheck -parse-as-library -sdk "$SDK_PATH" "$swift_files[@]"

echo "Running Debug build"
zsh -f "$SCRIPT_DIR/build-debug.sh"

echo "Running hosted XCTest launch guard"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH}-hosted-xctest" \
  zsh -f "$SCRIPT_DIR/run-hosted-xctest-guard.sh"

echo "Running OpenWriting XCTest suite"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH}-tests" \
  zsh -f "$SCRIPT_DIR/run-tests.sh"

echo "All checks passed"
