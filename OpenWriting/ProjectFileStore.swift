import Foundation
import CryptoKit

nonisolated struct ProjectFileStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let projectCodec = ProjectDocumentCodec()
    private let writeCache = ProjectFileWriteCache()
    private let accessLock: NSRecursiveLock

    private struct ProjectIndex: Codable {
        static let currentVersion = 2

        var version: Int
        var projectIDs: [NovelProject.ID]

        init(version: Int = currentVersion, projectIDs: [NovelProject.ID]) {
            self.version = version
            self.projectIDs = projectIDs
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
        baseDirectoryName: String = "OpenWriting"
    ) {
        self.fileManager = fileManager

        let baseURL = baseDirectoryURL ?? (
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
        )

        self.baseDirectoryURL = baseURL
            .appendingPathComponent(baseDirectoryName, isDirectory: true)
            .appendingPathComponent("ProjectStore", isDirectory: true)
        self.accessLock = NSRecursiveLock()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    private init(
        fileManager: FileManager,
        resolvedBaseDirectoryURL: URL,
        accessLock: NSRecursiveLock
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = resolvedBaseDirectoryURL
        self.accessLock = accessLock
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func independentCopy() -> ProjectFileStore {
        ProjectFileStore(
            fileManager: fileManager,
            resolvedBaseDirectoryURL: baseDirectoryURL,
            accessLock: accessLock
        )
    }

    func storageHealthReport(for projectID: NovelProject.ID, scope: String?) -> StorageHealthReport {
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

    func loadProjects(for scope: String?) -> [NovelProject]? {
        accessLock.lock()
        defer { accessLock.unlock() }
        if let projects = loadShardedProjects(for: scope) {
            return projects
        }

        let fileURL = projectsFileURL(for: scope)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? decoder.decode([NovelProject].self, from: data)
    }

    func saveProjects(_ projects: [NovelProject], for scope: String?) throws {
        accessLock.lock()
        defer { accessLock.unlock() }
        if projects.isEmpty {
            try removeProjects(for: scope)
            return
        }

        try saveShardedProjects(projects, for: scope)
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

    private func loadShardedProjects(for scope: String?) -> [NovelProject]? {
        let indexURL = projectIndexURL(for: scope)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ProjectIndex.self, from: indexData)
        else { return nil }

        var projects: [NovelProject] = []
        for projectID in index.projectIDs {
            let projectURL = projectMetadataURL(for: projectID, scope: scope)
            guard let projectData = try? Data(contentsOf: projectURL),
                  var project = try? projectCodec.decode(projectData).project
            else { continue }

            project.chapterCatalog = loadChapterMetadata(for: projectID, scope: scope)
            project.chapterDrafts = []
            projects.append(project)
        }

        return projects
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
        else { return [] }

        if let chapters = index.chapters, !chapters.isEmpty {
            return chapters
        }

        return loadChapterDrafts(for: projectID, scope: scope)
            .map(ChapterDraftMetadata.init)
            .sorted(by: ChapterDraftMetadata.sortDescending)
    }

    private func saveShardedProjects(_ projects: [NovelProject], for scope: String?) throws {
        let scopeURL = scopeDirectoryURL(for: scope)
        let projectsDirectory = scopeURL.appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)

        let incomingProjectIDs = Set(projects.map(\.id))
        let protection = existingProjectProtection(
            for: scope,
            excluding: incomingProjectIDs
        )

        for project in projects {
            try saveProject(project, scope: scope)
        }

        let index = ProjectIndex(
            version: 2,
            projectIDs: projects.map(\.id) + protection.indexedProjectIDs
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
        excluding incomingProjectIDs: Set<NovelProject.ID>
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
            return ExistingProjectProtection(
                indexedProjectIDs: [],
                directoryNames: directoryNames.subtracting(incomingDirectoryNames)
            )
        }

        var protectedProjectIDs: [NovelProject.ID] = []
        var protectedDirectoryNames = directoryNames.subtracting(
            Set(index.projectIDs.map(sanitizedStorageComponent))
        )

        for projectID in index.projectIDs where !incomingProjectIDs.contains(projectID) {
            let metadataURL = projectMetadataURL(for: projectID, scope: scope)
            guard let data = try? Data(contentsOf: metadataURL),
                  (try? projectCodec.decode(data)) != nil
            else {
                protectedProjectIDs.append(projectID)
                protectedDirectoryNames.insert(sanitizedStorageComponent(projectID))
                continue
            }
        }

        return ExistingProjectProtection(
            indexedProjectIDs: protectedProjectIDs,
            directoryNames: protectedDirectoryNames
        )
    }

    private func saveProject(_ project: NovelProject, scope: String?) throws {
        let chaptersDirectory = chapterDirectoryURL(for: project.id, scope: scope)
        try fileManager.createDirectory(at: chaptersDirectory, withIntermediateDirectories: true)

        var metadata = project
        metadata.chapterDrafts = []
        try writeIfChanged(try projectCodec.encode(metadata), to: projectMetadataURL(for: project.id, scope: scope))

        let chapterCatalog = resolvedChapterCatalog(for: project)
        let chapterIndex = ChapterIndex(
            version: 3,
            chapterIDs: chapterCatalog.map(\.id),
            chapters: chapterCatalog
        )
        try writeIfChanged(try encoder.encode(chapterIndex), to: chapterIndexURL(for: project.id, scope: scope))

        for chapterDraft in project.chapterDrafts {
            let chapterData = try encoder.encode(chapterDraft)
            try writeIfChanged(
                chapterData,
                to: chapterURL(for: chapterDraft.id, projectID: project.id, scope: scope)
            )
        }

        try removeDeletedChapterFiles(
            in: chaptersDirectory,
            keeping: Set(chapterCatalog.map(\.id))
        )
    }

    private func resolvedChapterCatalog(for project: NovelProject) -> [ChapterDraftMetadata] {
        var catalogByID = Dictionary(uniqueKeysWithValues: project.chapterCatalog.map { ($0.id, $0) })
        for chapterDraft in project.chapterDrafts {
            catalogByID[chapterDraft.id] = ChapterDraftMetadata(chapterDraft: chapterDraft)
        }

        return catalogByID.values.sorted(by: ChapterDraftMetadata.sortDescending)
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
        try data.write(to: url, options: .atomic)
        writeCache.set(fingerprint, for: url)
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

        let existingProjectIDs = (try? Data(contentsOf: projectIndexURL(for: scope)))
            .flatMap { try? decoder.decode(ProjectIndex.self, from: $0) }?
            .projectIDs ?? []
        let projectIDs = uniqueIDs(existingProjectIDs + [project.id])
        try writeIfChanged(
            try encoder.encode(ProjectIndex(version: 2, projectIDs: projectIDs)),
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
