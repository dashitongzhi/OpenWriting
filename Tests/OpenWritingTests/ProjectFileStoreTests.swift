import XCTest
@testable import OpenWriting

@MainActor
final class ProjectFileStoreTests: XCTestCase {
    private enum InjectedFailure: Error {
        case chapterWrite
    }

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

    func testWarmWriteCacheSkipsFileReadsButDetectsExternalMutation() throws {
        var verificationReadURLs: [URL] = []
        let cachedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: "",
            testHooks: .init(
                onExistingFileVerificationRead: { verificationReadURLs.append($0) }
            )
        )
        let project = NovelProject(
            id: "write-cache-project",
            title: "写缓存测试",
            genre: "悬疑",
            summary: "重复保存不得重新读取完整文件"
        )

        try cachedStore.saveProjects([project], for: scope)
        verificationReadURLs.removeAll()
        try cachedStore.saveProjects([project], for: scope)
        XCTAssertTrue(
            verificationReadURLs.isEmpty,
            "Warm no-op save unexpectedly read: \(verificationReadURLs.map(\.lastPathComponent))"
        )

        let metadataURL = try XCTUnwrap(firstStoredFile(named: "project.json"))
        let originalData = try Data(contentsOf: metadataURL)
        var externallyReformattedData = Data(" \n".utf8)
        externallyReformattedData.append(originalData)
        try externallyReformattedData.write(to: metadataURL)
        verificationReadURLs.removeAll()

        try cachedStore.saveProjects([project], for: scope)

        XCTAssertTrue(
            verificationReadURLs.contains { $0.lastPathComponent == metadataURL.lastPathComponent },
            "Expected metadata verification read; observed \(verificationReadURLs.map(\.path))"
        )
        XCTAssertEqual(try Data(contentsOf: metadataURL), originalData)
    }

    func testSaveEmptyProjectsList() async throws {
        try store.saveProjects([], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertEqual(loaded?.isEmpty, true)
    }

    func testDeletionTombstoneSurvivesStoreRestartAndBlocksStaleProject() throws {
        var project = NovelProject(
            id: "project-restart",
            title: "重启删除测试",
            genre: "都市",
            summary: "摘要"
        )
        project.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.121)
        let tombstone = ProjectDeletionTombstone(
            projectID: project.id,
            deletedAt: Date(timeIntervalSince1970: 1_710_000_000.124)
        )

        try store.saveProjects([project], for: scope)
        try store.saveProjects([], deletedProjects: [tombstone], for: scope)

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        XCTAssertEqual(
            restartedStore.loadProjectDeletionTombstones(for: scope),
            [tombstone]
        )
        XCTAssertEqual(restartedStore.loadProjects(for: scope)?.isEmpty, true)

        try restartedStore.saveProjects(
            [project],
            deletedProjects: restartedStore.loadProjectDeletionTombstones(for: scope),
            for: scope
        )
        XCTAssertEqual(restartedStore.loadProjects(for: scope)?.isEmpty, true)
        XCTAssertEqual(
            restartedStore.loadProjectDeletionTombstones(for: scope),
            [tombstone]
        )
    }

    func testCorruptIndexDoesNotReviveDeletedProjectFromPreservedLegacyFile() throws {
        var project = NovelProject(
            id: "deleted-legacy-project",
            title: "不得复活",
            genre: "悬疑",
            summary: "旧版副本只能作为恢复证据"
        )
        project.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.121)
        try store.saveProjects([project], for: scope)

        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        let legacyURL = indexURL.deletingLastPathComponent()
            .appendingPathComponent("projects.json")
        let projectObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(project))
                as? [String: Any]
        )
        let malformedObject: [String: Any] = [
            "schemaVersion": NovelProject.currentSchemaVersion,
            "id": "malformed-preserved"
        ]
        let legacyData = try JSONSerialization.data(
            withJSONObject: [projectObject, malformedObject],
            options: [.sortedKeys]
        )
        try legacyData.write(to: legacyURL)

        let tombstone = ProjectDeletionTombstone(
            projectID: project.id,
            deletedAt: Date(timeIntervalSince1970: 1_710_000_000.124)
        )
        try store.saveProjects([], deletedProjects: [tombstone], for: scope)
        XCTAssertEqual(store.loadProjects(for: scope)?.isEmpty, true)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)

        let corruptIndexData = Data("{ invalid index".utf8)
        try corruptIndexData.write(to: indexURL)
        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )

        XCTAssertEqual(restartedStore.loadProjects(for: scope)?.isEmpty, true)
        XCTAssertThrowsError(
            try restartedStore.saveProjects([], for: scope)
        )
        XCTAssertEqual(restartedStore.loadProjects(for: scope)?.isEmpty, true)
        XCTAssertEqual(try Data(contentsOf: indexURL), corruptIndexData)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
    }

    func testNewerProjectSupersedesPersistedDeletionTombstone() throws {
        var project = NovelProject(
            id: "project-restored",
            title: "恢复测试",
            genre: "都市",
            summary: "摘要"
        )
        project.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.121)
        let tombstone = ProjectDeletionTombstone(
            projectID: project.id,
            deletedAt: Date(timeIntervalSince1970: 1_710_000_000.124)
        )
        try store.saveProjects([], deletedProjects: [tombstone], for: scope)

        project.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.127)
        try store.saveProjects([project], deletedProjects: [tombstone], for: scope)

        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [project.id])
        XCTAssertTrue(store.loadProjectDeletionTombstones(for: scope).isEmpty)
    }

    func testPersistenceActorCarriesDeletionTombstones() async throws {
        let actor = ProjectPersistenceActor(store: store.independentCopy())
        let tombstone = ProjectDeletionTombstone(
            projectID: "project-deleted",
            deletedAt: Date(timeIntervalSince1970: 1_710_000_000.124)
        )

        let didWrite = try await actor.saveAfterDelay(
            [],
            deletedProjects: [tombstone],
            for: scope,
            delay: .milliseconds(1)
        )

        XCTAssertTrue(didWrite)
        XCTAssertEqual(store.loadProjectDeletionTombstones(for: scope), [tombstone])
    }

    func testDurableAtomicWritesLeaveNoTemporaryFiles() throws {
        var project = NovelProject(
            title: "原子写入测试",
            genre: "都市",
            summary: "摘要"
        )
        try store.saveProjects([project], for: scope)
        project.draftText = "第二次写入"
        try store.saveProjects([project], for: scope)

        let temporaryFiles = allStoredFiles().filter {
            $0.lastPathComponent.hasSuffix(".tmp")
        }
        XCTAssertTrue(
            temporaryFiles.isEmpty,
            "Durable writer left temporary files: \(temporaryFiles)"
        )
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

    func testDuplicateChapterIndexIsNormalizedBeforeLoadAndSaveWithoutLosingBodies() throws {
        let firstChapter = ChapterDraft(
            id: "chapter-first-order",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "必须保留的第一章正文"
        )
        let secondChapter = ChapterDraft(
            id: "chapter-second-order",
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "第二章",
            content: "必须保留的第二章正文"
        )
        var project = NovelProject(
            id: "duplicate-chapter-index-project",
            title: "重复章节索引",
            genre: "悬疑",
            summary: "摘要"
        )
        project.chapterDrafts = [firstChapter, secondChapter]
        try store.saveProjects([project], for: scope)

        let chapterIndexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            $0.path.contains("/chapters/")
        })
        var indexObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: chapterIndexURL))
                as? [String: Any]
        )
        let originalMetadata = try XCTUnwrap(indexObject["chapters"] as? [[String: Any]])
        var staleFirst = try XCTUnwrap(originalMetadata.first { $0["id"] as? String == firstChapter.id })
        let second = try XCTUnwrap(originalMetadata.first { $0["id"] as? String == secondChapter.id })
        staleFirst["chapterTitle"] = "过期标题"
        staleFirst["savedAt"] = "1710000000.100"
        var newestFirst = staleFirst
        newestFirst["chapterTitle"] = "较新标题"
        newestFirst["savedAt"] = "1720000000.200"
        var equalTimestampFirst = newestFirst
        equalTimestampFirst["chapterTitle"] = "相同时间的后置标题"

        indexObject["chapterIDs"] = [
            firstChapter.id,
            firstChapter.id,
            secondChapter.id,
            firstChapter.id
        ]
        indexObject["chapters"] = [
            staleFirst,
            second,
            newestFirst,
            equalTimestampFirst
        ]
        try JSONSerialization.data(
            withJSONObject: indexObject,
            options: [.sortedKeys]
        ).write(to: chapterIndexURL)

        let damagedReport = store.storageHealthReport(for: project.id, scope: scope)
        XCTAssertEqual(damagedReport.status, .blocked)
        XCTAssertTrue(
            damagedReport.issues.contains {
                $0.kind == .catalogFileMismatch && $0.title == "章节索引包含重复 ID"
            }
        )

        let loadedProject = try XCTUnwrap(store.loadProjects(for: scope)?.first)
        XCTAssertEqual(loadedProject.chapterCatalog.map(\.id), [firstChapter.id, secondChapter.id])
        XCTAssertEqual(loadedProject.chapterCatalog.first?.chapterTitle, "较新标题")

        let loadedDrafts = store.loadChapterDrafts(for: project.id, scope: scope)
        XCTAssertEqual(loadedDrafts.map(\.id), [firstChapter.id, secondChapter.id])
        XCTAssertEqual(loadedDrafts.map(\.content), [firstChapter.content, secondChapter.content])

        try store.saveProjects([loadedProject], for: scope)

        let repairedIndex = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: chapterIndexURL))
                as? [String: Any]
        )
        let repairedChapterIDs = try XCTUnwrap(repairedIndex["chapterIDs"] as? [String])
        let repairedMetadata = try XCTUnwrap(repairedIndex["chapters"] as? [[String: Any]])
        XCTAssertEqual(Set(repairedChapterIDs), Set([firstChapter.id, secondChapter.id]))
        XCTAssertEqual(repairedChapterIDs.count, 2)
        XCTAssertEqual(
            Set(repairedMetadata.compactMap { $0["id"] as? String }),
            Set(repairedChapterIDs)
        )
        XCTAssertEqual(repairedMetadata.count, 2)

        let persistedDrafts = store.loadChapterDrafts(for: project.id, scope: scope)
        XCTAssertEqual(
            Dictionary(grouping: persistedDrafts, by: \.id)
                .mapValues { $0.map(\.content) },
            [
                firstChapter.id: [firstChapter.content],
                secondChapter.id: [secondChapter.content]
            ]
        )
        XCTAssertEqual(store.storageHealthReport(for: project.id, scope: scope).status, .passed)
    }

    func testDuplicateInMemoryChapterCatalogCanSaveAndRebuildWithoutLosingBody() throws {
        let chapter = ChapterDraft(
            id: "duplicate-memory-catalog-chapter",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "正文标题",
            content: "重建前后必须逐字保留的正文"
        )
        var project = NovelProject(
            id: "duplicate-memory-catalog-project",
            title: "重复内存目录",
            genre: "都市",
            summary: "摘要"
        )
        project.chapterDrafts = [chapter]
        try store.saveProjects([project], for: scope)

        var staleMetadata = ChapterDraftMetadata(chapterDraft: chapter)
        staleMetadata.chapterTitle = "过期 metadata"
        staleMetadata.savedAt = "1710000000.100"
        var newestMetadata = staleMetadata
        newestMetadata.chapterTitle = "应保留 metadata"
        newestMetadata.savedAt = "1720000000.200"
        var equalTimestampMetadata = newestMetadata
        equalTimestampMetadata.chapterTitle = "相同时间的后置 metadata"

        var duplicateCatalogProject = try XCTUnwrap(store.loadProjects(for: scope)?.first)
        duplicateCatalogProject.chapterCatalog = [
            staleMetadata,
            newestMetadata,
            equalTimestampMetadata
        ]
        try store.saveProjects([duplicateCatalogProject], for: scope)
        XCTAssertEqual(
            store.loadChapterDraft(chapter.id, for: project.id, scope: scope)?.content,
            chapter.content
        )

        duplicateCatalogProject.chapterCatalog = [
            staleMetadata,
            newestMetadata,
            equalTimestampMetadata
        ]
        let forcedRebuildIssue = ProjectStorageIssue(
            id: "forced-duplicate-memory-catalog-rebuild",
            kind: .catalogFileMismatch,
            status: .blocked,
            projectID: project.id,
            chapterID: nil,
            title: "强制重建重复目录",
            detail: "验证重复内存 chapterCatalog 不触发字典构造崩溃",
            recoveryActions: [.rebuildChapterCatalog]
        )
        _ = try store.recoverStorageIssue(
            forcedRebuildIssue,
            action: .rebuildChapterCatalog,
            project: duplicateCatalogProject,
            scope: scope
        )

        let rebuiltProject = try XCTUnwrap(store.loadProjects(for: scope)?.first)
        XCTAssertEqual(rebuiltProject.chapterCatalog.map(\.id), [chapter.id])
        XCTAssertEqual(rebuiltProject.chapterCatalog.first?.chapterTitle, "应保留 metadata")
        XCTAssertEqual(
            store.loadChapterDraft(chapter.id, for: project.id, scope: scope)?.content,
            chapter.content
        )
        XCTAssertEqual(store.loadChapterDrafts(for: project.id, scope: scope).map(\.id), [chapter.id])
        XCTAssertEqual(store.storageHealthReport(for: project.id, scope: scope).status, .passed)
    }

    func testSanitizedChapterIDCollisionsRemainIsolatedAcrossRestartAndResave() throws {
        let firstChapter = ChapterDraft(
            id: "chapter/a",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "斜杠章节",
            content: "只属于 chapter/a 的正文"
        )
        let secondChapter = ChapterDraft(
            id: "chapter?a",
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "问号章节",
            content: "只属于 chapter?a 的正文"
        )
        var project = NovelProject(
            id: "chapter-path-collision-project",
            title: "章节路径碰撞",
            genre: "悬疑",
            summary: "摘要"
        )
        project.chapterDrafts = [firstChapter, secondChapter]

        try store.saveProjects([project], for: scope)

        let chapterFiles = allStoredFiles().filter {
            $0.path.contains("/chapters/")
                && $0.pathExtension == "json"
                && $0.lastPathComponent != "index.json"
        }
        XCTAssertEqual(chapterFiles.count, 2)
        XCTAssertEqual(Set(chapterFiles.map(\.lastPathComponent)).count, 2)
        XCTAssertTrue(chapterFiles.allSatisfy { $0.lastPathComponent.hasPrefix("chapter_a--") })

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: restartedStore
                    .loadChapterDrafts(for: project.id, scope: scope)
                    .map { ($0.id, $0.content) }
            ),
            [
                firstChapter.id: firstChapter.content,
                secondChapter.id: secondChapter.content
            ]
        )

        let restartedProjects = try XCTUnwrap(restartedStore.loadProjects(for: scope))
        try restartedStore.saveProjects(restartedProjects, for: scope)

        let secondRestartStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: secondRestartStore
                    .loadChapterDrafts(for: project.id, scope: scope)
                    .map { ($0.id, $0.content) }
            ),
            [
                firstChapter.id: firstChapter.content,
                secondChapter.id: secondChapter.content
            ]
        )
    }

    func testLegacySanitizedChapterFileMigratesToHashedPathWithoutLosingBody() throws {
        let chapter = ChapterDraft(
            id: "legacy/chapter",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "旧文件名章节",
            content: "旧 sanitized 文件中的正文"
        )
        var project = NovelProject(
            id: "legacy-chapter-file-project",
            title: "旧章节路径",
            genre: "都市",
            summary: "摘要"
        )
        project.chapterDrafts = [chapter]
        try store.saveProjects([project], for: scope)

        let canonicalURL = try XCTUnwrap(firstStoredChapterFile(for: chapter.id))
        let legacyURL = canonicalURL
            .deletingLastPathComponent()
            .appendingPathComponent("legacy_chapter.json")
        try FileManager.default.moveItem(at: canonicalURL, to: legacyURL)

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        let loadedProject = try XCTUnwrap(restartedStore.loadProjects(for: scope)?.first)
        XCTAssertEqual(
            restartedStore.loadChapterDraft(chapter.id, for: project.id, scope: scope)?.content,
            chapter.content
        )

        try restartedStore.saveProjects([loadedProject], for: scope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        let migratedURL = try XCTUnwrap(firstStoredChapterFile(for: chapter.id))
        XCTAssertTrue(migratedURL.lastPathComponent.hasPrefix("legacy_chapter--"))
        XCTAssertEqual(
            restartedStore.loadChapterDraft(chapter.id, for: project.id, scope: scope)?.content,
            chapter.content
        )
    }

    func testNewerLegacyChapterPayloadWinsAndMigratesToCanonicalPath() throws {
        var canonicalChapter = ChapterDraft(
            id: "dual-legacy-newer",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "canonical 旧正文"
        )
        canonicalChapter.savedAtDate = Date(timeIntervalSince1970: 1_710_000_000.101)
        var project = NovelProject(
            id: "dual-legacy-newer-project",
            title: "legacy 较新",
            genre: "悬疑",
            summary: "摘要"
        )
        project.chapterDrafts = [canonicalChapter]
        try store.saveProjects([project], for: scope)

        let canonicalURL = try XCTUnwrap(firstStoredChapterFile(for: canonicalChapter.id))
        let legacyURL = canonicalURL.deletingLastPathComponent()
            .appendingPathComponent("\(canonicalChapter.id).json")
        var legacyChapter = canonicalChapter
        legacyChapter.content = "legacy 较新正文"
        legacyChapter.savedAtDate = Date(timeIntervalSince1970: 1_720_000_000.202)
        var legacyPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacyChapter)
            ) as? [String: Any]
        )
        legacyPayload["updatedAt"] = legacyPayload.removeValue(forKey: "savedAt")
        try JSONSerialization.data(withJSONObject: legacyPayload).write(to: legacyURL)

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        XCTAssertEqual(
            restartedStore.loadChapterDraft(
                canonicalChapter.id,
                for: project.id,
                scope: scope
            )?.content,
            legacyChapter.content
        )

        let loadedProjects = try XCTUnwrap(restartedStore.loadProjects(for: scope))
        try restartedStore.saveProjects(loadedProjects, for: scope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        let migrated = try JSONDecoder().decode(
            ChapterDraft.self,
            from: Data(contentsOf: canonicalURL)
        )
        XCTAssertEqual(migrated.content, legacyChapter.content)
        XCTAssertEqual(
            restartedStore.loadChapterDraft(
                canonicalChapter.id,
                for: project.id,
                scope: scope
            )?.savedAtDate,
            legacyChapter.savedAtDate
        )
        XCTAssertEqual(
            restartedStore.loadProjects(for: scope)?.first?.chapterCatalog.first?.savedAtDate,
            legacyChapter.savedAtDate
        )
    }

    func testNewerCanonicalChapterPayloadWinsBeforeLegacyCleanup() throws {
        var canonicalChapter = ChapterDraft(
            id: "dual-canonical-newer",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "canonical 较新正文"
        )
        canonicalChapter.savedAtDate = Date(timeIntervalSince1970: 1_720_000_000.202)
        var project = NovelProject(
            id: "dual-canonical-newer-project",
            title: "canonical 较新",
            genre: "悬疑",
            summary: "摘要"
        )
        project.chapterDrafts = [canonicalChapter]
        try store.saveProjects([project], for: scope)

        let canonicalURL = try XCTUnwrap(firstStoredChapterFile(for: canonicalChapter.id))
        let canonicalData = try Data(contentsOf: canonicalURL)
        let legacyURL = canonicalURL.deletingLastPathComponent()
            .appendingPathComponent("\(canonicalChapter.id).json")
        var legacyChapter = canonicalChapter
        legacyChapter.content = "legacy 旧正文"
        legacyChapter.savedAtDate = Date(timeIntervalSince1970: 1_710_000_000.101)
        try JSONEncoder().encode(legacyChapter).write(to: legacyURL)

        XCTAssertEqual(
            store.loadChapterDraft(
                canonicalChapter.id,
                for: project.id,
                scope: scope
            )?.content,
            canonicalChapter.content
        )
        let loadedProjects = try XCTUnwrap(store.loadProjects(for: scope))
        try store.saveProjects(loadedProjects, for: scope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try Data(contentsOf: canonicalURL), canonicalData)
        XCTAssertEqual(
            store.loadChapterDraft(
                canonicalChapter.id,
                for: project.id,
                scope: scope
            )?.content,
            canonicalChapter.content
        )
    }

    func testEqualTimestampDifferentChapterPayloadsFailClosedAndRemainRecoverable() throws {
        let sharedTimestamp = Date(timeIntervalSince1970: 1_720_000_000.202)
        var canonicalChapter = ChapterDraft(
            id: "dual-equal-conflict",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "canonical 冲突正文"
        )
        canonicalChapter.savedAtDate = sharedTimestamp
        var project = NovelProject(
            id: "dual-equal-conflict-project",
            title: "相等时间冲突",
            genre: "悬疑",
            summary: "摘要"
        )
        project.chapterDrafts = [canonicalChapter]
        try store.saveProjects([project], for: scope)

        let canonicalURL = try XCTUnwrap(firstStoredChapterFile(for: canonicalChapter.id))
        let canonicalData = try Data(contentsOf: canonicalURL)
        let legacyURL = canonicalURL.deletingLastPathComponent()
            .appendingPathComponent("\(canonicalChapter.id).json")
        var legacyChapter = canonicalChapter
        legacyChapter.content = "legacy 冲突正文"
        let legacyData = try JSONEncoder().encode(legacyChapter)
        try legacyData.write(to: legacyURL)

        XCTAssertNil(
            store.loadChapterDraft(
                canonicalChapter.id,
                for: project.id,
                scope: scope
            )
        )
        let conflictIssue = try XCTUnwrap(
            store.storageHealthReport(for: project.id, scope: scope)
                .issues.first {
                    $0.kind == .chapterFileCorrupt
                        && $0.chapterID == canonicalChapter.id
                }
        )
        XCTAssertEqual(conflictIssue.status, .blocked)
        XCTAssertEqual(conflictIssue.recoveryActions, [.exportDiagnostics])
        XCTAssertTrue(conflictIssue.detail.contains("savedAt/updatedAt 相同"))

        let loadedProjects = try XCTUnwrap(store.loadProjects(for: scope))
        XCTAssertThrowsError(try store.saveProjects(loadedProjects, for: scope))
        XCTAssertEqual(try Data(contentsOf: canonicalURL), canonicalData)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
        XCTAssertFalse(
            allStoredFiles().contains {
                $0.lastPathComponent == ".pending-project-transaction.json"
            }
        )
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

        let chapterURL = try XCTUnwrap(firstStoredChapterFile(for: chapter.id))
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

        let chapterURL = try XCTUnwrap(firstStoredChapterFile(for: chapter.id))
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

        let chapterURL = try XCTUnwrap(firstStoredChapterFile(for: chapter.id))
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

    func testDiagnosticAndConflictArtifactsDoNotCollideOrOverwriteRepeatedExports() throws {
        let firstIssue = ProjectStorageIssue(
            id: "artifact-first",
            kind: .cloudSelectionConflict,
            status: .warning,
            projectID: "artifact/a",
            chapterID: nil,
            title: "第一个碰撞项目",
            detail: "诊断与冲突产物必须独立",
            recoveryActions: [.exportDiagnostics, .markCloudConflict]
        )
        let secondIssue = ProjectStorageIssue(
            id: "artifact-second",
            kind: .cloudSelectionConflict,
            status: .warning,
            projectID: "artifact?a",
            chapterID: nil,
            title: "第二个碰撞项目",
            detail: "诊断与冲突产物必须独立",
            recoveryActions: [.exportDiagnostics, .markCloudConflict]
        )

        let firstDiagnostic = try XCTUnwrap(
            store.recoverStorageIssue(
                firstIssue,
                action: .exportDiagnostics,
                project: nil,
                scope: scope
            ).outputURL
        )
        let repeatedDiagnostic = try XCTUnwrap(
            store.recoverStorageIssue(
                firstIssue,
                action: .exportDiagnostics,
                project: nil,
                scope: scope
            ).outputURL
        )
        let secondDiagnostic = try XCTUnwrap(
            store.recoverStorageIssue(
                secondIssue,
                action: .exportDiagnostics,
                project: nil,
                scope: scope
            ).outputURL
        )
        let firstConflict = try XCTUnwrap(
            store.recoverStorageIssue(
                firstIssue,
                action: .markCloudConflict,
                project: nil,
                scope: scope
            ).outputURL
        )
        let repeatedConflict = try XCTUnwrap(
            store.recoverStorageIssue(
                firstIssue,
                action: .markCloudConflict,
                project: nil,
                scope: scope
            ).outputURL
        )
        let secondConflict = try XCTUnwrap(
            store.recoverStorageIssue(
                secondIssue,
                action: .markCloudConflict,
                project: nil,
                scope: scope
            ).outputURL
        )

        let artifactURLs = [
            firstDiagnostic,
            repeatedDiagnostic,
            secondDiagnostic,
            firstConflict,
            repeatedConflict,
            secondConflict
        ]
        XCTAssertEqual(Set(artifactURLs.map(\.path)).count, artifactURLs.count)
        XCTAssertTrue(artifactURLs.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
                && $0.lastPathComponent.contains("artifact_a--")
        })
        XCTAssertEqual(
            try JSONDecoder()
                .decode(StorageHealthReport.self, from: Data(contentsOf: firstDiagnostic))
                .projectID,
            firstIssue.projectID
        )
        XCTAssertEqual(
            try JSONDecoder()
                .decode(StorageHealthReport.self, from: Data(contentsOf: secondDiagnostic))
                .projectID,
            secondIssue.projectID
        )
        XCTAssertEqual(
            try JSONDecoder()
                .decode(ProjectStorageIssue.self, from: Data(contentsOf: firstConflict))
                .projectID,
            firstIssue.projectID
        )
        XCTAssertEqual(
            try JSONDecoder()
                .decode(ProjectStorageIssue.self, from: Data(contentsOf: secondConflict))
                .projectID,
            secondIssue.projectID
        )
    }

    func testRecoveryBackupsSeparateCollidingProjectIDsAndPreserveRepeatedCopies() throws {
        let sharedChapterID = "shared-backup-chapter"
        let firstChapter = ChapterDraft(
            id: sharedChapterID,
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "斜杠项目章节",
            content: "第一份正文"
        )
        let secondChapter = ChapterDraft(
            id: sharedChapterID,
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "问号项目章节",
            content: "第二份正文"
        )
        var firstProject = NovelProject(
            id: "backup/a",
            title: "斜杠备份项目",
            genre: "都市",
            summary: "摘要"
        )
        firstProject.chapterDrafts = [firstChapter]
        var secondProject = NovelProject(
            id: "backup?a",
            title: "问号备份项目",
            genre: "科幻",
            summary: "摘要"
        )
        secondProject.chapterDrafts = [secondChapter]
        try store.saveProjects([firstProject, secondProject], for: scope)

        let firstChapterURL = try XCTUnwrap(
            firstStoredChapterFile(for: sharedChapterID, projectID: firstProject.id)
        )
        let secondChapterURL = try XCTUnwrap(
            firstStoredChapterFile(for: sharedChapterID, projectID: secondProject.id)
        )
        try Data("first corrupt payload".utf8).write(to: firstChapterURL)
        try Data("second corrupt payload".utf8).write(to: secondChapterURL)

        let firstIssue = try XCTUnwrap(
            store.storageHealthReport(for: firstProject.id, scope: scope)
                .issues.first { $0.kind == .chapterFileCorrupt }
        )
        let secondIssue = try XCTUnwrap(
            store.storageHealthReport(for: secondProject.id, scope: scope)
                .issues.first { $0.kind == .chapterFileCorrupt }
        )
        let firstBackup = try XCTUnwrap(
            store.recoverStorageIssue(
                firstIssue,
                action: .preserveMissingChapterPlaceholder,
                project: firstProject,
                scope: scope
            ).outputURL
        )
        let secondBackup = try XCTUnwrap(
            store.recoverStorageIssue(
                secondIssue,
                action: .preserveMissingChapterPlaceholder,
                project: secondProject,
                scope: scope
            ).outputURL
        )

        XCTAssertNotEqual(
            firstBackup.deletingLastPathComponent(),
            secondBackup.deletingLastPathComponent()
        )
        XCTAssertTrue(
            firstBackup.deletingLastPathComponent().lastPathComponent.hasPrefix("backup_a--")
        )
        XCTAssertTrue(
            secondBackup.deletingLastPathComponent().lastPathComponent.hasPrefix("backup_a--")
        )
        XCTAssertEqual(
            try String(contentsOf: firstBackup, encoding: .utf8),
            "first corrupt payload"
        )
        XCTAssertEqual(
            try String(contentsOf: secondBackup, encoding: .utf8),
            "second corrupt payload"
        )

        try Data("repeated corrupt payload".utf8).write(to: firstChapterURL)
        let repeatedIssue = try XCTUnwrap(
            store.storageHealthReport(for: firstProject.id, scope: scope)
                .issues.first { $0.kind == .chapterFileCorrupt }
        )
        let repeatedBackup = try XCTUnwrap(
            store.recoverStorageIssue(
                repeatedIssue,
                action: .preserveMissingChapterPlaceholder,
                project: firstProject,
                scope: scope
            ).outputURL
        )

        XCTAssertNotEqual(firstBackup, repeatedBackup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstBackup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repeatedBackup.path))
        XCTAssertEqual(
            try String(contentsOf: repeatedBackup, encoding: .utf8),
            "repeated corrupt payload"
        )
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

    func testLoadReportSurfacesFutureProjectDocumentAndKeepsHealthyProjects() throws {
        let healthyProject = NovelProject(
            id: "healthy-current-project",
            title: "当前版本项目",
            genre: "都市",
            summary: "摘要"
        )
        let futureProject = NovelProject(
            id: "future-version-project",
            title: "未来版本项目",
            genre: "科幻",
            summary: "摘要"
        )
        try store.saveProjects([healthyProject, futureProject], for: scope)

        let futureMetadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(futureProject.id)
        })
        var futureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: futureMetadataURL)) as? [String: Any]
        )
        let futureVersion = NovelProject.currentSchemaVersion + 1
        futureObject["schemaVersion"] = futureVersion
        try JSONSerialization.data(
            withJSONObject: futureObject,
            options: [.sortedKeys]
        ).write(to: futureMetadataURL)

        let report = try XCTUnwrap(store.loadProjectsReport(for: scope))
        XCTAssertEqual(report.projects.map(\.id), [healthyProject.id])
        XCTAssertEqual(report.unsupportedFutureProjectCount, 1)

        let issue = try XCTUnwrap(report.issues.first)
        XCTAssertEqual(issue.kind, .unsupportedFutureProjectDocument)
        XCTAssertEqual(issue.scope, scope)
        XCTAssertEqual(issue.projectID, futureProject.id)
        XCTAssertEqual(
            URL(fileURLWithPath: issue.path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path,
            futureMetadataURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
        )
        XCTAssertEqual(issue.sourceVersion, futureVersion)
        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [healthyProject.id])
    }

    func testIncomingCurrentProjectDoesNotOverwriteFutureShardedDocument() throws {
        var futureProject = NovelProject(
            id: "future-protected-project",
            title: "未来版本",
            genre: "科幻",
            summary: "必须原字节保留"
        )
        futureProject.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.111)
        try store.saveProjects([futureProject], for: scope)

        let metadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(futureProject.id)
        })
        var futureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any]
        )
        futureObject["schemaVersion"] = NovelProject.currentSchemaVersion + 1
        futureObject["futureOnlyField"] = "preserve-me"
        let futureData = try JSONSerialization.data(
            withJSONObject: futureObject,
            options: [.sortedKeys]
        )
        try futureData.write(to: metadataURL)

        var incoming = NovelProject(
            id: futureProject.id,
            title: "当前版本覆盖",
            genre: futureProject.genre,
            summary: "即使时间更新也不得覆盖"
        )
        incoming.updatedAtDate = Date(timeIntervalSince1970: 1_720_000_000.222)
        try store.saveProjects([incoming], for: scope)

        XCTAssertEqual(try Data(contentsOf: metadataURL), futureData)
        let report = try XCTUnwrap(store.loadProjectsReport(for: scope))
        XCTAssertTrue(report.projects.isEmpty)
        XCTAssertEqual(report.unsupportedFutureProjectCount, 1)
    }

    @MainActor
    func testAppStatePublishesAndClearsScopeLevelFutureProjectWarning() throws {
        let healthyProject = NovelProject(
            id: "app-state-healthy-project",
            title: "当前项目",
            genre: "都市",
            summary: "摘要"
        )
        let futureProject = NovelProject(
            id: "app-state-future-project",
            title: "未来项目",
            genre: "科幻",
            summary: "摘要"
        )
        try store.saveProjects([healthyProject, futureProject], for: nil)

        let futureMetadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(futureProject.id)
        })
        var futureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: futureMetadataURL)) as? [String: Any]
        )
        futureObject["schemaVersion"] = NovelProject.currentSchemaVersion + 1
        try JSONSerialization.data(
            withJSONObject: futureObject,
            options: [.sortedKeys]
        ).write(to: futureMetadataURL)

        let defaultsSuiteName = "ProjectFileStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let appState = AppState(
            userDefaults: defaults,
            projectStore: store,
            credentialStore: InMemoryCredentialStore()
        )

        XCTAssertEqual(appState.recentProjects.map(\.id), [healthyProject.id])
        XCTAssertEqual(appState.unsupportedFutureProjectCount, 1)
        XCTAssertEqual(
            appState.projectLoadWarningMessage,
            "有 1 个项目由更高版本的 OpenWriting 创建，请更新应用后再打开。"
        )

        futureObject["schemaVersion"] = NovelProject.currentSchemaVersion
        try JSONSerialization.data(
            withJSONObject: futureObject,
            options: [.sortedKeys]
        ).write(to: futureMetadataURL)
        appState.reloadAccountScopedProjects()

        XCTAssertTrue(appState.projectLoadIssues.isEmpty)
        XCTAssertNil(appState.projectLoadWarningMessage)
        XCTAssertEqual(
            Set(appState.recentProjects.map(\.id)),
            Set([healthyProject.id, futureProject.id])
        )
    }

    func testFutureProjectIndexVersionFailsClosedAndRejectsRecoveryWrites() async throws {
        let project = NovelProject(title: "未来索引项目", genre: "科幻", summary: "摘要")
        try store.saveProjects([project], for: scope)

        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        let metadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(project.id)
        })
        let originalMetadataData = try Data(contentsOf: metadataURL)
        var indexObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        )
        indexObject["version"] = 999
        indexObject["futureOnlyField"] = "preserve-me"
        let futureIndexData = try JSONSerialization.data(
            withJSONObject: indexObject,
            options: [.sortedKeys]
        )
        try futureIndexData.write(to: indexURL)

        let loaded = try XCTUnwrap(store.loadProjects(for: scope))
        XCTAssertTrue(loaded.isEmpty)
        let futureIssue = try XCTUnwrap(
            store.storageHealthReport(for: project.id, scope: scope)
                .issues.first { $0.kind == .projectIndexCorrupt }
        )
        XCTAssertEqual(futureIssue.recoveryActions, [.exportDiagnostics])
        XCTAssertTrue(futureIssue.title.contains("版本过新"))

        XCTAssertThrowsError(
            try store.saveProjects(loaded, for: scope)
        )
        let forcedRecoveryIssue = ProjectStorageIssue(
            id: "forced-future-project-index-recovery",
            kind: .projectIndexCorrupt,
            status: .blocked,
            projectID: project.id,
            chapterID: nil,
            title: "强制恢复",
            detail: "验证底层写保护",
            recoveryActions: [.recoverMetadataShell]
        )
        XCTAssertThrowsError(
            try store.recoverStorageIssue(
                forcedRecoveryIssue,
                action: .recoverMetadataShell,
                project: project,
                scope: scope
            )
        )
        XCTAssertEqual(try Data(contentsOf: indexURL), futureIndexData)
        XCTAssertEqual(try Data(contentsOf: metadataURL), originalMetadataData)
        XCTAssertTrue(try XCTUnwrap(store.loadProjects(for: scope)).isEmpty)
    }

    func testDuplicateShardedProjectIDsAreNormalizedBeforeSave() throws {
        let project = NovelProject(
            id: "duplicate-index-project",
            title: "重复索引项目",
            genre: "悬疑",
            summary: "摘要"
        )
        try store.saveProjects([project], for: scope)
        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        var indexObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        )
        indexObject["projectIDs"] = [project.id, project.id, project.id]
        try JSONSerialization.data(
            withJSONObject: indexObject,
            options: [.sortedKeys]
        ).write(to: indexURL)

        let loadedProjects = try XCTUnwrap(store.loadProjects(for: scope))
        XCTAssertEqual(loadedProjects.map(\.id), [project.id])
        guard loadedProjects.count == 1 else { return }

        try store.saveProjects(loadedProjects, for: scope)

        let repairedIndex = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        )
        XCTAssertEqual(repairedIndex["projectIDs"] as? [String], [project.id])
    }

    func testDuplicateIncomingProjectIDsPersistOnlyNewestVersion() throws {
        var olderProject = NovelProject(
            id: "duplicate-incoming-project",
            title: "旧版本",
            genre: "悬疑",
            summary: "不应保留"
        )
        olderProject.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.111)
        var newerProject = NovelProject(
            id: olderProject.id,
            title: "新版本",
            genre: "悬疑",
            summary: "应当保留"
        )
        newerProject.updatedAtDate = Date(timeIntervalSince1970: 1_720_000_000.222)

        try store.saveProjects([olderProject, newerProject], for: scope)

        let loadedProjects = try XCTUnwrap(store.loadProjects(for: scope))
        XCTAssertEqual(loadedProjects.map(\.id), [newerProject.id])
        XCTAssertEqual(loadedProjects.first?.title, newerProject.title)
        XCTAssertEqual(loadedProjects.first?.summary, newerProject.summary)
        XCTAssertEqual(loadedProjects.first?.updatedAtDate, newerProject.updatedAtDate)

        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        let indexObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        )
        XCTAssertEqual(indexObject["projectIDs"] as? [String], [newerProject.id])
    }

    func testSanitizedProjectIDCollisionsRemainIsolatedAcrossRestartAndResave() throws {
        let firstChapter = ChapterDraft(
            id: "collision-first-chapter",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "斜杠项目章节",
            content: "只属于 a/b 的正文"
        )
        let secondChapter = ChapterDraft(
            id: "collision-second-chapter",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "问号项目章节",
            content: "只属于 a?b 的正文"
        )
        var firstProject = NovelProject(
            id: "a/b",
            title: "斜杠项目",
            genre: "悬疑",
            summary: "第一个碰撞项目"
        )
        firstProject.chapterDrafts = [firstChapter]
        var secondProject = NovelProject(
            id: "a?b",
            title: "问号项目",
            genre: "科幻",
            summary: "第二个碰撞项目"
        )
        secondProject.chapterDrafts = [secondChapter]

        try store.saveProjects([firstProject, secondProject], for: scope)

        let metadataDirectories = Set(
            storedFiles(named: "project.json").map {
                $0.deletingLastPathComponent().lastPathComponent
            }
        )
        XCTAssertEqual(metadataDirectories.count, 2)
        XCTAssertTrue(metadataDirectories.allSatisfy { $0.hasPrefix("a_b--") })

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        let restartedProjects = try XCTUnwrap(restartedStore.loadProjects(for: scope))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: restartedProjects.map { ($0.id, $0.title) }),
            [
                firstProject.id: firstProject.title,
                secondProject.id: secondProject.title
            ]
        )
        XCTAssertEqual(
            restartedStore.loadChapterDraft(
                firstChapter.id,
                for: firstProject.id,
                scope: scope
            )?.content,
            firstChapter.content
        )
        XCTAssertEqual(
            restartedStore.loadChapterDraft(
                secondChapter.id,
                for: secondProject.id,
                scope: scope
            )?.content,
            secondChapter.content
        )

        try restartedStore.saveProjects(restartedProjects, for: scope)

        let secondRestartStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        XCTAssertEqual(
            Set(secondRestartStore.loadProjects(for: scope)?.map(\.id) ?? []),
            Set([firstProject.id, secondProject.id])
        )
        XCTAssertEqual(
            secondRestartStore.loadChapterDraft(
                firstChapter.id,
                for: firstProject.id,
                scope: scope
            )?.content,
            firstChapter.content
        )
        XCTAssertEqual(
            secondRestartStore.loadChapterDraft(
                secondChapter.id,
                for: secondProject.id,
                scope: scope
            )?.content,
            secondChapter.content
        )
    }

    func testLegacySanitizedProjectDirectoryMigratesToHashedPathWithoutLosingChapter() throws {
        let chapter = ChapterDraft(
            id: "legacy-path-chapter",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "旧路径章节",
            content: "旧 sanitized 目录中的正文"
        )
        var project = NovelProject(
            id: "legacy/path",
            title: "旧路径项目",
            genre: "都市",
            summary: "摘要"
        )
        project.chapterDrafts = [chapter]
        try store.saveProjects([project], for: scope)

        let metadataURL = try XCTUnwrap(storedFiles(named: "project.json").first)
        let canonicalDirectory = metadataURL.deletingLastPathComponent()
        let legacyDirectory = canonicalDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("legacy_path", isDirectory: true)
        try FileManager.default.moveItem(at: canonicalDirectory, to: legacyDirectory)

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        let loadedProject = try XCTUnwrap(restartedStore.loadProjects(for: scope)?.first)
        XCTAssertEqual(loadedProject.id, project.id)
        XCTAssertEqual(
            restartedStore.loadChapterDraft(chapter.id, for: project.id, scope: scope)?.content,
            chapter.content
        )

        try restartedStore.saveProjects([loadedProject], for: scope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
        let migratedMetadataURL = try XCTUnwrap(storedFiles(named: "project.json").first)
        XCTAssertNotEqual(
            migratedMetadataURL.deletingLastPathComponent().lastPathComponent,
            legacyDirectory.lastPathComponent
        )
        XCTAssertEqual(
            restartedStore.loadChapterDraft(chapter.id, for: project.id, scope: scope)?.content,
            chapter.content
        )
    }

    func testStaleIncomingProjectDoesNotOverwriteNewerShardedDocument() throws {
        var newerProject = NovelProject(
            id: "newer-sharded-project",
            title: "磁盘新版本",
            genre: "悬疑",
            summary: "必须保留"
        )
        newerProject.updatedAtDate = Date(timeIntervalSince1970: 1_720_000_000.222)
        try store.saveProjects([newerProject], for: scope)
        let metadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(newerProject.id)
        })
        let newerData = try Data(contentsOf: metadataURL)

        var staleIncoming = NovelProject(
            id: newerProject.id,
            title: "过期内存快照",
            genre: newerProject.genre,
            summary: "不得覆盖磁盘"
        )
        staleIncoming.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.111)
        try store.saveProjects([staleIncoming], for: scope)

        XCTAssertEqual(try Data(contentsOf: metadataURL), newerData)
        let loaded = try XCTUnwrap(store.loadProjects(for: scope))
        XCTAssertEqual(loaded.map(\.id), [newerProject.id])
        XCTAssertEqual(loaded.first?.title, newerProject.title)
        XCTAssertEqual(loaded.first?.summary, newerProject.summary)
        XCTAssertEqual(loaded.first?.updatedAtDate, newerProject.updatedAtDate)
    }

    func testEqualTimestampIncomingProjectOverwritesStoredSnapshot() throws {
        let sharedTimestamp = Date(timeIntervalSince1970: 1_772_500_000.125)
        var stored = NovelProject(
            id: "equal-timestamp-save",
            title: "同时间保存",
            genre: "悬疑",
            summary: "摘要"
        )
        stored.draftText = "Z-old-disk-value"
        stored.updatedAtDate = sharedTimestamp
        try store.saveProjects([stored], for: scope)

        var incoming = stored
        incoming.draftText = "A-new-memory-value"
        try store.saveProjects([incoming], for: scope)

        let loaded = try XCTUnwrap(store.loadProjects(for: scope)?.first)
        XCTAssertEqual(loaded.draftText, incoming.draftText)
        XCTAssertEqual(loaded.updatedAtDate, sharedTimestamp)
    }

    func testLegacyProjectArrayRecoversValidElementsIndependently() throws {
        let seed = NovelProject(title: "路径种子", genre: "都市", summary: "摘要")
        try store.saveProjects([seed], for: scope)
        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        let projectStoreRoot = indexURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let legacyScope = "legacy-partial"
        let legacyScopeURL = projectStoreRoot.appendingPathComponent(
            "account-\(legacyScope)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyScopeURL,
            withIntermediateDirectories: true
        )

        let validProject = NovelProject(
            id: "legacy-valid",
            title: "可恢复项目",
            genre: "悬疑",
            summary: "摘要"
        )
        let validObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(validProject))
                as? [String: Any]
        )
        let corruptObject: [String: Any] = [
            "schemaVersion": NovelProject.currentSchemaVersion + 1,
            "id": "legacy-corrupt",
            "title": "未来格式"
        ]
        let legacyData = try JSONSerialization.data(
            withJSONObject: [validObject, corruptObject],
            options: [.sortedKeys]
        )
        try legacyData.write(
            to: legacyScopeURL.appendingPathComponent("projects.json")
        )

        let report = try XCTUnwrap(store.loadProjectsReport(for: legacyScope))
        XCTAssertEqual(report.projects.map(\.id), [validProject.id])
        XCTAssertEqual(report.unsupportedFutureProjectCount, 1)

        let issue = try XCTUnwrap(report.issues.first)
        XCTAssertEqual(issue.kind, .unsupportedFutureProjectDocument)
        XCTAssertEqual(issue.scope, legacyScope)
        XCTAssertEqual(issue.projectID, "legacy-corrupt")
        XCTAssertTrue(
            issue.path.hasSuffix(
                "/account-\(legacyScope)/projects.json"
            )
        )
        XCTAssertEqual(
            issue.sourceVersion,
            NovelProject.currentSchemaVersion + 1
        )
        XCTAssertEqual(store.loadProjects(for: legacyScope)?.map(\.id), [validProject.id])
    }

    func testLegacyFutureProjectSurvivesMigrationSaveUntilItBecomesSupported() throws {
        let seed = NovelProject(title: "路径种子", genre: "都市", summary: "摘要")
        try store.saveProjects([seed], for: scope)
        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        let projectStoreRoot = indexURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let legacyScope = "legacy-future-preservation"
        let legacyScopeURL = projectStoreRoot.appendingPathComponent(
            "account-\(legacyScope)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyScopeURL,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyScopeURL.appendingPathComponent("projects.json")

        let healthyProject = NovelProject(
            id: "legacy-healthy",
            title: "当前项目",
            genre: "悬疑",
            summary: "摘要"
        )
        let futureProject = NovelProject(
            id: "legacy-future",
            title: "未来项目",
            genre: "科幻",
            summary: "未来数据必须保留"
        )
        let healthyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(healthyProject))
                as? [String: Any]
        )
        var futureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(futureProject))
                as? [String: Any]
        )
        futureObject["schemaVersion"] = NovelProject.currentSchemaVersion + 1
        futureObject["futureOnlyField"] = "preserve-me"
        try JSONSerialization.data(
            withJSONObject: [healthyObject, futureObject],
            options: [.sortedKeys]
        ).write(to: legacyURL)

        let initialReport = try XCTUnwrap(store.loadProjectsReport(for: legacyScope))
        XCTAssertEqual(initialReport.projects.map(\.id), [healthyProject.id])
        XCTAssertEqual(initialReport.unsupportedFutureProjectCount, 1)

        try store.saveProjects(initialReport.projects, for: legacyScope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        let preservedLegacyURL = try XCTUnwrap(
            storedFiles(named: "projects.json").first {
                $0.path.contains("/account-\(legacyScope)")
            }
        )
        let preservedElements = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: preservedLegacyURL)
            ) as? [[String: Any]]
        )
        XCTAssertEqual(
            preservedElements.first { $0["id"] as? String == futureProject.id }?["futureOnlyField"] as? String,
            "preserve-me"
        )
        let reportAfterSave = try XCTUnwrap(store.loadProjectsReport(for: legacyScope))
        XCTAssertEqual(reportAfterSave.projects.map(\.id), [healthyProject.id])
        XCTAssertEqual(reportAfterSave.unsupportedFutureProjectCount, 1)

        futureObject["schemaVersion"] = NovelProject.currentSchemaVersion
        try JSONSerialization.data(
            withJSONObject: [healthyObject, futureObject],
            options: [.sortedKeys]
        ).write(to: preservedLegacyURL)

        let supportedReport = try XCTUnwrap(store.loadProjectsReport(for: legacyScope))
        XCTAssertEqual(
            Set(supportedReport.projects.map(\.id)),
            Set([healthyProject.id, futureProject.id])
        )
        XCTAssertTrue(supportedReport.issues.isEmpty)

        try store.saveProjects(supportedReport.projects, for: legacyScope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: preservedLegacyURL.path))
        XCTAssertEqual(
            Set(store.loadProjects(for: legacyScope)?.map(\.id) ?? []),
            Set([healthyProject.id, futureProject.id])
        )
    }

    func testStaleSameIDSavePersistsNewerLegacyVersionBeforeCleanup() throws {
        let seed = NovelProject(title: "路径种子", genre: "都市", summary: "摘要")
        try store.saveProjects([seed], for: scope)
        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        let projectStoreRoot = indexURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let legacyScope = "legacy-newer-same-id"
        let legacyScopeURL = projectStoreRoot.appendingPathComponent(
            "account-\(legacyScope)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyScopeURL,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyScopeURL.appendingPathComponent("projects.json")

        var newerLegacy = NovelProject(
            id: "same-id-project",
            title: "较新的旧版项目",
            genre: "科幻",
            summary: "必须保留的新版本"
        )
        newerLegacy.updatedAtDate = Date(timeIntervalSince1970: 1_720_000_000.222)
        try JSONSerialization.data(
            withJSONObject: [
                try XCTUnwrap(
                    JSONSerialization.jsonObject(with: JSONEncoder().encode(newerLegacy))
                        as? [String: Any]
                )
            ],
            options: [.sortedKeys]
        ).write(to: legacyURL)

        var staleIncoming = NovelProject(
            id: newerLegacy.id,
            title: "过期快照",
            genre: newerLegacy.genre,
            summary: "不得覆盖新版本"
        )
        staleIncoming.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.111)

        try store.saveProjects([staleIncoming], for: legacyScope)

        let persistedMetadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(newerLegacy.id)
        })
        let persistedProject = try ProjectDocumentCodec()
            .decode(Data(contentsOf: persistedMetadataURL))
            .project
        XCTAssertEqual(persistedProject.title, newerLegacy.title)
        XCTAssertEqual(persistedProject.summary, newerLegacy.summary)
        XCTAssertEqual(persistedProject.updatedAtDate, newerLegacy.updatedAtDate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))

        let loaded = try XCTUnwrap(store.loadProjects(for: legacyScope))
        XCTAssertEqual(loaded.map(\.id), [newerLegacy.id])
        XCTAssertEqual(loaded.first?.title, newerLegacy.title)
        XCTAssertEqual(loaded.first?.updatedAtDate, newerLegacy.updatedAtDate)
    }

    func testMalformedLegacyProjectIsPreservedDuringPartialMigration() throws {
        let seed = NovelProject(title: "路径种子", genre: "都市", summary: "摘要")
        try store.saveProjects([seed], for: scope)
        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        let projectStoreRoot = indexURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let legacyScope = "legacy-malformed-preservation"
        let legacyScopeURL = projectStoreRoot.appendingPathComponent(
            "account-\(legacyScope)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyScopeURL,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyScopeURL.appendingPathComponent("projects.json")
        let healthyProject = NovelProject(
            id: "legacy-readable",
            title: "可迁移项目",
            genre: "都市",
            summary: "摘要"
        )
        let healthyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(healthyProject))
                as? [String: Any]
        )
        let malformedObject: [String: Any] = [
            "schemaVersion": NovelProject.currentSchemaVersion,
            "id": "legacy-malformed"
        ]
        let originalData = try JSONSerialization.data(
            withJSONObject: [healthyObject, malformedObject],
            options: [.sortedKeys]
        )
        try originalData.write(to: legacyURL)

        let report = try XCTUnwrap(store.loadProjectsReport(for: legacyScope))
        XCTAssertEqual(report.projects.map(\.id), [healthyProject.id])
        XCTAssertTrue(report.issues.isEmpty)

        try store.saveProjects(report.projects, for: legacyScope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        let preservedLegacyURL = try XCTUnwrap(
            storedFiles(named: "projects.json").first {
                $0.path.contains("/account-\(legacyScope)")
            }
        )
        XCTAssertEqual(try Data(contentsOf: preservedLegacyURL), originalData)
        XCTAssertTrue(
            store.storageHealthReport(for: healthyProject.id, scope: legacyScope)
                .issues.contains { $0.kind == .legacyProjectFile }
        )
    }

    func testFutureChapterIndexVersionFailsClosedForCatalogDraftsAndRecoveryWrites() async throws {
        let chapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "正文"
        )
        var project = NovelProject(title: "未来章节索引项目", genre: "科幻", summary: "摘要")
        project.chapterDrafts = [chapter]
        try store.saveProjects([project], for: scope)

        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            $0.path.contains("/chapters/")
        })
        var indexObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        )
        indexObject["version"] = 999
        try JSONSerialization.data(withJSONObject: indexObject).write(to: indexURL)

        let report = store.storageHealthReport(for: project.id, scope: scope)
        let futureIssue = try XCTUnwrap(
            report.issues.first { $0.kind == .chapterIndexCorrupt }
        )
        XCTAssertEqual(futureIssue.recoveryActions, [.exportDiagnostics])
        XCTAssertTrue(futureIssue.title.contains("版本过新"))
        XCTAssertTrue(
            try XCTUnwrap(store.loadProjects(for: scope)?.first)
                .chapterCatalog.isEmpty
        )
        XCTAssertNil(
            store.loadChapterDraft(chapter.id, for: project.id, scope: scope)
        )
        XCTAssertTrue(
            store.loadChapterDrafts(for: project.id, scope: scope).isEmpty
        )

        let futureIndexData = try Data(contentsOf: indexURL)
        let metadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(project.id)
        })
        let originalMetadataData = try Data(contentsOf: metadataURL)
        let loaded = try XCTUnwrap(store.loadProjects(for: scope))
        XCTAssertThrowsError(
            try store.saveProjects(loaded, for: scope)
        )
        let forcedRecoveryIssue = ProjectStorageIssue(
            id: "forced-future-chapter-index-recovery",
            kind: .chapterIndexCorrupt,
            status: .blocked,
            projectID: project.id,
            chapterID: nil,
            title: "强制重建",
            detail: "验证底层写保护",
            recoveryActions: [.rebuildChapterCatalog]
        )
        XCTAssertThrowsError(
            try store.recoverStorageIssue(
                forcedRecoveryIssue,
                action: .rebuildChapterCatalog,
                project: project,
                scope: scope
            )
        )
        XCTAssertEqual(try Data(contentsOf: indexURL), futureIndexData)
        XCTAssertEqual(try Data(contentsOf: metadataURL), originalMetadataData)
        XCTAssertNil(
            store.loadChapterDraft(chapter.id, for: project.id, scope: scope)
        )
    }

    func testFutureChapterIndexPreflightKeepsEarlierProjectBytesUnchanged() throws {
        let retainedChapter = ChapterDraft(
            id: "chapter-retained",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "保留章节",
            content: "原始正文"
        )
        let removableChapter = ChapterDraft(
            id: "chapter-removable",
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "不得提前删除",
            content: "删除必须等待全局预检完成"
        )
        var firstProject = NovelProject(
            id: "project-preflight-first",
            title: "先写项目",
            genre: "科幻",
            summary: "摘要"
        )
        firstProject.chapterDrafts = [retainedChapter, removableChapter]

        let blockedChapter = ChapterDraft(
            id: "chapter-blocked",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "未来索引章节",
            content: "正文"
        )
        var blockedProject = NovelProject(
            id: "project-preflight-blocked",
            title: "后置阻断项目",
            genre: "悬疑",
            summary: "摘要"
        )
        blockedProject.chapterDrafts = [blockedChapter]
        try store.saveProjects([firstProject, blockedProject], for: scope)

        let blockedIndexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            $0.path.contains(blockedProject.id)
        })
        var blockedIndexObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: blockedIndexURL))
                as? [String: Any]
        )
        blockedIndexObject["version"] = 999
        try JSONSerialization.data(
            withJSONObject: blockedIndexObject,
            options: [.sortedKeys]
        ).write(to: blockedIndexURL)
        let bytesBeforeFailedSave = try storedFileContents()

        var updatedFirstProject = firstProject
        updatedFirstProject.draftText = "不得部分提交"
        updatedFirstProject.chapterDrafts = [retainedChapter]
        updatedFirstProject.chapterCatalog = [
            ChapterDraftMetadata(chapterDraft: retainedChapter)
        ]
        updatedFirstProject.updatedAtDate = firstProject.updatedAtDate.addingTimeInterval(60)

        XCTAssertThrowsError(
            try store.saveProjects(
                [updatedFirstProject, blockedProject],
                for: scope
            )
        )
        XCTAssertEqual(try storedFileContents(), bytesBeforeFailedSave)
    }

    func testEqualTimestampProjectTieBreakIsIndependentOfInputOrder() throws {
        let sharedTimestamp = Date(timeIntervalSince1970: 1_772_500_000.125)
        var first = NovelProject(
            id: "project-equal-timestamp",
            title: "相同时间",
            genre: "科幻",
            summary: "摘要"
        )
        first.draftText = "版本 A"
        first.updatedAtDate = sharedTimestamp
        var second = first
        second.draftText = "版本 B"

        try store.saveProjects([first, second], for: "tie-break-forward")
        try store.saveProjects([second, first], for: "tie-break-reverse")

        let forward = try XCTUnwrap(
            store.loadProjects(for: "tie-break-forward")?.first
        )
        let reverse = try XCTUnwrap(
            store.loadProjects(for: "tie-break-reverse")?.first
        )
        XCTAssertEqual(forward.draftText, reverse.draftText)

        let metadataFiles = storedFiles(named: "project.json").filter {
            $0.path.contains(first.id)
        }
        XCTAssertEqual(metadataFiles.count, 2)
        XCTAssertEqual(
            try Data(contentsOf: metadataFiles[0]),
            try Data(contentsOf: metadataFiles[1])
        )
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

    func testSavingLoadedProjectsPreservesDirectoryForCorruptMetadata() async throws {
        let healthyProject = NovelProject(title: "健康项目", genre: "都市", summary: "摘要")
        let corruptProject = NovelProject(title: "损坏项目", genre: "玄幻", summary: "摘要")
        try store.saveProjects([healthyProject, corruptProject], for: scope)

        let corruptMetadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(corruptProject.id)
        })
        let corruptProjectDirectory = corruptMetadataURL.deletingLastPathComponent()
        try Data("{ invalid json".utf8).write(to: corruptMetadataURL)

        let loadedProjects = try XCTUnwrap(store.loadProjects(for: scope))
        try store.saveProjects(loadedProjects, for: scope)

        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptProjectDirectory.path))
        XCTAssertEqual(try Data(contentsOf: corruptMetadataURL), Data("{ invalid json".utf8))
    }

    func testLegacySameIDDoesNotOverwriteCorruptShardedMetadata() throws {
        var project = NovelProject(
            id: "corrupt-sharded-with-legacy",
            title: "分片项目",
            genre: "玄幻",
            summary: "分片损坏后必须保留原证据"
        )
        project.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.111)
        try store.saveProjects([project], for: scope)

        let metadataURL = try XCTUnwrap(storedFiles(named: "project.json").first {
            $0.path.contains(project.id)
        })
        let corruptData = Data("{ invalid project".utf8)
        try corruptData.write(to: metadataURL)

        var legacyProject = NovelProject(
            id: project.id,
            title: "旧版副本",
            genre: project.genre,
            summary: "不得覆盖损坏分片"
        )
        legacyProject.updatedAtDate = Date(timeIntervalSince1970: 1_720_000_000.222)
        let legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyProject))
                as? [String: Any]
        )
        let malformedObject: [String: Any] = [
            "schemaVersion": NovelProject.currentSchemaVersion,
            "id": "malformed-preserved"
        ]
        let legacyURL = metadataURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("projects.json")
        try JSONSerialization.data(
            withJSONObject: [legacyObject, malformedObject],
            options: [.sortedKeys]
        ).write(to: legacyURL)

        let loaded = try XCTUnwrap(store.loadProjects(for: scope))
        try store.saveProjects(loaded, for: scope)

        XCTAssertEqual(try Data(contentsOf: metadataURL), corruptData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(store.loadProjects(for: scope)?.contains { $0.id == project.id } ?? true)
    }

    func testCorruptProjectIndexFollowedByEmptySavePreservesRecoverableProjects() async throws {
        let project = NovelProject(title: "索引损坏项目", genre: "悬疑", summary: "摘要")
        try store.saveProjects([project], for: scope)
        let projectIndexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        try Data("{ invalid index".utf8).write(to: projectIndexURL)

        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [project.id])
        XCTAssertThrowsError(
            try store.saveProjects([], for: scope)
        )

        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [project.id])
        XCTAssertNotNil(firstStoredFile(named: "project.json"))
    }

    func testValidIndexRequiresTombstoneBeforeRemovingHealthyProject() throws {
        let first = NovelProject(
            id: "project-first",
            title: "项目一",
            genre: "都市",
            summary: "摘要"
        )
        let second = NovelProject(
            id: "project-second",
            title: "项目二",
            genre: "玄幻",
            summary: "摘要"
        )
        try store.saveProjects([first, second], for: scope)

        // A stale partial snapshot and an unexpected empty snapshot are not
        // deletion authority when the existing index and payloads are healthy.
        try store.saveProjects([first], for: scope)
        XCTAssertEqual(
            Set(store.loadProjects(for: scope)?.map(\.id) ?? []),
            Set([first.id, second.id])
        )
        try store.saveProjects([], for: scope)
        XCTAssertEqual(
            Set(store.loadProjects(for: scope)?.map(\.id) ?? []),
            Set([first.id, second.id])
        )

        let secondDeletion = ProjectDeletionTombstone(
            projectID: second.id,
            deletedAt: Date.distantFuture
        )
        try store.saveProjects(
            [first],
            deletedProjects: [secondDeletion],
            for: scope
        )
        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [first.id])
        XCTAssertEqual(
            store.loadProjectDeletionTombstones(for: scope),
            [secondDeletion]
        )
    }

    func testCorruptChapterIndexFollowedBySavePreservesEveryChapter() async throws {
        let chapters = [
            ChapterDraft(volumeNumber: 1, chapterNumber: 1, chapterTitle: "第一章", content: "正文一"),
            ChapterDraft(volumeNumber: 1, chapterNumber: 2, chapterTitle: "第二章", content: "正文二")
        ]
        var project = NovelProject(title: "章节索引损坏项目", genre: "科幻", summary: "摘要")
        project.chapterDrafts = chapters
        try store.saveProjects([project], for: scope)
        let chapterIndexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            $0.path.contains("/chapters/")
        })
        try Data("{ invalid chapter index".utf8).write(to: chapterIndexURL)

        let loadedProject = try XCTUnwrap(store.loadProjects(for: scope)?.first)
        XCTAssertEqual(Set(loadedProject.chapterCatalog.map(\.id)), Set(chapters.map(\.id)))
        try store.saveProjects([loadedProject], for: scope)

        XCTAssertEqual(
            Set(store.loadChapterDrafts(for: project.id, scope: scope).map(\.id)),
            Set(chapters.map(\.id))
        )
    }

    func testChapterPayloadFailureDoesNotPublishNewIndexOrDeleteOldChapter() throws {
        let oldChapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "旧章节",
            content: "旧正文"
        )
        let newChapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "新章节",
            content: "新正文"
        )
        var project = NovelProject(title: "顺序测试", genre: "悬疑", summary: "摘要")
        project.chapterDrafts = [oldChapter]
        try store.saveProjects([project], for: scope)

        let chapterIndexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            $0.path.contains("/chapters/")
        })
        let oldChapterURL = try XCTUnwrap(firstStoredChapterFile(for: oldChapter.id))
        let originalIndexData = try Data(contentsOf: chapterIndexURL)
        let hookedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: "",
            testHooks: .init(
                beforeAtomicWrite: { url in
                    if url.path.contains("/chapters/"),
                       url.lastPathComponent.hasPrefix("\(newChapter.id)--") {
                        throw InjectedFailure.chapterWrite
                    }
                }
            )
        )
        project.chapterDrafts = [newChapter]
        project.chapterCatalog = [ChapterDraftMetadata(chapterDraft: newChapter)]

        XCTAssertThrowsError(try hookedStore.saveProjects([project], for: scope))
        XCTAssertEqual(try Data(contentsOf: chapterIndexURL), originalIndexData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldChapterURL.path))
        XCTAssertEqual(
            try JSONDecoder().decode(
                ChapterDraft.self,
                from: Data(contentsOf: oldChapterURL)
            ).id,
            oldChapter.id
        )
        let blockedLoad = try XCTUnwrap(hookedStore.loadProjectsReport(for: scope))
        XCTAssertTrue(blockedLoad.projects.isEmpty)
        XCTAssertEqual(
            blockedLoad.issues.map(\.kind),
            [.pendingTransactionRecoveryFailure]
        )
    }

    func testInterruptedMultiProjectSaveRecoversFromPendingTransaction() throws {
        var first = NovelProject(
            id: "transaction-first",
            title: "旧项目一",
            genre: "悬疑",
            summary: "旧摘要一"
        )
        var second = NovelProject(
            id: "transaction-second",
            title: "旧项目二",
            genre: "科幻",
            summary: "旧摘要二"
        )
        first.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.101)
        second.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.102)
        try store.saveProjects([first, second], for: scope)

        var updatedFirst = NovelProject(
            id: first.id,
            title: "新项目一",
            genre: first.genre,
            summary: first.summary
        )
        var updatedSecond = NovelProject(
            id: second.id,
            title: "新项目二",
            genre: second.genre,
            summary: second.summary
        )
        updatedFirst.updatedAtDate = Date(timeIntervalSince1970: 1_720_000_000.201)
        updatedSecond.updatedAtDate = Date(timeIntervalSince1970: 1_720_000_000.202)

        let interruptedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: "",
            testHooks: .init(beforeAtomicWrite: { url in
                if url.lastPathComponent == "project.json",
                   url.path.contains(second.id) {
                    throw InjectedFailure.chapterWrite
                }
            })
        )

        XCTAssertThrowsError(
            try interruptedStore.saveProjects([updatedFirst, updatedSecond], for: scope)
        )
        XCTAssertNotNil(firstStoredFile(named: ".pending-project-transaction.json"))

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        let recovered = try XCTUnwrap(restartedStore.loadProjects(for: scope))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: recovered.map { ($0.id, $0.title) }),
            [updatedFirst.id: "新项目一", updatedSecond.id: "新项目二"]
        )
        XCTAssertNil(firstStoredFile(named: ".pending-project-transaction.json"))
    }

    func testChapterPayloadWritesPrecedeIndexPublishAndCleanup() throws {
        let oldChapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "旧章节",
            content: "旧正文"
        )
        let newChapter = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "新章节",
            content: "新正文"
        )
        var project = NovelProject(title: "顺序测试", genre: "悬疑", summary: "摘要")
        project.chapterDrafts = [oldChapter]
        try store.saveProjects([project], for: scope)

        var events: [String] = []
        let hookedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: "",
            testHooks: .init(
                beforeAtomicWrite: { url in events.append("write:\(url.path)") },
                beforeRemoveItem: { url in events.append("remove:\(url.path)") }
            )
        )
        project.chapterDrafts = [newChapter]
        project.chapterCatalog = [ChapterDraftMetadata(chapterDraft: newChapter)]

        try hookedStore.saveProjects([project], for: scope)

        let payloadWrite = try XCTUnwrap(events.firstIndex {
            $0.hasPrefix("write:")
                && $0.contains("/chapters/\(newChapter.id)--")
        })
        let indexPublish = try XCTUnwrap(events.firstIndex {
            $0.hasPrefix("write:") && $0.hasSuffix("/chapters/index.json")
        })
        let oldPayloadRemoval = try XCTUnwrap(events.firstIndex {
            $0.hasPrefix("remove:")
                && $0.contains("/chapters/\(oldChapter.id)--")
        })
        XCTAssertLessThan(payloadWrite, indexPublish)
        XCTAssertLessThan(indexPublish, oldPayloadRemoval)
    }

    func testNewIdentifierCannotReuseLegacyTitleSlugOrCorruptProtectedDirectory() async throws {
        let legacyProject = NovelProject(
            id: "same-title",
            title: "Same Title",
            genre: "都市",
            summary: "旧项目"
        )
        try store.saveProjects([legacyProject], for: scope)
        let legacyMetadataURL = try XCTUnwrap(firstStoredFile(named: "project.json"))
        try Data("{ invalid project".utf8).write(to: legacyMetadataURL)

        let newID = NovelProject.makeStorageIdentifier()
        XCTAssertTrue(newID.hasPrefix("project-"))
        XCTAssertNotEqual(newID, legacyProject.id)
        let newProject = NovelProject(
            id: newID,
            title: "Same Title",
            genre: "都市",
            summary: "新项目"
        )
        try store.saveProjects([newProject], for: scope)

        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [newID])
        XCTAssertEqual(try Data(contentsOf: legacyMetadataURL), Data("{ invalid project".utf8))
    }

    @MainActor
    func testPersistenceActorDropsStaleSaveForSameScope() async throws {
        let actor = ProjectPersistenceActor(store: store.independentCopy())
        let staleProject = NovelProject(title: "旧快照", genre: "都市", summary: "摘要")
        let currentProject = NovelProject(title: "当前快照", genre: "都市", summary: "摘要")

        let staleSave = Task {
            try await actor.saveAfterDelay(
                [staleProject],
                for: scope,
                delay: .milliseconds(120)
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        try await actor.saveNow([currentProject], for: scope)

        let staleSaveDidWrite = try await staleSave.value
        XCTAssertFalse(staleSaveDidWrite)
        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.title), ["当前快照"])
    }

    @MainActor
    func testPersistenceActorCancelAndRemovePreventsDelayedSaveResurrection() async throws {
        let actor = ProjectPersistenceActor(store: store.independentCopy())
        let project = NovelProject(title: "待删除项目", genre: "都市", summary: "摘要")
        try await actor.saveNow([project], for: scope)

        let delayedSave = Task {
            try await actor.saveAfterDelay(
                [project],
                for: scope,
                delay: .milliseconds(120)
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        try await actor.cancelAndRemove(for: scope)

        let delayedSaveDidWrite = try await delayedSave.value
        XCTAssertFalse(delayedSaveDidWrite)
        XCTAssertNil(store.loadProjects(for: scope))
    }

    @MainActor
    func testPersistenceActorKeepsScopeGenerationsIndependent() async throws {
        let actor = ProjectPersistenceActor(store: store.independentCopy())
        let firstProject = NovelProject(title: "账号一", genre: "都市", summary: "摘要")
        let secondProject = NovelProject(title: "账号二", genre: "玄幻", summary: "摘要")

        let firstScopeSave = Task {
            try await actor.saveAfterDelay(
                [firstProject],
                for: "scope-one",
                delay: .milliseconds(80)
            )
        }
        try await actor.saveNow([secondProject], for: "scope-two")

        let firstScopeDidWrite = try await firstScopeSave.value
        XCTAssertTrue(firstScopeDidWrite)
        XCTAssertEqual(store.loadProjects(for: "scope-one")?.map(\.title), ["账号一"])
        XCTAssertEqual(store.loadProjects(for: "scope-two")?.map(\.title), ["账号二"])
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

        let indexedURL = try XCTUnwrap(firstStoredChapterFile(for: indexedChapter.id))
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

        var updatedProject = NovelProject(
            id: project.id,
            title: "新标题",
            genre: project.genre,
            summary: project.summary,
            updatedAt: project.updatedAt,
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
        updatedProject.updatedAtDate = project.updatedAtDate.addingTimeInterval(1)

        try store.saveProjects([updatedProject], for: scope)

        let loaded = store.loadProjects(for: scope)
        XCTAssertEqual(loaded?.first?.title, "新标题")
    }

    // MARK: - Delete Project Tests

    func testDeleteProject() async throws {
        var project = NovelProject(
            title: "将被删除的项目",
            genre: "都市",
            summary: "摘要"
        )
        project.updatedAtDate = Date(timeIntervalSince1970: 1_710_000_000.121)

        try store.saveProjects([project], for: scope)

        try store.saveProjects(
            [],
            deletedProjects: [
                ProjectDeletionTombstone(
                    projectID: project.id,
                    deletedAt: Date(timeIntervalSince1970: 1_710_000_000.124)
                )
            ],
            for: scope
        )

        let loaded = store.loadProjects(for: scope)
        XCTAssertEqual(loaded?.isEmpty, true)
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

    func testSanitizedScopeCollisionsRemainIsolatedAcrossRestartAndResave() throws {
        let firstScope = "scope/a"
        let secondScope = "scope?a"
        let firstChapter = ChapterDraft(
            id: "first-scope-chapter",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "斜杠账号章节",
            content: "只属于 scope/a 的正文"
        )
        let secondChapter = ChapterDraft(
            id: "second-scope-chapter",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "问号账号章节",
            content: "只属于 scope?a 的正文"
        )
        var firstProject = NovelProject(
            id: "first-scope-project",
            title: "斜杠账号项目",
            genre: "都市",
            summary: "摘要"
        )
        firstProject.chapterDrafts = [firstChapter]
        var secondProject = NovelProject(
            id: "second-scope-project",
            title: "问号账号项目",
            genre: "科幻",
            summary: "摘要"
        )
        secondProject.chapterDrafts = [secondChapter]

        try store.saveProjects([firstProject], for: firstScope)
        try store.saveProjects([secondProject], for: secondScope)

        let scopeDirectories = storedFiles(named: "project.json")
            .map {
                $0.deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            }
            .filter { $0.lastPathComponent.hasPrefix("account-scope_a--") }
        XCTAssertEqual(scopeDirectories.count, 2)
        XCTAssertEqual(Set(scopeDirectories.map(\.lastPathComponent)).count, 2)

        let restartedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        let firstReload = try XCTUnwrap(restartedStore.loadProjects(for: firstScope))
        let secondReload = try XCTUnwrap(restartedStore.loadProjects(for: secondScope))
        XCTAssertEqual(firstReload.map(\.id), [firstProject.id])
        XCTAssertEqual(secondReload.map(\.id), [secondProject.id])
        XCTAssertEqual(
            restartedStore.loadChapterDraft(
                firstChapter.id,
                for: firstProject.id,
                scope: firstScope
            )?.content,
            firstChapter.content
        )
        XCTAssertEqual(
            restartedStore.loadChapterDraft(
                secondChapter.id,
                for: secondProject.id,
                scope: secondScope
            )?.content,
            secondChapter.content
        )

        try restartedStore.saveProjects(firstReload, for: firstScope)
        try restartedStore.saveProjects(secondReload, for: secondScope)

        let secondRestartStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: ""
        )
        XCTAssertEqual(
            secondRestartStore.loadProjects(for: firstScope)?.map(\.id),
            [firstProject.id]
        )
        XCTAssertEqual(
            secondRestartStore.loadProjects(for: secondScope)?.map(\.id),
            [secondProject.id]
        )
        XCTAssertEqual(
            secondRestartStore.loadChapterDraft(
                firstChapter.id,
                for: firstProject.id,
                scope: firstScope
            )?.content,
            firstChapter.content
        )
        XCTAssertEqual(
            secondRestartStore.loadChapterDraft(
                secondChapter.id,
                for: secondProject.id,
                scope: secondScope
            )?.content,
            secondChapter.content
        )
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

    private func firstStoredChapterFile(for chapterID: ChapterDraft.ID) -> URL? {
        allStoredFiles().first { url in
            guard url.path.contains("/chapters/"),
                  url.lastPathComponent != "index.json",
                  url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let chapter = try? JSONDecoder().decode(ChapterDraft.self, from: data) else {
                return false
            }
            return chapter.id == chapterID
        }
    }

    private func firstStoredChapterFile(
        for chapterID: ChapterDraft.ID,
        projectID: NovelProject.ID
    ) -> URL? {
        guard let projectDirectory = storedFiles(named: "project.json").first(where: { url in
            guard let data = try? Data(contentsOf: url),
                  let project = try? ProjectDocumentCodec().decode(data).project else {
                return false
            }
            return project.id == projectID
        })?.deletingLastPathComponent() else {
            return nil
        }

        return allStoredFiles().first { url in
            guard url.path.hasPrefix(projectDirectory.path + "/chapters/"),
                  url.lastPathComponent != "index.json",
                  url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let chapter = try? JSONDecoder().decode(ChapterDraft.self, from: data) else {
                return false
            }
            return chapter.id == chapterID
        }
    }

    private func allStoredFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: testDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
    }

    private func storedFileContents() throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for url in allStoredFiles() {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = String(
                url.path.dropFirst(testDirectory.path.count)
            )
            contents[relativePath] = try Data(contentsOf: url)
        }
        return contents
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
