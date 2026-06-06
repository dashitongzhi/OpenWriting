import XCTest
@testable import OpenWriting

final class NovelProjectTests: XCTestCase {

    // MARK: - NovelProject Basic Tests

    func testNovelProjectCreation() {
        let project = NovelProject(
            title: "测试小说",
            genre: "都市",
            summary: "这是一个测试故事"
        )

        XCTAssertEqual(project.title, "测试小说")
        XCTAssertEqual(project.genre, "都市")
        XCTAssertEqual(project.summary, "这是一个测试故事")
        XCTAssertEqual(project.storyLength, .medium) // Default
        XCTAssertEqual(project.writtenChapters, 0)
        XCTAssertEqual(project.currentChapterNumber, 1)
        XCTAssertEqual(project.currentVolumeNumber, 1)
    }

    func testNovelProjectDefaultValues() {
        let project = NovelProject(
            title: "Test",
            genre: "Test",
            summary: "Test"
        )

        XCTAssertEqual(project.draftText, "")
        XCTAssertEqual(project.outlineText, "")
        XCTAssertEqual(project.chapterCatalog, [])
        XCTAssertEqual(project.chapterDrafts, [])
    }

    // MARK: - Chapter Draft Tests

    func testChapterDraftCreation() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "这是第一章的内容。这是一个很长的测试内容。"
        )

        XCTAssertEqual(draft.volumeNumber, 1)
        XCTAssertEqual(draft.chapterNumber, 1)
        XCTAssertEqual(draft.chapterTitle, "第一章")
        XCTAssertFalse(draft.content.isEmpty)
    }

    func testChapterDraftWordCount() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "测试",
            content: "这是测试内容。包含中文和标点符号！"
        )

        // Word count counts non-whitespace unicode scalars
        let wordCount = draft.wordCount
        XCTAssertGreaterThan(wordCount, 0)
    }

    func testChapterDraftVersionSnapshot() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "测试章节",
            content: "原始内容"
        )

        let version = draft.versionSnapshot(reason: "手动保存", savedAt: "2026-06-06")
        XCTAssertEqual(version.chapterTitle, "测试章节")
        XCTAssertEqual(version.content, "原始内容")
        XCTAssertEqual(version.reason, "手动保存")
    }

    func testChapterDraftSorting() {
        let draft1 = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "内容1"
        )
        let draft2 = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "第二章",
            content: "内容2"
        )
        let draft3 = ChapterDraft(
            volumeNumber: 2,
            chapterNumber: 1,
            chapterTitle: "第三卷第一章",
            content: "内容3"
        )

        let sorted = [draft3, draft1, draft2].sorted(by: ChapterDraft.sortDescending)
        XCTAssertEqual(sorted[0].chapterNumber, 1)
        XCTAssertEqual(sorted[0].volumeNumber, 2) // Volume 2 comes first
        XCTAssertEqual(sorted[1].chapterNumber, 2)
        XCTAssertEqual(sorted[2].chapterNumber, 1)
    }

    // MARK: - Chapter Draft Metadata Tests

    func testChapterDraftMetadataFromDraft() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 5,
            chapterTitle: "测试章节",
            content: "这是测试章节的完整内容。"
        )

        let metadata = ChapterDraftMetadata(chapterDraft: draft)

        XCTAssertEqual(metadata.volumeNumber, 1)
        XCTAssertEqual(metadata.chapterNumber, 5)
        XCTAssertEqual(metadata.chapterTitle, "测试章节")
        XCTAssertGreaterThan(metadata.wordCount, 0)
        XCTAssertFalse(metadata.previewText.isEmpty)
    }

    func testChapterDraftMetadataSorting() {
        let meta1 = ChapterDraftMetadata(chapterDraft: ChapterDraft(
            id: "1",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "预览1",
            savedAt: "2024-01-01"
        ))
        let meta2 = ChapterDraftMetadata(chapterDraft: ChapterDraft(
            id: "2",
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "第二章",
            content: "预览2",
            savedAt: "2024-01-02"
        ))

        let sorted = [meta2, meta1].sorted(by: ChapterDraftMetadata.sortDescending)
        XCTAssertEqual(sorted[0].chapterNumber, 2)
    }

    // MARK: - Volume Planning Tests

    func testNovelProjectVolumeNumberIsNormalized() {
        let project = NovelProject(
            id: "volume-normalization",
            title: "测试小说",
            genre: "都市",
            summary: "故事的开始",
            updatedAt: "2026-06-06",
            currentChapterTitle: "第一章",
            currentVolumeNumber: 0,
            currentChapterNumber: 1,
            writtenChapters: 0,
            chapterFocus: "推进开篇",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: []
        )

        XCTAssertEqual(project.currentVolumeNumber, 1)
    }

    func testLongLengthSupportsVolumePlanning() {
        XCTAssertTrue(NovelLength.long.supportsVolumePlanning)
        XCTAssertTrue(NovelLength.long.creationChecklist.contains { $0.contains("分卷") })
    }

    func testShortAndMediumDoNotRequireVolumePlanning() {
        XCTAssertFalse(NovelLength.short.supportsVolumePlanning)
        XCTAssertFalse(NovelLength.medium.supportsVolumePlanning)
    }

    // MARK: - Reference Document Tests

    func testReferenceDocumentCreation() {
        let doc = ReferenceDocument(
            title: "主角设定",
            content: "主角是一个年轻人..."
        )

        XCTAssertEqual(doc.title, "主角设定")
        XCTAssertFalse(doc.content.isEmpty)
    }

    func testReferenceDocumentCategoryInference() {
        let category = ReferenceMaterialCategory.infer(fromTitle: "主角人物设定", content: "姓名：小明\n年龄：20")
        XCTAssertEqual(category, .character)
    }

    func testReferenceDocumentWordCount() {
        let doc = ReferenceDocument(
            title: "测试",
            content: "这是测试内容。"
        )

        XCTAssertGreaterThan(doc.wordCount, 0)
    }

    // MARK: - Global Memory Snapshot Tests

    func testGlobalMemorySnapshotEmpty() {
        let memory = GlobalMemorySnapshot.empty

        XCTAssertEqual(memory.recentDevelopments, "")
        XCTAssertEqual(memory.characterRelations, "")
        XCTAssertEqual(memory.populatedSectionCount, 0)
        XCTAssertFalse(memory.hasStructuredContent)
    }

    func testGlobalMemorySnapshotSetValue() {
        var memory = GlobalMemorySnapshot.empty

        memory.setValue("主角受伤了", for: .injuries)
        memory.setValue("主角与反派的关系紧张", for: .characterRelations)

        XCTAssertEqual(memory.recentDevelopments, "")
        XCTAssertEqual(memory.injuries, "主角受伤了")
        XCTAssertEqual(memory.characterRelations, "主角与反派的关系紧张")
        XCTAssertEqual(memory.populatedSectionCount, 2)
        XCTAssertTrue(memory.hasStructuredContent)
    }

    func testGlobalMemorySnapshotParseFrom() {
        let text = """
        前情推进
        主角刚刚完成了第一个任务

        人物关系
        主角和配角A是好朋友

        关键地点
        城市中心广场
        """

        let memory = GlobalMemorySnapshot.parse(from: text)

        XCTAssertFalse(memory.recentDevelopments.isEmpty)
        XCTAssertFalse(memory.characterRelations.isEmpty)
        XCTAssertFalse(memory.locations.isEmpty)
    }

    func testGlobalMemorySnapshotFormattedText() {
        var memory = GlobalMemorySnapshot.empty
        memory.setValue("测试发展", for: .recentDevelopments)
        memory.setValue("测试关系", for: .characterRelations)

        let formatted = memory.formattedText

        XCTAssertTrue(formatted.contains("前情推进"))
        XCTAssertTrue(formatted.contains("测试发展"))
        XCTAssertTrue(formatted.contains("人物关系"))
        XCTAssertTrue(formatted.contains("测试关系"))
    }
}
