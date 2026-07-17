import XCTest
@testable import OpenWriting

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
}
