#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LONGFORM="$REPO_ROOT/OpenWriting/LongformStorySystem.swift"
WRITING_DESK="$REPO_ROOT/OpenWriting/WritingDeskView.swift"
REVIEWER="$REPO_ROOT/OpenWriting/ChapterQualityReviewer.swift"
PROMPTS="$REPO_ROOT/OpenWriting/AIWritingService+Prompts.swift"

fail() {
    echo "error: $1" >&2
    exit 1
}

require_text() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if ! rg -q --fixed-strings "$pattern" "$file"; then
        fail "$message"
    fi
}

require_regex() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if ! rg -q --multiline "$pattern" "$file"; then
        fail "$message"
    fi
}

echo "Checking longform quality gates"

require_regex "$LONGFORM" 'case \.short:\s+return 60' \
    "short-form minimum review score must remain 60"
require_regex "$LONGFORM" 'case \.medium:\s+return 68' \
    "medium-form minimum review score must remain 68"
require_regex "$LONGFORM" 'case \.long:\s+return 75' \
    "long-form minimum review score must remain 75"

require_text "$LONGFORM" "requiresPostwriteReview: project.storyLength.supportsVolumePlanning" \
    "longform contract must require postwrite review"
require_text "$LONGFORM" 'review.map { $0.overallScore < contract.review.minimumAcceptedScore }' \
    "longform commit must reject scores below the active minimum"
require_text "$LONGFORM" "requiresReview && review == nil" \
    "longform commit must reject missing required reviews"
require_text "$LONGFORM" "buildWriteGateReport(commit: updatedCommit, contract: contract)" \
    "longform commits must refresh write-gate reports"
require_text "$LONGFORM" "let qualityTrend = buildQualityTrend(for: project)" \
    "runtime health must include quality trends"
require_text "$LONGFORM" 'recentScores.filter { $0 < minimumAcceptedScore }.count' \
    "quality trend low-score counts must use the active minimum review score"
require_text "$LONGFORM" "minimumAcceptedScore: minimumAcceptedScore(for: project.storyLength)" \
    "quality trend must carry the active minimum review score"
if rg -q --fixed-strings 'recentScores.filter { $0 < 75 }' "$LONGFORM"; then
    fail "quality trend low-score counts must not hard-code the long-form threshold"
fi
require_text "$LONGFORM" "buildRuntimeHealth(for: self)" \
    "NovelProject must expose runtime health"
require_text "$LONGFORM" "当前规模最低审查通过线" \
    "longform execution contract must expose the active minimum review score"
require_text "$LONGFORM" "let allSavedChapters = savedChapterRuntimeProbes" \
    "runtime health must inspect the full saved chapter catalog"
require_text "$LONGFORM" "let recentSavedChapters = Array(allSavedChapters.prefix(40))" \
    "runtime health must keep recent content-staleness checks bounded"
require_text "$LONGFORM" "missingSavedVolumeLabels(in: allSavedChapters)" \
    "runtime health must detect gaps in the saved volume sequence"
require_text "$LONGFORM" "分卷目录存在断卷" \
    "runtime health must block missing saved volumes"
require_text "$LONGFORM" "missingSavedChapterLabels(in: allSavedChapters)" \
    "runtime health must detect gaps in the saved chapter sequence"
require_text "$LONGFORM" "duplicateSavedChapterLabels(for: project)" \
    "runtime health must detect duplicate saved chapter positions"
require_text "$LONGFORM" "当前编辑位置落后于已保存最新章" \
    "runtime health must warn when the editor is behind the latest saved chapter"
if rg -q --fixed-strings "acceptedCommits = Array(acceptedCommits.prefix" "$LONGFORM"; then
    fail "accepted commit chain must not be truncated; full longform catalog health depends on it"
fi
require_text "$LONGFORM" "rejectedCommitHistoryLimit" \
    "rejected commit history should remain explicitly bounded"
require_regex "$LONGFORM" 'if commit\.isAccepted \{\s+acceptedCommits\.removeAll \{ \$0\.matchesPosition\(of: commit\) \}\s+rejectedCommits\.removeAll \{ \$0\.matchesPosition\(of: commit\) \}\s+acceptedCommits\.insert\(commit, at: 0\)' \
    "accepted commits must clear stale rejected commits at the same chapter position"

require_text "$REVIEWER" "let severity = issue.blocking == true" \
    "review parser must upgrade blocking issues to critical"
require_text "$REVIEWER" "return .critical" \
    "unknown or unsafe review severities must default to critical"
require_text "$REVIEWER" "ChapterReviewResult(" \
    "review parser must return unified review results"

require_text "$WRITING_DESK" "latestAISuggestionAcceptanceContext == acceptanceContext(for: project)" \
    "candidate acceptance must bind to generation context"
require_text "$WRITING_DESK" "latestChapterReviewDraftContext == chapterSaveValidationContext(for: project)" \
    "displayed draft reviews must bind to the current save context"
require_text "$WRITING_DESK" "let reviewedSaveContext = preSaveReview.map" \
    "pre-save reviews must carry a save context through async title generation"
require_text "$WRITING_DESK" "拟标题期间正文、章节位置或长篇上下文已经变化" \
    "async title generation must reject stale pre-save reviews"
require_text "$WRITING_DESK" "longformChapterSaveBlockingMessage(review: review, project: currentProject)" \
    "longform save must block failed pre-save reviews"
require_text "$WRITING_DESK" "LongformStorySystem.missingMandatoryNodes" \
    "longform save and candidate acceptance must check mandatory nodes"
require_text "$WRITING_DESK" "allowsCurrentChapterRepair: true" \
    "writing generation must allow repair candidates for the currently rejected chapter"
require_text "$WRITING_DESK" "case \"最新章节提交被拒\":" \
    "current rejected chapter must be recognized as repairable"
require_text "$WRITING_DESK" "case \"章节目录存在断章\":" \
    "missing saved chapter blockers must allow repairing the current missing chapter"
require_text "$WRITING_DESK" "textReferencesCurrentChapterPosition" \
    "current missing chapter repair must compare parsed volume and chapter positions"
require_text "$WRITING_DESK" '第\s*(\d+)\s*卷.*?第\s*(\d+)\s*章' \
    "current missing chapter repair must parse multi-volume chapter labels"
require_text "$WRITING_DESK" "case \"分卷目录存在断卷\":" \
    "missing saved volume blockers must allow repairing the current missing volume start"
require_text "$WRITING_DESK" "parsedVolumeNumber(in:" \
    "missing saved volume repair must parse volume numbers"
require_text "$WRITING_DESK" "&& max(project.currentChapterNumber, 1) == 1" \
    "missing saved volume repair must only allow the first chapter of the missing volume"

require_text "$REPO_ROOT/OpenWriting/AppState.swift" "nextExistingChapterMetadata(after: chapterDraft, in: project)" \
    "beginNextChapter must detect existing cross-volume successor chapters"
require_text "$REPO_ROOT/OpenWriting/AppState.swift" "nextExistingChapterDraft(after: chapterDraft, in: project.chapterDrafts)" \
    "beginNextChapter must load existing successor chapter drafts before creating a new chapter"

require_text "$PROMPTS" "writingExecutionContractPrompt" \
    "generation prompts must include the longform execution contract"
require_text "$PROMPTS" "近期质量趋势" \
    "generation prompts must include recent quality trend feedback"

echo "Longform quality gates passed"
