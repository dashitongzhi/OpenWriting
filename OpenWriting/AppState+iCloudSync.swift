import AuthenticationServices
import Foundation

extension AppState {
    func noteLocalProjectMutation() {
        currentProjectSnapshotTimestamp = Date().timeIntervalSince1970
    }

    func mergeChapterTreeSection(
        current: inout String,
        replacement: String,
        baseline: String?
    ) -> ChapterTreeSectionMergeDecision {
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReplacement.isEmpty else { return .ignored }

        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if let baseline, normalizedCurrent != baseline {
            return .protected
        }

        current = trimmedReplacement
        return .accepted
    }

    func scheduleCloudSnapshotSave() {
        cloudSaveTask?.cancel()

        guard let scope = currentStorageScope else {
            Task { @MainActor in
                await refreshCloudAvailability()
            }
            return
        }

        let snapshotProjects = hydratedProjectsForPersistenceSnapshot(recentProjects)
        let snapshot = AccountProjectSnapshot(
            activeProjectID: activeProjectID,
            recentProjects: snapshotProjects,
            updatedAt: Date(timeIntervalSince1970: currentProjectSnapshotTimestamp)
        )

        cloudSaveTask = Task { [cloudStore] in
            try? await Task.sleep(for: .milliseconds(900))
            let availability = await cloudStore.availability()

            switch availability {
            case .available:
                do {
                    try await cloudStore.saveSnapshot(snapshot, for: scope)
                    await MainActor.run {
                        self.setCloudSyncStatus(
                            title: "iCloud 已连接",
                            symbolName: "icloud.fill",
                            message: "最新修改已经推送到 iCloud。"
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.setCloudSyncStatus(
                            title: "本机保存",
                            symbolName: "icloud.slash",
                            message: error.localizedDescription
                        )
                    }
                }
            case let .unavailable(message):
                await MainActor.run {
                    self.setCloudSyncStatus(
                        title: "本机保存",
                        symbolName: "icloud.slash",
                        message: message
                    )
                }
            }
        }
    }

    func refreshCloudAvailability() async {
        guard activeAccount != nil else {
            setCloudSyncStatus(
                title: "本机保存",
                symbolName: "icloud.slash",
                message: "登录 Apple ID 后即可通过 iCloud 同步项目。"
            )
            return
        }

        let availability = await cloudStore.availability()
        let isAvailable: Bool
        switch availability {
        case .available:
            isAvailable = true
        case .unavailable:
            isAvailable = false
        }

        setCloudSyncStatus(
            title: isAvailable ? "iCloud 已连接" : "本机保存",
            symbolName: isAvailable ? "icloud.fill" : "icloud.slash",
            message: availability.message
        )
    }

    func refreshActiveAppleCredentialState() async -> Bool {
        guard let activeAccount else {
            return false
        }

        do {
            let credentialState = try await credentialState(for: activeAccount.userID)
            switch credentialState {
            case .authorized:
                return true
            case .revoked, .notFound:
                logoutAccount()
                setCloudSyncStatus(
                    title: "本机保存",
                    symbolName: "icloud.slash",
                    message: "当前 Apple ID 授权已失效，请重新登录。"
                )
                return false
            case .transferred:
                return true
            @unknown default:
                return false
            }
        } catch {
            return true
        }
    }

    func synchronizeWithICloud(forcePull: Bool) async {
        guard let scope = currentStorageScope else {
            await refreshCloudAvailability()
            return
        }

        setCloudSyncStatus(
            title: "正在同步",
            symbolName: "arrow.triangle.2.circlepath.icloud",
            message: "正在检查 iCloud 中的项目快照。"
        )

        let availability = await cloudStore.availability()
        guard case .available = availability else {
            setCloudSyncStatus(title: "本机保存", symbolName: "icloud.slash", message: availability.message)
            return
        }

        do {
            if let remoteSnapshot = try await cloudStore.loadSnapshot(for: scope) {
                let remoteTimestamp = remoteSnapshot.updatedAt.timeIntervalSince1970

                if forcePull || remoteTimestamp > currentProjectSnapshotTimestamp {
                    applyCloudSnapshot(remoteSnapshot)
                    setCloudSyncStatus(
                        title: "iCloud 已连接",
                        symbolName: "icloud.fill",
                        message: "已从 iCloud 拉取最新项目。"
                    )
                    return
                }
            }

            if !recentProjects.isEmpty {
                let snapshotProjects = hydratedProjectsForPersistenceSnapshot(recentProjects)
                let snapshot = AccountProjectSnapshot(
                    activeProjectID: activeProjectID,
                    recentProjects: snapshotProjects,
                    updatedAt: Date(timeIntervalSince1970: max(currentProjectSnapshotTimestamp, Date().timeIntervalSince1970))
                )
                try await cloudStore.saveSnapshot(snapshot, for: scope)
                if currentProjectSnapshotTimestamp == 0 {
                    currentProjectSnapshotTimestamp = snapshot.updatedAt.timeIntervalSince1970
                }
            }

            setCloudSyncStatus(
                title: "iCloud 已连接",
                symbolName: "icloud.fill",
                message: "当前设备上的项目已与 iCloud 对齐。"
            )
        } catch {
            setCloudSyncStatus(
                title: "本机保存",
                symbolName: "icloud.slash",
                message: error.localizedDescription
            )
        }
    }

    func applyCloudSnapshot(_ snapshot: AccountProjectSnapshot) {
        let previousActiveProjectID = activeProjectID
        let previousSelectedProjectID = selectedProjectID
        let snapshotProjectIDs = Set(snapshot.recentProjects.map(\.id))
        let preservedSelection = Self.preservedCloudSelection(
            selectedProjectID: previousSelectedProjectID,
            activeProjectID: previousActiveProjectID,
            snapshotActiveProjectID: snapshot.activeProjectID,
            projectIDs: snapshotProjectIDs
        )

        currentProjectSnapshotTimestamp = snapshot.updatedAt.timeIntervalSince1970
        isHydratingAccountScopedData = true
        recentProjects = snapshot.recentProjects
        activeProjectID = preservedSelection
        selectedProjectID = preservedSelection
        normalizeProjectSelection()
        isHydratingAccountScopedData = false
    }

    static func preservedCloudSelection(
        selectedProjectID: NovelProject.ID?,
        activeProjectID: NovelProject.ID?,
        snapshotActiveProjectID: NovelProject.ID?,
        projectIDs: Set<NovelProject.ID>
    ) -> NovelProject.ID? {
        [
            selectedProjectID,
            activeProjectID,
            snapshotActiveProjectID
        ]
        .compactMap { $0 }
        .first { projectIDs.contains($0) }
    }

    func setCloudSyncStatus(title: String, symbolName: String, message: String) {
        cloudSyncTitle = title
        cloudSyncSymbolName = symbolName
        cloudSyncStatusMessage = message
    }

    func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }

    static func activeProjectIDStorageKey(for scope: String?) -> String {
        scopedStorageKey(base: StorageKey.activeProjectID, scope: scope)
    }

    static func recentProjectsStorageKey(for scope: String?) -> String {
        scopedStorageKey(base: StorageKey.recentProjects, scope: scope)
    }

    static func projectSnapshotTimestampStorageKey(for scope: String?) -> String {
        scopedStorageKey(base: StorageKey.projectSnapshotTimestamp, scope: scope)
    }

    static func scopedStorageKey(base: String, scope: String?) -> String {
        guard let scope = normalizedStorageScope(scope) else {
            return base
        }

        return "\(base).\(sanitizedStorageComponent(scope))"
    }

    static func normalizedStorageScope(_ scope: String?) -> String? {
        guard let scope else { return nil }
        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
