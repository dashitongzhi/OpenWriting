#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

chapters=30
mode="mock"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chapters)
            chapters="$2"
            shift 2
            ;;
        --mode)
            mode="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument $1" >&2
            exit 2
            ;;
    esac
done

case "$mode" in
    mock)
        python3 "$REPO_ROOT/LongformEvals/run_mock_eval.py" \
            --chapters "$chapters" \
            --mode mock \
            --seeds "$REPO_ROOT/LongformEvals/seeds.json" \
            --output "$REPO_ROOT/LongformEvals/runs"
        ;;
    local)
        build_dir="$REPO_ROOT/LongformEvals/.build"
        runner="$build_dir/longform-pipeline-eval"
        mkdir -p "$build_dir"

        source_files=(
            "$REPO_ROOT/LongformEvals/RunLongformPipelineEval.swift"
            "$REPO_ROOT/OpenWriting/AIWritingService.swift"
            "$REPO_ROOT/OpenWriting/AIWritingService+Prompts.swift"
            "$REPO_ROOT/OpenWriting/ChapterQualityReviewer.swift"
            "$REPO_ROOT/OpenWriting/ChapterTreeRefresh.swift"
            "$REPO_ROOT/OpenWriting/DomainModels.swift"
            "$REPO_ROOT/OpenWriting/GenreTemplateData.swift"
            "$REPO_ROOT/OpenWriting/GenreTemplateEngine.swift"
            "$REPO_ROOT/OpenWriting/GenreTemplates.swift"
            "$REPO_ROOT/OpenWriting/LongformStorySystem.swift"
            "$REPO_ROOT/OpenWriting/MemorySystem.swift"
            "$REPO_ROOT/OpenWriting/NovelProject+WebnovelIntegration.swift"
            "$REPO_ROOT/OpenWriting/PrewriteValidator.swift"
            "$REPO_ROOT/OpenWriting/QualityReviewService.swift"
            "$REPO_ROOT/OpenWriting/StrandWeaveTracker.swift"
            "$REPO_ROOT/OpenWriting/WritingMemoryBuckets.swift"
        )

        sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
        xcrun swiftc -sdk "$sdk_path" -o "$runner" "$source_files[@]"
        "$runner" \
            --chapters "$chapters" \
            --mode local \
            --seeds "$REPO_ROOT/LongformEvals/seeds.json" \
            --output "$REPO_ROOT/LongformEvals/runs"
        ;;
    real)
        echo "error: --mode real is not wired yet. Use --mode local for the real Swift prompt/review pipeline without network calls." >&2
        exit 2
        ;;
    *)
        echo "error: --mode must be mock, local, or real" >&2
        exit 2
        ;;
esac
