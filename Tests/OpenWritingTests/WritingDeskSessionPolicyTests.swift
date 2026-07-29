import XCTest
@testable import OpenWriting

@MainActor
final class WritingDeskSessionPolicyTests: XCTestCase {
    func testPreferredLengthFallsBackToStoryLengthWithoutChapterTarget() {
        let project = NovelProject(
            title: "短篇测试",
            genre: "悬疑",
            summary: "测试章节字数策略。",
            storyLength: .short
        )

        XCTAssertEqual(ChapterWritingSessionPolicy.preferredLength(for: project), .short)
    }

    func testPreferredLengthPrioritizesChapterTargetOverWholeBookTarget() {
        var project = NovelProject(
            title: "长篇测试",
            genre: "玄幻",
            summary: "测试混合字数描述。",
            storyLength: .long
        )
        project.wordTargetText = "全书预计 30 万字，本章控制在 1800-2200 字。"

        XCTAssertEqual(ChapterWritingSessionPolicy.preferredLength(for: project), .long)
    }

    func testDraftGenerationContextChangesWhenAuthorEditsDraft() {
        var project = NovelProject(
            title: "过期结果测试",
            genre: "都市",
            summary: "确保生成期间的作者修改不会被旧结果覆盖。"
        )
        project.draftText = "第一版正文"

        let initial = ChapterWritingSessionPolicy.draftGenerationContext(
            for: project,
            rewriteDirection: .freshTake,
            rejectedSuggestion: "  上一版候选稿  "
        )

        project.draftText = "作者已经修改后的正文"
        let updated = ChapterWritingSessionPolicy.draftGenerationContext(
            for: project,
            rewriteDirection: .freshTake,
            rejectedSuggestion: "上一版候选稿"
        )

        XCTAssertNotEqual(initial, updated)
        XCTAssertEqual(initial.rejectedSuggestion, "上一版候选稿")
    }

    func testAcceptanceContextNormalizesInvalidChapterPosition() {
        var project = NovelProject(
            title: "章节位置测试",
            genre: "科幻",
            summary: "确保候选稿接受上下文使用有效章节位置。"
        )
        project.currentVolumeNumber = 0
        project.currentChapterNumber = 0

        let context = ChapterWritingSessionPolicy.acceptanceContext(for: project)

        XCTAssertEqual(context.currentVolumeNumber, 1)
        XCTAssertEqual(context.currentChapterNumber, 1)
    }

    func testRewriteInstructionCarriesDirectionAndReviewFeedback() {
        let instruction = ChapterWritingSessionPolicy.generationInstruction(
            rewriteDirection: .sharperTension,
            rejectedSuggestion: "上一版候选稿",
            reviewFeedback: "冲突升级不足，需要增加选择压力。"
        )

        XCTAssertTrue(instruction.contains(AIRewriteDirection.sharperTension.title))
        XCTAssertTrue(instruction.contains("冲突升级不足"))
        XCTAssertTrue(instruction.contains("上一版候选稿"))
    }

    func testSavedContextBecomesStaleAfterDraftChanges() {
        var project = NovelProject(
            title: "保存上下文测试",
            genre: "悬疑",
            summary: "确保异步保存不会覆盖作者的新修改。"
        )
        project.draftText = "待保存正文"

        let context = ChapterWritingSessionPolicy.chapterSaveValidationContext(for: project)
        XCTAssertTrue(ChapterWritingSessionPolicy.isCurrent(context, for: project))

        project.draftText = "作者保存期间修改后的正文"
        XCTAssertFalse(ChapterWritingSessionPolicy.isCurrent(context, for: project))
    }

    func testChapterLoadConfirmationTracksUnsavedDraftChanges() {
        var project = NovelProject(
            title: "章节载入测试",
            genre: "都市",
            summary: "确保只有未保存修改才需要覆盖确认。"
        )
        let savedDraft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "已保存正文",
            savedAt: "2026-07-17"
        )
        project.currentVolumeNumber = 1
        project.currentChapterNumber = 1
        project.chapterDrafts = [savedDraft]
        project.draftText = "已保存正文"

        XCTAssertFalse(ChapterWritingSessionPolicy.shouldConfirmChapterLoad(in: project))

        project.draftText = "尚未保存的新正文"
        XCTAssertTrue(ChapterWritingSessionPolicy.shouldConfirmChapterLoad(in: project))
    }

    func testChapterRepairEligibilityAllowsOnlyCurrentSingleChapterGap() {
        var project = repairProject(
            savedPositions: [(1, 1), (1, 3)],
            currentPosition: (1, 2)
        )
        let issue = repairIssue(kind: .missingChapterSequence)

        XCTAssertTrue(
            ChapterRepairEligibility.canRepair(
                issue,
                in: project,
                allowsCurrentChapterRepair: true
            )
        )

        project.currentChapterNumber = 1
        XCTAssertFalse(
            ChapterRepairEligibility.canRepair(
                issue,
                in: project,
                allowsCurrentChapterRepair: true
            )
        )
    }

    func testFullHealthAllowsRepairingOnlyCurrentSingleChapterGap() {
        let project = repairProject(
            savedPositions: [(1, 1), (1, 3)],
            currentPosition: (1, 2)
        )
        let blockers = project.longformRuntimeHealth.blockingIssues
            .filter { $0.kind != .prewriteGate }

        XCTAssertEqual(Set(blockers.map(\.kind)), [.missingChapterSequence])
        XCTAssertTrue(
            blockers.allSatisfy {
                ChapterRepairEligibility.canRepair(
                    $0,
                    in: project,
                    allowsCurrentChapterRepair: true
                )
            }
        )
    }

    func testChapterRepairEligibilityRejectsWhenMultipleChapterGapsRemain() {
        let project = repairProject(
            savedPositions: [(1, 1), (1, 3), (1, 5)],
            currentPosition: (1, 2)
        )

        XCTAssertFalse(
            ChapterRepairEligibility.canRepair(
                repairIssue(kind: .missingChapterSequence),
                in: project,
                allowsCurrentChapterRepair: true
            )
        )
    }

    func testChapterRepairEligibilityAllowsOnlyCurrentSingleVolumeGapStart() {
        let project = repairProject(
            savedPositions: [(1, 1), (3, 1)],
            currentPosition: (2, 1)
        )

        XCTAssertTrue(
            ChapterRepairEligibility.canRepair(
                repairIssue(kind: .missingVolumeSequence),
                in: project,
                allowsCurrentChapterRepair: true
            )
        )
    }

    func testFullHealthAllowsRepairingOnlyCurrentSingleVolumeGapStart() {
        let project = repairProject(
            savedPositions: [(1, 1), (3, 1)],
            currentPosition: (2, 1)
        )
        let blockers = project.longformRuntimeHealth.blockingIssues
            .filter { $0.kind != .prewriteGate }

        XCTAssertEqual(Set(blockers.map(\.kind)), [.missingVolumeSequence])
        XCTAssertTrue(
            blockers.allSatisfy {
                ChapterRepairEligibility.canRepair(
                    $0,
                    in: project,
                    allowsCurrentChapterRepair: true
                )
            }
        )
    }

    func testChapterRepairEligibilityRejectsMultipleVolumeGaps() {
        let project = repairProject(
            savedPositions: [(1, 1), (3, 1), (5, 1)],
            currentPosition: (2, 1)
        )

        XCTAssertFalse(
            ChapterRepairEligibility.canRepair(
                repairIssue(kind: .missingVolumeSequence),
                in: project,
                allowsCurrentChapterRepair: true
            )
        )
    }

    private func repairProject(
        savedPositions: [(volume: Int, chapter: Int)],
        currentPosition: (volume: Int, chapter: Int)
    ) -> NovelProject {
        var project = NovelProject(
            title: "卷章修复测试",
            genre: "玄幻",
            summary: "验证修复资格只依据结构化目录状态。",
            storyLength: .long
        )
        project.currentVolumeNumber = currentPosition.volume
        project.currentChapterNumber = currentPosition.chapter
        project.chapterDrafts = savedPositions.map { position in
            ChapterDraft(
                volumeNumber: position.volume,
                chapterNumber: position.chapter,
                chapterTitle: "第 \(position.chapter) 章",
                content: "已保存正文 \(position.volume)-\(position.chapter)",
                savedAt: "2026-07-28T12:00:00Z"
            )
        }
        var runtime = LongformStoryRuntimeState.empty
        for draft in project.chapterDrafts {
            runtime.record(commit: acceptedCommit(projectID: project.id, draft: draft))
        }
        project.longformRuntimeState = runtime
        return project
    }

    private func acceptedCommit(
        projectID: NovelProject.ID,
        draft: ChapterDraft
    ) -> LongformChapterCommit {
        let rawID = [
            "commit",
            projectID,
            String(max(draft.volumeNumber, 1)),
            String(draft.chapterNumber),
            draft.content
        ].joined(separator: "|")
        let hash = rawID.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1.value)) &* 1_099_511_628_211
        }
        return LongformChapterCommit(
            id: String(format: "%016llx", hash),
            chapterNumber: draft.chapterNumber,
            volumeNumber: draft.volumeNumber,
            chapterTitle: draft.chapterTitle,
            status: .accepted,
            createdAt: draft.savedAtDate,
            plannedNodes: [],
            coveredNodes: [],
            missedNodes: [],
            rejectionReasons: [],
            revisionHints: [],
            acceptedEvents: [],
            extractedMemoryItems: [],
            dominantThreadType: .quest,
            reviewStatus: .completed,
            reviewSummary: "通过",
            projectionStatus: [
                "memory": "done",
                "foreshadowing": "done",
                "threads": "done",
                "strands": "done",
                "runtime": "done"
            ]
        )
    }

    private func repairIssue(kind: LongformRuntimeHealthIssueKind) -> LongformRuntimeHealthIssue {
        LongformRuntimeHealthIssue(
            id: "repair-\(kind.rawValue)",
            kind: kind,
            status: .blocked,
            title: "可变显示文案",
            detail: "此处文案不参与控制流。",
            repairHint: "补齐唯一缺口。"
        )
    }
}
