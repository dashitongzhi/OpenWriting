#!/bin/sh
if [ -z "${ZSH_VERSION:-}" ]; then
  exec /bin/zsh -f "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LONGFORM="$REPO_ROOT/OpenWriting/LongformStorySystem.swift"
WRITING_DESK="$REPO_ROOT/OpenWriting/WritingDeskView.swift"
REVIEWER="$REPO_ROOT/OpenWriting/ChapterQualityReviewer.swift"
ENHANCED="$REPO_ROOT/OpenWriting/AIWritingService+Enhanced.swift"
PROMPTS="$REPO_ROOT/OpenWriting/AIWritingService+Prompts.swift"
MEMORY_BUCKETS="$REPO_ROOT/OpenWriting/WritingMemoryBuckets.swift"
SAVED_CHAPTERS_SHEET="$REPO_ROOT/OpenWriting/ProjectSavedChaptersSheet.swift"
APP_STATE="$REPO_ROOT/OpenWriting/AppState.swift"
APP_STATE_ICLOUD="$REPO_ROOT/OpenWriting/AppState+iCloudSync.swift"
PROJECT_STORE="$REPO_ROOT/OpenWriting/ProjectFileStore.swift"
ENTITLEMENTS="$REPO_ROOT/OpenWriting/OpenWriting.entitlements"
PROJECT_FILE="$REPO_ROOT/OpenWriting.xcodeproj/project.pbxproj"
RUN_ALL="$REPO_ROOT/scripts/run-all-checks.sh"
RUN_EVALS="$REPO_ROOT/scripts/run-longform-evals.sh"
EVAL_RUNNER="$REPO_ROOT/LongformEvals/run_mock_eval.py"
PIPELINE_EVAL_RUNNER="$REPO_ROOT/LongformEvals/RunLongformPipelineEval.swift"
EVAL_SEEDS="$REPO_ROOT/LongformEvals/seeds.json"
TEST_PACKAGE="$REPO_ROOT/Tests/Package.swift"
TEST_README="$REPO_ROOT/Tests/README.md"
SHARED_SCHEME="$REPO_ROOT/OpenWriting.xcodeproj/xcshareddata/xcschemes/OpenWriting.xcscheme"
APP_ENTRY="$REPO_ROOT/OpenWriting/OpenWritingApp.swift"

fail() {
    echo "error: $1" >&2
    exit 1
}

require_text() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if ! rg -q --fixed-strings -- "$pattern" "$file"; then
        fail "$message"
    fi
}

reject_text() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if rg -q --fixed-strings -- "$pattern" "$file"; then
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
require_text "$LONGFORM" "minimumAcceptedScore: minimumAcceptedScore," \
    "quality trend must carry the active minimum review score"
require_text "$LONGFORM" "qualityDebtTargets: uniqueOrderedStrings(qualityDebtTargets, limit: 6)" \
    "quality trend must convert low-score reviews into actionable quality debt targets"
require_text "$LONGFORM" "低分章节续写约束" \
    "generation prompts must expose low-score quality debt as writing constraints"
require_text "$LONGFORM" "struct LongformNextChapterBrief" \
    "longform system must expose a next-chapter brief data layer"
require_text "$LONGFORM" "buildNextChapterBrief(for project: NovelProject)" \
    "next-chapter brief must be derived from the active project"
require_text "$LONGFORM" "var longformNextChapterBrief" \
    "NovelProject must expose the next-chapter brief"
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
require_text "$REVIEWER" "validatedDimensionScores" \
    "review parser must validate all required dimension scores"
require_text "$REVIEWER" "审查结果结构不完整" \
    "review parser must turn malformed AI review JSON into a blocking result"
require_text "$REVIEWER" "reviewSchemaIssues" \
    "review parser must surface missing summary or evidence as schema issues"
require_text "$REVIEWER" "localHeuristicIssues" \
    "reviewer must merge local heuristic issues with AI review output"
require_text "$REVIEWER" "mergeLocalHeuristicIssues" \
    "reviewer must expose local heuristic merge logic"
require_text "$ENHANCED" "mergeLocalHeuristicIssues" \
    "enhanced candidate review must also merge local heuristic issues"

require_text "$MEMORY_BUCKETS" "restoringLatestActiveItems" \
    "memory rollback must restore the latest previous active memory after deleting a chapter"
require_text "$MEMORY_BUCKETS" "restoredItems[restorationIndex].status = .active" \
    "memory rollback must explicitly reactivate the restored memory item"

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
require_text "$WRITING_DESK" "保存并下一章" \
    "writing desk must expose save-and-next for longform chapter flow"
require_text "$WRITING_DESK" "advanceToNextChapter: true" \
    "save-and-next control must call the advancing save path"
require_text "$WRITING_DESK" "writingDeskStatusStrip" \
    "writing desk must expose the heavy-author status strip"
require_text "$WRITING_DESK" "nextChapterBriefPanel" \
    "writing desk must expose the next-chapter brief panel"
require_text "$WRITING_DESK" "qualityDebtPanel" \
    "writing desk must expose unresolved quality debt"
require_text "$WRITING_DESK" "storageHealthPanel" \
    "writing desk must expose storage health and recovery actions"
require_text "$WRITING_DESK" "ChapterLoadDiffSheet" \
    "writing desk chapter loads must show a diff/confirmation sheet"
require_text "$WRITING_DESK" "pendingChapterLoad" \
    "writing desk chapter navigator must track pending chapter loads"
require_text "$WRITING_DESK" "载入并覆盖当前草稿" \
    "writing desk chapter navigator must confirm destructive chapter loads"
require_text "$WRITING_DESK" "先保存当前草稿" \
    "writing desk chapter navigator must offer a save-before-load path"
require_text "$SAVED_CHAPTERS_SHEET" "pendingChapterLoad" \
    "saved chapters sheet must track pending chapter loads"
require_text "$SAVED_CHAPTERS_SHEET" "ProjectSavedChapterLoadDiffSheet" \
    "saved chapters sheet must show a diff/confirmation sheet"
require_text "$SAVED_CHAPTERS_SHEET" "载入并覆盖当前草稿" \
    "saved chapters sheet must confirm destructive chapter loads"
require_text "$SAVED_CHAPTERS_SHEET" "先保存当前草稿" \
    "saved chapters sheet must offer a save-before-load path"
require_text "$ENTITLEMENTS" "com.apple.security.files.user-selected.read-write" \
    "sandbox export entitlement must allow writing user-selected files"
require_text "$PROJECT_FILE" "ENABLE_USER_SELECTED_FILES = readwrite;" \
    "Xcode project must allow read/write access for user-selected export files"

require_text "$APP_STATE" "nextExistingChapterMetadata(after: chapterDraft, in: project)" \
    "beginNextChapter must detect existing cross-volume successor chapters"
require_text "$APP_STATE" "nextExistingChapterDraft(after: chapterDraft, in: project.chapterDrafts)" \
    "beginNextChapter must load existing successor chapter drafts before creating a new chapter"
require_text "$APP_STATE" "loadChapterDraftReport" \
    "persistence snapshots must inspect chapter load completeness"
require_text "$APP_STATE" "catalogChapterIDs.isSubset(of: hydratedChapterIDs)" \
    "persistence snapshots must not rebuild chapter catalogs from partial draft loads"
require_text "$APP_STATE" "persistRecentProjects(recentProjects, for: currentStorageScope)" \
    "chapter save must synchronously persist the local project store before reporting success"
require_text "$APP_STATE" "storageHealthReport(for projectID: NovelProject.ID)" \
    "AppState must expose project storage health"
require_text "$APP_STATE" "recoverStorageIssue" \
    "AppState must expose explicit storage recovery actions"
require_text "$PROJECT_STORE" "missingChapterIDs" \
    "sharded chapter loading must report missing or corrupt chapter files"
require_text "$PROJECT_STORE" "loadChapterDraftReport" \
    "project store must expose explicit chapter load completeness"
require_text "$PROJECT_STORE" "StorageHealthReport" \
    "project store must expose storage health reports"
require_text "$PROJECT_STORE" "ProjectStorageIssue" \
    "project store must expose storage issue records"
require_text "$PROJECT_STORE" "orphanChapterFileNames" \
    "storage health must detect orphan chapter files"
require_text "$PROJECT_STORE" "preserveMissingChapterPlaceholder" \
    "storage recovery must preserve missing chapter placeholders"
require_text "$APP_STATE_ICLOUD" "preservedCloudSelection" \
    "iCloud snapshot application must preserve valid local project selection"

require_text "$PROMPTS" "writingExecutionContractPrompt" \
    "generation prompts must include the longform execution contract"
require_text "$PROMPTS" "下一章 brief" \
    "generation prompts must inject the next-chapter brief"
require_text "$PROMPTS" "近期质量趋势" \
    "generation prompts must include recent quality trend feedback"

require_text "$RUN_ALL" "run-smoke-checks.sh" \
    "run-all checks must include smoke checks"
require_text "$RUN_ALL" "swiftc -typecheck" \
    "run-all checks must include Swift typecheck"
require_text "$RUN_ALL" "build-debug.sh" \
    "run-all checks must include Debug build"
require_text "$RUN_ALL" "test \\" \
    "run-all checks must run hosted OpenWritingTests by default"
require_text "$RUN_ALL" "TEST_CLASSES" \
    "run-all checks must target hosted OpenWritingTests classes explicitly"
require_text "$RUN_ALL" "Tests/OpenWritingTests" \
    "run-all checks must discover hosted tests from the OpenWritingTests directory"
require_text "$RUN_ALL" "XCTestCase" \
    "run-all checks must discover hosted XCTestCase classes"
require_text "$RUN_ALL" "no hosted OpenWritingTests classes discovered" \
    "run-all checks must fail loudly if hosted test discovery returns no classes"
require_text "$RUN_ALL" '"-only-testing:OpenWritingTests/$test_class"' \
    "run-all checks must run each hosted test class through xcodebuild"
require_text "$RUN_ALL" 'OpenWritingChecksDerivedData-${USER:-user}-$$' \
    "run-all checks must isolate hosted XCTest DerivedData per run"
require_text "$RUN_ALL" 'CODE_SIGN_IDENTITY="-"' \
    "run-all checks must ad-hoc sign the hosted macOS app before LaunchServices starts it"
require_text "$RUN_ALL" "-parallel-testing-enabled NO" \
    "run-all checks must run hosted macOS XCTest classes serially"
reject_text "$RUN_ALL" "RUN_HOSTED_XCTEST" \
    "run-all checks must not hide hosted tests behind RUN_HOSTED_XCTEST"
require_text "$RUN_ALL" "-scheme OpenWriting" \
    "run-all checks must run the shared OpenWriting scheme tests"
require_text "$SHARED_SCHEME" "OpenWritingTests.xctest" \
    "shared Xcode scheme must include OpenWritingTests"
require_text "$SHARED_SCHEME" "Xcode.IDEFoundation.Launcher.PosixSpawn" \
    "shared Xcode scheme must use PosixSpawn for hosted macOS XCTest launches"
reject_text "$APP_ENTRY" "NSApp.setActivationPolicy(.prohibited)" \
    "test startup must not switch the hosted app into prohibited activation policy before XCTest injects"
require_text "$TEST_PACKAGE" "XcodeOnlyPlaceholder" \
    "Tests Package.swift must not advertise a broken SwiftPM app-test target"
require_text "$TEST_README" '不要用 `swift test`' \
    "tests README must document the Xcode-only test entry"
require_text "$RUN_EVALS" "run_mock_eval.py" \
    "longform eval script must invoke the deterministic runner"
require_text "$RUN_EVALS" "RunLongformPipelineEval.swift" \
    "longform eval script must compile the real Swift pipeline runner"
require_text "$RUN_EVALS" '--mode "$mode"' \
    "longform eval script must forward the selected Swift pipeline mode"
require_text "$RUN_EVALS" 'local|real)' \
    "longform eval script must expose a network-backed real mode"
require_text "$RUN_EVALS" "ModelConnectionConfigurationStore.swift" \
    "longform eval script must compile the shared OpenWriting model configuration resolver"
require_text "$RUN_EVALS" "xcrun swiftc" \
    "longform eval script must compile the local Swift eval runner"
require_text "$PIPELINE_EVAL_RUNNER" "ModelConnectionConfigurationStore.loadConnectionConfiguration" \
    "real longform eval must reuse OpenWriting model/provider configuration"
require_text "$PIPELINE_EVAL_RUNNER" 'fputs("error:' \
    "real longform eval must fail through a guarded CLI error path"
require_text "$PIPELINE_EVAL_RUNNER" '\(timestamp)-\(options.mode)-\(options.chapters)' \
    "longform eval artifacts must be emitted beside mock/local runs with the active mode in the directory name"
require_text "$PIPELINE_EVAL_RUNNER" "failure.json" \
    "longform eval failures must leave a useful artifact in the run directory"
require_text "$EVAL_RUNNER" "average_score_at_least" \
    "longform eval runner must enforce the 90-point scorecard threshold"
require_text "$EVAL_RUNNER" "foreshadowing_miss_rate_below" \
    "longform eval runner must enforce foreshadowing miss-rate thresholds"
require_text "$PIPELINE_EVAL_RUNNER" "AIWritingService.writingPlanUserPrompt" \
    "local longform eval must exercise the real writing plan prompt"
require_text "$PIPELINE_EVAL_RUNNER" "AIWritingService.userPrompt" \
    "local longform eval must exercise the real generation prompt"
require_text "$PIPELINE_EVAL_RUNNER" "ChapterQualityReviewer.reviewUserPrompt" \
    "local longform eval must exercise the real review prompt"
require_text "$PIPELINE_EVAL_RUNNER" "ChapterQualityReviewer.parseReviewResult" \
    "local longform eval must exercise the real review parser"
require_text "$PIPELINE_EVAL_RUNNER" "ChapterQualityReviewer.mergeLocalHeuristicIssues" \
    "local longform eval must merge local review heuristics"
require_text "$PIPELINE_EVAL_RUNNER" "LongformStorySystem.buildCommit" \
    "local longform eval must exercise longform commit gating"
require_text "$PIPELINE_EVAL_RUNNER" "LongformStorySystem.apply" \
    "local longform eval must exercise longform runtime projection"
require_text "$EVAL_SEEDS" "long_foreshadowing" \
    "longform eval fixtures must include long foreshadowing seeds"

echo "Longform quality gates passed"
