import Foundation
import CryptoKit
import Darwin

nonisolated struct ProjectEmergencySnapshot: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var scope: String?
    var projects: [NovelProject]
    var deletedProjects: [ProjectDeletionTombstone]
    var createdAt: Date
    var failureReason: String

    init(
        scope: String?,
        projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone],
        createdAt: Date = Date(),
        failureReason: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.scope = scope
        self.projects = projects
        self.deletedProjects = ProjectDeletionTombstone.normalized(deletedProjects)
        self.createdAt = createdAt
        self.failureReason = failureReason
    }
}

nonisolated enum ProjectLoadIssueKind: String, Equatable {
    case unsupportedFutureProjectDocument
}

nonisolated struct ProjectLoadIssue: Identifiable, Equatable {
    let id: String
    let kind: ProjectLoadIssueKind
    let scope: String?
    let projectID: NovelProject.ID?
    let path: String
    let sourceVersion: Int
}

nonisolated struct ProjectLoadReport {
    var projects: [NovelProject]
    var issues: [ProjectLoadIssue]

    var unsupportedFutureProjectCount: Int {
        issues.filter { $0.kind == .unsupportedFutureProjectDocument }.count
    }
}

nonisolated struct ProjectFileStore: @unchecked Sendable {
    struct TestHooks: @unchecked Sendable {
        var beforeAtomicWrite: ((URL) throws -> Void)?
        var beforeRemoveItem: ((URL) throws -> Void)?
        var onStorageHealthScan: (() -> Void)?

        init(
            beforeAtomicWrite: ((URL) throws -> Void)? = nil,
            beforeRemoveItem: ((URL) throws -> Void)? = nil,
            onStorageHealthScan: (() -> Void)? = nil
        ) {
            self.beforeAtomicWrite = beforeAtomicWrite
            self.beforeRemoveItem = beforeRemoveItem
            self.onStorageHealthScan = onStorageHealthScan
        }

        static let none = TestHooks()
    }

    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let projectCodec = ProjectDocumentCodec()
    private let writeCache = ProjectFileWriteCache()
    private let accessLock: NSRecursiveLock
    private let testHooks: TestHooks

    private struct ProjectIndex: Codable {
        static let currentVersion = 3

        var version: Int
        var projectIDs: [NovelProject.ID]
        var deletedProjects: [ProjectDeletionTombstone]

        init(
            version: Int = currentVersion,
            projectIDs: [NovelProject.ID],
            deletedProjects: [ProjectDeletionTombstone] = []
        ) {
            self.version = version
            self.projectIDs = projectIDs
            self.deletedProjects = ProjectDeletionTombstone.normalized(deletedProjects)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let sourceVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            guard (1...Self.currentVersion).contains(sourceVersion) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version,
                    in: container,
                    debugDescription: "Unsupported project index version \(sourceVersion)."
                )
            }
            version = Self.currentVersion
            projectIDs = try container.decode([NovelProject.ID].self, forKey: .projectIDs)
            deletedProjects = ProjectDeletionTombstone.normalized(
                try container.decodeIfPresent(
                    [ProjectDeletionTombstone].self,
                    forKey: .deletedProjects
                ) ?? []
            )
        }
    }

    private struct ChapterIndex: Codable {
        static let currentVersion = 3

        var version: Int
        var chapterIDs: [ChapterDraft.ID]
        var chapters: [ChapterDraftMetadata]?

        init(
            version: Int = currentVersion,
            chapterIDs: [ChapterDraft.ID],
            chapters: [ChapterDraftMetadata]?
        ) {
            self.version = version
            self.chapterIDs = chapterIDs
            self.chapters = chapters
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let sourceVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            guard (1...Self.currentVersion).contains(sourceVersion) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version,
                    in: container,
                    debugDescription: "Unsupported chapter index version \(sourceVersion)."
                )
            }
            version = Self.currentVersion
            chapterIDs = try container.decode([ChapterDraft.ID].self, forKey: .chapterIDs)
            chapters = try container.decodeIfPresent([ChapterDraftMetadata].self, forKey: .chapters)
        }
    }

    private struct ExistingProjectProtection {
        var indexedProjectIDs: [NovelProject.ID]
        var directoryNames: Set<String>
        var updatedAtByProjectID: [NovelProject.ID: Date]
    }

    struct ChapterDraftLoadReport {
        var drafts: [ChapterDraft]
        var missingChapterIDs: [ChapterDraft.ID]

        var isComplete: Bool {
            missingChapterIDs.isEmpty
        }
    }

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        baseDirectoryName: String = "OpenWriting",
        testHooks: TestHooks = .none
    ) {
        self.fileManager = fileManager

        let baseURL = baseDirectoryURL ?? Self.defaultApplicationSupportDirectory(
            fileManager: fileManager
        )

        self.baseDirectoryURL = baseURL
            .appendingPathComponent(baseDirectoryName, isDirectory: true)
            .appendingPathComponent("ProjectStore", isDirectory: true)
        self.accessLock = NSRecursiveLock()
        self.testHooks = testHooks

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    nonisolated static func defaultApplicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        if let resolved = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) {
            return resolved
        }

        // Keep persistence on the user-domain Application Support path even if
        // URL discovery fails. A later write error must surface to the caller;
        // silently switching user data to a disposable temporary directory is
        // never an acceptable fallback.
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    private init(
        fileManager: FileManager,
        resolvedBaseDirectoryURL: URL,
        accessLock: NSRecursiveLock,
        testHooks: TestHooks
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = resolvedBaseDirectoryURL
        self.accessLock = accessLock
        self.testHooks = testHooks
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func independentCopy() -> ProjectFileStore {
        ProjectFileStore(
            fileManager: fileManager,
            resolvedBaseDirectoryURL: baseDirectoryURL,
            accessLock: accessLock,
            testHooks: testHooks
        )
    }

    func storageHealthReport(for projectID: NovelProject.ID, scope: String?) -> StorageHealthReport {
        testHooks.onStorageHealthScan?()
        accessLock.lock()
        defer { accessLock.unlock() }
        var issues: [ProjectStorageIssue] = []
        let resolvedScopeName = scopeDirectoryName(for: scope)
        let legacyURL = projectsFileURL(for: scope)

        if fileManager.fileExists(atPath: legacyURL.path) {
            issues.append(storageIssue(
                kind: .legacyProjectFile,
                status: .warning,
                projectID: projectID,
                title: "发现旧版整包项目文件",
                detail: "当前存储已经使用分片格式，但 scope 内仍存在 projects.json。建议确认迁移结果后保留诊断。",
                actions: [.exportDiagnostics]
            ))
        }

        var projectFromMetadata: NovelProject?
        let indexURL = projectIndexURL(for: scope)
        if !fileManager.fileExists(atPath: indexURL.path) {
            issues.append(storageIssue(
                kind: .projectIndexMissing,
                status: .blocked,
                projectID: projectID,
                title: "项目索引缺失",
                detail: "scope \(resolvedScopeName) 缺少 index.json，项目列表无法被完整信任。",
                actions: [.exportDiagnostics, .recoverMetadataShell]
            ))
        } else if let indexData = try? Data(contentsOf: indexURL),
                  let index = try? decoder.decode(ProjectIndex.self, from: indexData) {
            if !index.projectIDs.contains(projectID) {
                issues.append(storageIssue(
                    kind: .projectIndexMissing,
                    status: .blocked,
                    projectID: projectID,
                    title: "项目索引未包含当前项目",
                    detail: "index.json 中没有当前项目 ID，重新启动后可能丢失入口。",
                    actions: [.exportDiagnostics, .recoverMetadataShell]
                ))
            }
        } else {
            issues.append(storageIssue(
                kind: .projectIndexCorrupt,
                status: .blocked,
                projectID: projectID,
                title: "项目索引损坏",
                detail: "index.json 无法按当前 ProjectIndex 格式解码。",
                actions: [.exportDiagnostics, .recoverMetadataShell]
            ))
        }

        let metadataURL = projectMetadataURL(for: projectID, scope: scope)
        if !fileManager.fileExists(atPath: metadataURL.path) {
            issues.append(storageIssue(
                kind: .projectMetadataMissing,
                status: .blocked,
                projectID: projectID,
                title: "项目 metadata 缺失",
                detail: "项目目录中缺少 project.json。章节文件可能仍在，但项目壳需要恢复。",
                actions: [.exportDiagnostics, .recoverMetadataShell]
            ))
        } else if let metadataData = try? Data(contentsOf: metadataURL),
                  let decodedProject = try? projectCodec.decode(metadataData) {
            projectFromMetadata = decodedProject.project
        } else {
            issues.append(storageIssue(
                kind: .projectMetadataCorrupt,
                status: .blocked,
                projectID: projectID,
                title: "项目 metadata 损坏",
                detail: "project.json 无法按当前 NovelProject 格式解码。",
                actions: [.exportDiagnostics, .recoverMetadataShell]
            ))
        }

        let chapterDirectory = chapterDirectoryURL(for: projectID, scope: scope)
        let chapterIndexURL = chapterIndexURL(for: projectID, scope: scope)
        var indexedChapterIDs: [ChapterDraft.ID] = []
        var indexedMetadata: [ChapterDraftMetadata] = []
        if !fileManager.fileExists(atPath: chapterIndexURL.path) {
            issues.append(storageIssue(
                kind: .chapterIndexMissing,
                status: (projectFromMetadata?.chapterCatalog.isEmpty ?? true) ? .warning : .blocked,
                projectID: projectID,
                title: "章节索引缺失",
                detail: "chapters/index.json 不存在，已保存章节目录无法完整恢复。",
                actions: [.exportDiagnostics, .rebuildChapterCatalog]
            ))
        } else if let indexData = try? Data(contentsOf: chapterIndexURL),
                  let index = try? decoder.decode(ChapterIndex.self, from: indexData) {
            indexedChapterIDs = index.chapterIDs
            indexedMetadata = index.chapters ?? []

            let metadataIDs = Set(indexedMetadata.map(\.id))
            let indexIDs = Set(indexedChapterIDs)
            if !metadataIDs.isEmpty, metadataIDs != indexIDs {
                issues.append(storageIssue(
                    kind: .catalogFileMismatch,
                    status: .blocked,
                    projectID: projectID,
                    title: "章节目录与文件索引不一致",
                    detail: "chapters/index.json 的 chapterIDs 与 chapters metadata 不一致。",
                    actions: [.exportDiagnostics, .rebuildChapterCatalog]
                ))
            }
        } else {
            issues.append(storageIssue(
                kind: .chapterIndexCorrupt,
                status: .blocked,
                projectID: projectID,
                title: "章节索引损坏",
                detail: "chapters/index.json 无法按当前 ChapterIndex 格式解码。",
                actions: [.exportDiagnostics, .rebuildChapterCatalog]
            ))
        }

        for chapterID in indexedChapterIDs {
            let url = chapterURL(for: chapterID, projectID: projectID, scope: scope)
            if !fileManager.fileExists(atPath: url.path) {
                issues.append(storageIssue(
                    kind: .chapterFileMissing,
                    status: .blocked,
                    projectID: projectID,
                    chapterID: chapterID,
                    title: "章节文件缺失",
                    detail: "目录中记录了章节 \(chapterID)，但对应正文 JSON 不存在。",
                    actions: [.exportDiagnostics, .preserveMissingChapterPlaceholder]
                ))
            } else if let chapterData = try? Data(contentsOf: url),
                      (try? decoder.decode(ChapterDraft.self, from: chapterData)) != nil {
                continue
            } else {
                issues.append(storageIssue(
                    kind: .chapterFileCorrupt,
                    status: .blocked,
                    projectID: projectID,
                    chapterID: chapterID,
                    title: "章节文件损坏",
                    detail: "章节 \(chapterID) 的 JSON 文件无法解码，暂不能写入长期记忆。",
                    actions: [.exportDiagnostics, .preserveMissingChapterPlaceholder]
                ))
            }
        }

        let orphanFileNames = orphanChapterFileNames(in: chapterDirectory, indexedChapterIDs: Set(indexedChapterIDs))
        for fileName in orphanFileNames {
            issues.append(storageIssue(
                kind: .orphanChapterFile,
                status: .warning,
                projectID: projectID,
                title: "发现孤儿章节文件",
                detail: "\(fileName) 不在章节索引中；为了避免误删，当前只报告不清理。",
                actions: [.exportDiagnostics, .rebuildChapterCatalog]
            ))
        }

        if let project = projectFromMetadata, !project.chapterCatalog.isEmpty {
            let catalogIDs = Set(project.chapterCatalog.map(\.id))
            let indexIDs = Set(indexedChapterIDs)
            if !indexedChapterIDs.isEmpty, catalogIDs != indexIDs {
                issues.append(storageIssue(
                    kind: .catalogFileMismatch,
                    status: .blocked,
                    projectID: projectID,
                    title: "项目目录与章节索引不一致",
                    detail: "project.json 中的 chapterCatalog 与 chapters/index.json 不一致。",
                    actions: [.exportDiagnostics, .rebuildChapterCatalog]
                ))
            }
        }

        let status: StorageHealthStatus
        if issues.contains(where: { $0.status == .blocked }) {
            status = .blocked
        } else if issues.contains(where: { $0.status == .warning }) {
            status = .warning
        } else {
            status = .passed
        }

        let summary: String
        let nextAction: String
        switch status {
        case .passed:
            summary = "项目分片、metadata、章节索引和正文文件一致。"
            nextAction = "可以继续写作；保存后仍会走分片完整性检查。"
        case .warning:
            summary = "发现 \(issues.count) 个非阻断存储提醒。"
            nextAction = "先导出诊断，再按需重建章节目录。"
        case .blocked:
            summary = "发现 \(issues.filter { $0.status == .blocked }.count) 个阻断性存储问题。"
            nextAction = "先导出诊断，再使用恢复动作保留章节入口。"
        }

        let metrics = [
            "scope": resolvedScopeName,
            "indexedChapters": "\(indexedChapterIDs.count)",
            "catalogChapters": "\(max(projectFromMetadata?.chapterCatalog.count ?? 0, indexedMetadata.count))",
            "missingOrCorrupt": "\(issues.filter { $0.kind == .chapterFileMissing || $0.kind == .chapterFileCorrupt }.count)",
            "orphanFiles": "\(orphanFileNames.count)"
        ]

        return StorageHealthReport(
            id: stableStorageID(parts: ["storage_health", resolvedScopeName, projectID, status.rawValue, "\(issues.count)"]),
            projectID: projectID,
            scopeName: resolvedScopeName,
            checkedAt: Date(),
            status: status,
            summary: summary,
            nextAction: nextAction,
            issues: issues,
            metrics: metrics
        )
    }

    func recoverStorageIssue(
        _ issue: ProjectStorageIssue,
        action: StorageRecoveryAction,
        project: NovelProject?,
        scope: String?
    ) throws -> StorageRecoveryResult {
        accessLock.lock()
        defer { accessLock.unlock() }
        guard issue.recoveryActions.contains(action) else {
            throw recoveryError("恢复动作“\(action.title)”不适用于“\(issue.title)”。")
        }

        switch action {
        case .exportDiagnostics:
            let url = try exportStorageDiagnostics(for: issue.projectID, scope: scope)
            return StorageRecoveryResult(
                action: action,
                issueID: issue.id,
                didChangeStore: false,
                message: "已导出存储诊断：\(url.lastPathComponent)",
                outputURL: url
            )
        case .rebuildChapterCatalog:
            let includeCatalogEntriesWithoutReadableFiles = issue.kind == .chapterIndexMissing
                || issue.kind == .chapterIndexCorrupt
            try rebuildChapterIndexPreservingFiles(
                for: issue.projectID,
                project: project,
                scope: scope,
                includeCatalogEntriesWithoutReadableFiles: includeCatalogEntriesWithoutReadableFiles
            )
            return StorageRecoveryResult(
                action: action,
                issueID: issue.id,
                didChangeStore: true,
                message: includeCatalogEntriesWithoutReadableFiles
                    ? "已根据现有章节文件和项目目录重建章节索引。"
                    : "已根据可读取章节文件重建章节索引，孤儿章节已重新纳入目录。",
                outputURL: nil
            )
        case .preserveMissingChapterPlaceholder:
            guard let chapterID = issue.chapterID else {
                throw recoveryError("该问题没有可占位的章节 ID。")
            }
            let backupURL = try preserveMissingChapterPlaceholder(chapterID, for: issue.projectID, project: project, scope: scope)
            return StorageRecoveryResult(
                action: action,
                issueID: issue.id,
                didChangeStore: true,
                message: backupURL == nil
                    ? "已为缺失章节保留正文占位，原目录位置不会被静默删除。"
                    : "已备份损坏章节文件并写入正文占位，原目录位置不会被静默删除。",
                outputURL: backupURL
            )
        case .recoverMetadataShell:
            guard let project else {
                throw recoveryError("当前内存中没有可用于恢复的项目壳。")
            }
            try recoverMetadataShell(for: project, scope: scope)
            return StorageRecoveryResult(
                action: action,
                issueID: issue.id,
                didChangeStore: true,
                message: "已从当前内存项目恢复 project.json 和项目索引。",
                outputURL: nil
            )
        case .markCloudConflict:
            let url = try writeCloudConflictMarker(issue: issue, scope: scope)
            return StorageRecoveryResult(
                action: action,
                issueID: issue.id,
                didChangeStore: true,
                message: "已写入 iCloud 冲突标记：\(url.lastPathComponent)",
                outputURL: url
            )
        }
    }

    func loadProjectsReport(for scope: String?) -> ProjectLoadReport? {
        accessLock.lock()
        defer { accessLock.unlock() }
        if let report = loadShardedProjectsReport(for: scope) {
            return report
        }

        let fileURL = projectsFileURL(for: scope)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return decodeLegacyProjectsReport(
            from: data,
            fileURL: fileURL,
            scope: scope
        )
    }

    func loadProjects(for scope: String?) -> [NovelProject]? {
        loadProjectsReport(for: scope)?.projects
    }

    func saveProjects(_ projects: [NovelProject], for scope: String?) throws {
        accessLock.lock()
        defer { accessLock.unlock() }
        try saveShardedProjects(
            projects,
            deletedProjects: loadProjectDeletionTombstonesWithoutLock(for: scope),
            for: scope
        )
    }

    func saveProjects(
        _ projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone],
        for scope: String?
    ) throws {
        accessLock.lock()
        defer { accessLock.unlock() }
        try saveShardedProjects(
            projects,
            deletedProjects: deletedProjects,
            for: scope
        )
    }

    func loadProjectDeletionTombstones(
        for scope: String?
    ) -> [ProjectDeletionTombstone] {
        accessLock.lock()
        defer { accessLock.unlock() }
        return loadProjectDeletionTombstonesWithoutLock(for: scope)
    }

    func hasProjects(for scope: String?) -> Bool {
        accessLock.lock()
        defer { accessLock.unlock() }
        return fileManager.fileExists(atPath: projectIndexURL(for: scope).path)
            || fileManager.fileExists(atPath: projectsFileURL(for: scope).path)
    }

    func removeProjects(for scope: String?) throws {
        accessLock.lock()
        defer { accessLock.unlock() }
        let scopeURL = scopeDirectoryURL(for: scope)
        if fileManager.fileExists(atPath: scopeURL.path) {
            try fileManager.removeItem(at: scopeURL)
            writeCache.removeAll()
        }
    }

    @discardableResult
    func writeEmergencySnapshot(
        projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone],
        for scope: String?,
        failureReason: String
    ) throws -> URL {
        accessLock.lock()
        defer { accessLock.unlock() }

        let directoryURL = baseDirectoryURL.appendingPathComponent(
            "emergency-snapshots",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let scopeComponent = sanitizedStorageComponent(
            normalizedScope(scope) ?? "local"
        )
        let fileURL = directoryURL.appendingPathComponent(
            "\(scopeComponent)-\(Self.diagnosticTimestamp())-\(UUID().uuidString).emergency.json",
            isDirectory: false
        )
        let snapshot = ProjectEmergencySnapshot(
            scope: normalizedScope(scope),
            projects: projects,
            deletedProjects: deletedProjects,
            failureReason: failureReason
        )
        try DurableAtomicFileWriter.write(try encoder.encode(snapshot), to: fileURL)
        return fileURL
    }

    private func loadShardedProjectsReport(for scope: String?) -> ProjectLoadReport? {
        let indexURL = projectIndexURL(for: scope)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ProjectIndex.self, from: indexData) else {
            return loadProjectsFromDirectoriesReport(for: scope)
        }

        var projects: [NovelProject] = []
        var issues: [ProjectLoadIssue] = []
        let tombstonesByProjectID = Dictionary(
            uniqueKeysWithValues: index.deletedProjects.map { ($0.projectID, $0) }
        )
        for projectID in index.projectIDs {
            let projectURL = projectMetadataURL(for: projectID, scope: scope)
            guard let projectData = try? Data(contentsOf: projectURL) else { continue }
            var project: NovelProject
            do {
                project = try projectCodec.decode(projectData).project
            } catch ProjectDocumentCodecError.unsupportedFutureVersion(let sourceVersion) {
                issues.append(futureProjectLoadIssue(
                    scope: scope,
                    projectID: projectID,
                    fileURL: projectURL,
                    sourceVersion: sourceVersion
                ))
                continue
            } catch {
                continue
            }

            if let tombstone = tombstonesByProjectID[projectID],
               tombstone.deletedAt >= project.updatedAtDate {
                continue
            }
            project.chapterCatalog = loadChapterMetadata(for: projectID, scope: scope)
            project.chapterDrafts = []
            projects.append(project)
        }

        return ProjectLoadReport(projects: projects, issues: issues)
    }

    private func loadProjectsFromDirectoriesReport(for scope: String?) -> ProjectLoadReport? {
        let projectsDirectory = scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects", isDirectory: true)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ), !directories.isEmpty else {
            return nil
        }

        var projects: [NovelProject] = []
        var issues: [ProjectLoadIssue] = []
        for directory in directories {
            let metadataURL = directory.appendingPathComponent("project.json", isDirectory: false)
            guard let data = try? Data(contentsOf: metadataURL) else { continue }
            do {
                var project = try projectCodec.decode(data).project
                project.chapterCatalog = loadChapterMetadata(for: project.id, scope: scope)
                project.chapterDrafts = []
                projects.append(project)
            } catch ProjectDocumentCodecError.unsupportedFutureVersion(let sourceVersion) {
                issues.append(futureProjectLoadIssue(
                    scope: scope,
                    projectID: projectID(in: data),
                    fileURL: metadataURL,
                    sourceVersion: sourceVersion
                ))
            } catch {
                continue
            }
        }
        projects.sort { $0.updatedAtDate > $1.updatedAtDate }
        return ProjectLoadReport(projects: projects, issues: issues)
    }

    private func decodeLegacyProjectsReport(
        from data: Data,
        fileURL: URL,
        scope: String?
    ) -> ProjectLoadReport? {
        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }
        var projects: [NovelProject] = []
        var issues: [ProjectLoadIssue] = []
        for (index, element) in elements.enumerated() {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(
                    withJSONObject: element,
                    options: [.sortedKeys]
                  ) else {
                continue
            }
            do {
                projects.append(try projectCodec.decode(elementData).project)
            } catch ProjectDocumentCodecError.unsupportedFutureVersion(let sourceVersion) {
                issues.append(ProjectLoadIssue(
                    id: "\(fileURL.path)#\(index)#future-\(sourceVersion)",
                    kind: .unsupportedFutureProjectDocument,
                    scope: normalizedScope(scope),
                    projectID: projectID(in: elementData),
                    path: fileURL.path,
                    sourceVersion: sourceVersion
                ))
            } catch {
                continue
            }
        }
        if !elements.isEmpty, projects.isEmpty, issues.isEmpty {
            return nil
        }
        return ProjectLoadReport(projects: projects, issues: issues)
    }

    private func futureProjectLoadIssue(
        scope: String?,
        projectID: NovelProject.ID?,
        fileURL: URL,
        sourceVersion: Int
    ) -> ProjectLoadIssue {
        ProjectLoadIssue(
            id: "\(fileURL.path)#future-\(sourceVersion)",
            kind: .unsupportedFutureProjectDocument,
            scope: normalizedScope(scope),
            projectID: projectID,
            path: fileURL.path,
            sourceVersion: sourceVersion
        )
    }

    private func projectID(in data: Data) -> NovelProject.ID? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projectID = object["id"] as? String,
              !projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return projectID
    }

    func loadChapterDraft(_ chapterID: ChapterDraft.ID, for projectID: NovelProject.ID, scope: String?) -> ChapterDraft? {
        accessLock.lock()
        defer { accessLock.unlock() }
        let chapterURL = chapterURL(for: chapterID, projectID: projectID, scope: scope)
        guard let data = try? Data(contentsOf: chapterURL) else { return nil }
        return try? decoder.decode(ChapterDraft.self, from: data)
    }

    func loadChapterDrafts(for projectID: NovelProject.ID, scope: String?) -> [ChapterDraft] {
        accessLock.lock()
        defer { accessLock.unlock() }
        return loadChapterDraftReport(for: projectID, scope: scope).drafts
    }

    func loadChapterDraftReport(for projectID: NovelProject.ID, scope: String?) -> ChapterDraftLoadReport {
        accessLock.lock()
        defer { accessLock.unlock() }
        let indexURL = chapterIndexURL(for: projectID, scope: scope)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ChapterIndex.self, from: indexData)
        else {
            return ChapterDraftLoadReport(drafts: [], missingChapterIDs: [])
        }

        var drafts: [ChapterDraft] = []
        var missingChapterIDs: [ChapterDraft.ID] = []

        for chapterID in index.chapterIDs {
            if let draft = loadChapterDraft(chapterID, for: projectID, scope: scope) {
                drafts.append(draft)
            } else {
                missingChapterIDs.append(chapterID)
            }
        }

        return ChapterDraftLoadReport(drafts: drafts, missingChapterIDs: missingChapterIDs)
    }

    private func loadChapterMetadata(for projectID: NovelProject.ID, scope: String?) -> [ChapterDraftMetadata] {
        let indexURL = chapterIndexURL(for: projectID, scope: scope)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ChapterIndex.self, from: indexData)
        else {
            return decodedChapterDrafts(in: chapterDirectoryURL(for: projectID, scope: scope))
                .map(ChapterDraftMetadata.init)
                .sorted(by: ChapterDraftMetadata.sortDescending)
        }

        if let chapters = index.chapters, !chapters.isEmpty {
            return chapters
        }

        return loadChapterDrafts(for: projectID, scope: scope)
            .map(ChapterDraftMetadata.init)
            .sorted(by: ChapterDraftMetadata.sortDescending)
    }

    private func saveShardedProjects(
        _ projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone],
        for scope: String?
    ) throws {
        let scopeURL = scopeDirectoryURL(for: scope)
        let projectsDirectory = scopeURL.appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)

        let normalizedDeletedProjects = ProjectDeletionTombstone.normalized(deletedProjects)
        let tombstonesByProjectID = Dictionary(
            uniqueKeysWithValues: normalizedDeletedProjects.map { ($0.projectID, $0) }
        )
        let resolvedProjects = projects.filter { project in
            guard let tombstone = tombstonesByProjectID[project.id] else { return true }
            return project.updatedAtDate > tombstone.deletedAt
        }
        let incomingProjectIDs = Set(resolvedProjects.map(\.id))
        let protection = existingProjectProtection(
            for: scope,
            excluding: incomingProjectIDs,
            tombstonesByProjectID: tombstonesByProjectID
        )
        let finalProjectUpdatedAt = Dictionary(
            uniqueKeysWithValues: resolvedProjects.map { ($0.id, $0.updatedAtDate) }
        ).merging(protection.updatedAtByProjectID) { incoming, _ in incoming }
        let resolvedDeletedProjects = normalizedDeletedProjects.filter { tombstone in
            guard let updatedAt = finalProjectUpdatedAt[tombstone.projectID] else {
                return true
            }
            return tombstone.deletedAt >= updatedAt
        }

        for project in resolvedProjects {
            try saveProject(project, scope: scope)
        }

        let index = ProjectIndex(
            version: ProjectIndex.currentVersion,
            projectIDs: resolvedProjects.map(\.id) + protection.indexedProjectIDs,
            deletedProjects: resolvedDeletedProjects
        )
        try writeIfChanged(try encoder.encode(index), to: projectIndexURL(for: scope))

        try removeDeletedProjectDirectories(
            keeping: incomingProjectIDs,
            protectedDirectoryNames: protection.directoryNames,
            scope: scope
        )
        let legacyURL = projectsFileURL(for: scope)
        if fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
    }

    private func existingProjectProtection(
        for scope: String?,
        excluding incomingProjectIDs: Set<NovelProject.ID>,
        tombstonesByProjectID: [NovelProject.ID: ProjectDeletionTombstone]
    ) -> ExistingProjectProtection {
        let projectsDirectory = scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects", isDirectory: true)
        let directoryNames = Set(
            (try? fileManager.contentsOfDirectory(
                at: projectsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ))?.map(\.lastPathComponent) ?? []
        )
        let incomingDirectoryNames = Set(incomingProjectIDs.map(sanitizedStorageComponent))

        guard let indexData = try? Data(contentsOf: projectIndexURL(for: scope)),
              let index = try? decoder.decode(ProjectIndex.self, from: indexData)
        else {
            var recoveredProjectIDs: [NovelProject.ID] = []
            var protectedDirectoryNames = Set<String>()
            var updatedAtByProjectID: [NovelProject.ID: Date] = [:]
            for directoryName in directoryNames {
                guard !incomingDirectoryNames.contains(directoryName) else { continue }
                let metadataURL = projectsDirectory
                    .appendingPathComponent(directoryName, isDirectory: true)
                    .appendingPathComponent("project.json", isDirectory: false)
                guard let data = try? Data(contentsOf: metadataURL),
                      let project = try? projectCodec.decode(data).project else {
                    protectedDirectoryNames.insert(directoryName)
                    continue
                }
                guard !incomingProjectIDs.contains(project.id) else { continue }
                if let tombstone = tombstonesByProjectID[project.id],
                   tombstone.deletedAt >= project.updatedAtDate {
                    continue
                }
                recoveredProjectIDs.append(project.id)
                protectedDirectoryNames.insert(directoryName)
                updatedAtByProjectID[project.id] = project.updatedAtDate
            }
            return ExistingProjectProtection(
                indexedProjectIDs: recoveredProjectIDs,
                directoryNames: protectedDirectoryNames,
                updatedAtByProjectID: updatedAtByProjectID
            )
        }

        var protectedProjectIDs: [NovelProject.ID] = []
        var protectedDirectoryNames = directoryNames.subtracting(
            Set(index.projectIDs.map(sanitizedStorageComponent))
        )
        var updatedAtByProjectID: [NovelProject.ID: Date] = [:]

        for projectID in index.projectIDs where !incomingProjectIDs.contains(projectID) {
            let metadataURL = projectMetadataURL(for: projectID, scope: scope)
            guard let data = try? Data(contentsOf: metadataURL),
                  let project = try? projectCodec.decode(data).project
            else {
                protectedProjectIDs.append(projectID)
                protectedDirectoryNames.insert(sanitizedStorageComponent(projectID))
                continue
            }
            if let tombstone = tombstonesByProjectID[projectID],
               tombstone.deletedAt >= project.updatedAtDate {
                continue
            }
            protectedProjectIDs.append(projectID)
            protectedDirectoryNames.insert(sanitizedStorageComponent(projectID))
            updatedAtByProjectID[projectID] = project.updatedAtDate
        }

        return ExistingProjectProtection(
            indexedProjectIDs: protectedProjectIDs,
            directoryNames: protectedDirectoryNames,
            updatedAtByProjectID: updatedAtByProjectID
        )
    }

    private func saveProject(_ project: NovelProject, scope: String?) throws {
        let chaptersDirectory = chapterDirectoryURL(for: project.id, scope: scope)
        try fileManager.createDirectory(at: chaptersDirectory, withIntermediateDirectories: true)
        let chapterIndexWasReadable = loadChapterIndex(for: project.id, scope: scope) != nil

        let chapterCatalog = resolvedChapterCatalog(
            for: project,
            preservingStoredChapters: !chapterIndexWasReadable,
            scope: scope
        )

        for chapterDraft in project.chapterDrafts {
            let chapterData = try encoder.encode(chapterDraft)
            try writeIfChanged(
                chapterData,
                to: chapterURL(for: chapterDraft.id, projectID: project.id, scope: scope)
            )
        }

        var metadata = project
        metadata.chapterDrafts = []
        try writeIfChanged(try projectCodec.encode(metadata), to: projectMetadataURL(for: project.id, scope: scope))

        let chapterIndex = ChapterIndex(
            version: 3,
            chapterIDs: chapterCatalog.map(\.id),
            chapters: chapterCatalog
        )
        try writeIfChanged(try encoder.encode(chapterIndex), to: chapterIndexURL(for: project.id, scope: scope))

        if chapterIndexWasReadable {
            try removeDeletedChapterFiles(
                in: chaptersDirectory,
                keeping: Set(chapterCatalog.map(\.id))
            )
        }
    }

    private func resolvedChapterCatalog(
        for project: NovelProject,
        preservingStoredChapters: Bool,
        scope: String?
    ) -> [ChapterDraftMetadata] {
        var catalogByID = Dictionary(uniqueKeysWithValues: project.chapterCatalog.map { ($0.id, $0) })
        for chapterDraft in project.chapterDrafts {
            catalogByID[chapterDraft.id] = ChapterDraftMetadata(chapterDraft: chapterDraft)
        }
        if preservingStoredChapters {
            let directory = chapterDirectoryURL(for: project.id, scope: scope)
            for chapterDraft in decodedChapterDrafts(in: directory) {
                catalogByID[chapterDraft.id] = catalogByID[chapterDraft.id]
                    ?? ChapterDraftMetadata(chapterDraft: chapterDraft)
            }
        }

        return catalogByID.values.sorted(by: ChapterDraftMetadata.sortDescending)
    }

    private func loadChapterIndex(for projectID: NovelProject.ID, scope: String?) -> ChapterIndex? {
        let url = chapterIndexURL(for: projectID, scope: scope)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ChapterIndex.self, from: data)
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        let fingerprint = ProjectFileFingerprint(size: data.count, hash: stableHash(data))
        if writeCache.fingerprint(for: url) == fingerprint {
            if let existingData = try? Data(contentsOf: url), existingData == data {
                return
            }
        }

        if let existingData = try? Data(contentsOf: url), existingData == data {
            writeCache.set(fingerprint, for: url)
            return
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try testHooks.beforeAtomicWrite?(url)
        try DurableAtomicFileWriter.write(data, to: url)
        writeCache.set(fingerprint, for: url)
    }

    private func loadProjectDeletionTombstonesWithoutLock(
        for scope: String?
    ) -> [ProjectDeletionTombstone] {
        let indexURL = projectIndexURL(for: scope)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ProjectIndex.self, from: indexData) else {
            return []
        }
        return ProjectDeletionTombstone.normalized(index.deletedProjects)
    }

    /// Deterministic content hash. Data.hashValue is seeded per-process, so it
    /// would change every launch and defeat the write cache.
    private func stableHash(_ data: Data) -> Int {
        let digest = SHA256.hash(data: data)
        return digest.withUnsafeBytes { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            var value: UInt64 = 0
            for byte in bytes.prefix(8) {
                value = (value << 8) | UInt64(byte)
            }
            return Int(truncatingIfNeeded: value)
        }
    }

    private func removeDeletedProjectDirectories(
        keeping projectIDs: Set<NovelProject.ID>,
        protectedDirectoryNames: Set<String>,
        scope: String?
    ) throws {
        let projectsDirectory = scopeDirectoryURL(for: scope).appendingPathComponent("projects", isDirectory: true)
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let expectedDirectoryNames = Set(projectIDs.map(sanitizedStorageComponent))
            .union(protectedDirectoryNames)
        for url in directoryContents where !expectedDirectoryNames.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
            writeCache.removeItems(under: url)
        }
    }

    private func removeDeletedChapterFiles(in chaptersDirectory: URL, keeping chapterIDs: Set<ChapterDraft.ID>) throws {
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: chaptersDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let expectedFileNames = Set(chapterIDs.map { "\(sanitizedStorageComponent($0)).json" })
        for url in directoryContents where url.lastPathComponent != "index.json" && !expectedFileNames.contains(url.lastPathComponent) {
            try testHooks.beforeRemoveItem?(url)
            try fileManager.removeItem(at: url)
            writeCache.remove(url)
        }
    }

    private func storageIssue(
        kind: ProjectStorageIssueKind,
        status: StorageHealthStatus,
        projectID: NovelProject.ID,
        chapterID: ChapterDraft.ID? = nil,
        title: String,
        detail: String,
        actions: [StorageRecoveryAction]
    ) -> ProjectStorageIssue {
        ProjectStorageIssue(
            id: stableStorageID(parts: [
                kind.rawValue,
                projectID,
                chapterID ?? "",
                title,
                detail
            ]),
            kind: kind,
            status: status,
            projectID: projectID,
            chapterID: chapterID,
            title: title,
            detail: detail,
            recoveryActions: actions
        )
    }

    private func orphanChapterFileNames(in chapterDirectory: URL, indexedChapterIDs: Set<ChapterDraft.ID>) -> [String] {
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: chapterDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let expectedFileNames = Set(indexedChapterIDs.map { "\(sanitizedStorageComponent($0)).json" })
        return directoryContents
            .map(\.lastPathComponent)
            .filter { fileName in
                fileName != "index.json"
                    && fileName.hasSuffix(".json")
                    && !expectedFileNames.contains(fileName)
            }
            .sorted()
    }

    private func exportStorageDiagnostics(for projectID: NovelProject.ID, scope: String?) throws -> URL {
        let report = storageHealthReport(for: projectID, scope: scope)
        let diagnosticsDirectory = scopeDirectoryURL(for: scope)
            .appendingPathComponent("diagnostics", isDirectory: true)
        try fileManager.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)

        let fileName = "storage-health-\(sanitizedStorageComponent(projectID))-\(Self.diagnosticTimestamp()).json"
        let outputURL = diagnosticsDirectory.appendingPathComponent(fileName, isDirectory: false)
        try writeIfChanged(try encoder.encode(report), to: outputURL)
        return outputURL
    }

    private func rebuildChapterIndexPreservingFiles(
        for projectID: NovelProject.ID,
        project: NovelProject?,
        scope: String?,
        includeCatalogEntriesWithoutReadableFiles: Bool = true
    ) throws {
        let chapterDirectory = chapterDirectoryURL(for: projectID, scope: scope)
        try fileManager.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)

        for draft in project?.chapterDrafts ?? [] {
            try writeIfChanged(
                try encoder.encode(draft),
                to: chapterURL(for: draft.id, projectID: projectID, scope: scope)
            )
        }

        let decodedDrafts = decodedChapterDrafts(in: chapterDirectory)
        var metadataByID: [ChapterDraft.ID: ChapterDraftMetadata] = [:]
        let currentMetadataByID = Dictionary(uniqueKeysWithValues: (project?.chapterCatalog ?? []).map { ($0.id, $0) })
        if includeCatalogEntriesWithoutReadableFiles {
            metadataByID = currentMetadataByID
        }
        for draft in decodedDrafts {
            metadataByID[draft.id] = currentMetadataByID[draft.id] ?? ChapterDraftMetadata(chapterDraft: draft)
        }

        let sortedMetadata = metadataByID.values.sorted(by: ChapterDraftMetadata.sortDescending)
        let index = ChapterIndex(
            version: 3,
            chapterIDs: sortedMetadata.map(\.id),
            chapters: sortedMetadata
        )
        try writeIfChanged(try encoder.encode(index), to: chapterIndexURL(for: projectID, scope: scope))
        try updateProjectMetadataCatalog(
            sortedMetadata,
            for: projectID,
            project: project,
            scope: scope
        )
    }

    private func updateProjectMetadataCatalog(
        _ catalog: [ChapterDraftMetadata],
        for projectID: NovelProject.ID,
        project: NovelProject?,
        scope: String?
    ) throws {
        guard var metadata = project ?? loadProjectMetadata(for: projectID, scope: scope) else { return }

        metadata.chapterCatalog = catalog
        metadata.chapterDrafts = []
        try writeIfChanged(try projectCodec.encode(metadata), to: projectMetadataURL(for: projectID, scope: scope))
    }

    private func preserveMissingChapterPlaceholder(
        _ chapterID: ChapterDraft.ID,
        for projectID: NovelProject.ID,
        project: NovelProject?,
        scope: String?
    ) throws -> URL? {
        let metadata = project?.chapterCatalog.first(where: { $0.id == chapterID })
        let placeholder = ChapterDraft(
            id: chapterID,
            volumeNumber: max(metadata?.volumeNumber ?? project?.currentVolumeNumber ?? 1, 1),
            chapterNumber: max(metadata?.chapterNumber ?? project?.currentChapterNumber ?? 1, 1),
            chapterTitle: metadata?.chapterTitle ?? "缺失章节占位",
            content: """
            [章节文件缺失占位]
            原章节正文文件缺失或损坏。OpenWriting 已保留这个章节入口，避免目录在下一次保存时被静默清理。
            请从版本历史、导出备份或 iCloud 冲突副本恢复真实正文后再继续写作。
            """,
            savedAt: Self.diagnosticTimestamp()
        )

        let chapterURL = chapterURL(for: chapterID, projectID: projectID, scope: scope)
        let backupURL = try backupExistingChapterFileIfNeeded(
            chapterURL,
            projectID: projectID,
            reason: "placeholder",
            scope: scope
        )
        try writeIfChanged(try encoder.encode(placeholder), to: chapterURL)

        var recoveryProject = project
        recoveryProject?.chapterDrafts.removeAll { $0.id == chapterID }
        try rebuildChapterIndexPreservingFiles(
            for: projectID,
            project: recoveryProject,
            scope: scope,
            includeCatalogEntriesWithoutReadableFiles: true
        )
        return backupURL
    }

    private func recoverMetadataShell(for project: NovelProject, scope: String?) throws {
        let scopeURL = scopeDirectoryURL(for: scope)
        let projectsDirectory = scopeURL.appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)

        var metadata = project
        metadata.chapterDrafts = []
        try writeIfChanged(try projectCodec.encode(metadata), to: projectMetadataURL(for: project.id, scope: scope))

        let existingIndex = (try? Data(contentsOf: projectIndexURL(for: scope)))
            .flatMap { try? decoder.decode(ProjectIndex.self, from: $0) }
        let existingProjectIDs = existingIndex?.projectIDs ?? []
        let projectIDs = uniqueIDs(existingProjectIDs + [project.id])
        try writeIfChanged(
            try encoder.encode(ProjectIndex(
                projectIDs: projectIDs,
                deletedProjects: (existingIndex?.deletedProjects ?? []).filter {
                    $0.projectID != project.id
                }
            )),
            to: projectIndexURL(for: scope)
        )
        try rebuildChapterIndexPreservingFiles(
            for: project.id,
            project: project,
            scope: scope,
            includeCatalogEntriesWithoutReadableFiles: true
        )
    }

    private func writeCloudConflictMarker(issue: ProjectStorageIssue, scope: String?) throws -> URL {
        let conflictDirectory = scopeDirectoryURL(for: scope)
            .appendingPathComponent("conflicts", isDirectory: true)
        try fileManager.createDirectory(at: conflictDirectory, withIntermediateDirectories: true)
        let outputURL = conflictDirectory
            .appendingPathComponent("cloud-conflict-\(sanitizedStorageComponent(issue.projectID))-\(Self.diagnosticTimestamp()).json")
        try writeIfChanged(try encoder.encode(issue), to: outputURL)
        return outputURL
    }

    private func decodedChapterDrafts(in chapterDirectory: URL) -> [ChapterDraft] {
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: chapterDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return directoryContents
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ChapterDraft.self, from: data)
            }
            .sorted(by: ChapterDraft.sortDescending)
    }

    private func loadProjectMetadata(for projectID: NovelProject.ID, scope: String?) -> NovelProject? {
        let metadataURL = projectMetadataURL(for: projectID, scope: scope)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? projectCodec.decode(data).project
    }

    private func backupExistingChapterFileIfNeeded(
        _ chapterURL: URL,
        projectID: NovelProject.ID,
        reason: String,
        scope: String?
    ) throws -> URL? {
        guard fileManager.fileExists(atPath: chapterURL.path) else {
            return nil
        }

        let backupDirectory = scopeDirectoryURL(for: scope)
            .appendingPathComponent("recovery-backups", isDirectory: true)
            .appendingPathComponent(sanitizedStorageComponent(projectID), isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let backupName = [
            chapterURL.deletingPathExtension().lastPathComponent,
            sanitizedStorageComponent(reason),
            Self.diagnosticTimestamp()
        ].joined(separator: "-") + ".json"
        let backupURL = backupDirectory.appendingPathComponent(backupName, isDirectory: false)
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: chapterURL, to: backupURL)
        return backupURL
    }

    private func projectsFileURL(for scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects.json", isDirectory: false)
    }

    private func projectIndexURL(for scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent("index.json", isDirectory: false)
    }

    private func projectDirectoryURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(sanitizedStorageComponent(projectID), isDirectory: true)
    }

    private func projectMetadataURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        projectDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent("project.json", isDirectory: false)
    }

    private func chapterDirectoryURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        projectDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent("chapters", isDirectory: true)
    }

    private func chapterIndexURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        chapterDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent("index.json", isDirectory: false)
    }

    private func chapterURL(for chapterID: ChapterDraft.ID, projectID: NovelProject.ID, scope: String?) -> URL {
        chapterDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent(sanitizedStorageComponent(chapterID), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func scopeDirectoryURL(for scope: String?) -> URL {
        baseDirectoryURL.appendingPathComponent(scopeDirectoryName(for: scope), isDirectory: true)
    }

    private func scopeDirectoryName(for scope: String?) -> String {
        guard let normalizedScope = normalizedScope(scope) else {
            return "local"
        }

        return "account-\(sanitizedStorageComponent(normalizedScope))"
    }

    private func normalizedScope(_ scope: String?) -> String? {
        guard let scope else {
            return nil
        }

        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func sanitizedStorageComponent(_ value: String) -> String {
        value.map { character in
            if character.isLetter || character.isNumber {
                return String(character)
            }

            if character == "." || character == "_" || character == "-" {
                return String(character)
            }

            return "_"
        }
        .joined()
    }

    private func stableStorageID(parts: [String]) -> String {
        let rawValue = parts.joined(separator: "::")
        guard let data = rawValue.data(using: .utf8) else {
            return sanitizedStorageComponent(rawValue)
        }
        let digest = SHA256.hash(data: data)
        let prefix = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return String(prefix)
    }

    private func uniqueIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            guard !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }

    private func recoveryError(_ message: String) -> CocoaError {
        CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func diagnosticTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withFractionalSeconds]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }
}

nonisolated private enum DurableAtomicFileWriter {
    static func write(_ data: Data, to destinationURL: URL) throws {
        let directoryURL = destinationURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )

        var descriptor: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else {
            throw posixError("create temporary file", url: temporaryURL)
        }

        var shouldRemoveTemporaryFile = true
        defer {
            if descriptor >= 0 {
                _ = Darwin.close(descriptor)
            }
            if shouldRemoveTemporaryFile {
                temporaryURL.withUnsafeFileSystemRepresentation { path in
                    if let path {
                        _ = Darwin.unlink(path)
                    }
                }
            }
        }

        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard let baseAddress = bytes.baseAddress else { break }
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                guard written >= 0 else {
                    if errno == EINTR { continue }
                    throw posixError("write temporary file", url: temporaryURL)
                }
                guard written > 0 else {
                    throw posixError(
                        "write temporary file",
                        url: temporaryURL,
                        code: EIO
                    )
                }
                offset += written
            }
        }

        guard Darwin.fsync(descriptor) == 0 else {
            throw posixError("fsync temporary file", url: temporaryURL)
        }
        // F_FULLFSYNC asks macOS to flush the drive's volatile write cache.
        // Filesystems that do not implement it still retain the fsync above.
        _ = Darwin.fcntl(descriptor, F_FULLFSYNC)
        guard Darwin.close(descriptor) == 0 else {
            descriptor = -1
            throw posixError("close temporary file", url: temporaryURL)
        }
        descriptor = -1

        let renameResult: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { sourcePath -> Int32 in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath -> Int32 in
                guard let sourcePath, let destinationPath else { return -1 }
                return Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw posixError("atomically replace destination", url: destinationURL)
        }
        shouldRemoveTemporaryFile = false

        let directoryDescriptor: Int32 = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard directoryDescriptor >= 0 else {
            throw posixError("open parent directory", url: directoryURL)
        }
        defer { _ = Darwin.close(directoryDescriptor) }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw posixError("fsync parent directory", url: directoryURL)
        }
    }

    private static func posixError(
        _ operation: String,
        url: URL,
        code: Int32 = errno
    ) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Failed to \(operation) at \(url.path): \(String(cString: strerror(code)))"
            ]
        )
    }
}

nonisolated private struct ProjectFileFingerprint: Equatable {
    let size: Int
    let hash: Int
}

nonisolated private final class ProjectFileWriteCache: @unchecked Sendable {
    private var fingerprints: [String: ProjectFileFingerprint] = [:]

    func fingerprint(for url: URL) -> ProjectFileFingerprint? {
        fingerprints[url.path]
    }

    func set(_ fingerprint: ProjectFileFingerprint, for url: URL) {
        fingerprints[url.path] = fingerprint
    }

    func remove(_ url: URL) {
        fingerprints.removeValue(forKey: url.path)
    }

    func removeItems(under url: URL) {
        let prefix = url.path + "/"
        fingerprints = fingerprints.filter { key, _ in
            key != url.path && !key.hasPrefix(prefix)
        }
    }

    func removeAll() {
        fingerprints.removeAll()
    }
}
