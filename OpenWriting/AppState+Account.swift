import Foundation
import OSLog

nonisolated enum LegacyProjectPayloadMigrationState: Equatable {
    case notPresent
    case migrated
    case partial(failedElementCount: Int)
    case unreadable
    case persistenceFailed

    var isComplete: Bool {
        self == .notPresent || self == .migrated
    }
}

nonisolated struct LegacyProjectArrayDecodeResult {
    var projects: [NovelProject]
    var failedElementCount: Int

    var isComplete: Bool {
        failedElementCount == 0
    }
}

nonisolated struct AccountScopedProjectLoadResult {
    var projects: [NovelProject]?
    var issues: [ProjectLoadIssue]
    var legacyPayloadState: LegacyProjectPayloadMigrationState = .notPresent
}

extension AppState {
    var isAccountSignedIn: Bool {
        activeAccount != nil
    }

    var accountDisplayName: String {
        activeAccount?.displayName ?? "未登录"
    }

    var accountSecondaryLabel: String {
        activeAccount?.secondaryLabel ?? "使用 Apple ID 登录后即可开始同步。"
    }

    var accountStorageSummary: String {
        if let activeAccount {
            return "当前项目已绑定到 \(activeAccount.displayName)，修改会自动尝试同步到 iCloud。"
        }

        return "登录 Apple ID 后，项目会按 Apple 账户隔离，并同步到 iCloud。"
    }

    var unsupportedFutureProjectCount: Int {
        projectLoadIssues.filter {
            $0.kind == .unsupportedFutureProjectDocument
        }.count
    }

    var projectLoadWarningMessage: String? {
        if projectLoadIssues.contains(where: {
            $0.kind == .pendingTransactionRecoveryFailure
        }) {
            return "检测到未完成的项目保存事务，但自动恢复未成功。为避免读取新旧混合数据，项目加载已暂停。"
        }
        if projectLoadIssues.contains(where: {
            $0.kind == .unsupportedFutureProjectIndex
        }) {
            return "项目索引由更高版本的 OpenWriting 创建，请更新应用后再打开；现有文件已原样保留。"
        }
        if projectLoadIssues.contains(where: {
            $0.kind == .legacyProjectPayloadPersistenceFailed
                || $0.kind == .legacyDefaultsMigrationIncomplete
        }) {
            return "旧版项目数据尚未完整写入当前存储；原始数据已保留，OpenWriting 会在下次启动时重试。"
        }
        if projectLoadIssues.contains(where: {
            $0.kind == .legacyProjectPayloadPartial
                || $0.kind == .legacyProjectPayloadUnreadable
        }) {
            return "旧版项目数据包含无法读取的内容；可恢复项目已保留，原始数据未删除。"
        }
        let count = unsupportedFutureProjectCount
        guard count > 0 else { return nil }
        return "有 \(count) 个项目由更高版本的 OpenWriting 创建，请更新应用后再打开。"
    }

    @discardableResult
    func bindAppleAccount(_ profile: AppleAccountProfile) async -> Bool {
        let normalizedProfile = Self.normalizedAppleAccount(profile)
        let targetScope = normalizedProfile.userID
        guard flushAPIKeyPersistence() else { return false }
        guard await flushProjectPersistence() else { return false }
        let targetLoadResult = Self.loadRecentProjectsReport(
            for: targetScope,
            from: userDefaults,
            projectStore: projectStore
        )
        guard targetLoadResult.issues.isEmpty else { return false }
        if targetLoadResult.projects == nil {
            guard targetLoadResult.legacyPayloadState == .notPresent else {
                return false
            }
            guard Self.copyAccountScopedProjectData(
                from: currentStorageScope,
                to: targetScope,
                userDefaults: userDefaults,
                projectStore: projectStore
            ) else {
                return false
            }
        } else if !targetLoadResult.legacyPayloadState.isComplete {
            return false
        }

        if activeAccount?.userID != targetScope {
            guard updateOfficialChannelCredential(nil) else { return false }
            cancelAIMemoryExtractionTasks(scope: currentStorageScope)
            cloudSaveTask?.cancel()
            cloudSaveTask = nil
            cloudSaveGeneration &+= 1
        }

        activeAccount = normalizedProfile
        currentProjectSnapshotTimestamp = Self.doubleValue(
            forKey: Self.projectSnapshotTimestampStorageKey(for: targetScope),
            userDefaults: userDefaults
        ) ?? 0
        reloadAccountScopedProjects()

        Task { @MainActor in
            let hasValidAppleCredential = await refreshActiveAppleCredentialState()
            await refreshCommerceEntitlements()
            if hasValidAppleCredential {
                await synchronizeWithICloud(forcePull: false)
            }
        }
        return true
    }

    @discardableResult
    func logoutAccount(removingLocalData: Bool = false) async -> Bool {
        guard let account = activeAccount else { return true }
        guard flushAPIKeyPersistence() else { return false }
        if !removingLocalData, !(await flushProjectPersistence()) {
            return false
        }
        guard updateOfficialChannelCredential(nil) else { return false }

        cancelAIMemoryExtractionTasks(scope: account.userID)
        cloudSaveTask?.cancel()
        cloudSaveTask = nil
        cloudSaveGeneration &+= 1
        var didRemoveLocalData = true
        if removingLocalData {
            cancelPendingProjectPersistence(for: account.userID)

            do {
                try await projectPersistence.cancelAndRemove(for: account.userID)
                userDefaults.removeObject(forKey: Self.activeProjectIDStorageKey(for: account.userID))
                userDefaults.removeObject(forKey: Self.recentProjectsStorageKey(for: account.userID))
                userDefaults.removeObject(forKey: Self.projectSnapshotTimestampStorageKey(for: account.userID))
            } catch {
                didRemoveLocalData = false
                AppLogger.persistence.error("Account local data cleanup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        activeAccount = nil
        currentProjectSnapshotTimestamp = Self.doubleValue(
            forKey: Self.projectSnapshotTimestampStorageKey(for: nil),
            userDefaults: userDefaults
        ) ?? 0
        reloadAccountScopedProjects()

        Task { @MainActor in
            await refreshCommerceEntitlements()
            await refreshCloudAvailability()
        }
        return didRemoveLocalData
    }

    func refreshICloudProjects() async {
        await synchronizeWithICloud(forcePull: true)
    }

    func reloadAccountScopedProjects() {
        cancelPendingProjectPersistence(for: currentStorageScope)
        invalidateStorageHealthCache()
        isHydratingAccountScopedData = true
        projectDeletionTombstones = projectStore.loadProjectDeletionTombstones(
            for: currentStorageScope
        )
        let loadResult = Self.loadRecentProjectsReport(
            for: currentStorageScope,
            from: userDefaults,
            projectStore: projectStore
        )
        projectLoadIssues = loadResult.issues
        invalidateAllLongformWritingDeskContexts()
        recentProjects = loadResult.projects ?? Self.defaultRecentProjects
        activeProjectID = Self.stringValue(
            forKey: Self.activeProjectIDStorageKey(for: currentStorageScope),
            userDefaults: userDefaults
        )
        selectedProjectID = activeProjectID
        normalizeProjectSelection()
        isHydratingAccountScopedData = false
    }

    static func loadRecentProjects(
        for scope: String?,
        from userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) -> [NovelProject]? {
        loadRecentProjectsReport(
            for: scope,
            from: userDefaults,
            projectStore: projectStore
        ).projects
    }

    static func loadRecentProjectsReport(
        for scope: String?,
        from userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) -> AccountScopedProjectLoadResult {
        if let report = projectStore.loadProjectsReport(for: scope) {
            let storageKey = recentProjectsStorageKey(for: scope)
            var projectsToMigrate = report.projects
            var legacyDecodeResult: LegacyProjectArrayDecodeResult?
            var shouldPersistLegacyMerge = false

            if let legacyData = dataValue(
                forKey: storageKey,
                userDefaults: userDefaults
            ) {
                guard let decodeResult = decodeLegacyProjectArray(
                    from: legacyData
                ) else {
                    let legacyState =
                        LegacyProjectPayloadMigrationState.unreadable
                    return AccountScopedProjectLoadResult(
                        projects: report.projects,
                        issues: report.issues + legacyProjectLoadIssues(
                            for: legacyState,
                            scope: scope,
                            storageKey: storageKey
                        ),
                        legacyPayloadState: legacyState
                    )
                }
                legacyDecodeResult = decodeResult
                shouldPersistLegacyMerge = true
                projectsToMigrate = mergedLegacyProjects(
                    existing: report.projects,
                    legacy: decodeResult.projects
                )
            }

            if !report.issues.isEmpty {
                let legacyState: LegacyProjectPayloadMigrationState
                if let legacyDecodeResult {
                    legacyState = legacyDecodeResult.isComplete
                        ? (shouldPersistLegacyMerge
                            ? .persistenceFailed
                            : .migrated)
                        : .partial(
                            failedElementCount:
                                legacyDecodeResult.failedElementCount
                        )
                } else {
                    legacyState = .notPresent
                }
                return AccountScopedProjectLoadResult(
                    projects: projectsToMigrate,
                    issues: report.issues + legacyProjectLoadIssues(
                        for: legacyState,
                        scope: scope,
                        storageKey: storageKey
                    ),
                    legacyPayloadState: legacyState
                )
            }

            var persistenceFailed = false
            var didPersistProjects = false
            let migratedProjects = LegacyProjectSidecarMigrator(userDefaults: userDefaults).migrate(
                projectsToMigrate
            ) { projects in
                do {
                    try projectStore.saveProjects(projects, for: scope)
                    didPersistProjects = true
                    return true
                } catch {
                    persistenceFailed = true
                    return false
                }
            }

            if shouldPersistLegacyMerge,
               !didPersistProjects,
               !persistenceFailed {
                do {
                    try projectStore.saveProjects(
                        migratedProjects,
                        for: scope
                    )
                } catch {
                    persistenceFailed = true
                }
            }

            let legacyState: LegacyProjectPayloadMigrationState
            if persistenceFailed {
                legacyState = .persistenceFailed
            } else if let legacyDecodeResult {
                if legacyDecodeResult.isComplete {
                    clearLegacyRecentProjectsFromUserDefaults(
                        for: scope,
                        userDefaults: userDefaults
                    )
                    legacyState = .migrated
                } else {
                    legacyState = .partial(
                        failedElementCount:
                            legacyDecodeResult.failedElementCount
                    )
                }
            } else {
                legacyState = .notPresent
            }
            return AccountScopedProjectLoadResult(
                projects: migratedProjects,
                issues: report.issues + legacyProjectLoadIssues(
                    for: legacyState,
                    scope: scope,
                    storageKey: storageKey
                ),
                legacyPayloadState: legacyState
            )
        }

        guard let legacyData = dataValue(
            forKey: recentProjectsStorageKey(for: scope),
            userDefaults: userDefaults
        ) else {
            return AccountScopedProjectLoadResult(projects: nil, issues: [])
        }
        guard let decodeResult = decodeLegacyProjectArray(from: legacyData) else {
            let legacyState = LegacyProjectPayloadMigrationState.unreadable
            return AccountScopedProjectLoadResult(
                projects: nil,
                issues: legacyProjectLoadIssues(
                    for: legacyState,
                    scope: scope,
                    storageKey: recentProjectsStorageKey(for: scope)
                ),
                legacyPayloadState: legacyState
            )
        }

        var persistenceFailed = false
        var didPersistSidecarMigration = false
        let migratedProjects = LegacyProjectSidecarMigrator(userDefaults: userDefaults).migrate(
            decodeResult.projects
        ) { projects in
            do {
                try projectStore.saveProjects(projects, for: scope)
                didPersistSidecarMigration = true
                return true
            } catch {
                persistenceFailed = true
                return false
            }
        }

        if !didPersistSidecarMigration, !persistenceFailed {
            do {
                try projectStore.saveProjects(migratedProjects, for: scope)
            } catch {
                persistenceFailed = true
            }
        }

        if persistenceFailed {
            let legacyState = LegacyProjectPayloadMigrationState.persistenceFailed
            return AccountScopedProjectLoadResult(
                projects: migratedProjects,
                issues: legacyProjectLoadIssues(
                    for: legacyState,
                    scope: scope,
                    storageKey: recentProjectsStorageKey(for: scope)
                ),
                legacyPayloadState: legacyState
            )
        }

        if decodeResult.isComplete {
            clearLegacyRecentProjectsFromUserDefaults(for: scope, userDefaults: userDefaults)
        }

        let legacyState: LegacyProjectPayloadMigrationState =
            decodeResult.isComplete
                ? .migrated
                : .partial(failedElementCount: decodeResult.failedElementCount)
        return AccountScopedProjectLoadResult(
            projects: migratedProjects,
            issues: legacyProjectLoadIssues(
                for: legacyState,
                scope: scope,
                storageKey: recentProjectsStorageKey(for: scope)
            ),
            legacyPayloadState: legacyState
        )
    }

    static func loadLegacyRecentProjectsFromUserDefaults(
        for scope: String?,
        userDefaults: UserDefaults
    ) -> [NovelProject]? {
        guard let data = dataValue(
            forKey: recentProjectsStorageKey(for: scope),
            userDefaults: userDefaults
        ) else {
            return nil
        }

        return decodeLegacyProjectArray(from: data)?.projects
    }

    static func decodeProjects(from data: Data) -> [NovelProject]? {
        guard let result = decodeLegacyProjectArray(from: data),
              result.isComplete else {
            return nil
        }
        return result.projects
    }

    static func decodeLegacyProjectArray(
        from data: Data
    ) -> LegacyProjectArrayDecodeResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let elements = object as? [Any] else {
            return nil
        }

        var projects: [NovelProject] = []
        var failedElementCount = 0
        let decoder = JSONDecoder()
        for element in elements {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(
                    withJSONObject: element,
                    options: [.sortedKeys]
                  ),
                  let project = try? decoder.decode(NovelProject.self, from: elementData) else {
                failedElementCount += 1
                continue
            }
            projects.append(project)
        }
        return LegacyProjectArrayDecodeResult(
            projects: projects,
            failedElementCount: failedElementCount
        )
    }

    static func clearLegacyRecentProjectsFromUserDefaults(for scope: String?, userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: recentProjectsStorageKey(for: scope))
    }

    static func legacyProjectLoadIssue(
        kind: ProjectLoadIssueKind,
        scope: String?,
        storageKey: String,
        failedElementCount: Int = 0
    ) -> ProjectLoadIssue {
        ProjectLoadIssue(
            id: [
                kind.rawValue,
                scope ?? "local",
                storageKey,
                "\(failedElementCount)"
            ].joined(separator: ":"),
            kind: kind,
            scope: scope,
            projectID: nil,
            path: "UserDefaults:\(storageKey)",
            sourceVersion: 0
        )
    }

    private static func legacyProjectLoadIssues(
        for state: LegacyProjectPayloadMigrationState,
        scope: String?,
        storageKey: String
    ) -> [ProjectLoadIssue] {
        switch state {
        case .notPresent, .migrated:
            return []
        case let .partial(failedElementCount):
            return [legacyProjectLoadIssue(
                kind: .legacyProjectPayloadPartial,
                scope: scope,
                storageKey: storageKey,
                failedElementCount: failedElementCount
            )]
        case .unreadable:
            return [legacyProjectLoadIssue(
                kind: .legacyProjectPayloadUnreadable,
                scope: scope,
                storageKey: storageKey
            )]
        case .persistenceFailed:
            return [legacyProjectLoadIssue(
                kind: .legacyProjectPayloadPersistenceFailed,
                scope: scope,
                storageKey: storageKey
            )]
        }
    }

    static func normalizedAppleAccount(_ profile: AppleAccountProfile) -> AppleAccountProfile {
        AppleAccountProfile(
            userID: profile.userID.trimmingCharacters(in: .whitespacesAndNewlines),
            email: profile.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            fullName: profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func loadActiveAppleAccount(from userDefaults: UserDefaults) -> AppleAccountProfile? {
        guard let userID = stringValue(forKey: StorageKey.activeAppleUserID, userDefaults: userDefaults)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            !userID.isEmpty
        else {
            return nil
        }

        return AppleAccountProfile(
            userID: userID,
            email: stringValue(forKey: StorageKey.activeAppleUserEmail, userDefaults: userDefaults) ?? "",
            fullName: stringValue(forKey: StorageKey.activeAppleUserName, userDefaults: userDefaults) ?? ""
        )
    }

    static func sanitizedStorageComponent(_ value: String) -> String {
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
}
