import Foundation
import OSLog

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

    func bindAppleAccount(_ profile: AppleAccountProfile) {
        let normalizedProfile = Self.normalizedAppleAccount(profile)
        let targetScope = normalizedProfile.userID

        invalidateCloudOperations()

        // Only migrate legacy anonymous data into the first signed-in account.
        // Never copy a previously signed-in account's projects into another
        // Apple account on this device.
        if currentStorageScope == nil,
           Self.loadRecentProjects(for: targetScope, from: userDefaults, projectStore: projectStore) == nil {
            Self.copyAccountScopedProjectData(
                from: currentStorageScope,
                to: targetScope,
                userDefaults: userDefaults,
                projectStore: projectStore
            )
        }
        migrateAnonymousWritingSkillsIfNeeded(to: targetScope)

        activeAccount = normalizedProfile
        currentProjectSnapshotTimestamp = Self.doubleValue(
            forKey: Self.projectSnapshotTimestampStorageKey(for: targetScope),
            userDefaults: userDefaults
        ) ?? 0
        reloadAccountScopedProjects()

        Task { @MainActor in
            _ = await refreshActiveAppleCredentialState()
            await refreshCommerceEntitlements()
            await synchronizeWithICloud(forcePull: false)
        }
    }

    @discardableResult
    func logoutAccount(removingLocalData: Bool = false) -> Bool {
        guard let account = activeAccount else { return true }
        invalidateCloudOperations()
        var didRemoveLocalData = true
        if removingLocalData {
            let accountProjectStorageKey = Self.recentProjectsStorageKey(for: account.userID)
            recentProjectsPersistTasks[accountProjectStorageKey]?.cancel()
            recentProjectsPersistTasks.removeValue(forKey: accountProjectStorageKey)

            do {
                try projectStore.removeProjects(for: account.userID)
                userDefaults.removeObject(forKey: Self.activeProjectIDStorageKey(for: account.userID))
                userDefaults.removeObject(forKey: Self.recentProjectsStorageKey(for: account.userID))
                userDefaults.removeObject(forKey: Self.projectSnapshotTimestampStorageKey(for: account.userID))
            } catch {
                didRemoveLocalData = false
                AppLogger.persistence.error("Account local data cleanup failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
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

    func invalidateCloudOperations() {
        cloudSaveTask?.cancel()
        cloudSaveTask = nil
        cloudSaveGeneration &+= 1
        cloudSyncEpoch &+= 1
    }

    func refreshICloudProjects() async {
        await synchronizeWithICloud(forcePull: true)
    }

    func reloadAccountScopedProjects() {
        isHydratingAccountScopedData = true
        let loadReport = Self.loadRecentProjectsReport(
            for: currentStorageScope,
            from: userDefaults,
            projectStore: projectStore
        )
        isCurrentStoragePersistenceSafe = loadReport.isComplete
        recentProjects = loadReport.projects ?? Self.defaultRecentProjects
        writingSkills = Self.loadWritingSkills(for: currentStorageScope, from: userDefaults) ?? []
        activeProjectID = Self.stringValue(
            forKey: Self.activeProjectIDStorageKey(for: currentStorageScope),
            userDefaults: userDefaults
        )
        selectedProjectID = activeProjectID
        normalizeProjectSelection()
        isHydratingAccountScopedData = false
        if !loadReport.isComplete {
            setCloudSyncStatus(
                title: "本机存储待恢复",
                symbolName: "exclamationmark.triangle",
                message: "检测到本机项目文件不完整，已停止自动保存和同步；请先在项目空间导出诊断或执行恢复。"
            )
        }
    }

    private func migrateAnonymousWritingSkillsIfNeeded(to targetScope: String) {
        guard currentStorageScope == nil,
              userDefaults.data(forKey: Self.writingSkillsStorageKey(for: targetScope)) == nil,
              let anonymousSkills = Self.loadWritingSkills(for: nil, from: userDefaults)
        else { return }

        guard let data = try? JSONEncoder().encode(anonymousSkills) else { return }
        userDefaults.set(data, forKey: Self.writingSkillsStorageKey(for: targetScope))
        userDefaults.removeObject(forKey: Self.writingSkillsStorageKey(for: nil))
    }

    static func loadRecentProjects(
        for scope: String?,
        from userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) -> [NovelProject]? {
        loadRecentProjectsReport(for: scope, from: userDefaults, projectStore: projectStore).projects
    }

    static func loadRecentProjectsReport(
        for scope: String?,
        from userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) -> ProjectFileStore.ProjectLoadReport {
        let storedReport = projectStore.loadProjectsReport(for: scope)
        if storedReport.projects != nil || !storedReport.isComplete {
            return storedReport
        }

        guard let decodedProjects = loadLegacyRecentProjectsFromUserDefaults(for: scope, userDefaults: userDefaults) else {
            return .missing
        }

        if (try? projectStore.saveProjects(decodedProjects, for: scope)) != nil {
            clearLegacyRecentProjectsFromUserDefaults(for: scope, userDefaults: userDefaults)
        }

        return ProjectFileStore.ProjectLoadReport(projects: decodedProjects, isComplete: true)
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
