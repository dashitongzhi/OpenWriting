import XCTest
@testable import OpenWriting

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
        XCTAssertTrue(
            issue.path.hasSuffix(
                "/projects/\(futureProject.id)/project.json"
            )
        )
        XCTAssertEqual(issue.sourceVersion, futureVersion)
        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [healthyProject.id])
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

    func testFutureProjectIndexVersionIsRejectedButProjectPayloadIsRecovered() async throws {
        let project = NovelProject(title: "未来索引项目", genre: "科幻", summary: "摘要")
        try store.saveProjects([project], for: scope)

        let indexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        var indexObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        )
        indexObject["version"] = 999
        try JSONSerialization.data(withJSONObject: indexObject).write(to: indexURL)

        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [project.id])
        XCTAssertTrue(
            store.storageHealthReport(for: project.id, scope: scope).issues.contains {
                $0.kind == .projectIndexCorrupt
            }
        )
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

    func testFutureChapterIndexVersionIsRejectedButChapterPayloadIsRecovered() async throws {
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
        XCTAssertTrue(report.issues.contains { $0.kind == .chapterIndexCorrupt })
        XCTAssertEqual(store.loadProjects(for: scope)?.first?.chapterCatalog.map(\.id), [chapter.id])
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

    func testCorruptProjectIndexFollowedByEmptySavePreservesRecoverableProjects() async throws {
        let project = NovelProject(title: "索引损坏项目", genre: "悬疑", summary: "摘要")
        try store.saveProjects([project], for: scope)
        let projectIndexURL = try XCTUnwrap(storedFiles(named: "index.json").first {
            !$0.path.contains("/chapters/")
        })
        try Data("{ invalid index".utf8).write(to: projectIndexURL)

        XCTAssertEqual(store.loadProjects(for: scope)?.map(\.id), [project.id])
        try store.saveProjects([], for: scope)

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
        let oldChapterURL = try XCTUnwrap(firstStoredFile(named: "\(oldChapter.id).json"))
        let originalIndexData = try Data(contentsOf: chapterIndexURL)
        let hookedStore = ProjectFileStore(
            fileManager: .default,
            baseDirectoryURL: testDirectory.appendingPathComponent("ProjectStore"),
            baseDirectoryName: "",
            testHooks: .init(
                beforeAtomicWrite: { url in
                    if url.lastPathComponent == "\(newChapter.id).json" {
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
        XCTAssertEqual(hookedStore.loadChapterDrafts(for: project.id, scope: scope).map(\.id), [oldChapter.id])
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
            $0.hasPrefix("write:") && $0.hasSuffix("/\(newChapter.id).json")
        })
        let indexPublish = try XCTUnwrap(events.firstIndex {
            $0.hasPrefix("write:") && $0.hasSuffix("/chapters/index.json")
        })
        let oldPayloadRemoval = try XCTUnwrap(events.firstIndex {
            $0.hasPrefix("remove:") && $0.hasSuffix("/\(oldChapter.id).json")
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

    private func allStoredFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: testDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
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
