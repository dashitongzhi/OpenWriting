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

    func testStorageHealthReportPassesForCompleteShardedStore() async throws {
        let project = NovelProject(title: "健康项目", genre: "都市", summary: "摘要")
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "这是完整章节。"
        )
        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]

        try store.saveProjects([projectWithChapter], for: scope)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        XCTAssertEqual(report.status, .passed)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.metrics["indexedChapters"], "1")
    }

    func testStorageHealthReportDetectsMissingChapterAndPreservesPlaceholder() async throws {
        let project = NovelProject(title: "缺章项目", genre: "都市", summary: "摘要")
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "原始正文"
        )
        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]
        try store.saveProjects([projectWithChapter], for: scope)

        let chapterURL = try XCTUnwrap(firstStoredFile(named: "\(chapter.id).json"))
        try FileManager.default.removeItem(at: chapterURL)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        let missingIssue = try XCTUnwrap(report.issues.first { $0.kind == .chapterFileMissing })
        XCTAssertEqual(report.status, .blocked)

        _ = try store.recoverStorageIssue(
            missingIssue,
            action: .preserveMissingChapterPlaceholder,
            project: projectWithChapter,
            scope: scope
        )

        let recoveredChapter = store.loadChapterDraft(chapter.id, for: project.id, scope: scope)
        XCTAssertTrue(recoveredChapter?.content.contains("章节文件缺失占位") ?? false)

        let recoveredReport = store.storageHealthReport(for: project.id, scope: scope)
        XCTAssertEqual(recoveredReport.status, .passed)
        XCTAssertFalse(recoveredReport.issues.contains { $0.kind == .chapterFileMissing })
    }

    func testStorageRecoveryRejectsActionNotOfferedByIssue() async throws {
        let project = NovelProject(title: "动作保护项目", genre: "都市", summary: "摘要")
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "原始正文"
        )
        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]
        try store.saveProjects([projectWithChapter], for: scope)

        let chapterURL = try XCTUnwrap(firstStoredFile(named: "\(chapter.id).json"))
        try FileManager.default.removeItem(at: chapterURL)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        let missingIssue = try XCTUnwrap(report.issues.first { $0.kind == .chapterFileMissing })
        XCTAssertFalse(missingIssue.recoveryActions.contains(.recoverMetadataShell))

        XCTAssertThrowsError(try store.recoverStorageIssue(
            missingIssue,
            action: .recoverMetadataShell,
            project: projectWithChapter,
            scope: scope
        ))
    }

    func testStorageRecoveryPreservesPlaceholderForCorruptChapter() async throws {
        let project = NovelProject(title: "损坏章节项目", genre: "都市", summary: "摘要")
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "原始正文"
        )
        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [chapter]
        try store.saveProjects([projectWithChapter], for: scope)

        let chapterURL = try XCTUnwrap(firstStoredFile(named: "\(chapter.id).json"))
        try Data("{ invalid json".utf8).write(to: chapterURL)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        let corruptIssue = try XCTUnwrap(report.issues.first { $0.kind == .chapterFileCorrupt })
        XCTAssertEqual(corruptIssue.recoveryActions, [.exportDiagnostics, .preserveMissingChapterPlaceholder])

        let result = try store.recoverStorageIssue(
            corruptIssue,
            action: .preserveMissingChapterPlaceholder,
            project: projectWithChapter,
            scope: scope
        )

        let backupURL = try XCTUnwrap(result.outputURL)
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "{ invalid json")

        let recoveredChapter = store.loadChapterDraft(chapter.id, for: project.id, scope: scope)
        XCTAssertTrue(recoveredChapter?.content.contains("章节文件缺失占位") ?? false)

        let recoveredReport = store.storageHealthReport(for: project.id, scope: scope)
        XCTAssertEqual(recoveredReport.status, .passed)
    }

    func testStorageHealthReportDetectsCorruptProjectMetadata() async throws {
        let project = NovelProject(title: "损坏项目", genre: "都市", summary: "摘要")
        try store.saveProjects([project], for: scope)

        let metadataURL = try XCTUnwrap(firstStoredFile(named: "project.json"))
        try Data("{ invalid json".utf8).write(to: metadataURL)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertTrue(report.issues.contains { $0.kind == .projectMetadataCorrupt })
    }

    func testLoadProjectsSkipsCorruptProjectMetadata() async throws {
        let healthyProject = NovelProject(title: "健康项目", genre: "都市", summary: "摘要")
        let corruptProject = NovelProject(title: "损坏项目", genre: "玄幻", summary: "摘要")
        try store.saveProjects([healthyProject, corruptProject], for: scope)

        let corruptMetadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(corruptProject.id)
        })
        try Data("{ invalid json".utf8).write(to: corruptMetadataURL)

        let loadedProjects = try XCTUnwrap(store.loadProjects(for: scope))

        XCTAssertEqual(loadedProjects.map(\.id), [healthyProject.id])
    }

    func testRebuildChapterCatalogPreservesOrphanChapterFile() async throws {
        let project = NovelProject(title: "孤儿章节项目", genre: "都市", summary: "摘要")
        let indexedChapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "已索引正文"
        )
        let orphanChapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "第二章",
            content: "孤儿正文"
        )
        var projectWithChapter = project
        projectWithChapter.chapterDrafts = [indexedChapter]
        try store.saveProjects([projectWithChapter], for: scope)

        let indexedURL = try XCTUnwrap(firstStoredFile(named: "\(indexedChapter.id).json"))
        let orphanURL = indexedURL.deletingLastPathComponent().appendingPathComponent("\(orphanChapter.id).json")
        try JSONEncoder().encode(orphanChapter).write(to: orphanURL)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        let orphanIssue = try XCTUnwrap(report.issues.first { $0.kind == .orphanChapterFile })
        XCTAssertEqual(orphanIssue.status, .warning)

        _ = try store.recoverStorageIssue(
            orphanIssue,
            action: .rebuildChapterCatalog,
            project: projectWithChapter,
            scope: scope
        )

        let chapters = store.loadChapterDrafts(for: project.id, scope: scope)
        XCTAssertTrue(chapters.contains { $0.id == indexedChapter.id })
        XCTAssertTrue(chapters.contains { $0.id == orphanChapter.id })

        let loadedProject = try XCTUnwrap(store.loadProjects(for: scope)?.first)
        XCTAssertTrue(loadedProject.chapterCatalog.contains { $0.id == orphanChapter.id })

        let recoveredReport = store.storageHealthReport(for: project.id, scope: scope)
        XCTAssertEqual(recoveredReport.status, .passed)
        XCTAssertFalse(recoveredReport.issues.contains { $0.kind == .catalogFileMismatch })
    }

    func testRecoverMetadataShellRestoresMissingProjectIndex() async throws {
        let project = NovelProject(title: "索引恢复项目", genre: "都市", summary: "摘要")
        try store.saveProjects([project], for: scope)

        let projectIndexURL = try XCTUnwrap(storedFiles(named: "index.json").first { !$0.path.contains("/chapters/") })
        try FileManager.default.removeItem(at: projectIndexURL)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        let indexIssue = try XCTUnwrap(report.issues.first { $0.kind == .projectIndexMissing })
        XCTAssertEqual(report.status, .blocked)

        _ = try store.recoverStorageIssue(
            indexIssue,
            action: .recoverMetadataShell,
            project: project,
            scope: scope
        )

        let loadedProjects = store.loadProjects(for: scope)
        XCTAssertEqual(loadedProjects?.first?.id, project.id)

        let recoveredReport = store.storageHealthReport(for: project.id, scope: scope)
        XCTAssertEqual(recoveredReport.status, .passed)
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

    private func firstStoredFile(named fileName: String) -> URL? {
        storedFiles(named: fileName).first
    }

    private func storedFiles(named fileName: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: testDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == fileName {
            urls.append(url)
        }
        return urls
    }
}
