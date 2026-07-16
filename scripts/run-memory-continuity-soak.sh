#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/LongformEvals/.build"
RUNNER="$BUILD_DIR/memory-continuity-soak"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

chapters=2000
characters_per_chapter=1100

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chapters)
            chapters="$2"
            shift 2
            ;;
        --characters-per-chapter)
            characters_per_chapter="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument $1" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$BUILD_DIR" "$REPO_ROOT/LongformEvals/runs"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
source_files=(
    "$REPO_ROOT/LongformEvals/RunMemoryContinuitySoak.swift"
    "$REPO_ROOT/OpenWriting/AIWritingService.swift"
    "$REPO_ROOT/OpenWriting/AIWritingService+Prompts.swift"
    "$REPO_ROOT/OpenWriting/AppLogger.swift"
    "$REPO_ROOT/OpenWriting/ChapterQualityReviewer.swift"
    "$REPO_ROOT/OpenWriting/ChapterTreeRefresh.swift"
    "$REPO_ROOT/OpenWriting/DomainModels.swift"
    "$REPO_ROOT/OpenWriting/GenreTemplateData.swift"
    "$REPO_ROOT/OpenWriting/GenreTemplateEngine.swift"
    "$REPO_ROOT/OpenWriting/GenreTemplates.swift"
    "$REPO_ROOT/OpenWriting/LongformStorySystem.swift"
    "$REPO_ROOT/OpenWriting/MemoryExtractionService.swift"
    "$REPO_ROOT/OpenWriting/ModelConnectionConfigurationStore.swift"
    "$REPO_ROOT/OpenWriting/NovelProject+WebnovelIntegration.swift"
    "$REPO_ROOT/OpenWriting/PrewriteValidator.swift"
    "$REPO_ROOT/OpenWriting/QualityReviewService.swift"
    "$REPO_ROOT/OpenWriting/SidebarItem.swift"
    "$REPO_ROOT/OpenWriting/StrandWeaveTracker.swift"
    "$REPO_ROOT/OpenWriting/WritingMemoryBuckets.swift"
)
xcrun swiftc \
    -sdk "$sdk_path" \
    -O \
    -o "$RUNNER" \
    "$source_files[@]"

"$RUNNER" \
    --chapters "$chapters" \
    --characters-per-chapter "$characters_per_chapter" \
    --output "$REPO_ROOT/LongformEvals/runs/$TIMESTAMP-memory-soak-$chapters.json"
