import AuthenticationServices
import Foundation
import OSLog

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
        cloudSaveGeneration &+= 1
        let saveGeneration = cloudSaveGeneration

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
            do {
                try await Task.sleep(for: .milliseconds(900))
                try Task.checkCancellation()
            } catch {
                return
            }

            let shouldSave = await MainActor.run {
                self.cloudSaveGeneration == saveGeneration && self.currentStorageScope == scope
            }
            guard shouldSave else { return }

            let availability = await cloudStore.availability()
            do {
                try Task.checkCancellation()
            } catch {
                return
            }

            switch availability {
            case .available:
                do {
                    let shouldStillSave = await MainActor.run {
                        self.cloudSaveGeneration == saveGeneration && self.currentStorageScope == scope
                    }
                    guard shouldStillSave else { return }

                    try await cloudStore.saveSnapshot(snapshot, for: scope)
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard self.cloudSaveGeneration == saveGeneration else { return }
                        self.setCloudSyncStatus(
                            title: "iCloud 已连接",
                            symbolName: "icloud.fill",
                            message: "最新修改已经推送到 iCloud。"
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    AppLogger.sync.error("CloudKit background save failed: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        guard self.cloudSaveGeneration == saveGeneration else { return }
                        self.setCloudSyncStatus(
                            title: "本机保存",
                            symbolName: "icloud.slash",
                            message: UserFacingError.syncMessage(for: error)
                        )
                    }
                }
            case let .unavailable(message):
                await MainActor.run {
                    guard self.cloudSaveGeneration == saveGeneration else { return }
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
            AppLogger.sync.error("Apple credential state refresh failed: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }

    func synchronizeWithICloud(forcePull: Bool) async {
        guard !isCloudSynchronizationInProgress else {
            setCloudSyncStatus(
                title: "正在同步",
                symbolName: "arrow.triangle.2.circlepath.icloud",
                message: "已有 iCloud 同步正在进行。"
            )
            return
        }

        guard let scope = currentStorageScope else {
            await refreshCloudAvailability()
            return
        }

        isCloudSynchronizationInProgress = true
        cloudSaveTask?.cancel()
        cloudSaveGeneration &+= 1
        defer {
            isCloudSynchronizationInProgress = false
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
                currentProjectSnapshotTimestamp = snapshot.updatedAt.timeIntervalSince1970
            }

            setCloudSyncStatus(
                title: "iCloud 已连接",
                symbolName: "icloud.fill",
                message: "当前设备上的项目已与 iCloud 对齐。"
            )
        } catch {
            AppLogger.sync.error("Manual iCloud synchronization failed: \(error.localizedDescription, privacy: .public)")
            setCloudSyncStatus(
                title: "本机保存",
                symbolName: "icloud.slash",
                message: UserFacingError.syncMessage(for: error)
            )
        }
    }

    func applyCloudSnapshot(_ snapshot: AccountProjectSnapshot) {
        let previousActiveProjectID = activeProjectID
        let previousSelectedProjectID = selectedProjectID
        let mergedProjects = Self.mergeCloudProjects(local: recentProjects, remote: snapshot.recentProjects)
        let mergedProjectIDs = Set(mergedProjects.map(\.id))
        let preservedSelection = Self.preservedCloudSelection(
            selectedProjectID: previousSelectedProjectID,
            activeProjectID: previousActiveProjectID,
            snapshotActiveProjectID: snapshot.activeProjectID,
            projectIDs: mergedProjectIDs
        )

        currentProjectSnapshotTimestamp = max(currentProjectSnapshotTimestamp, snapshot.updatedAt.timeIntervalSince1970)
        isHydratingAccountScopedData = true
        recentProjects = mergedProjects
        activeProjectID = preservedSelection
        selectedProjectID = preservedSelection
        normalizeProjectSelection()
        isHydratingAccountScopedData = false
    }

    static func mergeCloudProjects(local: [NovelProject], remote: [NovelProject]) -> [NovelProject] {
        var localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var merged: [NovelProject] = []
        var visitedIDs = Set<NovelProject.ID>()

        for remoteProject in remote {
            if let localProject = localByID.removeValue(forKey: remoteProject.id) {
                merged.append(mergeCloudProject(local: localProject, remote: remoteProject))
            } else {
                merged.append(remoteProject)
            }
            visitedIDs.insert(remoteProject.id)
        }

        let remainingLocal = local
            .filter { !visitedIDs.contains($0.id) }
            .sorted { $0.updatedAtDate > $1.updatedAtDate }
        merged.append(contentsOf: remainingLocal)
        return merged.sorted { lhs, rhs in
            if lhs.updatedAtDate == rhs.updatedAtDate {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAtDate > rhs.updatedAtDate
        }
    }

    private static func mergeCloudProject(local: NovelProject, remote: NovelProject) -> NovelProject {
        var merged = remote.updatedAtDate >= local.updatedAtDate ? remote : local
        merged.chapterDrafts = mergeCloudChapterDrafts(local: local.chapterDrafts, remote: remote.chapterDrafts)
        merged.chapterCatalog = merged.chapterDrafts
            .map(ChapterDraftMetadata.init)
            .sorted(by: ChapterDraftMetadata.sortDescending)

        if local.updatedAtDate > remote.updatedAtDate {
            merged.draftText = local.draftText
            merged.currentChapterTitle = local.currentChapterTitle
            merged.currentVolumeNumber = local.currentVolumeNumber
            merged.currentChapterNumber = local.currentChapterNumber
            merged.chapterFocus = local.chapterFocus
            merged.updatedAtDate = local.updatedAtDate
        }

        if let newestChapterDate = merged.chapterDrafts.map(\.savedAtDate).max(),
           newestChapterDate > merged.updatedAtDate {
            merged.updatedAtDate = newestChapterDate
        }

        return merged
    }

    private static func mergeCloudChapterDrafts(
        local: [ChapterDraft],
        remote: [ChapterDraft]
    ) -> [ChapterDraft] {
        var draftsByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for remoteDraft in remote {
            if let localDraft = draftsByID[remoteDraft.id] {
                draftsByID[remoteDraft.id] = remoteDraft.savedAtDate >= localDraft.savedAtDate
                    ? remoteDraft
                    : localDraft
            } else {
                draftsByID[remoteDraft.id] = remoteDraft
            }
        }
        return draftsByID.values.sorted(by: ChapterDraft.sortDescending)
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
