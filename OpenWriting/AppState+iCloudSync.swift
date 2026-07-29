import AuthenticationServices
import Foundation
import OSLog

extension AppState {
    nonisolated static func cloudSaveCompletionIsCurrent(
        saveGeneration: UInt64,
        currentGeneration: UInt64,
        scope: String,
        currentScope: String?
    ) -> Bool {
        saveGeneration == currentGeneration && scope == currentScope
    }

    nonisolated static func reconciledCloudSnapshotTimestamp(
        current: TimeInterval,
        savedSnapshotDate: Date
    ) -> TimeInterval {
        max(current, savedSnapshotDate.timeIntervalSince1970)
    }

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

        cloudSaveTask = Task { [cloudStore] in
            do {
                try await Task.sleep(for: .milliseconds(900))
                try Task.checkCancellation()
            } catch {
                return
            }

            let pendingSnapshot = await MainActor.run { () -> AccountProjectSnapshot? in
                guard self.cloudSaveGeneration == saveGeneration,
                      self.currentStorageScope == scope else {
                    return nil
                }
                return AccountProjectSnapshot(
                    activeProjectID: self.activeProjectID,
                    recentProjects: self.recentProjects.map {
                        $0.detachedPersistenceSnapshot()
                    },
                    deletedProjects: self.projectDeletionTombstones,
                    updatedAt: Date(timeIntervalSince1970: self.currentProjectSnapshotTimestamp)
                )
            }
            guard !Task.isCancelled else { return }
            guard var snapshot = pendingSnapshot else { return }
            snapshot.recentProjects = await self.projectPersistence
                .hydratedProjectsForPersistenceSnapshot(
                    snapshot.recentProjects,
                    for: scope
                )
            guard !Task.isCancelled else { return }
            let hydrationIsCurrent = await MainActor.run {
                self.cloudSaveGeneration == saveGeneration
                    && self.currentStorageScope == scope
            }
            guard hydrationIsCurrent, !Task.isCancelled else { return }

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
                    guard shouldStillSave, !Task.isCancelled else { return }

                    try await cloudStore.saveSnapshot(snapshot, for: scope)
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard Self.cloudSaveCompletionIsCurrent(
                            saveGeneration: saveGeneration,
                            currentGeneration: self.cloudSaveGeneration,
                            scope: scope,
                            currentScope: self.currentStorageScope
                        ) else {
                            return
                        }
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
                        guard Self.cloudSaveCompletionIsCurrent(
                            saveGeneration: saveGeneration,
                            currentGeneration: self.cloudSaveGeneration,
                            scope: scope,
                            currentScope: self.currentStorageScope
                        ) else {
                            return
                        }
                        self.setCloudSyncStatus(
                            title: "本机保存",
                            symbolName: "icloud.slash",
                            message: UserFacingError.syncMessage(for: error)
                        )
                    }
                }
            case let .unavailable(message):
                await MainActor.run {
                    guard Self.cloudSaveCompletionIsCurrent(
                        saveGeneration: saveGeneration,
                        currentGeneration: self.cloudSaveGeneration,
                        scope: scope,
                        currentScope: self.currentStorageScope
                    ) else {
                        return
                    }
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
                await logoutAccount()
                setCloudSyncStatus(
                    title: "本机保存",
                    symbolName: "icloud.slash",
                    message: "当前 Apple ID 授权已失效，请重新登录。"
                )
                return false
            case .transferred:
                return true
            @unknown default:
                setCloudSyncStatus(
                    title: "本机保存",
                    symbolName: "icloud.slash",
                    message: "暂时无法确认 Apple ID 授权状态，已暂停 iCloud 同步。"
                )
                return false
            }
        } catch {
            AppLogger.sync.error("Apple credential state refresh failed: \(error.localizedDescription, privacy: .public)")
            setCloudSyncStatus(
                title: "本机保存",
                symbolName: "icloud.slash",
                message: "暂时无法确认 Apple ID 授权状态，已暂停 iCloud 同步。"
            )
            return false
        }
    }

    func synchronizeWithICloud(forcePull: Bool) async {
        guard !isCloudSynchronizationInProgress else {
            if let scope = currentStorageScope {
                if pendingCloudSynchronizationScope == scope {
                    pendingCloudSynchronizationForcePull =
                        pendingCloudSynchronizationForcePull || forcePull
                } else {
                    pendingCloudSynchronizationScope = scope
                    pendingCloudSynchronizationForcePull = forcePull
                }
            }
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
        let synchronizationGeneration = cloudSaveGeneration
        var shouldRetrySynchronization = false
        defer {
            let pendingScope = pendingCloudSynchronizationScope
            let pendingForcePull = pendingCloudSynchronizationForcePull
            pendingCloudSynchronizationScope = nil
            pendingCloudSynchronizationForcePull = false
            isCloudSynchronizationInProgress = false
            if let pendingScope, currentStorageScope == pendingScope {
                Task { @MainActor [weak self] in
                    await self?.synchronizeWithICloud(forcePull: pendingForcePull)
                }
            } else if shouldRetrySynchronization, currentStorageScope == scope {
                Task { @MainActor [weak self] in
                    await self?.synchronizeWithICloud(forcePull: false)
                }
            }
        }

        setCloudSyncStatus(
            title: "正在同步",
            symbolName: "arrow.triangle.2.circlepath.icloud",
            message: "正在检查 iCloud 中的项目快照。"
        )

        let availability = await cloudStore.availability()
        guard Self.cloudSaveCompletionIsCurrent(
            saveGeneration: synchronizationGeneration,
            currentGeneration: cloudSaveGeneration,
            scope: scope,
            currentScope: currentStorageScope
        ) else {
            shouldRetrySynchronization = currentStorageScope == scope
            return
        }
        guard case .available = availability else {
            setCloudSyncStatus(title: "本机保存", symbolName: "icloud.slash", message: availability.message)
            return
        }

        do {
            let remoteSnapshot = try await cloudStore.loadSnapshot(for: scope)
            guard Self.cloudSaveCompletionIsCurrent(
                saveGeneration: synchronizationGeneration,
                currentGeneration: cloudSaveGeneration,
                scope: scope,
                currentScope: currentStorageScope
            ) else {
                shouldRetrySynchronization = currentStorageScope == scope
                return
            }
            if let remoteSnapshot {
                let didPersist = await reconcileAndPersistCloudSnapshot(
                    remoteSnapshot
                )
                guard Self.cloudSaveCompletionIsCurrent(
                    saveGeneration: synchronizationGeneration,
                    currentGeneration: cloudSaveGeneration,
                    scope: scope,
                    currentScope: currentStorageScope
                ) else {
                    shouldRetrySynchronization = currentStorageScope == scope
                    return
                }
                guard didPersist else {
                    setCloudSyncStatus(
                        title: "保存失败",
                        symbolName: "exclamationmark.triangle",
                        message: lastProjectPersistenceErrorMessage
                            ?? "已拉取 iCloud 项目，但写入本机存储失败。"
                    )
                    return
                }

                scheduleCloudSnapshotSave()
                setCloudSyncStatus(
                    title: "iCloud 已连接",
                    symbolName: "icloud.fill",
                    message: "已协调 iCloud 项目并保存到本机，合并结果正在回传。"
                )
                return
            }

            if !recentProjects.isEmpty || !projectDeletionTombstones.isEmpty {
                let persistenceProjects = recentProjects.map {
                    $0.detachedPersistenceSnapshot()
                }
                let snapshotProjects = await projectPersistence
                    .hydratedProjectsForPersistenceSnapshot(
                        persistenceProjects,
                        for: scope
                    )
                guard Self.cloudSaveCompletionIsCurrent(
                    saveGeneration: synchronizationGeneration,
                    currentGeneration: cloudSaveGeneration,
                    scope: scope,
                    currentScope: currentStorageScope
                ) else {
                    if currentStorageScope == scope {
                        scheduleCloudSnapshotSave()
                        setCloudSyncStatus(
                            title: "本机保存",
                            symbolName: "icloud.slash",
                            message: "同步准备期间检测到新修改，已安排重新同步。"
                        )
                    }
                    return
                }
                let snapshot = AccountProjectSnapshot(
                    activeProjectID: activeProjectID,
                    recentProjects: snapshotProjects,
                    deletedProjects: projectDeletionTombstones,
                    updatedAt: Date(timeIntervalSince1970: max(currentProjectSnapshotTimestamp, Date().timeIntervalSince1970))
                )
                try await cloudStore.saveSnapshot(snapshot, for: scope)
                guard Self.cloudSaveCompletionIsCurrent(
                    saveGeneration: synchronizationGeneration,
                    currentGeneration: cloudSaveGeneration,
                    scope: scope,
                    currentScope: currentStorageScope
                ) else {
                    if currentStorageScope == scope {
                        scheduleCloudSnapshotSave()
                        setCloudSyncStatus(
                            title: "本机保存",
                            symbolName: "icloud.slash",
                            message: "同步上传期间检测到新修改，已安排重新同步。"
                        )
                    }
                    return
                }
                currentProjectSnapshotTimestamp = Self.reconciledCloudSnapshotTimestamp(
                    current: currentProjectSnapshotTimestamp,
                    savedSnapshotDate: snapshot.updatedAt
                )
            }

            setCloudSyncStatus(
                title: "iCloud 已连接",
                symbolName: "icloud.fill",
                message: "当前设备上的项目已与 iCloud 对齐。"
            )
        } catch {
            guard Self.cloudSaveCompletionIsCurrent(
                saveGeneration: synchronizationGeneration,
                currentGeneration: cloudSaveGeneration,
                scope: scope,
                currentScope: currentStorageScope
            ) else {
                shouldRetrySynchronization = currentStorageScope == scope
                return
            }
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
        let mergedState = CloudProjectMergePolicy.mergeCloudProjectState(
            local: recentProjects,
            localDeletedProjects: projectDeletionTombstones,
            remote: snapshot.recentProjects,
            remoteDeletedProjects: snapshot.deletedProjects
        )
        let mergedProjects = mergedState.projects
        let mergedProjectIDs = Set(mergedProjects.map(\.id))
        let preservedSelection = CloudProjectMergePolicy.preservedCloudSelection(
            selectedProjectID: previousSelectedProjectID,
            activeProjectID: previousActiveProjectID,
            snapshotActiveProjectID: snapshot.activeProjectID,
            projectIDs: mergedProjectIDs
        )

        currentProjectSnapshotTimestamp = max(currentProjectSnapshotTimestamp, snapshot.updatedAt.timeIntervalSince1970)
        isHydratingAccountScopedData = true
        projectDeletionTombstones = mergedState.deletedProjects
        invalidateAllLongformWritingDeskContexts()
        recentProjects = mergedProjects
        activeProjectID = preservedSelection
        selectedProjectID = preservedSelection
        normalizeProjectSelection()
        isHydratingAccountScopedData = false
    }

    @discardableResult
    func reconcileAndPersistCloudSnapshot(
        _ snapshot: AccountProjectSnapshot
    ) async -> Bool {
        applyCloudSnapshot(snapshot)
        return await flushProjectPersistence()
    }

    func setCloudSyncStatus(title: String, symbolName: String, message: String) {
        cloudSyncTitle = title
        cloudSyncSymbolName = symbolName
        cloudSyncStatusMessage = message
    }

    func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await appleCredentialStateProvider.credentialState(for: userID)
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
