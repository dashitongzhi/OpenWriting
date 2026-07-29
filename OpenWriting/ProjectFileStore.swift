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
    case unsupportedFutureProjectIndex
    case pendingTransactionRecoveryFailure
    case legacyProjectPayloadPartial
    case legacyProjectPayloadUnreadable
    case legacyProjectPayloadPersistenceFailed
    case legacyDefaultsMigrationIncomplete
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
    var skippedDocumentCount = 0

    var unsupportedFutureProjectCount: Int {
        issues.filter { $0.kind == .unsupportedFutureProjectDocument }.count
    }
}

nonisolated struct ProjectFileStore: @unchecked Sendable {
    struct TestHooks: @unchecked Sendable {
        var beforeAtomicWrite: ((URL) throws -> Void)?
        var beforeRemoveItem: ((URL) throws -> Void)?
        var onStorageHealthScan: (() -> Void)?
        var onExistingFileVerificationRead: ((URL) -> Void)?

        init(
            beforeAtomicWrite: ((URL) throws -> Void)? = nil,
            beforeRemoveItem: ((URL) throws -> Void)? = nil,
            onStorageHealthScan: (() -> Void)? = nil,
            onExistingFileVerificationRead: ((URL) -> Void)? = nil
        ) {
            self.beforeAtomicWrite = beforeAtomicWrite
            self.beforeRemoveItem = beforeRemoveItem
            self.onStorageHealthScan = onStorageHealthScan
            self.onExistingFileVerificationRead = onExistingFileVerificationRead
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
            self.projectIDs = Self.normalizedProjectIDs(projectIDs)
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
            projectIDs = Self.normalizedProjectIDs(
                try container.decode([NovelProject.ID].self, forKey: .projectIDs)
            )
            deletedProjects = ProjectDeletionTombstone.normalized(
                try container.decodeIfPresent(
                    [ProjectDeletionTombstone].self,
                    forKey: .deletedProjects
                ) ?? []
            )
        }

        private static func normalizedProjectIDs(
            _ projectIDs: [NovelProject.ID]
        ) -> [NovelProject.ID] {
            var seen = Set<NovelProject.ID>()
            return projectIDs.filter { seen.insert($0).inserted }
        }
    }

    private struct ChapterIndex: Codable {
        static let currentVersion = 3

        var version: Int
        var chapterIDs: [ChapterDraft.ID]
        var chapters: [ChapterDraftMetadata]?
        var hadDuplicateChapterIDs: Bool
        var hadDuplicateChapterMetadata: Bool

        private enum CodingKeys: String, CodingKey {
            case version
            case chapterIDs
            case chapters
        }

        init(
            version: Int = currentVersion,
            chapterIDs: [ChapterDraft.ID],
            chapters: [ChapterDraftMetadata]?
        ) {
            let normalizedChapterIDs = ProjectFileStore.normalizedChapterIDs(chapterIDs)
            let normalizedChapters = chapters.map(ProjectFileStore.normalizedChapterMetadata)
            self.version = version
            self.chapterIDs = normalizedChapterIDs
            self.chapters = normalizedChapters
            self.hadDuplicateChapterIDs = normalizedChapterIDs.count != chapterIDs.count
            self.hadDuplicateChapterMetadata = normalizedChapters?.count != chapters?.count
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
            let decodedChapterIDs = try container.decode([ChapterDraft.ID].self, forKey: .chapterIDs)
            let decodedChapters = try container.decodeIfPresent(
                [ChapterDraftMetadata].self,
                forKey: .chapters
            )
            let normalizedChapterIDs = ProjectFileStore.normalizedChapterIDs(decodedChapterIDs)
            let normalizedChapters = decodedChapters.map(ProjectFileStore.normalizedChapterMetadata)
            version = Self.currentVersion
            chapterIDs = normalizedChapterIDs
            chapters = normalizedChapters
            hadDuplicateChapterIDs = normalizedChapterIDs.count != decodedChapterIDs.count
            hadDuplicateChapterMetadata = normalizedChapters?.count != decodedChapters?.count
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(chapterIDs, forKey: .chapterIDs)
            try container.encodeIfPresent(chapters, forKey: .chapters)
        }
    }

    private struct PendingProjectTransaction: Codable {
        static let currentVersion = 1

        var version: Int
        var projects: [NovelProject]
        var deletedProjects: [ProjectDeletionTombstone]

        init(
            projects: [NovelProject],
            deletedProjects: [ProjectDeletionTombstone]
        ) {
            self.version = Self.currentVersion
            self.projects = projects
            self.deletedProjects = ProjectDeletionTombstone.normalized(deletedProjects)
        }
    }

    private struct IndexVersionHeader: Decodable {
        var version: Int?
    }

    private struct ExistingProjectProtection {
        var indexedProjectIDs: [NovelProject.ID]
        var directoryNames: Set<String>
        var updatedAtByProjectID: [NovelProject.ID: Date]
    }

    private enum ProjectIndexReadState {
        case missing
        case readable(ProjectIndex)
        case corrupt
        case unsupportedFuture(Int)

        var canPublishCurrentIndex: Bool {
            switch self {
            case .missing, .readable:
                return true
            case .corrupt, .unsupportedFuture:
                return false
            }
        }
    }

    private enum ChapterIndexReadState {
        case missing
        case readable(ChapterIndex)
        case corrupt
        case unsupportedFuture(Int)
    }

    private enum ChapterPayloadCandidate {
        case missing(URL)
        case valid(
            url: URL,
            data: Data,
            draft: ChapterDraft,
            persistedTimestamp: Date?
        )
        case invalid(url: URL, reason: String)
    }

    private enum ChapterPayloadResolution {
        case missing(canonicalURL: URL)
        case invalid(url: URL, reason: String)
        case resolved(
            draft: ChapterDraft,
            data: Data,
            sourceURL: URL,
            canonicalURL: URL,
            legacyURL: URL,
            legacyFileExists: Bool
        )
        case conflict(canonicalURL: URL, legacyURL: URL, reason: String)
    }

    private struct ExistingShardedProjectState {
        var readableProjects: [NovelProject]
        var protectedProjectIDs: Set<NovelProject.ID>
        var protectedDirectoryNames: Set<String>
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
        let resolvedScopeName = scopeDirectoryName(for: scope)
        do {
            try recoverPendingTransactionIfNeeded(for: scope)
        } catch {
            let issue = storageIssue(
                kind: .pendingTransactionRecoveryFailure,
                status: .blocked,
                projectID: projectID,
                title: "未完成保存事务恢复失败",
                detail: "为避免读取新旧混合数据，项目加载已暂停。事务文件保留在 \(pendingTransactionURL(for: scope).path)。",
                actions: [.exportDiagnostics]
            )
            return StorageHealthReport(
                id: stableStorageID(parts: [
                    "storage_health",
                    resolvedScopeName,
                    projectID,
                    issue.kind.rawValue
                ]),
                projectID: projectID,
                scopeName: resolvedScopeName,
                checkedAt: Date(),
                status: .blocked,
                summary: "检测到未完成的跨文件保存事务，自动恢复尚未成功。",
                nextAction: "保留事务文件并导出诊断；排除磁盘或权限问题后重新加载。",
                issues: [issue],
                metrics: ["pendingTransaction": "1"]
            )
        }
        var issues: [ProjectStorageIssue] = []
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
        switch projectIndexReadState(for: scope) {
        case .missing:
            issues.append(storageIssue(
                kind: .projectIndexMissing,
                status: .blocked,
                projectID: projectID,
                title: "项目索引缺失",
                detail: "scope \(resolvedScopeName) 缺少 index.json，项目列表无法被完整信任。",
                actions: [.exportDiagnostics, .recoverMetadataShell]
            ))
        case let .readable(index):
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
        case .corrupt:
            issues.append(storageIssue(
                kind: .projectIndexCorrupt,
                status: .blocked,
                projectID: projectID,
                title: "项目索引损坏",
                detail: "index.json 无法按当前 ProjectIndex 格式解码。",
                actions: [.exportDiagnostics, .recoverMetadataShell]
            ))
        case let .unsupportedFuture(sourceVersion):
            issues.append(storageIssue(
                kind: .projectIndexCorrupt,
                status: .blocked,
                projectID: projectID,
                title: "项目索引版本过新",
                detail: "index.json 版本 \(sourceVersion) 高于当前支持版本 \(ProjectIndex.currentVersion)，只能导出诊断，不能读取或重建。",
                actions: [.exportDiagnostics]
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
                  let decodedProject = try? projectCodec.decode(metadataData),
                  decodedProject.project.id == projectID {
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
        var indexedChapterIDs: [ChapterDraft.ID] = []
        var indexedMetadata: [ChapterDraftMetadata] = []
        var canInspectChapterDirectoryForRecovery = true
        switch chapterIndexReadState(for: projectID, scope: scope) {
        case .missing:
            issues.append(storageIssue(
                kind: .chapterIndexMissing,
                status: (projectFromMetadata?.chapterCatalog.isEmpty ?? true) ? .warning : .blocked,
                projectID: projectID,
                title: "章节索引缺失",
                detail: "chapters/index.json 不存在，已保存章节目录无法完整恢复。",
                actions: [.exportDiagnostics, .rebuildChapterCatalog]
            ))
        case let .readable(index):
            indexedChapterIDs = index.chapterIDs
            indexedMetadata = index.chapters ?? []

            if index.hadDuplicateChapterIDs || index.hadDuplicateChapterMetadata {
                issues.append(storageIssue(
                    kind: .catalogFileMismatch,
                    status: .blocked,
                    projectID: projectID,
                    title: "章节索引包含重复 ID",
                    detail: "chapters/index.json 的重复 chapter ID 已按首次顺序规范化；重复 metadata 优先保留 savedAt 较新的项，相同时间保留首次出现项。",
                    actions: [.exportDiagnostics, .rebuildChapterCatalog]
                ))
            }

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
        case .corrupt:
            issues.append(storageIssue(
                kind: .chapterIndexCorrupt,
                status: .blocked,
                projectID: projectID,
                title: "章节索引损坏",
                detail: "chapters/index.json 无法按当前 ChapterIndex 格式解码。",
                actions: [.exportDiagnostics, .rebuildChapterCatalog]
            ))
        case let .unsupportedFuture(sourceVersion):
            canInspectChapterDirectoryForRecovery = false
            issues.append(storageIssue(
                kind: .chapterIndexCorrupt,
                status: .blocked,
                projectID: projectID,
                title: "章节索引版本过新",
                detail: "chapters/index.json 版本 \(sourceVersion) 高于当前支持版本 \(ChapterIndex.currentVersion)，只能导出诊断，不能读取或重建。",
                actions: [.exportDiagnostics]
            ))
        }

        for chapterID in indexedChapterIDs {
            switch chapterPayloadResolution(
                for: chapterID,
                projectID: projectID,
                scope: scope
            ) {
            case .missing:
                issues.append(storageIssue(
                    kind: .chapterFileMissing,
                    status: .blocked,
                    projectID: projectID,
                    chapterID: chapterID,
                    title: "章节文件缺失",
                    detail: "目录中记录了章节 \(chapterID)，但对应正文 JSON 不存在。",
                    actions: [.exportDiagnostics, .preserveMissingChapterPlaceholder]
                ))
            case .resolved:
                continue
            case let .invalid(_, reason):
                issues.append(storageIssue(
                    kind: .chapterFileCorrupt,
                    status: .blocked,
                    projectID: projectID,
                    chapterID: chapterID,
                    title: "章节文件损坏",
                    detail: "章节 \(chapterID) 的 JSON 文件无法安全读取：\(reason)",
                    actions: [.exportDiagnostics, .preserveMissingChapterPlaceholder]
                ))
            case let .conflict(_, _, reason):
                issues.append(storageIssue(
                    kind: .chapterFileCorrupt,
                    status: .blocked,
                    projectID: projectID,
                    chapterID: chapterID,
                    title: "章节正文副本冲突",
                    detail: "章节 \(chapterID) 的 canonical/legacy 正文无法安全归并：\(reason)",
                    actions: [.exportDiagnostics]
                ))
            }
        }

        var orphanFileNames: [String] = []
        if canInspectChapterDirectoryForRecovery {
            orphanFileNames = orphanChapterFileNames(
                in: chapterDirectory,
                indexedChapterIDs: Set(indexedChapterIDs)
            )
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
        if action != .exportDiagnostics {
            try recoverPendingTransactionIfNeeded(for: scope)
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
        do {
            try recoverPendingTransactionIfNeeded(for: scope)
        } catch {
            return ProjectLoadReport(
                projects: [],
                issues: [pendingTransactionRecoveryIssue(for: scope)]
            )
        }
        let indexState = projectIndexReadState(for: scope)
        if case let .unsupportedFuture(sourceVersion) = indexState {
            return ProjectLoadReport(
                projects: [],
                issues: [ProjectLoadIssue(
                    id: stableStorageID(parts: [
                        ProjectLoadIssueKind.unsupportedFutureProjectIndex.rawValue,
                        normalizedScope(scope) ?? "local",
                        "\(sourceVersion)"
                    ]),
                    kind: .unsupportedFutureProjectIndex,
                    scope: normalizedScope(scope),
                    projectID: nil,
                    path: projectIndexURL(for: scope).path,
                    sourceVersion: sourceVersion
                )]
            )
        }
        let shardedReport = loadShardedProjectsReport(
            for: scope,
            indexState: indexState
        )

        // A corrupt current-version index exposes only recoverable sharded
        // payloads and keeps the legacy file as untouched recovery evidence.
        // Future-version indexes return above without scanning any payloads.
        guard indexState.canPublishCurrentIndex else {
            return shardedReport ?? ProjectLoadReport(projects: [], issues: [])
        }

        let legacyReport = loadLegacyProjectsReport(for: scope)
        let shardedState = existingShardedProjectState(
            for: scope,
            indexState: indexState
        )

        switch (shardedReport, legacyReport) {
        case let (sharded?, legacy?):
            return mergeProjectLoadReports(
                sharded: sharded,
                legacy: legacy,
                blockedLegacyProjectIDs: shardedState.protectedProjectIDs,
                blockedLegacyDirectoryNames: shardedState.protectedDirectoryNames,
                scope: scope
            )
        case let (sharded?, nil):
            return sharded
        case let (nil, legacy?):
            return legacy
        case (nil, nil):
            return nil
        }
    }

    func loadProjects(for scope: String?) -> [NovelProject]? {
        loadProjectsReport(for: scope)?.projects
    }

    func saveProjects(_ projects: [NovelProject], for scope: String?) throws {
        accessLock.lock()
        defer { accessLock.unlock() }
        try migrateLegacyScopeDirectoryIfNeeded(for: scope)
        try recoverPendingTransactionIfNeeded(for: scope)
        try saveProjectsTransactionally(
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
        try migrateLegacyScopeDirectoryIfNeeded(for: scope)
        try recoverPendingTransactionIfNeeded(for: scope)
        try saveProjectsTransactionally(
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
        do {
            try recoverPendingTransactionIfNeeded(for: scope)
        } catch {
            return []
        }
        return loadProjectDeletionTombstonesWithoutLock(for: scope)
    }

    func hasProjects(for scope: String?) -> Bool {
        accessLock.lock()
        defer { accessLock.unlock() }
        return fileManager.fileExists(atPath: projectIndexURL(for: scope).path)
            || fileManager.fileExists(atPath: projectsFileURL(for: scope).path)
            || fileManager.fileExists(atPath: pendingTransactionURL(for: scope).path)
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

    private func loadShardedProjectsReport(
        for scope: String?,
        indexState: ProjectIndexReadState
    ) -> ProjectLoadReport? {
        let index: ProjectIndex
        switch indexState {
        case let .readable(readableIndex):
            index = readableIndex
        case .missing, .corrupt:
            return loadProjectsFromDirectoriesReport(for: scope)
        case .unsupportedFuture:
            return ProjectLoadReport(projects: [], issues: [])
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
                guard project.id == projectID else { continue }
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

        return ProjectLoadReport(
            projects: normalizedProjects(projects),
            issues: issues
        )
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
        projects = normalizedProjects(projects)
        projects.sort {
            if $0.updatedAtDate != $1.updatedAtDate {
                return $0.updatedAtDate > $1.updatedAtDate
            }
            return $0.id < $1.id
        }
        return ProjectLoadReport(projects: projects, issues: issues)
    }

    private func loadLegacyProjectsReport(for scope: String?) -> ProjectLoadReport? {
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

    private func mergeProjectLoadReports(
        sharded: ProjectLoadReport,
        legacy: ProjectLoadReport,
        blockedLegacyProjectIDs: Set<NovelProject.ID>,
        blockedLegacyDirectoryNames: Set<String>,
        scope: String?
    ) -> ProjectLoadReport {
        let tombstonesByProjectID = Dictionary(
            uniqueKeysWithValues: loadProjectDeletionTombstonesWithoutLock(for: scope).map {
                ($0.projectID, $0)
            }
        )
        let futureShardedProjectIDs = Set(sharded.issues.compactMap(\.projectID))
            .union(blockedLegacyProjectIDs)
        let eligibleLegacyProjects = legacy.projects.filter { legacyProject in
            if let tombstone = tombstonesByProjectID[legacyProject.id],
               tombstone.deletedAt >= legacyProject.updatedAtDate {
                return false
            }
            guard !futureShardedProjectIDs.contains(legacyProject.id) else {
                return false
            }
            guard !blockedLegacyDirectoryNames.contains(
                projectDirectoryName(for: legacyProject.id)
            ), !blockedLegacyDirectoryNames.contains(
                sanitizedStorageComponent(legacyProject.id)
            ) else {
                return false
            }
            return true
        }

        let projects = normalizedProjects(
            sharded.projects + eligibleLegacyProjects
        ).sorted {
            if $0.updatedAtDate != $1.updatedAtDate {
                return $0.updatedAtDate > $1.updatedAtDate
            }
            return $0.id < $1.id
        }
        var issuesByID: [String: ProjectLoadIssue] = [:]
        for issue in sharded.issues + legacy.issues {
            issuesByID[issue.id] = issue
        }
        return ProjectLoadReport(
            projects: projects,
            issues: issuesByID.values.sorted { $0.id < $1.id },
            skippedDocumentCount: sharded.skippedDocumentCount
                + legacy.skippedDocumentCount
        )
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
        var skippedDocumentCount = 0
        for (index, element) in elements.enumerated() {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(
                    withJSONObject: element,
                    options: [.sortedKeys]
                  ) else {
                skippedDocumentCount += 1
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
                skippedDocumentCount += 1
                continue
            }
        }
        if !elements.isEmpty, projects.isEmpty, issues.isEmpty {
            return nil
        }
        return ProjectLoadReport(
            projects: normalizedProjects(projects),
            issues: issues,
            skippedDocumentCount: skippedDocumentCount
        )
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
        guard (try? recoverPendingTransactionIfNeeded(for: scope)) != nil else {
            return nil
        }
        if case .unsupportedFuture = chapterIndexReadState(
            for: projectID,
            scope: scope
        ) {
            return nil
        }
        return loadChapterDraftWithoutRecovery(
            chapterID,
            for: projectID,
            scope: scope
        )
    }

    func loadChapterDrafts(for projectID: NovelProject.ID, scope: String?) -> [ChapterDraft] {
        accessLock.lock()
        defer { accessLock.unlock() }
        return loadChapterDraftReport(for: projectID, scope: scope).drafts
    }

    func loadChapterDraftReport(for projectID: NovelProject.ID, scope: String?) -> ChapterDraftLoadReport {
        accessLock.lock()
        defer { accessLock.unlock() }
        guard (try? recoverPendingTransactionIfNeeded(for: scope)) != nil else {
            return ChapterDraftLoadReport(drafts: [], missingChapterIDs: [])
        }
        let index: ChapterIndex
        switch chapterIndexReadState(for: projectID, scope: scope) {
        case let .readable(readableIndex):
            index = readableIndex
        case .missing, .corrupt, .unsupportedFuture:
            return ChapterDraftLoadReport(drafts: [], missingChapterIDs: [])
        }

        var drafts: [ChapterDraft] = []
        var missingChapterIDs: [ChapterDraft.ID] = []

        for chapterID in index.chapterIDs {
            if let draft = loadChapterDraftWithoutRecovery(
                chapterID,
                for: projectID,
                scope: scope
            ) {
                drafts.append(draft)
            } else {
                missingChapterIDs.append(chapterID)
            }
        }

        return ChapterDraftLoadReport(drafts: drafts, missingChapterIDs: missingChapterIDs)
    }

    private func loadChapterMetadata(for projectID: NovelProject.ID, scope: String?) -> [ChapterDraftMetadata] {
        let index: ChapterIndex
        switch chapterIndexReadState(for: projectID, scope: scope) {
        case let .readable(readableIndex):
            index = readableIndex
        case .missing, .corrupt:
            return decodedChapterDrafts(in: chapterDirectoryURL(for: projectID, scope: scope))
                .map(ChapterDraftMetadata.init)
                .sorted(by: ChapterDraftMetadata.sortDescending)
        case .unsupportedFuture:
            return []
        }

        if let chapters = index.chapters, !chapters.isEmpty {
            return chapters
        }

        return index.chapterIDs
            .compactMap {
                loadChapterDraftWithoutRecovery(
                    $0,
                    for: projectID,
                    scope: scope
                )
            }
            .map(ChapterDraftMetadata.init)
            .sorted(by: ChapterDraftMetadata.sortDescending)
    }

    private func loadChapterDraftWithoutRecovery(
        _ chapterID: ChapterDraft.ID,
        for projectID: NovelProject.ID,
        scope: String?
    ) -> ChapterDraft? {
        guard case let .resolved(chapter, _, _, _, _, _) = chapterPayloadResolution(
            for: chapterID,
            projectID: projectID,
            scope: scope
        ) else {
            return nil
        }
        return chapter
    }

    private func projectIndexReadState(for scope: String?) -> ProjectIndexReadState {
        let indexURL = projectIndexURL(for: scope)
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return .missing
        }
        guard let indexData = try? Data(contentsOf: indexURL) else {
            return .corrupt
        }
        if let sourceVersion = decodedIndexVersion(in: indexData),
           sourceVersion > ProjectIndex.currentVersion {
            return .unsupportedFuture(sourceVersion)
        }
        guard let index = try? decoder.decode(ProjectIndex.self, from: indexData) else {
            return .corrupt
        }
        return .readable(index)
    }

    private func chapterIndexReadState(
        for projectID: NovelProject.ID,
        scope: String?
    ) -> ChapterIndexReadState {
        let indexURL = chapterIndexURL(for: projectID, scope: scope)
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return .missing
        }
        guard let indexData = try? Data(contentsOf: indexURL) else {
            return .corrupt
        }
        if let sourceVersion = decodedIndexVersion(in: indexData),
           sourceVersion > ChapterIndex.currentVersion {
            return .unsupportedFuture(sourceVersion)
        }
        guard let index = try? decoder.decode(ChapterIndex.self, from: indexData) else {
            return .corrupt
        }
        return .readable(index)
    }

    private func decodedIndexVersion(in data: Data) -> Int? {
        guard let header = try? decoder.decode(IndexVersionHeader.self, from: data) else {
            return nil
        }
        return header.version
    }

    private func existingShardedProjectState(
        for scope: String?,
        indexState: ProjectIndexReadState
    ) -> ExistingShardedProjectState {
        let projectsDirectory = scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects", isDirectory: true)
        let directories = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        let directoryNames = Set(directories.map(\.lastPathComponent))
        var readableProjects: [NovelProject] = []
        var protectedProjectIDs = Set<NovelProject.ID>()
        var protectedDirectoryNames = Set<String>()

        switch indexState {
        case let .readable(index):
            let indexedDirectoryNames = Set(
                index.projectIDs.compactMap {
                    existingProjectDirectoryURL(
                        for: $0,
                        scope: scope
                    )?.lastPathComponent
                }
            )
            protectedDirectoryNames.formUnion(
                directoryNames.subtracting(indexedDirectoryNames)
            )

            for projectID in index.projectIDs {
                let directoryName = existingProjectDirectoryURL(
                    for: projectID,
                    scope: scope
                )?.lastPathComponent ?? projectDirectoryName(for: projectID)
                let metadataURL = projectMetadataURL(for: projectID, scope: scope)
                guard let data = try? Data(contentsOf: metadataURL),
                      let decoded = try? projectCodec.decode(data),
                      decoded.project.id == projectID else {
                    protectedProjectIDs.insert(projectID)
                    protectedDirectoryNames.insert(directoryName)
                    continue
                }
                var project = decoded.project
                project.chapterCatalog = loadChapterMetadata(
                    for: project.id,
                    scope: scope
                )
                project.chapterDrafts = []
                readableProjects.append(project)
            }
            readableProjects = normalizedProjects(readableProjects)

        case .missing, .corrupt:
            for directory in directories {
                let metadataURL = directory
                    .appendingPathComponent("project.json", isDirectory: false)
                guard let data = try? Data(contentsOf: metadataURL) else {
                    protectedDirectoryNames.insert(directory.lastPathComponent)
                    continue
                }

                guard let decoded = try? projectCodec.decode(data) else {
                    protectedDirectoryNames.insert(directory.lastPathComponent)
                    if let projectID = projectID(in: data) {
                        protectedProjectIDs.insert(projectID)
                    }
                    continue
                }

                var project = decoded.project
                project.chapterCatalog = loadChapterMetadata(
                    for: project.id,
                    scope: scope
                )
                project.chapterDrafts = []
                readableProjects.append(project)
                if directory.lastPathComponent
                    != projectDirectoryName(for: project.id) {
                    protectedDirectoryNames.insert(directory.lastPathComponent)
                }
            }
            readableProjects = normalizedProjects(readableProjects).sorted {
                if $0.updatedAtDate != $1.updatedAtDate {
                    return $0.updatedAtDate > $1.updatedAtDate
                }
                return $0.id < $1.id
            }
        case .unsupportedFuture:
            protectedDirectoryNames.formUnion(directoryNames)
        }

        return ExistingShardedProjectState(
            readableProjects: readableProjects,
            protectedProjectIDs: protectedProjectIDs,
            protectedDirectoryNames: protectedDirectoryNames
        )
    }

    private func saveShardedProjects(
        _ projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone],
        for scope: String?
    ) throws {
        let indexState = projectIndexReadState(for: scope)
        guard indexState.canPublishCurrentIndex else {
            throw recoveryError(
                "项目索引无法按当前版本读取；已保留原始 index.json 和全部分片文件，请先通过存储恢复流程处理。"
            )
        }
        let shardedState = existingShardedProjectState(
            for: scope,
            indexState: indexState
        )
        let legacyReport = loadLegacyProjectsReport(for: scope)
        let normalizedDeletedProjects = ProjectDeletionTombstone.normalized(deletedProjects)
        let tombstonesByProjectID = Dictionary(
            uniqueKeysWithValues: normalizedDeletedProjects.map { ($0.projectID, $0) }
        )
        let projectIsProtected: (NovelProject) -> Bool = { project in
            shardedState.protectedProjectIDs.contains(project.id)
        }
        let readableIncomingProjects = projects.filter {
            !projectIsProtected($0)
        }
        let readableLegacyProjects = (legacyReport?.projects ?? []).filter {
            !projectIsProtected($0)
        }
        let normalizedIncomingProjects = normalizedProjects(
            readableIncomingProjects
        )
        let candidateProjects = normalizedProjects(
            normalizedIncomingProjects
                + shardedState.readableProjects
                + readableLegacyProjects
        )
        let incomingProjectsByID = Dictionary(
            uniqueKeysWithValues: normalizedIncomingProjects.map {
                ($0.id, $0)
            }
        )
        let projectsWithAuthoritativeTies = candidateProjects.map { candidate in
            guard let incoming = incomingProjectsByID[candidate.id],
                  incoming.updatedAtDate >= candidate.updatedAtDate else {
                return candidate
            }
            // A save request is the authoritative in-memory snapshot when its
            // timestamp ties the recovered disk value. Canonical ordering is
            // still used to deduplicate one input batch above, but must not
            // turn a legitimate same-timestamp edit back into old disk data.
            return incoming
        }
        let resolvedProjects = projectsWithAuthoritativeTies.filter { project in
            guard let tombstone = tombstonesByProjectID[project.id] else { return true }
            return project.updatedAtDate > tombstone.deletedAt
        }
        for project in resolvedProjects {
            try ensureChapterIndexIsNotFuture(
                for: project.id,
                scope: scope
            )
        }

        let scopeURL = scopeDirectoryURL(for: scope)
        let projectsDirectory = scopeURL.appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(
            at: projectsDirectory,
            withIntermediateDirectories: true
        )
        let incomingProjectIDs = Set(resolvedProjects.map(\.id))
        let protection = existingProjectProtection(
            for: scope,
            excluding: incomingProjectIDs,
            tombstonesByProjectID: tombstonesByProjectID
        )
        let combinedProtection = ExistingProjectProtection(
            indexedProjectIDs: uniqueIDs(
                protection.indexedProjectIDs
                    + shardedState.protectedProjectIDs.sorted()
            ),
            directoryNames: protection.directoryNames
                .union(shardedState.protectedDirectoryNames),
            updatedAtByProjectID: protection.updatedAtByProjectID
        )
        let finalProjectUpdatedAt = Dictionary(
            uniqueKeysWithValues: resolvedProjects.map { ($0.id, $0.updatedAtDate) }
        ).merging(combinedProtection.updatedAtByProjectID) { incoming, _ in incoming }
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
            projectIDs: resolvedProjects.map(\.id) + combinedProtection.indexedProjectIDs,
            deletedProjects: resolvedDeletedProjects
        )
        try writeIfChanged(try encoder.encode(index), to: projectIndexURL(for: scope))

        try removeDeletedProjectDirectories(
            keeping: incomingProjectIDs,
            protectedDirectoryNames: combinedProtection.directoryNames,
            scope: scope
        )
        let legacyURL = projectsFileURL(for: scope)
        if fileManager.fileExists(atPath: legacyURL.path),
           canRemoveLegacyProjectsFile(
                report: legacyReport,
                persistedProjectUpdatedAt: finalProjectUpdatedAt,
                deletedProjects: resolvedDeletedProjects
           ) {
            try? fileManager.removeItem(at: legacyURL)
        }
    }

    private func saveProjectsTransactionally(
        _ projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone],
        for scope: String?
    ) throws {
        try preflightPendingTransaction(projects: projects, for: scope)
        let transaction = PendingProjectTransaction(
            projects: projects,
            deletedProjects: deletedProjects
        )
        let transactionURL = pendingTransactionURL(for: scope)
        try writeIfChanged(
            try encoder.encode(transaction),
            to: transactionURL,
            invokeTestHook: false
        )

        try saveShardedProjects(
            transaction.projects,
            deletedProjects: transaction.deletedProjects,
            for: scope
        )
        try removePendingTransaction(at: transactionURL)
    }

    private func recoverPendingTransactionIfNeeded(for scope: String?) throws {
        let transactionURL = pendingTransactionURL(for: scope)
        guard fileManager.fileExists(atPath: transactionURL.path) else {
            return
        }

        let data = try Data(contentsOf: transactionURL)
        let transaction = try decoder.decode(PendingProjectTransaction.self, from: data)
        guard transaction.version == PendingProjectTransaction.currentVersion else {
            throw recoveryError(
                "未完成项目事务的版本 \(transaction.version) 高于当前支持版本；已停止加载并保留事务文件。"
            )
        }

        try preflightPendingTransaction(
            projects: transaction.projects,
            for: scope
        )
        try saveShardedProjects(
            transaction.projects,
            deletedProjects: transaction.deletedProjects,
            for: scope
        )
        try removePendingTransaction(at: transactionURL)
    }

    private func preflightPendingTransaction(
        projects: [NovelProject],
        for scope: String?
    ) throws {
        let indexState = projectIndexReadState(for: scope)
        guard indexState.canPublishCurrentIndex else {
            throw recoveryError(
                "项目索引无法按当前版本读取；已保留原始 index.json、全部分片文件和未完成事务。"
            )
        }

        var projectIDs = Set(projects.map(\.id))
        if case let .readable(index) = indexState {
            projectIDs.formUnion(index.projectIDs)
        }
        let projectsDirectory = projectsDirectoryURL(for: scope)
        let directoryURLs = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        for directoryURL in directoryURLs {
            let metadataURL = directoryURL.appendingPathComponent(
                "project.json",
                isDirectory: false
            )
            guard let data = try? Data(contentsOf: metadataURL),
                  let decodedProject = try? projectCodec.decode(data).project else {
                continue
            }
            projectIDs.insert(decodedProject.id)
        }

        for projectID in projectIDs {
            try ensureChapterIndexIsNotFuture(for: projectID, scope: scope)
            try ensureChapterPayloadsCanBeSafelyReconciled(
                for: projectID,
                scope: scope
            )
        }
    }

    private func removePendingTransaction(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try testHooks.beforeRemoveItem?(url)
        try fileManager.removeItem(at: url)
        writeCache.remove(url)
    }

    private func pendingTransactionRecoveryIssue(
        for scope: String?
    ) -> ProjectLoadIssue {
        ProjectLoadIssue(
            id: stableStorageID(parts: [
                ProjectLoadIssueKind.pendingTransactionRecoveryFailure.rawValue,
                normalizedScope(scope) ?? "local"
            ]),
            kind: .pendingTransactionRecoveryFailure,
            scope: normalizedScope(scope),
            projectID: nil,
            path: pendingTransactionURL(for: scope).path,
            sourceVersion: PendingProjectTransaction.currentVersion
        )
    }

    private func canRemoveLegacyProjectsFile(
        report: ProjectLoadReport?,
        persistedProjectUpdatedAt: [NovelProject.ID: Date],
        deletedProjects: [ProjectDeletionTombstone]
    ) -> Bool {
        guard let report,
              report.issues.isEmpty,
              report.skippedDocumentCount == 0
        else {
            return false
        }
        let tombstonesByProjectID = Dictionary(
            uniqueKeysWithValues: deletedProjects.map { ($0.projectID, $0) }
        )
        return report.projects.allSatisfy { project in
            if let persistedUpdatedAt = persistedProjectUpdatedAt[project.id],
               persistedUpdatedAt >= project.updatedAtDate {
                return true
            }
            guard let tombstone = tombstonesByProjectID[project.id] else {
                return false
            }
            return tombstone.deletedAt >= project.updatedAtDate
        }
    }

    private func normalizedProjects(
        _ projects: [NovelProject]
    ) -> [NovelProject] {
        var orderedProjectIDs: [NovelProject.ID] = []
        var projectsByID: [NovelProject.ID: NovelProject] = [:]

        for project in projects {
            guard let existing = projectsByID[project.id] else {
                orderedProjectIDs.append(project.id)
                projectsByID[project.id] = project
                continue
            }
            if project.updatedAtDate > existing.updatedAtDate {
                projectsByID[project.id] = project
            } else if project.updatedAtDate == existing.updatedAtDate,
                      canonicalProjectTieBreakData(existing)
                        .lexicographicallyPrecedes(canonicalProjectTieBreakData(project)) {
                projectsByID[project.id] = project
            }
        }

        return orderedProjectIDs.compactMap { projectsByID[$0] }
    }

    private func canonicalProjectTieBreakData(_ project: NovelProject) -> Data {
        if let data = try? projectCodec.encode(project) {
            return data
        }

        // Invalid in-memory floating-point values can make JSONEncoder fail.
        // They cannot originate from a valid stored document, but keep the
        // fallback deterministic rather than reverting to input order.
        return Data([
            project.id,
            project.title,
            project.genre,
            project.summary,
            project.storyLength.rawValue,
            String(project.updatedAtDate.timeIntervalSince1970)
        ].joined(separator: "\u{1F}").utf8)
    }

    private func existingProjectProtection(
        for scope: String?,
        excluding incomingProjectIDs: Set<NovelProject.ID>,
        tombstonesByProjectID: [NovelProject.ID: ProjectDeletionTombstone]
    ) -> ExistingProjectProtection {
        let projectsDirectory = projectsDirectoryURL(for: scope)
        let directoryNames = Set(
            (try? fileManager.contentsOfDirectory(
                at: projectsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ))?.map(\.lastPathComponent) ?? []
        )
        let incomingDirectoryNames = Set(incomingProjectIDs.map(projectDirectoryName))

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
            Set(index.projectIDs.compactMap {
                existingProjectDirectoryURL(
                    for: $0,
                    scope: scope
                )?.lastPathComponent
            })
        )
        var updatedAtByProjectID: [NovelProject.ID: Date] = [:]

        for projectID in index.projectIDs where !incomingProjectIDs.contains(projectID) {
            let metadataURL = projectMetadataURL(for: projectID, scope: scope)
            guard let data = try? Data(contentsOf: metadataURL),
                  let project = try? projectCodec.decode(data).project,
                  project.id == projectID
            else {
                protectedProjectIDs.append(projectID)
                if let existingDirectory = existingProjectDirectoryURL(
                    for: projectID,
                    scope: scope
                ) {
                    protectedDirectoryNames.insert(existingDirectory.lastPathComponent)
                }
                continue
            }
            if let tombstone = tombstonesByProjectID[projectID],
               tombstone.deletedAt >= project.updatedAtDate {
                continue
            }
            protectedProjectIDs.append(projectID)
            if let existingDirectory = existingProjectDirectoryURL(
                for: projectID,
                scope: scope
            ) {
                protectedDirectoryNames.insert(existingDirectory.lastPathComponent)
            }
            updatedAtByProjectID[projectID] = project.updatedAtDate
        }

        return ExistingProjectProtection(
            indexedProjectIDs: protectedProjectIDs,
            directoryNames: protectedDirectoryNames,
            updatedAtByProjectID: updatedAtByProjectID
        )
    }

    private func saveProject(_ project: NovelProject, scope: String?) throws {
        try ensureChapterIndexIsNotFuture(
            for: project.id,
            scope: scope
        )
        try migrateLegacyProjectDirectoryIfNeeded(
            for: project.id,
            scope: scope
        )
        let chaptersDirectory = chapterDirectoryURL(for: project.id, scope: scope)
        try fileManager.createDirectory(at: chaptersDirectory, withIntermediateDirectories: true)
        try reconcileChapterPayloadsIfSafe(
            for: project.id,
            scope: scope
        )
        let chapterIndexWasReadable: Bool
        if case .readable = chapterIndexReadState(for: project.id, scope: scope) {
            chapterIndexWasReadable = true
        } else {
            chapterIndexWasReadable = false
        }

        let chapterCatalog = resolvedChapterCatalog(
            for: project,
            preservingStoredChapters: !chapterIndexWasReadable,
            scope: scope
        )

        for chapterID in chapterCatalog.map(\.id) {
            try migrateLegacyChapterFileIfNeeded(
                chapterID,
                for: project.id,
                scope: scope
            )
        }
        for chapterDraft in project.chapterDrafts {
            let chapterData = try encoder.encode(chapterDraft)
            try writeIfChanged(
                chapterData,
                to: canonicalChapterURL(
                    for: chapterDraft.id,
                    projectID: project.id,
                    scope: scope
                )
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
        var catalogByID = Self.chapterMetadataByID(project.chapterCatalog)
        for chapterDraft in project.chapterDrafts {
            catalogByID[chapterDraft.id] = ChapterDraftMetadata(chapterDraft: chapterDraft)
        }
        let directory = chapterDirectoryURL(for: project.id, scope: scope)
        for chapterDraft in decodedChapterDrafts(in: directory) {
            if preservingStoredChapters || catalogByID[chapterDraft.id] != nil {
                var storedMetadata = ChapterDraftMetadata(chapterDraft: chapterDraft)
                storedMetadata.savedAt = PersistedTimestampCodec.storageValue(
                    for: chapterDraft.savedAtDate
                )
                if let current = catalogByID[chapterDraft.id],
                   current.savedAtDate >= storedMetadata.savedAtDate {
                    continue
                }
                catalogByID[chapterDraft.id] = storedMetadata
            }
        }

        return catalogByID.values.sorted(by: ChapterDraftMetadata.sortDescending)
    }

    private static func normalizedChapterIDs(
        _ chapterIDs: [ChapterDraft.ID]
    ) -> [ChapterDraft.ID] {
        var seen = Set<ChapterDraft.ID>()
        return chapterIDs.filter { seen.insert($0).inserted }
    }

    private static func normalizedChapterMetadata(
        _ chapters: [ChapterDraftMetadata]
    ) -> [ChapterDraftMetadata] {
        var orderedIDs: [ChapterDraft.ID] = []
        var metadataByID: [ChapterDraft.ID: ChapterDraftMetadata] = [:]

        for metadata in chapters {
            guard let current = metadataByID[metadata.id] else {
                orderedIDs.append(metadata.id)
                metadataByID[metadata.id] = metadata
                continue
            }
            if metadata.savedAtDate > current.savedAtDate {
                metadataByID[metadata.id] = metadata
            }
            // Equal timestamps intentionally keep the first metadata value.
            // This preserves the source order and makes repeated normalization stable.
        }

        return orderedIDs.compactMap { metadataByID[$0] }
    }

    private static func chapterMetadataByID(
        _ chapters: [ChapterDraftMetadata]
    ) -> [ChapterDraft.ID: ChapterDraftMetadata] {
        var metadataByID: [ChapterDraft.ID: ChapterDraftMetadata] = [:]
        for metadata in normalizedChapterMetadata(chapters) {
            metadataByID[metadata.id] = metadata
        }
        return metadataByID
    }

    private func ensureChapterIndexIsNotFuture(
        for projectID: NovelProject.ID,
        scope: String?
    ) throws {
        guard case let .unsupportedFuture(sourceVersion) = chapterIndexReadState(
            for: projectID,
            scope: scope
        ) else {
            return
        }
        throw recoveryError(
            "项目 \(projectID) 的章节索引版本 \(sourceVersion) 高于当前支持版本；已保留原始章节索引和项目分片。"
        )
    }

    private func writeIfChanged(
        _ data: Data,
        to url: URL,
        invokeTestHook: Bool = true
    ) throws {
        let fingerprint = ProjectFileFingerprint(size: data.count, hash: stableHash(data))
        let currentIdentity = ProjectFileIdentity.read(from: url)
        if let cached = writeCache.entry(for: url),
           cached.fingerprint == fingerprint,
           cached.identity == currentIdentity,
           currentIdentity != nil {
            return
        }

        if currentIdentity != nil {
            testHooks.onExistingFileVerificationRead?(url)
        }
        if let existingData = try? Data(contentsOf: url), existingData == data {
            writeCache.set(
                ProjectFileWriteCacheEntry(
                    fingerprint: fingerprint,
                    identity: currentIdentity
                ),
                for: url
            )
            return
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if invokeTestHook {
            try testHooks.beforeAtomicWrite?(url)
        }
        try DurableAtomicFileWriter.write(data, to: url)
        writeCache.set(
            ProjectFileWriteCacheEntry(
                fingerprint: fingerprint,
                identity: ProjectFileIdentity.read(from: url)
            ),
            for: url
        )
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
        let projectsDirectory = projectsDirectoryURL(for: scope)
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let expectedDirectoryNames = Set(projectIDs.map(projectDirectoryName))
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

        let expectedFileNames = Set(chapterIDs.map(chapterFileName))
        let legacyFileNamesForRetainedChapters = Set(chapterIDs.map(legacyChapterFileName))
        for url in directoryContents where url.lastPathComponent != "index.json" && !expectedFileNames.contains(url.lastPathComponent) {
            if legacyFileNamesForRetainedChapters.contains(url.lastPathComponent) {
                throw recoveryError(
                    "保留章节的 legacy 正文尚未完成 canonical 归并；已停止清理 \(url.lastPathComponent)。"
                )
            }
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

        let expectedFileNames = Set(
            indexedChapterIDs.flatMap {
                [
                    chapterFileName(for: $0),
                    legacyChapterFileName(for: $0)
                ]
            }
        )
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

        let fileName = uniqueArtifactFileName(
            prefix: "storage-health",
            projectID: projectID
        )
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
        try ensureProjectIndexIsNotFuture(scope: scope)
        try ensureChapterIndexIsNotFuture(for: projectID, scope: scope)
        try migrateLegacyProjectDirectoryIfNeeded(
            for: projectID,
            scope: scope
        )
        let chapterDirectory = chapterDirectoryURL(for: projectID, scope: scope)
        try fileManager.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        try ensureChapterPayloadsCanBeSafelyReconciled(
            for: projectID,
            scope: scope
        )
        try reconcileChapterPayloadsIfSafe(
            for: projectID,
            scope: scope
        )

        for draft in project?.chapterDrafts ?? [] {
            try writeIfChanged(
                try encoder.encode(draft),
                to: canonicalChapterURL(
                    for: draft.id,
                    projectID: projectID,
                    scope: scope
                )
            )
        }

        let decodedDrafts = decodedChapterDrafts(in: chapterDirectory)
        for draft in decodedDrafts {
            try migrateLegacyChapterFileIfNeeded(
                draft.id,
                for: projectID,
                scope: scope
            )
        }
        var metadataByID: [ChapterDraft.ID: ChapterDraftMetadata] = [:]
        let currentMetadataByID = Self.chapterMetadataByID(project?.chapterCatalog ?? [])
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
        try ensureProjectIndexIsNotFuture(scope: scope)
        try ensureChapterIndexIsNotFuture(for: projectID, scope: scope)
        try ensureChapterPayloadsCanBeSafelyReconciled(
            for: projectID,
            scope: scope
        )
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
        try ensureProjectIndexIsNotFuture(scope: scope)
        try ensureChapterIndexIsNotFuture(for: project.id, scope: scope)
        try migrateLegacyProjectDirectoryIfNeeded(
            for: project.id,
            scope: scope
        )
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

    private func ensureProjectIndexIsNotFuture(scope: String?) throws {
        guard case let .unsupportedFuture(sourceVersion) = projectIndexReadState(
            for: scope
        ) else {
            return
        }
        throw recoveryError(
            "项目索引版本 \(sourceVersion) 高于当前支持版本；已保留原始 index.json 和全部分片文件。"
        )
    }

    private func writeCloudConflictMarker(issue: ProjectStorageIssue, scope: String?) throws -> URL {
        let conflictDirectory = scopeDirectoryURL(for: scope)
            .appendingPathComponent("conflicts", isDirectory: true)
        try fileManager.createDirectory(at: conflictDirectory, withIntermediateDirectories: true)
        let outputURL = conflictDirectory
            .appendingPathComponent(
                uniqueArtifactFileName(
                    prefix: "cloud-conflict",
                    projectID: issue.projectID
                )
            )
        try writeIfChanged(try encoder.encode(issue), to: outputURL)
        return outputURL
    }

    private func decodedChapterDrafts(in chapterDirectory: URL) -> [ChapterDraft] {
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: chapterDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var discoveredDraftsByID: [ChapterDraft.ID: ChapterDraft] = [:]
        let chapterURLs = directoryContents
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .sorted(by: { $0.path < $1.path })
        for url in chapterURLs {
            guard let data = try? Data(contentsOf: url),
                  let draft = try? decoder.decode(ChapterDraft.self, from: data) else {
                continue
            }
            discoveredDraftsByID[draft.id] = discoveredDraftsByID[draft.id] ?? draft
        }

        var resolvedDraftsByID: [ChapterDraft.ID: ChapterDraft] = [:]
        for chapterID in discoveredDraftsByID.keys.sorted() {
            switch chapterPayloadResolution(
                for: chapterID,
                in: chapterDirectory
            ) {
            case let .resolved(draft, _, _, _, _, _):
                resolvedDraftsByID[chapterID] = draft
            case .missing:
                resolvedDraftsByID[chapterID] = discoveredDraftsByID[chapterID]
            case .invalid, .conflict:
                break
            }
        }

        return resolvedDraftsByID.values
            .sorted(by: ChapterDraft.sortDescending)
    }

    private func loadProjectMetadata(for projectID: NovelProject.ID, scope: String?) -> NovelProject? {
        let metadataURL = projectMetadataURL(for: projectID, scope: scope)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        guard let project = try? projectCodec.decode(data).project,
              project.id == projectID else {
            return nil
        }
        return project
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
            .appendingPathComponent(projectArtifactComponent(for: projectID), isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let backupName = [
            chapterURL.deletingPathExtension().lastPathComponent,
            sanitizedStorageComponent(reason),
            Self.diagnosticTimestamp(),
            UUID().uuidString
        ].joined(separator: "-") + ".json"
        let backupURL = backupDirectory.appendingPathComponent(backupName, isDirectory: false)
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

    private func pendingTransactionURL(for scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent(".pending-project-transaction.json", isDirectory: false)
    }

    private func projectDirectoryURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        existingProjectDirectoryURL(for: projectID, scope: scope)
            ?? canonicalProjectDirectoryURL(for: projectID, scope: scope)
    }

    private func canonicalProjectDirectoryURL(
        for projectID: NovelProject.ID,
        scope: String?
    ) -> URL {
        projectsDirectoryURL(for: scope)
            .appendingPathComponent(projectDirectoryName(for: projectID), isDirectory: true)
    }

    private func legacyProjectDirectoryURL(
        for projectID: NovelProject.ID,
        scope: String?
    ) -> URL {
        projectsDirectoryURL(for: scope)
            .appendingPathComponent(sanitizedStorageComponent(projectID), isDirectory: true)
    }

    private func projectsDirectoryURL(for scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects", isDirectory: true)
    }

    private func existingProjectDirectoryURL(
        for projectID: NovelProject.ID,
        scope: String?
    ) -> URL? {
        let candidates = [
            canonicalProjectDirectoryURL(for: projectID, scope: scope),
            legacyProjectDirectoryURL(for: projectID, scope: scope)
        ]
        var seenPaths = Set<String>()
        for directory in candidates where seenPaths.insert(directory.path).inserted {
            let metadataURL = directory.appendingPathComponent(
                "project.json",
                isDirectory: false
            )
            guard let data = try? Data(contentsOf: metadataURL),
                  self.projectID(in: data) == projectID else {
                continue
            }
            return directory
        }
        return nil
    }

    private func migrateLegacyProjectDirectoryIfNeeded(
        for projectID: NovelProject.ID,
        scope: String?
    ) throws {
        let canonicalURL = canonicalProjectDirectoryURL(for: projectID, scope: scope)
        guard !fileManager.fileExists(atPath: canonicalURL.path) else { return }

        let legacyURL = legacyProjectDirectoryURL(for: projectID, scope: scope)
        guard legacyURL.path != canonicalURL.path,
              fileManager.fileExists(atPath: legacyURL.path),
              existingProjectDirectoryURL(for: projectID, scope: scope)?.path == legacyURL.path else {
            return
        }

        try fileManager.moveItem(at: legacyURL, to: canonicalURL)
        writeCache.removeItems(under: legacyURL)
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
        switch chapterPayloadResolution(
            for: chapterID,
            projectID: projectID,
            scope: scope
        ) {
        case let .missing(canonicalURL):
            return canonicalURL
        case let .invalid(url, _):
            return url
        case let .resolved(_, _, sourceURL, _, _, _):
            return sourceURL
        case let .conflict(canonicalURL, _, _):
            return canonicalURL
        }
    }

    private func canonicalChapterURL(
        for chapterID: ChapterDraft.ID,
        projectID: NovelProject.ID,
        scope: String?
    ) -> URL {
        chapterDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent(chapterFileName(for: chapterID), isDirectory: false)
    }

    private func legacyChapterURL(
        for chapterID: ChapterDraft.ID,
        projectID: NovelProject.ID,
        scope: String?
    ) -> URL {
        chapterDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent(legacyChapterFileName(for: chapterID), isDirectory: false)
    }

    private func chapterFileName(for chapterID: ChapterDraft.ID) -> String {
        let sanitizedPrefix = String(sanitizedStorageComponent(chapterID).prefix(48))
        let readablePrefix = sanitizedPrefix.isEmpty ? "chapter" : sanitizedPrefix
        let hashSuffix = stableStorageID(parts: ["chapter-file", chapterID])
        return "\(readablePrefix)--\(hashSuffix).json"
    }

    private func legacyChapterFileName(for chapterID: ChapterDraft.ID) -> String {
        "\(sanitizedStorageComponent(chapterID)).json"
    }

    private func chapterPayloadResolution(
        for chapterID: ChapterDraft.ID,
        projectID: NovelProject.ID,
        scope: String?
    ) -> ChapterPayloadResolution {
        chapterPayloadResolution(
            for: chapterID,
            in: chapterDirectoryURL(for: projectID, scope: scope)
        )
    }

    private func chapterPayloadResolution(
        for chapterID: ChapterDraft.ID,
        in chapterDirectory: URL
    ) -> ChapterPayloadResolution {
        let canonicalURL = chapterDirectory
            .appendingPathComponent(chapterFileName(for: chapterID), isDirectory: false)
        let legacyURL = chapterDirectory
            .appendingPathComponent(legacyChapterFileName(for: chapterID), isDirectory: false)
        let canonical = chapterPayloadCandidate(
            at: canonicalURL,
            expectedChapterID: chapterID
        )
        guard canonicalURL.path != legacyURL.path else {
            switch canonical {
            case .missing:
                return .missing(canonicalURL: canonicalURL)
            case let .invalid(url, reason):
                return .invalid(url: url, reason: reason)
            case let .valid(url, data, draft, _):
                return .resolved(
                    draft: draft,
                    data: data,
                    sourceURL: url,
                    canonicalURL: canonicalURL,
                    legacyURL: legacyURL,
                    legacyFileExists: false
                )
            }
        }

        let legacy = chapterPayloadCandidate(
            at: legacyURL,
            expectedChapterID: chapterID
        )
        switch (canonical, legacy) {
        case (.missing, .missing):
            return .missing(canonicalURL: canonicalURL)
        case let (.valid(url, data, draft, _), .missing):
            return .resolved(
                draft: draft,
                data: data,
                sourceURL: url,
                canonicalURL: canonicalURL,
                legacyURL: legacyURL,
                legacyFileExists: false
            )
        case let (.missing, .valid(url, data, draft, _)):
            return .resolved(
                draft: draft,
                data: data,
                sourceURL: url,
                canonicalURL: canonicalURL,
                legacyURL: legacyURL,
                legacyFileExists: true
            )
        case let (.invalid(url, reason), .missing),
             let (.missing, .invalid(url, reason)):
            return .invalid(url: url, reason: reason)
        case let (
            .valid(canonicalURL, canonicalData, canonicalDraft, canonicalTimestamp),
            .valid(_, legacyData, legacyDraft, legacyTimestamp)
        ):
            guard let canonicalTimestamp, let legacyTimestamp else {
                return .conflict(
                    canonicalURL: canonicalURL,
                    legacyURL: legacyURL,
                    reason: "两个正文文件同时存在，但至少一个缺少可解析的 persisted savedAt/updatedAt；原文件均已保留。"
                )
            }
            if canonicalTimestamp > legacyTimestamp {
                return .resolved(
                    draft: canonicalDraft,
                    data: canonicalData,
                    sourceURL: canonicalURL,
                    canonicalURL: canonicalURL,
                    legacyURL: legacyURL,
                    legacyFileExists: true
                )
            }
            if legacyTimestamp > canonicalTimestamp {
                return .resolved(
                    draft: legacyDraft,
                    data: legacyData,
                    sourceURL: legacyURL,
                    canonicalURL: canonicalURL,
                    legacyURL: legacyURL,
                    legacyFileExists: true
                )
            }
            guard canonicalDraft == legacyDraft else {
                return .conflict(
                    canonicalURL: canonicalURL,
                    legacyURL: legacyURL,
                    reason: "两个正文文件的 persisted savedAt/updatedAt 相同，但正文或版本内容不同；原文件均已保留。"
                )
            }
            return .resolved(
                draft: canonicalDraft,
                data: canonicalData,
                sourceURL: canonicalURL,
                canonicalURL: canonicalURL,
                legacyURL: legacyURL,
                legacyFileExists: true
            )
        case let (.invalid(_, canonicalReason), .invalid(_, legacyReason)):
            return .conflict(
                canonicalURL: canonicalURL,
                legacyURL: legacyURL,
                reason: "canonical 文件\(canonicalReason)；legacy 文件\(legacyReason)。"
            )
        case let (.invalid(_, reason), .valid),
             let (.valid, .invalid(_, reason)):
            return .conflict(
                canonicalURL: canonicalURL,
                legacyURL: legacyURL,
                reason: "两个正文文件同时存在，但其中一个\(reason)；为避免覆盖可恢复副本，已停止读取和清理。"
            )
        }
    }

    private func chapterPayloadCandidate(
        at url: URL,
        expectedChapterID: ChapterDraft.ID
    ) -> ChapterPayloadCandidate {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing(url)
        }
        guard let data = try? Data(contentsOf: url) else {
            return .invalid(url: url, reason: "无法读取")
        }
        guard var draft = try? decoder.decode(ChapterDraft.self, from: data) else {
            return .invalid(url: url, reason: "无法解码")
        }
        guard draft.id == expectedChapterID else {
            return .invalid(
                url: url,
                reason: "内含 chapter ID \(draft.id)，预期为 \(expectedChapterID)"
            )
        }
        let persistedTimestamp = persistedChapterTimestamp(in: data)
        if let persistedTimestamp {
            draft.savedAtDate = persistedTimestamp
        }
        return .valid(
            url: url,
            data: data,
            draft: draft,
            persistedTimestamp: persistedTimestamp
        )
    }

    private func persistedChapterTimestamp(in data: Data) -> Date? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return nil
        }
        for key in ["savedAt", "updatedAt"] {
            if let rawValue = payload[key] as? String,
               let date = PersistedTimestampCodec.parse(rawValue) {
                return date
            }
            if let rawValue = payload[key] as? NSNumber,
               let date = PersistedTimestampCodec.parse(rawValue.stringValue) {
                return date
            }
        }
        return nil
    }

    private func chapterPayloadCandidateIDs(
        for projectID: NovelProject.ID,
        scope: String?
    ) -> [ChapterDraft.ID] {
        var chapterIDs = Set<ChapterDraft.ID>()
        if case let .readable(index) = chapterIndexReadState(
            for: projectID,
            scope: scope
        ) {
            chapterIDs.formUnion(index.chapterIDs)
        }

        let chapterDirectory = chapterDirectoryURL(for: projectID, scope: scope)
        let urls = (try? fileManager.contentsOfDirectory(
            at: chapterDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in urls
        where url.pathExtension == "json" && url.lastPathComponent != "index.json" {
            guard let data = try? Data(contentsOf: url),
                  let draft = try? decoder.decode(ChapterDraft.self, from: data) else {
                continue
            }
            chapterIDs.insert(draft.id)
        }
        return chapterIDs.sorted()
    }

    private func ensureChapterPayloadsCanBeSafelyReconciled(
        for projectID: NovelProject.ID,
        scope: String?
    ) throws {
        for chapterID in chapterPayloadCandidateIDs(
            for: projectID,
            scope: scope
        ) {
            guard case let .conflict(_, _, reason) = chapterPayloadResolution(
                for: chapterID,
                projectID: projectID,
                scope: scope
            ) else {
                continue
            }
            throw recoveryError(
                "章节 \(chapterID) 的 canonical/legacy 正文冲突：\(reason)"
            )
        }
    }

    private func reconcileChapterPayloadsIfSafe(
        for projectID: NovelProject.ID,
        scope: String?
    ) throws {
        let chapterIDs = chapterPayloadCandidateIDs(
            for: projectID,
            scope: scope
        )
        for chapterID in chapterIDs {
            try migrateLegacyChapterFileIfNeeded(
                chapterID,
                for: projectID,
                scope: scope
            )
        }
    }

    private func migrateLegacyChapterFileIfNeeded(
        _ chapterID: ChapterDraft.ID,
        for projectID: NovelProject.ID,
        scope: String?
    ) throws {
        switch chapterPayloadResolution(
            for: chapterID,
            projectID: projectID,
            scope: scope
        ) {
        case .missing, .invalid:
            return
        case let .conflict(_, _, reason):
            throw recoveryError(
                "章节 \(chapterID) 的 canonical/legacy 正文冲突：\(reason)"
            )
        case let .resolved(
            draft,
            data,
            sourceURL,
            canonicalURL,
            legacyURL,
            legacyFileExists
        ):
            guard legacyFileExists, canonicalURL.path != legacyURL.path else {
                return
            }

            if sourceURL.path == legacyURL.path {
                if fileManager.fileExists(atPath: canonicalURL.path),
                   (try? Data(contentsOf: canonicalURL)) != data {
                    _ = try backupExistingChapterFileIfNeeded(
                        canonicalURL,
                        projectID: projectID,
                        reason: "canonical-stale",
                        scope: scope
                    )
                }
                try writeIfChanged(data, to: canonicalURL)
            }

            guard case let .resolved(
                verifiedDraft,
                verifiedData,
                verifiedSourceURL,
                _,
                _,
                _
            ) = chapterPayloadResolution(
                for: chapterID,
                projectID: projectID,
                scope: scope
            ),
            verifiedSourceURL.path == canonicalURL.path,
            verifiedDraft == draft,
            verifiedData == data else {
                throw recoveryError(
                    "章节 \(chapterID) 写入 canonical 路径后的校验未通过；legacy 文件已保留。"
                )
            }

            if let legacyData = try? Data(contentsOf: legacyURL),
               legacyData != verifiedData {
                _ = try backupExistingChapterFileIfNeeded(
                    legacyURL,
                    projectID: projectID,
                    reason: "legacy-stale",
                    scope: scope
                )
            }
            guard case let .resolved(
                finalDraft,
                finalData,
                finalSourceURL,
                _,
                _,
                _
            ) = chapterPayloadResolution(
                for: chapterID,
                projectID: projectID,
                scope: scope
            ),
            finalSourceURL.path == canonicalURL.path,
            finalDraft == draft,
            finalData == data else {
                throw recoveryError(
                    "章节 \(chapterID) 清理 legacy 文件前的最终校验未通过；原文件均已保留。"
                )
            }

            try testHooks.beforeRemoveItem?(legacyURL)
            try fileManager.removeItem(at: legacyURL)
            writeCache.remove(legacyURL)
        }
    }

    private func scopeDirectoryURL(for scope: String?) -> URL {
        let canonicalURL = canonicalScopeDirectoryURL(for: scope)
        guard normalizedScope(scope) != nil,
              !fileManager.fileExists(atPath: canonicalURL.path) else {
            return canonicalURL
        }
        let legacyURL = legacyScopeDirectoryURL(for: scope)
        return fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : canonicalURL
    }

    private func scopeDirectoryName(for scope: String?) -> String {
        guard let normalizedScope = normalizedScope(scope) else {
            return "local"
        }

        let sanitizedPrefix = String(sanitizedStorageComponent(normalizedScope).prefix(48))
        let readablePrefix = sanitizedPrefix.isEmpty ? "scope" : sanitizedPrefix
        let hashSuffix = stableStorageID(parts: ["scope-directory", normalizedScope])
        return "account-\(readablePrefix)--\(hashSuffix)"
    }

    private func canonicalScopeDirectoryURL(for scope: String?) -> URL {
        baseDirectoryURL.appendingPathComponent(
            scopeDirectoryName(for: scope),
            isDirectory: true
        )
    }

    private func legacyScopeDirectoryURL(for scope: String?) -> URL {
        guard let normalizedScope = normalizedScope(scope) else {
            return canonicalScopeDirectoryURL(for: nil)
        }
        return baseDirectoryURL.appendingPathComponent(
            "account-\(sanitizedStorageComponent(normalizedScope))",
            isDirectory: true
        )
    }

    private func migrateLegacyScopeDirectoryIfNeeded(for scope: String?) throws {
        guard normalizedScope(scope) != nil else { return }
        let canonicalURL = canonicalScopeDirectoryURL(for: scope)
        guard !fileManager.fileExists(atPath: canonicalURL.path) else { return }
        let legacyURL = legacyScopeDirectoryURL(for: scope)
        guard legacyURL.path != canonicalURL.path,
              fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }
        try fileManager.moveItem(at: legacyURL, to: canonicalURL)
        writeCache.removeItems(under: legacyURL)
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

    private func projectDirectoryName(for projectID: NovelProject.ID) -> String {
        let sanitizedPrefix = String(sanitizedStorageComponent(projectID).prefix(48))
        let readablePrefix = sanitizedPrefix.isEmpty ? "project" : sanitizedPrefix
        let hashSuffix = stableStorageID(parts: ["project-directory", projectID])
        return "\(readablePrefix)--\(hashSuffix)"
    }

    private func projectArtifactComponent(for projectID: NovelProject.ID) -> String {
        let sanitizedPrefix = String(sanitizedStorageComponent(projectID).prefix(48))
        let readablePrefix = sanitizedPrefix.isEmpty ? "project" : sanitizedPrefix
        let hashSuffix = stableStorageID(parts: ["project-artifact", projectID])
        return "\(readablePrefix)--\(hashSuffix)"
    }

    private func uniqueArtifactFileName(
        prefix: String,
        projectID: NovelProject.ID
    ) -> String {
        [
            prefix,
            projectArtifactComponent(for: projectID),
            Self.diagnosticTimestamp(),
            UUID().uuidString
        ].joined(separator: "-") + ".json"
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

nonisolated private struct ProjectFileIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let statusChangeSeconds: Int64
    let statusChangeNanoseconds: Int64

    static func read(from url: URL) -> ProjectFileIdentity? {
        var fileStatus = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &fileStatus)
        }
        guard result == 0 else { return nil }
        return ProjectFileIdentity(
            device: UInt64(fileStatus.st_dev),
            inode: UInt64(fileStatus.st_ino),
            size: Int64(fileStatus.st_size),
            modificationSeconds: Int64(fileStatus.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(fileStatus.st_mtimespec.tv_nsec),
            statusChangeSeconds: Int64(fileStatus.st_ctimespec.tv_sec),
            statusChangeNanoseconds: Int64(fileStatus.st_ctimespec.tv_nsec)
        )
    }
}

nonisolated private struct ProjectFileWriteCacheEntry {
    let fingerprint: ProjectFileFingerprint
    let identity: ProjectFileIdentity?
}

nonisolated private final class ProjectFileWriteCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: ProjectFileWriteCacheEntry] = [:]

    func entry(for url: URL) -> ProjectFileWriteCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[url.path]
    }

    func set(_ entry: ProjectFileWriteCacheEntry, for url: URL) {
        lock.lock()
        entries[url.path] = entry
        lock.unlock()
    }

    func remove(_ url: URL) {
        lock.lock()
        entries.removeValue(forKey: url.path)
        lock.unlock()
    }

    func removeItems(under url: URL) {
        let prefix = url.path + "/"
        lock.lock()
        entries = entries.filter { key, _ in
            key != url.path && !key.hasPrefix(prefix)
        }
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
