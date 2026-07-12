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

        _ = try ProjectExportService.exportProject(project, to: testDirectory)
        try FileManager.default.removeItem(at: testDirectory.appendingPathComponent("full-book.md"))

        XCTAssertThrowsError(try ProjectExportService.validateExport(at: testDirectory)) { error in
            guard case ProjectExportError.invalidExport(_, let missingFiles, _) = error else {
                XCTFail("Expected invalidExport, got \(error)")
                return
            }
            XCTAssertTrue(missingFiles.contains("full-book.md"))
        }
    }

    func testValidateExportRejectsManifestPathTraversal() throws {
        let manifest = """
        {"title":"恶意备份","exportedAt":"2026-07-12T00:00:00Z","chapterCount":0,"savedWordCount":0,"currentDraftWordCount":0,"manuscriptWordCount":0,"files":["project.json","../outside.md"]}
        """
        try Data(manifest.utf8).write(to: testDirectory.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(try ProjectExportService.validateExport(at: testDirectory)) { error in
            guard case ProjectExportError.unsafeManifestPath("../outside.md") = error else {
                XCTFail("Expected unsafeManifestPath, got \(error)")
                return
            }
        }
    }

    func testValidateExportRejectsUnsafeProjectStorageID() throws {
        let project = NovelProject(
            id: "..",
            title: "恶意项目 ID",
            genre: "都市",
            summary: "摘要",
            updatedAt: "2026-07-12",
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
        _ = try ProjectExportService.exportProject(project, to: testDirectory)

        XCTAssertThrowsError(try ProjectExportService.validateExport(at: testDirectory)) { error in
            guard case ProjectExportError.invalidProjectData("项目 ID 不安全") = error else {
                XCTFail("Expected unsafe project ID error, got \(error)")
                return
            }
        }
    }

    func testValidateExportRejectsUnsafeChapterStorageID() throws {
        let chapter = ChapterDraft(id: "..", chapterNumber: 1, chapterTitle: "第一章", content: "正文")
        let project = NovelProject(
            id: "safe-project",
            title: "恶意章节 ID",
            genre: "都市",
            summary: "摘要",
            updatedAt: "2026-07-12",
            currentChapterTitle: "第一章",
            currentChapterNumber: 1,
            writtenChapters: 1,
            chapterFocus: "开篇",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: [],
            chapterDrafts: [chapter]
        )
        _ = try ProjectExportService.exportProject(project, to: testDirectory)

        XCTAssertThrowsError(try ProjectExportService.validateExport(at: testDirectory)) { error in
            guard case ProjectExportError.invalidProjectData("章节 ID 不安全") = error else {
                XCTFail("Expected unsafe chapter ID error, got \(error)")
                return
            }
        }
    }

    func testEPUBMimetypeIsFirstStoredEntry() throws {
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "第一章正文。"
        )
        let project = NovelProject(
            id: "epub-mimetype-test",
            title: "EPUB 测试",
            genre: "玄幻",
            summary: "测试 EPUB mimetype",
            updatedAt: "2026-06-22",
            currentChapterTitle: "第一章",
            currentChapterNumber: 1,
            writtenChapters: 1,
            chapterFocus: "开篇",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: [],
            chapterDrafts: [chapter]
        )

        _ = try ProjectExportService.exportProject(project, to: testDirectory)
        let epubData = try Data(contentsOf: testDirectory.appendingPathComponent("full-book.epub"))

        XCTAssertEqual(littleEndianUInt32(in: epubData, at: 0), 0x04034b50)
        XCTAssertEqual(littleEndianUInt16(in: epubData, at: 8), 0)

        let nameLength = Int(littleEndianUInt16(in: epubData, at: 26))
        let extraLength = Int(littleEndianUInt16(in: epubData, at: 28))
        let nameStart = 30
        let nameEnd = nameStart + nameLength
        let contentStart = nameEnd + extraLength
        let contentEnd = contentStart + Int(littleEndianUInt32(in: epubData, at: 18))

        let firstName = String(data: epubData.subdata(in: nameStart..<nameEnd), encoding: .utf8)
        let firstContent = String(data: epubData.subdata(in: contentStart..<contentEnd), encoding: .utf8)
        XCTAssertEqual(firstName, "mimetype")
        XCTAssertEqual(firstContent, "application/epub+zip")
    }

    private func littleEndianUInt16(in data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
