import XCTest
@testable import OpenWriting

final class ProjectExportServiceTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        testDirectory = base.appendingPathComponent("OpenWritingExportTests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testExportValidateAndImportProject() throws {
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "第一章正文。"
        )
        let project = NovelProject(
            id: "export-test",
            title: "备份测试",
            genre: "玄幻",
            summary: "测试导出恢复",
            updatedAt: "2026-06-06",
            currentChapterTitle: "第一章",
            currentChapterNumber: 1,
            writtenChapters: 1,
            chapterFocus: "继续推进主线",
            draftText: "当前草稿",
            outlineText: "全书大纲",
            referenceContextText: "参考文本",
            specialRequirements: "保持爽点",
            wordTargetText: "2000 字",
            continuityNotes: "主角进入秘境。",
            referenceDocuments: [
                ReferenceDocument(title: "主角设定", content: "主角名为林澈。")
            ],
            chapterDrafts: [chapter]
        )

        let summary = try ProjectExportService.exportProject(project, to: testDirectory)
        XCTAssertGreaterThanOrEqual(summary.fileCount, 6)

        let report = try ProjectExportService.validateExport(at: testDirectory)
        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.project.title, "备份测试")
        XCTAssertEqual(report.project.chapterDrafts.count, 1)

        let imported = try ProjectExportService.importProject(from: testDirectory)
        XCTAssertEqual(imported.title, project.title)
        XCTAssertEqual(imported.chapterDrafts.first?.content, chapter.content)
    }

    func testValidateExportFailsWhenListedFileIsMissing() throws {
        let project = NovelProject(
            id: "missing-file-test",
            title: "缺文件测试",
            genre: "都市",
            summary: "测试缺失文件",
            updatedAt: "2026-06-06",
            currentChapterTitle: "第一章",
            currentChapterNumber: 1,
            writtenChapters: 0,
            chapterFocus: "开篇",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: []
        )

        try ProjectExportService.exportProject(project, to: testDirectory)
        try FileManager.default.removeItem(at: testDirectory.appendingPathComponent("full-book.md"))

        XCTAssertThrowsError(try ProjectExportService.validateExport(at: testDirectory)) { error in
            guard case ProjectExportError.invalidExport(_, let missingFiles, _) = error else {
                XCTFail("Expected invalidExport, got \(error)")
                return
            }
            XCTAssertTrue(missingFiles.contains("full-book.md"))
        }
    }
}
