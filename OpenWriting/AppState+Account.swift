import Foundation
import OSLog

nonisolated struct AccountScopedProjectLoadResult {
    var projects: [NovelProject]?
    var issues: [ProjectLoadIssue]
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
        let count = unsupportedFutureProjectCount
        guard count > 0 else { return nil }
        return "有 \(count) 个项目由更高版本的 OpenWriting 创建，请更新应用后再打开。"
    }

    @discardableResult
    func bindAppleAccount(_ profile: AppleAccountProfile) async -> Bool {
        let normalizedProfile = Self.normalizedAppleAccount(profile)
        let targetScope = normalizedProfile.userID
        flushAPIKeyPersistence()
        guard await flushProjectPersistence() else { return false }
        if activeAccount?.userID != targetScope {
            cloudSaveTask?.cancel()
            cloudSaveTask = nil
            cloudSaveGeneration &+= 1
            _ = updateOfficialChannelCredential(nil)
        }

        if Self.loadRecentProjects(for: targetScope, from: userDefaults, projectStore: projectStore) == nil {
            Self.copyAccountScopedProjectData(
                from: currentStorageScope,
                to: targetScope,
                userDefaults: userDefaults,
                projectStore: projectStore
            )
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
        flushAPIKeyPersistence()
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
        } else if !(await flushProjectPersistence()) {
            return false
        }
        _ = updateOfficialChannelCredential(nil)
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
            let migratedProjects = LegacyProjectSidecarMigrator(userDefaults: userDefaults).migrate(report.projects) {
                (try? projectStore.saveProjects($0, for: scope)) != nil
            }
            return AccountScopedProjectLoadResult(
                projects: migratedProjects,
                issues: report.issues
            )
        }

        guard let decodedProjects = loadLegacyRecentProjectsFromUserDefaults(for: scope, userDefaults: userDefaults) else {
            return AccountScopedProjectLoadResult(projects: nil, issues: [])
        }

        let migratedProjects = LegacyProjectSidecarMigrator(userDefaults: userDefaults).migrate(decodedProjects) {
            (try? projectStore.saveProjects($0, for: scope)) != nil
        }

        if projectStore.hasProjects(for: scope) {
            clearLegacyRecentProjectsFromUserDefaults(for: scope, userDefaults: userDefaults)
        }

        return AccountScopedProjectLoadResult(
            projects: migratedProjects,
            issues: []
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

        return decodeProjects(from: data)
    }

    static func decodeProjects(from data: Data) -> [NovelProject]? {
        try? JSONDecoder().decode([NovelProject].self, from: data)
    }

    static func clearLegacyRecentProjectsFromUserDefaults(for scope: String?, userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: recentProjectsStorageKey(for: scope))
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
