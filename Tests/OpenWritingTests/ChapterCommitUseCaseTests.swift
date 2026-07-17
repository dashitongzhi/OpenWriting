import XCTest
@testable import OpenWriting

final class KeywordMemoryExtractorTests: XCTestCase {
    func testExtractionIsDeterministicAndPreservesVolumeChapterSource() {
        let text = """
        沈青：“清晨在青石古镇会合。”
        陆白：“我已经到了。”
        沈青与陆白一起进入青石古镇，钟楼背后的秘密似乎仍未揭开。
        沈青：“这个秘密不能告诉别人。”
        陆白：“这里果然有些蹊跷。”
        """

        let first = KeywordMemoryExtractor.extract(
            from: text,
            volumeNumber: 2,
            chapterNumber: 7
        )
        let second = KeywordMemoryExtractor.extract(
            from: text,
            volumeNumber: 2,
            chapterNumber: 7
        )

        XCTAssertEqual(signatures(first), signatures(second))
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.allSatisfy { $0.sourceVolumeNumber == 2 && $0.sourceChapter == 7 })
        XCTAssertTrue(first.contains { $0.category == .characterState && $0.subject == "沈青" })
        XCTAssertTrue(first.contains { $0.category == .timeline && $0.subject == "清晨" })
        XCTAssertTrue(first.contains { $0.category == .openLoop })
    }

    func testExtractionNormalizesInvalidVolumeAndChapterNumbers() {
        let items = KeywordMemoryExtractor.extract(
            from: "第二天，林舟来到青石古镇，发现秘密仍未揭开。",
            volumeNumber: 0,
            chapterNumber: 0
        )

        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.sourceVolumeNumber == 1 && $0.sourceChapter == 1 })
    }

    private func signatures(_ items: [MemoryItem]) -> [String] {
        items.map {
            [
                $0.category.rawValue,
                $0.subject,
                $0.field,
                $0.value,
                $0.status.rawValue,
                String($0.sourceVolumeNumber),
                String($0.sourceChapter)
            ].joined(separator: "|")
        }
    }
}

final class ChapterCommitUseCaseTests: XCTestCase {
    func testAcceptedCommitProjectsMemoryAndAntiPatternsWithoutMutatingInput() {
        let project = makeProject(id: "accepted-\(UUID().uuidString)")
        let projectID = project.id
        addTeardownBlock { NovelProject.clearIntegrationCache(for: projectID) }
        let originalUpdatedAt = project.updatedAt
        let draft = ChapterDraft(
            volumeNumber: 2,
            chapterNumber: 7,
            chapterTitle: "钟楼密约",
            content: "清晨，林舟来到青石古镇。他缓缓抬头，缓缓走近，又缓缓推开钟楼木门。秘密似乎仍未揭开。"
        )

        let outcome = ChapterCommitUseCase.commit(ChapterCommitRequest(
            project: project,
            chapterDraft: draft,
            review: nil,
            reviewFailureReason: nil,
            contractOverride: acceptingContract(for: project, draft: draft),
            updatedAt: "2026-07-17"
        ))

        XCTAssertTrue(outcome.commit.isAccepted)
        XCTAssertEqual(outcome.project.longformRuntimeState.acceptedCommits.count, 1)
        XCTAssertTrue(outcome.project.longformRuntimeState.rejectedCommits.isEmpty)
        XCTAssertTrue(outcome.project.memoryBuckets.timeline.contains {
            $0.subject == "清晨" && $0.sourceVolumeNumber == 2 && $0.sourceChapter == 7
        })
        XCTAssertTrue(outcome.project.accumulatedAntiPatterns.contains { $0.contains("缓缓") })
        XCTAssertGreaterThan(outcome.project.updatedAtDate, project.updatedAtDate)

        XCTAssertEqual(project.updatedAt, originalUpdatedAt)
        XCTAssertEqual(project.persistedLongformRuntimeState, .empty)
        XCTAssertEqual(project.persistedMemoryBuckets, .empty)
        XCTAssertEqual(project.persistedAntiPatterns, [])
    }

    func testRejectedCommitInvalidatesOnlyTheMatchingChapterProjection() {
        var project = makeProject(id: "rejected-\(UUID().uuidString)")
        let projectID = project.id
        addTeardownBlock { NovelProject.clearIntegrationCache(for: projectID) }
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .timeline,
            subject: "旧章节投影",
            field: "时间标记",
            value: "应被清理",
            sourceVolumeNumber: 2,
            sourceChapter: 7
        ))
        buckets.upsert(MemoryItem(
            category: .timeline,
            subject: "其他章节投影",
            field: "时间标记",
            value: "应被保留",
            sourceVolumeNumber: 2,
            sourceChapter: 6
        ))
        project.persistedMemoryBuckets = buckets
        let draft = ChapterDraft(
            volumeNumber: 2,
            chapterNumber: 7,
            chapterTitle: "未通过章节",
            content: "第二天，林舟再次进入青石古镇。"
        )
        var contract = acceptingContract(for: project, draft: draft)
        contract.prewrite = .init(
            isBlocked: true,
            blockingReasons: ["章节目标尚未明确"],
            warnings: [],
            memoryConflicts: []
        )

        let outcome = ChapterCommitUseCase.commit(ChapterCommitRequest(
            project: project,
            chapterDraft: draft,
            review: nil,
            reviewFailureReason: nil,
            contractOverride: contract,
            updatedAt: "2026-07-17"
        ))

        XCTAssertFalse(outcome.commit.isAccepted)
        XCTAssertTrue(outcome.commit.extractedMemoryItems.isEmpty)
        XCTAssertEqual(outcome.project.longformRuntimeState.rejectedCommits.count, 1)
        XCTAssertFalse(outcome.project.memoryBuckets.timeline.contains {
            $0.sourceVolumeNumber == 2 && $0.sourceChapter == 7
        })
        XCTAssertTrue(outcome.project.memoryBuckets.timeline.contains {
            $0.subject == "其他章节投影" && $0.sourceChapter == 6
        })
    }

    private func makeProject(id: String) -> NovelProject {
        NovelProject(
            id: id,
            title: "章节收录测试",
            genre: "悬疑",
            summary: "验证章节收录及长篇后台投影。",
            storyLength: .medium,
            updatedAt: "2026-06-06",
            currentChapterTitle: "钟楼密约",
            currentVolumeNumber: 2,
            currentChapterNumber: 7,
            writtenChapters: 6,
            chapterFocus: "林舟进入钟楼寻找秘密。",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: [],
            persistedMemoryBuckets: .empty,
            persistedStrandWeaveState: .empty,
            persistedAntiPatterns: [],
            persistedLongformRuntimeState: .empty
        )
    }

    private func acceptingContract(
        for project: NovelProject,
        draft: ChapterDraft
    ) -> LongformStoryContractBundle {
        var contract = LongformStorySystem.buildRuntimeContract(for: project)
        contract.chapter.chapterNumber = draft.chapterNumber
        contract.chapter.chapterTitle = draft.chapterTitle
        contract.chapter.mandatoryNodes = []
        contract.chapter.requiresMandatoryNodeCoverage = false
        contract.review.requiresPostwriteReview = false
        contract.prewrite = .init(
            isBlocked: false,
            blockingReasons: [],
            warnings: [],
            memoryConflicts: []
        )
        return contract
    }
}
