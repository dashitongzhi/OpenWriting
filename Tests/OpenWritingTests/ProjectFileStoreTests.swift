import XCTest
@testable import OpenWriting

final class ProjectFileStoreTests: XCTestCase {

    var store: ProjectFileStore!
    var testDirectory: URL!
    var scope: String = "test-scope"

    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("OpenWritingTest/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Initialize store with test directory (using init with baseDirectoryName and custom baseURL)
        store = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
    }

    override func tearDown() async throws {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        try await super.tearDown()
    }

    // MARK: - Project Save/Load Tests

    func testSaveAndLoadSingleProject() async throws {
        let project = NovelProject(
            title: "测试项目",
            genre: "都市",
            summary: "这是一个测试项目"
        )

        try store.saveProjects([project], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?[0].title, "测试项目")
    }

    func testSaveAndLoadMultipleProjects() async throws {
        let project1 = NovelProject(title: "项目1", genre: "都市", summary: "摘要1")
        let project2 = NovelProject(title: "项目2", genre: "玄幻", summary: "摘要2")

        try store.saveProjects([project1, project2], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertTrue(loaded?.contains(where: { $0.title == "项目1" }) ?? false)
        XCTAssertTrue(loaded?.contains(where: { $0.title == "项目2" }) ?? false)
    }

    func testSaveEmptyProjectsList() async throws {
        // Saving empty list should not crash
        try store.saveProjects([], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertNil(loaded)
    }

    // MARK: - Chapter Draft Tests

    func testSaveAndLoadChapterDraft() async throws {
        let project = NovelProject(
            title: "测试项目",
            genre: "都市",
            summary: "摘要"
        )

        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "这是第一章的内容。"
        )

        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]

        try store.saveProjects([projectWithChapter], for: scope)

        // Load the project
        guard let loaded = store.loadProjects(for: scope),
              let loadedProject = loaded.first else {
            XCTFail("Failed to load project")
            return
        }

        XCTAssertEqual(loadedProject.chapterCatalog.count, 1)
        XCTAssertEqual(loadedProject.chapterCatalog.first?.chapterTitle, "第一章")
        XCTAssertEqual(loadedProject.chapterDrafts.count, 0) // Should be empty (lazy loaded)
    }

    func testLoadChapterDraft() async throws {
        let project = NovelProject(
            title: "测试项目",
            genre: "都市",
            summary: "摘要"
        )

        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "这是第一章的完整内容。"
        )

        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]

        try store.saveProjects([projectWithChapter], for: scope)

        // Load specific chapter
        let loadedChapter = store.loadChapterDraft(chapter.id, for: project.id, scope: scope)
        XCTAssertNotNil(loadedChapter)
        XCTAssertEqual(loadedChapter?.content, "这是第一章的完整内容。")
    }

    func testLoadChapterDrafts() async throws {
        let project = NovelProject(
            title: "测试项目",
            genre: "都市",
            summary: "摘要"
        )

        let chapter1 = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "内容1"
        )
        let chapter2 = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "第二章",
            content: "内容2"
        )

        var projectWithChapters = project
        projectWithChapters.chapterDrafts = [chapter1, chapter2]

        try store.saveProjects([projectWithChapters], for: scope)

        let chapters = store.loadChapterDrafts(for: project.id, scope: scope)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertTrue(chapters.contains { $0.chapterNumber == 1 })
        XCTAssertTrue(chapters.contains { $0.chapterNumber == 2 })
    }

    // MARK: - Update Project Tests

    func testUpdateExistingProject() async throws {
        let project = NovelProject(
            title: "原始标题",
            genre: "都市",
            summary: "摘要"
        )

        try store.saveProjects([project], for: scope)

        let updatedProject = NovelProject(
            id: project.id,
            title: "新标题",
            genre: project.genre,
            summary: project.summary,
            updatedAt: "2026-06-06",
            currentChapterTitle: project.currentChapterTitle,
            currentChapterNumber: project.currentChapterNumber,
            writtenChapters: project.writtenChapters,
            chapterFocus: project.chapterFocus,
            draftText: project.draftText,
            outlineText: project.outlineText,
            referenceContextText: project.referenceContextText,
            specialRequirements: project.specialRequirements,
            wordTargetText: project.wordTargetText,
            continuityNotes: project.continuityNotes,
            referenceDocuments: project.referenceDocuments
        )

        try store.saveProjects([updatedProject], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertEqual(loaded?.first?.title, "新标题")
    }

    // MARK: - Delete Project Tests

    func testDeleteProject() async throws {
        let project = NovelProject(
            title: "将被删除的项目",
            genre: "都市",
            summary: "摘要"
        )

        try store.saveProjects([project], for: scope)

        // Save empty list to effectively delete
        try store.saveProjects([], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertNil(loaded)
    }

    // MARK: - Scope Tests

    func testDifferentScopesAreIsolated() async throws {
        let project1 = NovelProject(title: "项目1", genre: "都市", summary: "摘要")
        let project2 = NovelProject(title: "项目2", genre: "玄幻", summary: "摘要")

        // Save to different scopes
        try store.saveProjects([project1], for: "scope1")
        try store.saveProjects([project2], for: "scope2")

        // Load from each scope
        let loaded1 = store.loadProjects(for: "scope1")
        let loaded2 = store.loadProjects(for: "scope2")

        XCTAssertEqual(loaded1?.first?.title, "项目1")
        XCTAssertEqual(loaded2?.first?.title, "项目2")
    }

    // MARK: - Chapter Version History Tests

    func testChapterVersionHistory() async throws {
        let project = NovelProject(
            title: "测试项目",
            genre: "都市",
            summary: "摘要"
        )

        var chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "版本1内容"
        )

        // Add version history
        let version1 = ChapterDraftVersion(
            chapterTitle: "第一章",
            content: "原始内容",
            reason: "初始保存"
        )
        let version2 = ChapterDraftVersion(
            chapterTitle: "第一章",
            content: "版本2内容",
            reason: "修改后保存"
        )
        chapter.versionHistory = [version1, version2]

        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]

        try store.saveProjects([projectWithChapter], for: scope)

        // Load and verify version history
        let loadedChapter = store.loadChapterDraft(chapter.id, for: project.id, scope: scope)
        XCTAssertNotNil(loadedChapter)
        XCTAssertEqual(loadedChapter?.versionHistory.count, 2)
    }

    // MARK: - Edge Cases

    func testProjectWithSpecialCharactersInTitle() async throws {
        let project = NovelProject(
            title: "项目: 特殊/字符<>|?*",
            genre: "都市",
            summary: "摘要"
        )

        try store.saveProjects([project], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertNotNil(loaded?.first)
    }

    func testLargeChapterContent() async throws {
        let project = NovelProject(
            title: "测试项目",
            genre: "都市",
            summary: "摘要"
        )

        // Create a large chapter content
        let largeContent = String(repeating: "这是测试内容。", count: 10000)
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "大型章节",
            content: largeContent
        )

        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]

        try store.saveProjects([projectWithChapter], for: scope)

        let loadedChapter = store.loadChapterDraft(chapter.id, for: project.id, scope: scope)
        XCTAssertNotNil(loadedChapter)
        XCTAssertEqual(loadedChapter?.content.count, largeContent.count)
    }

    func testLoadFromNonexistentScope() {
        let loaded = store.loadProjects(for: "nonexistent-scope-12345")
        XCTAssertNil(loaded)
    }

    func testLoadNonexistentChapter() {
        let loaded = store.loadChapterDraft("nonexistent-id", for: "nonexistent-project", scope: scope)
        XCTAssertNil(loaded)
    }
}
