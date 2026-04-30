import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let emptyConfigurationMessage = "自定义模型需填写 Base URL、模型 ID 与 API Key 后再测试连接。"

    let userDefaults: UserDefaults
    let projectStore: ProjectFileStore
    @ObservationIgnored let cloudStore = ICloudProjectStore()
    @ObservationIgnored var cloudSaveTask: Task<Void, Never>?
    @ObservationIgnored var recentProjectsPersistTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var isHydratingAccountScopedData = false
    @ObservationIgnored var isApplyingProviderConfiguration = false
    @ObservationIgnored var validationTask: Task<Void, Never>?

    var selectedProvider: ModelProvider {
        willSet {
            guard !isApplyingProviderConfiguration else { return }
            persistConnectionSettings(for: selectedProvider)
        }
        didSet {
            persistSelectedProvider()
            loadConnectionSettings(for: selectedProvider)
        }
    }
    var modelName: String {
        didSet {
            guard !isApplyingProviderConfiguration else { return }
            persistModelName()
            markConfigurationAsEdited()
        }
    }
    var apiKey: String {
        didSet {
            guard !isApplyingProviderConfiguration else { return }
            persistAPIKey()
            markConfigurationAsEdited()
        }
    }
    var baseURL: String {
        didSet {
            guard !isApplyingProviderConfiguration else { return }
            persistBaseURL()
            markConfigurationAsEdited()
        }
    }
    var autoValidateOnLaunch: Bool {
        didSet {
            persistAutoValidatePreference()
        }
    }
    var showWritingDeskCachePanel: Bool {
        didSet {
            persistWritingDeskDisplayPreferences()
        }
    }
    var showWritingDeskTimeline: Bool {
        didSet {
            persistWritingDeskDisplayPreferences()
        }
    }
    var connectionStatus: ConnectionStatus
    var validationMessage: String
    var selectedSidebarItem: SidebarItem = .home
    var selectedProjectID: NovelProject.ID?
    var projectSpaceScrollTarget: NovelProject.ID?
    var projectSpaceSelectionPulse = 0
    let quoteSeed = Int.random(in: 0 ..< Int.max)

    var activeProjectID: NovelProject.ID? {
        didSet {
            persistActiveProjectID()
            guard !isHydratingAccountScopedData else { return }
            noteLocalProjectMutation()
            scheduleCloudSnapshotSave()
        }
    }

    var activeAccount: AppleAccountProfile? {
        didSet {
            persistActiveAccountProfile()
        }
    }

    var recentProjects: [NovelProject] {
        didSet {
            scheduleRecentProjectsPersistence(snapshot: recentProjects, for: currentStorageScope)
            guard !isHydratingAccountScopedData else { return }
            noteLocalProjectMutation()
            scheduleCloudSnapshotSave()
        }
    }
    var cloudSyncTitle = "本机保存"
    var cloudSyncSymbolName = "icloud.slash"
    var cloudSyncStatusMessage = "登录 Apple ID 后即可通过 iCloud 同步项目。"

    var currentProjectSnapshotTimestamp: TimeInterval {
        didSet {
            persistProjectSnapshotTimestamp()
        }
    }

    let writingPillars: [StoryPillar] = [
        StoryPillar(
            title: "角色弧线",
            detail: "把主角、反派与配角的欲望变化放在同一张时间轴里。"
        ),
        StoryPillar(
            title: "章节树",
            detail: "让大纲、场景目标和伏笔回收保持可追踪，而不是散落在备忘录里。"
        )
    ]

    let inspirationSignals: [InspirationSignal] = [
        InspirationSignal(title: "人物关系图", description: "适合先搭冲突，再落章节。"),
        InspirationSignal(title: "世界观卡片", description: "把地点、组织和规则集中收纳。"),
        InspirationSignal(title: "章节节奏盘", description: "观察高潮、低潮与信息释放的密度。")
    ]

    init(
        userDefaults: UserDefaults = .standard,
        projectStore: ProjectFileStore? = nil
    ) {
        let projectStore = projectStore ?? ProjectFileStore()
        Self.migrateLegacyUserDefaultsIfNeeded(userDefaults, projectStore: projectStore)
        Self.migrateLegacyEmailScopeIfNeeded(userDefaults, projectStore: projectStore)
        Self.migrateAPIKeysToKeychainIfNeeded(userDefaults)
        self.userDefaults = userDefaults
        self.projectStore = projectStore
        let resolvedActiveAccount = Self.loadActiveAppleAccount(from: userDefaults)
        let resolvedStorageScope = resolvedActiveAccount?.userID
        let resolvedProvider = ModelProvider(
            rawValue: Self.stringValue(
                forKey: StorageKey.selectedProvider,
                userDefaults: userDefaults
            ) ?? ""
        ) ?? .openAICompatible
        self.activeAccount = resolvedActiveAccount
        self.selectedProvider = resolvedProvider
        self.modelName = Self.loadModelName(for: resolvedProvider, userDefaults: userDefaults)
        self.apiKey = Self.loadAPIKeyFromKeychain(for: resolvedProvider) ?? ""
        self.baseURL = Self.loadBaseURL(for: resolvedProvider, userDefaults: userDefaults)
        self.autoValidateOnLaunch = Self.boolValue(
            forKey: StorageKey.autoValidateOnLaunch,
            userDefaults: userDefaults
        ) ?? true
        self.showWritingDeskCachePanel = Self.boolValue(
            forKey: StorageKey.showWritingDeskCachePanel,
            userDefaults: userDefaults
        ) ?? true
        self.showWritingDeskTimeline = Self.boolValue(
            forKey: StorageKey.showWritingDeskTimeline,
            userDefaults: userDefaults
        ) ?? true
        self.currentProjectSnapshotTimestamp = Self.doubleValue(
            forKey: Self.projectSnapshotTimestampStorageKey(for: resolvedStorageScope),
            userDefaults: userDefaults
        ) ?? 0
        self.recentProjects = Self.loadRecentProjects(
            for: resolvedStorageScope,
            from: userDefaults,
            projectStore: projectStore
        ) ?? Self.defaultRecentProjects
        self.connectionStatus = .idle
        self.validationMessage = Self.emptyConfigurationMessage
        self.activeProjectID = Self.stringValue(
            forKey: Self.activeProjectIDStorageKey(for: resolvedStorageScope),
            userDefaults: userDefaults
        )
        self.selectedProjectID = Self.stringValue(
            forKey: Self.activeProjectIDStorageKey(for: resolvedStorageScope),
            userDefaults: userDefaults
        )

        normalizeProjectSelection()

        if autoValidateOnLaunch, hasEnteredConnectionInfo {
            validateConfiguration()
        } else {
            refreshIdleValidationMessage()
        }

        Task { @MainActor in
            let hasValidAppleCredential = await refreshActiveAppleCredentialState()
            await refreshCloudAvailability()

            if hasValidAppleCredential {
                await synchronizeWithICloud(forcePull: false)
            }
        }
    }

    var activeWorkspaceName: String {
        activeProject?.title ?? "当前工作区"
    }

    var dashboardStats: [DashboardStat] {
        [
            DashboardStat(
                title: "活跃项目",
                value: String(format: "%02d", recentProjects.count),
                detail: "打开项目空间",
                symbolName: SidebarItem.projects.symbolName,
                destination: .projects
            ),
            DashboardStat(
                title: "正文总字数",
                value: Self.abbreviatedCount(totalDraftWordCount),
                detail: "回到写作台继续",
                symbolName: SidebarItem.writingDesk.symbolName,
                destination: .writingDesk
            ),
            DashboardStat(
                title: "设定资料",
                value: "\(totalReferenceDocumentCount)",
                detail: "进入素材库整理",
                symbolName: SidebarItem.library.symbolName,
                destination: .library
            )
        ]
    }

    var totalDraftWordCount: Int {
        recentProjects.reduce(0) { $0 + $1.manuscriptWordCount }
    }

    var totalReferenceDocumentCount: Int {
        recentProjects.reduce(0) { $0 + $1.referenceDocuments.count }
    }

    var totalWrittenChapters: Int {
        recentProjects.reduce(0) { $0 + $1.writtenChapters }
    }

    var totalSavedChapterWordCount: Int {
        recentProjects.reduce(0) { $0 + $1.savedChapterWordCount }
    }

    var activeProject: NovelProject? {
        recentProjects.first(where: { $0.id == activeProjectID }) ?? recentProjects.first
    }

    var isConfigurationReady: Bool {
        resolvedAIConfiguration != nil
    }

    func validateConfiguration() {
        validationTask?.cancel()

        guard let configuration = resolvedAIConfiguration else {
            return
        }

        connectionStatus = .checking
        validationMessage = "正在验证 \(selectedProvider.title) 连接..."

        let providerTitle = selectedProvider.title
        validationTask = Task { @MainActor in
            do {
                let resolvedModel = try await AIWritingService.validateConnection(configuration: configuration)
                guard !Task.isCancelled else { return }

                connectionStatus = .ready
                validationMessage = providerTitle == ModelProvider.openAICompatible.title
                    ? "已连接 OpenW 模型"
                    : "已连接 \(resolvedModel)"
            } catch {
                guard !Task.isCancelled else { return }

                connectionStatus = .needsAttention
                validationMessage = Self.validationFailureMessage(for: error)
            }
        }
    }

    var aiConfiguration: AIConnectionConfiguration? {
        resolvedAIConfiguration
    }

    func createProject(named title: String, length: NovelLength) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectTitle = trimmedTitle.isEmpty ? "未命名计划" : trimmedTitle
        let draftProject = NovelProject(
            id: makeProjectIdentifier(from: projectTitle),
            title: projectTitle,
            genre: "待设定",
            summary: Self.defaultProjectSummary(for: length),
            storyLength: length,
            updatedAt: Self.currentTimestampLabel(),
            currentChapterTitle: "开篇设定",
            currentChapterNumber: 1,
            writtenChapters: 0,
            chapterFocus: Self.defaultChapterFocus(for: length),
            draftText: "",
            outlineText: "",
            outlineGenerationProfile: Self.defaultOutlineGenerationProfile(for: length),
            structureNotes: Self.defaultStructureNotes(for: length),
            sceneProgressNotes: Self.defaultSceneProgressNotes(for: length),
            characterArcNotes: Self.defaultCharacterArcNotes(for: length),
            foreshadowNotes: Self.defaultForeshadowNotes(for: length),
            volumePlanNotes: Self.defaultVolumePlanNotes(for: length),
            activeThreadsNotes: Self.defaultActiveThreadsNotes(for: length),
            referenceContextText: "",
            specialRequirements: Self.defaultSpecialRequirements(for: length),
            wordTargetText: Self.defaultWordTargetText(for: length),
            continuityNotes: Self.defaultContinuityNotes(for: length),
            referenceDocuments: []
        )

        recentProjects.insert(draftProject, at: 0)
        openProjectSpace(for: draftProject.id, scrollToProject: true)
    }

    func continueWriting() {
        openWritingDesk(for: activeProject?.id ?? recentProjects.first?.id)
    }

    func openProjectSpace(for projectID: NovelProject.ID? = nil, scrollToProject: Bool = false) {
        selectedSidebarItem = .projects

        let resolvedProjectID = projectID ?? activeProject?.id ?? recentProjects.first?.id
        guard let resolvedProjectID else {
            projectSpaceScrollTarget = nil
            return
        }

        activeProjectID = resolvedProjectID
        selectedProjectID = resolvedProjectID

        if scrollToProject {
            projectSpaceScrollTarget = resolvedProjectID
            projectSpaceSelectionPulse += 1
        } else {
            projectSpaceScrollTarget = nil
        }
    }

    func openWritingDesk(for projectID: NovelProject.ID? = nil) {
        selectedSidebarItem = .writingDesk

        let resolvedProjectID = projectID ?? activeProject?.id ?? recentProjects.first?.id
        guard let resolvedProjectID else { return }

        activeProjectID = resolvedProjectID
        selectedProjectID = resolvedProjectID
    }

    func openOutline() {
        selectedSidebarItem = .outline
    }

    func openLibrary() {
        selectedSidebarItem = .library
    }

    func navigate(to item: SidebarItem) {
        switch item {
        case .home:
            selectedSidebarItem = .home
        case .projects:
            openProjectSpace()
        case .writingDesk:
            openWritingDesk()
        case .outline:
            openOutline()
        case .library:
            openLibrary()
        }
    }

    func selectProject(_ projectID: NovelProject.ID) {
        activeProjectID = projectID
        selectedProjectID = projectID
    }

    func deleteProject(_ projectID: NovelProject.ID) {
        guard recentProjects.contains(where: { $0.id == projectID }) else { return }

        recentProjects.removeAll { $0.id == projectID }

        if projectSpaceScrollTarget == projectID {
            projectSpaceScrollTarget = nil
        }

        normalizeProjectSelection()
    }

    func clearProjectSpaceScrollTarget() {
        projectSpaceScrollTarget = nil
    }

    func updateDraftText(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.draftText = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateCurrentChapterTitle(_ title: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.currentChapterTitle = title
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateCurrentChapterNumber(_ number: Int, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.currentChapterNumber = max(number, 1)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateChapterFocus(_ focus: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.chapterFocus = focus
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateOutlineText(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.outlineText = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateOutlineGenerationProfile(_ profile: OutlineGenerationProfile, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.outlineGenerationProfile = profile
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateStructureNotes(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.structureNotes = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateSceneProgressNotes(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.sceneProgressNotes = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateCharacterArcNotes(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.characterArcNotes = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateForeshadowNotes(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.foreshadowNotes = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateVolumePlanNotes(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.volumePlanNotes = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateActiveThreadsNotes(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.activeThreadsNotes = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateOutlineSummary(_ text: String, updatedAt: String? = nil, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.outlineSummary = text
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                project.outlineSummaryUpdatedAt = ""
            } else if let updatedAt {
                project.outlineSummaryUpdatedAt = updatedAt
            } else if project.outlineSummaryUpdatedAt.isEmpty {
                project.outlineSummaryUpdatedAt = Self.currentTimestampLabel()
            }
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateReferenceContextText(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.referenceContextText = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateSpecialRequirements(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.specialRequirements = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateWordTargetText(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.wordTargetText = text
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateContinuityNotes(_ text: String, updatedAt: String? = nil, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            project.continuityNotes = trimmedText
            project.globalMemorySnapshot = GlobalMemorySnapshot.parse(from: trimmedText)
            if trimmedText.isEmpty {
                project.globalMemoryUpdatedAt = ""
            } else if let updatedAt {
                project.globalMemoryUpdatedAt = updatedAt
            } else if project.globalMemoryUpdatedAt.isEmpty {
                project.globalMemoryUpdatedAt = Self.currentTimestampLabel()
            }
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    @discardableResult
    func applyChapterTreeRefresh(
        _ refresh: ChapterTreeRefresh,
        baseline: ChapterTreeRefreshBaseline? = nil,
        updatedAt: String? = nil,
        for projectID: NovelProject.ID
    ) -> ChapterTreeRefreshApplyOutcome {
        var outcome = ChapterTreeRefreshApplyOutcome()

        updateProject(projectID) { project in
            let timestamp = updatedAt ?? Self.currentTimestampLabel()

            let outlineDecision = mergeChapterTreeSection(
                current: &project.outlineSummary,
                replacement: refresh.outlineSummary,
                baseline: baseline?.outlineSummary
            )
            if outlineDecision.accepted {
                project.outlineSummaryUpdatedAt = timestamp
                outcome.acceptedSections += 1
            } else if outlineDecision.protectedLocalChange {
                outcome.protectedSections += 1
            }

            let structureDecision = mergeChapterTreeSection(
                current: &project.structureNotes,
                replacement: refresh.structureNotes,
                baseline: baseline?.structureNotes
            )
            if structureDecision.accepted {
                outcome.acceptedSections += 1
            } else if structureDecision.protectedLocalChange {
                outcome.protectedSections += 1
            }

            let sceneDecision = mergeChapterTreeSection(
                current: &project.sceneProgressNotes,
                replacement: refresh.sceneProgressNotes,
                baseline: baseline?.sceneProgressNotes
            )
            if sceneDecision.accepted {
                outcome.acceptedSections += 1
            } else if sceneDecision.protectedLocalChange {
                outcome.protectedSections += 1
            }

            let characterDecision = mergeChapterTreeSection(
                current: &project.characterArcNotes,
                replacement: refresh.characterArcNotes,
                baseline: baseline?.characterArcNotes
            )
            if characterDecision.accepted {
                outcome.acceptedSections += 1
            } else if characterDecision.protectedLocalChange {
                outcome.protectedSections += 1
            }

            let foreshadowDecision = mergeChapterTreeSection(
                current: &project.foreshadowNotes,
                replacement: refresh.foreshadowNotes,
                baseline: baseline?.foreshadowNotes
            )
            if foreshadowDecision.accepted {
                outcome.acceptedSections += 1
            } else if foreshadowDecision.protectedLocalChange {
                outcome.protectedSections += 1
            }

            if outcome.acceptedSections > 0 {
                project.updatedAt = Self.currentTimestampLabel()
            }
        }

        return outcome
    }

    func updateGlobalMemorySnapshot(
        _ snapshot: GlobalMemorySnapshot,
        updatedAt: String? = nil,
        for projectID: NovelProject.ID
    ) {
        updateProject(projectID) { project in
            project.globalMemorySnapshot = snapshot
            project.continuityNotes = snapshot.formattedText
            if snapshot.hasStructuredContent {
                project.globalMemoryUpdatedAt = updatedAt ?? Self.currentTimestampLabel()
            } else {
                project.globalMemoryUpdatedAt = ""
            }
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func appendDraftText(_ text: String, for projectID: NovelProject.ID) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        updateProject(projectID) { project in
            if project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project.draftText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                project.draftText += "\n\n" + text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func saveCurrentChapterDraft(for projectID: NovelProject.ID) -> ChapterDraftSaveResult? {
        var result: ChapterDraftSaveResult?

        updateProject(projectID) { project in
            let trimmedDraft = project.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDraft.isEmpty else { return }

            let normalizedChapterNumber = max(project.currentChapterNumber, 1)
            let normalizedChapterTitle = Self.normalizedChapterTitle(project.currentChapterTitle)
            let timestamp = Self.currentTimestampLabel()

            if let existingIndex = project.chapterDrafts.firstIndex(where: { $0.chapterNumber == normalizedChapterNumber }) {
                let hasMeaningfulChange = project.chapterDrafts[existingIndex].chapterTitle != normalizedChapterTitle
                    || project.chapterDrafts[existingIndex].content != trimmedDraft
                let previousSnapshot = hasMeaningfulChange
                    ? project.chapterDrafts[existingIndex].versionSnapshot(reason: "保存前自动版本", savedAt: timestamp)
                    : nil
                project.chapterDrafts[existingIndex].chapterTitle = normalizedChapterTitle
                project.chapterDrafts[existingIndex].content = trimmedDraft
                project.chapterDrafts[existingIndex].savedAt = timestamp
                if let previousSnapshot {
                    project.chapterDrafts[existingIndex].versionHistory.insert(previousSnapshot, at: 0)
                }
                let updatedChapterDraft = project.chapterDrafts[existingIndex]
                project.chapterDrafts.sort(by: ChapterDraft.sortDescending)
                result = .updated(updatedChapterDraft)
            } else {
                let chapterDraft = ChapterDraft(
                    chapterNumber: normalizedChapterNumber,
                    chapterTitle: normalizedChapterTitle,
                    content: trimmedDraft,
                    savedAt: timestamp
                )
                project.chapterDrafts.append(chapterDraft)
                project.chapterDrafts.sort(by: ChapterDraft.sortDescending)
                result = .created(chapterDraft)
            }

            project.currentChapterNumber = normalizedChapterNumber
            project.currentChapterTitle = normalizedChapterTitle
            project.writtenChapters = max(project.writtenChapters, normalizedChapterNumber)
            project.updatedAt = timestamp
        }

        return result
    }

    func loadChapterDraft(_ chapterDraftID: ChapterDraft.ID, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            guard let chapterDraft = project.chapterDrafts.first(where: { $0.id == chapterDraftID }) else { return }
            project.currentChapterNumber = max(chapterDraft.chapterNumber, 1)
            project.currentChapterTitle = chapterDraft.chapterTitle
            project.draftText = chapterDraft.content
            project.writtenChapters = max(project.writtenChapters, chapterDraft.chapterNumber)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func beginNextChapter(after chapterDraft: ChapterDraft, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            let nextChapterNumber = max(chapterDraft.chapterNumber + 1, 1)

            if let existingDraft = project.chapterDrafts.first(where: { $0.chapterNumber == nextChapterNumber }) {
                project.currentChapterNumber = nextChapterNumber
                project.currentChapterTitle = existingDraft.chapterTitle
                project.draftText = existingDraft.content
            } else {
                project.currentChapterNumber = nextChapterNumber
                project.currentChapterTitle = "待命名章节"
                project.chapterFocus = Self.defaultNextChapterFocus(
                    after: chapterDraft,
                    storyLength: project.storyLength
                )
                project.draftText = ""
            }

            project.writtenChapters = max(project.writtenChapters, chapterDraft.chapterNumber)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    @discardableResult
    func updateSavedChapterDraft(
        _ chapterDraftID: ChapterDraft.ID,
        title: String,
        content: String,
        for projectID: NovelProject.ID
    ) -> ChapterDraft? {
        var updatedDraft: ChapterDraft?

        updateProject(projectID) { project in
            guard let existingIndex = project.chapterDrafts.firstIndex(where: { $0.id == chapterDraftID }) else { return }

            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContent.isEmpty else { return }

            let normalizedTitle = Self.normalizedChapterTitle(title)
            let timestamp = Self.currentTimestampLabel()
            let hasMeaningfulChange = project.chapterDrafts[existingIndex].chapterTitle != normalizedTitle
                || project.chapterDrafts[existingIndex].content != trimmedContent
            let previousSnapshot = hasMeaningfulChange
                ? project.chapterDrafts[existingIndex].versionSnapshot(reason: "手动编辑前自动版本", savedAt: timestamp)
                : nil

            project.chapterDrafts[existingIndex].chapterTitle = normalizedTitle
            project.chapterDrafts[existingIndex].content = trimmedContent
            project.chapterDrafts[existingIndex].savedAt = timestamp
            if let previousSnapshot {
                project.chapterDrafts[existingIndex].versionHistory.insert(previousSnapshot, at: 0)
            }

            let chapterNumber = project.chapterDrafts[existingIndex].chapterNumber
            let updated = project.chapterDrafts[existingIndex]
            project.chapterDrafts.sort(by: ChapterDraft.sortDescending)

            if project.currentChapterNumber == chapterNumber {
                project.currentChapterTitle = normalizedTitle
                project.draftText = trimmedContent
            }

            project.writtenChapters = max(project.writtenChapters, chapterNumber)
            project.updatedAt = timestamp
            updatedDraft = updated
        }

        return updatedDraft
    }

    @discardableResult
    func restoreChapterVersion(
        _ versionID: ChapterDraftVersion.ID,
        chapterDraftID: ChapterDraft.ID,
        for projectID: NovelProject.ID
    ) -> ChapterDraft? {
        var restoredDraft: ChapterDraft?

        updateProject(projectID) { project in
            guard let existingIndex = project.chapterDrafts.firstIndex(where: { $0.id == chapterDraftID }),
                  let version = project.chapterDrafts[existingIndex].versionHistory.first(where: { $0.id == versionID })
            else { return }

            let timestamp = Self.currentTimestampLabel()
            let currentSnapshot = project.chapterDrafts[existingIndex].versionSnapshot(
                reason: "回滚前自动版本",
                savedAt: timestamp
            )

            project.chapterDrafts[existingIndex].chapterTitle = version.chapterTitle
            project.chapterDrafts[existingIndex].content = version.content
            project.chapterDrafts[existingIndex].savedAt = timestamp
            project.chapterDrafts[existingIndex].versionHistory.insert(currentSnapshot, at: 0)

            let restored = project.chapterDrafts[existingIndex]
            project.chapterDrafts.sort(by: ChapterDraft.sortDescending)

            if project.currentChapterNumber == restored.chapterNumber {
                project.currentChapterTitle = restored.chapterTitle
                project.draftText = restored.content
            }

            project.writtenChapters = max(project.writtenChapters, restored.chapterNumber)
            project.updatedAt = timestamp
            restoredDraft = restored
        }

        return restoredDraft
    }

    func touchProject(_ projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func importReferenceDocuments(_ documents: [ReferenceDocument], for projectID: NovelProject.ID) {
        guard !documents.isEmpty else { return }
        updateProject(projectID) { project in
            project.referenceDocuments.insert(contentsOf: documents, at: 0)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func removeReferenceDocument(_ documentID: ReferenceDocument.ID, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.referenceDocuments.removeAll { $0.id == documentID }
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateReferenceDocumentCategory(
        _ category: ReferenceMaterialCategory,
        documentID: ReferenceDocument.ID,
        for projectID: NovelProject.ID
    ) {
        updateProject(projectID) { project in
            guard let index = project.referenceDocuments.firstIndex(where: { $0.id == documentID }) else { return }
            project.referenceDocuments[index].category = category
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func appendOutlineSummaryToContinuity(for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            let summary = project.outlineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return }

            var snapshot = project.globalMemorySnapshot.hasStructuredContent
                ? project.globalMemorySnapshot
                : GlobalMemorySnapshot.parse(from: project.continuityNotes)
            let stampedSummary = "- 章节树总结（\(project.outlineSummaryUpdatedAt.isEmpty ? Self.currentTimestampLabel() : project.outlineSummaryUpdatedAt)）：\(summary.replacingOccurrences(of: "\n", with: " "))"
            let existingRecentDevelopments = snapshot.recentDevelopments.trimmingCharacters(in: .whitespacesAndNewlines)

            if existingRecentDevelopments.isEmpty {
                snapshot.recentDevelopments = stampedSummary
            } else {
                snapshot.recentDevelopments = stampedSummary + "\n" + existingRecentDevelopments
            }

            project.globalMemorySnapshot = snapshot
            project.continuityNotes = snapshot.formattedText
            project.globalMemoryUpdatedAt = Self.currentTimestampLabel()
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func searchLongformProject(_ query: String, in projectID: NovelProject.ID, limit: Int = 60) -> [LongformSearchResult] {
        guard let project = project(for: projectID) else { return [] }
        let tokens = Self.searchTokens(from: query)
        guard !tokens.isEmpty else { return [] }

        var results: [LongformSearchResult] = []

        for chapter in project.chapterDrafts {
            let haystack = "\(chapter.chapterSummary)\n\(chapter.content)"
            let score = Self.searchScore(in: haystack, tokens: tokens)
            guard score > 0 else { continue }

            results.append(
                LongformSearchResult(
                    id: "chapter-\(chapter.id)",
                    kind: .chapter,
                    title: chapter.chapterSummary,
                    subtitle: "\(chapter.wordCount) 字 · \(chapter.savedAt)",
                    excerpt: Self.searchExcerpt(from: haystack, tokens: tokens, limit: 180),
                    score: score + 8,
                    chapterID: chapter.id,
                    referenceDocumentID: nil
                )
            )
        }

        for document in project.referenceDocuments {
            let haystack = "\(document.title)\n\(document.content)"
            let score = Self.searchScore(in: haystack, tokens: tokens)
            guard score > 0 else { continue }

            results.append(
                LongformSearchResult(
                    id: "reference-\(document.id)",
                    kind: .reference,
                    title: document.title,
                    subtitle: "\(document.category.title) · \(document.wordCount) 字",
                    excerpt: Self.searchExcerpt(from: haystack, tokens: tokens, limit: 180),
                    score: score + 5,
                    chapterID: nil,
                    referenceDocumentID: document.id
                )
            )
        }

        let outlineSources: [(LongformSearchResultKind, String, String, String)] = [
            (.outline, "作品大纲", "大纲设定", project.outlineText),
            (.outline, "章节树总结", project.outlineSummaryStatusLabel, project.outlineSummary),
            (.outline, "章节骨架拆解", project.structureStatusLabel, project.structureNotes),
            (.outline, "场景推进记录", project.sceneProgressStatusLabel, project.sceneProgressNotes),
            (.outline, "角色弧线记录", project.characterArcStatusLabel, project.characterArcNotes),
            (.outline, "伏笔与回收记录", project.foreshadowStatusLabel, project.foreshadowNotes),
            (.outline, "分卷/阶段规划", project.volumePlanStatusLabel, project.volumePlanNotes),
            (.outline, "在途线索", project.activeThreadsStatusLabel, project.activeThreadsNotes),
            (.memory, "全局记忆", project.globalMemoryStatusLabel, project.continuityNotes)
        ]

        for (kind, title, subtitle, text) in outlineSources {
            let score = Self.searchScore(in: text, tokens: tokens)
            guard score > 0 else { continue }
            results.append(
                LongformSearchResult(
                    id: "\(kind.rawValue)-\(title)",
                    kind: kind,
                    title: title,
                    subtitle: subtitle,
                    excerpt: Self.searchExcerpt(from: text, tokens: tokens, limit: 180),
                    score: score + 3,
                    chapterID: nil,
                    referenceDocumentID: nil
                )
            )
        }

        return results
            .sorted {
                if $0.score == $1.score {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map { $0 }
    }

    func project(for projectID: NovelProject.ID) -> NovelProject? {
        recentProjects.first(where: { $0.id == projectID })
    }

    func navigationDestination(for pillar: StoryPillar) -> SidebarItem {
        switch pillar.title {
        case "章节树":
            return .outline
        default:
            return .projects
        }
    }

    private var hasValidBaseURL: Bool {
        guard let components = URLComponents(string: normalizedBaseURLString ?? baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        let scheme = components.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && components.host != nil
    }

    private var hasEnteredConnectionInfo: Bool {
        switch selectedProvider {
        case .openAICompatible:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .custom:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func normalizeProjectSelection() {
        let fallbackProjectID = recentProjects.first?.id

        if let activeProjectID, recentProjects.contains(where: { $0.id == activeProjectID }) {
            selectedProjectID = activeProjectID
        } else {
            activeProjectID = fallbackProjectID
            selectedProjectID = fallbackProjectID
        }
    }

    func refreshIdleValidationMessage() {
        validationTask?.cancel()
        connectionStatus = .idle
        switch selectedProvider {
        case .openAICompatible:
            validationMessage = hasEnteredConnectionInfo
                ? "OpenW 配置已保存，可点击“测试连接”以重新检查。"
                : "OpenW 使用内置模型连接配置；当前安装未检测到本机授权凭据时不可用。"
        case .custom:
            validationMessage = hasEnteredConnectionInfo
                ? "配置已保存，可点击“测试连接”以重新检查。"
                : Self.emptyConfigurationMessage
        }
    }

    private func markConfigurationAsEdited() {
        refreshIdleValidationMessage()
    }

    private var normalizedBaseURLString: String? {
        Self.normalizedBaseURLString(from: baseURL)
    }

    private var resolvedAIConfiguration: AIConnectionConfiguration? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard hasValidBaseURL else {
            connectionStatus = .needsAttention
            validationMessage = "Base URL 需要是完整的 http 或 https 地址。"
            return nil
        }

        guard !trimmedKey.isEmpty else {
            connectionStatus = .needsAttention
            validationMessage = selectedProvider == .openAICompatible
                ? "OpenW 模型连接暂不可用：当前安装未检测到本机授权凭据。"
                : "API Key 不能为空。"
            return nil
        }

        guard !trimmedModelName.isEmpty else {
            connectionStatus = .needsAttention
            validationMessage = "模型 ID 不能为空。"
            return nil
        }

        guard
            let normalizedBaseURLString,
            let resolvedBaseURL = URL(string: normalizedBaseURLString)
        else {
            connectionStatus = .needsAttention
            validationMessage = "Base URL 需要是完整的 http 或 https 地址。"
            return nil
        }

        if normalizedBaseURLString != baseURL.trimmingCharacters(in: .whitespacesAndNewlines) {
            isApplyingProviderConfiguration = true
            baseURL = normalizedBaseURLString
            isApplyingProviderConfiguration = false
            persistBaseURL()
        }

        return AIConnectionConfiguration(
            baseURL: resolvedBaseURL,
            apiKey: trimmedKey,
            modelName: trimmedModelName
        )
    }

    private func updateProject(_ projectID: NovelProject.ID, mutate: (inout NovelProject) -> Void) {
        guard let index = recentProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var updatedProject = recentProjects[index]
        mutate(&updatedProject)
        recentProjects[index] = updatedProject
    }

    private static func currentTimestampLabel() -> String {
        PersistedTimestampCodec.displayLabel(for: Date(), style: .project)
    }

    private static func normalizedChapterTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名章节" : trimmed
    }

    private static func searchTokens(from query: String) -> [String] {
        var seen = Set<String>()
        return query
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard token.count >= 2 else { return false }
                let normalized = token.lowercased()
                guard !seen.contains(normalized) else { return false }
                seen.insert(normalized)
                return true
            }
            .prefix(12)
            .map { String($0) }
    }

    private static func searchScore(in text: String, tokens: [String]) -> Int {
        guard !text.isEmpty else { return 0 }
        let lowercasedText = text.lowercased()
        return tokens.reduce(0) { score, token in
            let lowercasedToken = token.lowercased()
            var tokenScore = 0
            var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex
            while let range = lowercasedText.range(of: lowercasedToken, options: [], range: searchRange) {
                tokenScore += max(1, lowercasedToken.count)
                searchRange = range.upperBound..<lowercasedText.endIndex
            }
            return score + tokenScore
        }
    }

    private static func searchExcerpt(from text: String, tokens: [String], limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }

        let lowercasedText = trimmed.lowercased()
        let firstRange = tokens
            .compactMap { lowercasedText.range(of: $0.lowercased()) }
            .min { lhs, rhs in
                lhs.lowerBound < rhs.lowerBound
            }

        guard let firstRange else {
            return String(trimmed.prefix(limit)) + "..."
        }

        let lowerDistance = lowercasedText.distance(from: lowercasedText.startIndex, to: firstRange.lowerBound)
        let startOffset = max(0, lowerDistance - limit / 3)
        let endOffset = min(trimmed.count, startOffset + limit)
        let start = trimmed.index(trimmed.startIndex, offsetBy: startOffset)
        let end = trimmed.index(trimmed.startIndex, offsetBy: endOffset)
        let prefix = startOffset == 0 ? "" : "..."
        let suffix = endOffset == trimmed.count ? "" : "..."
        return prefix + String(trimmed[start..<end]) + suffix
    }

    private static func defaultNextChapterFocus(after chapterDraft: ChapterDraft, storyLength: NovelLength) -> String {
        let trimmedEnding = chapterDraft.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ending = trimmedEnding.count > 180
            ? String(trimmedEnding.suffix(180))
            : trimmedEnding

        let baseFocus: String
        switch storyLength {
        case .short:
            baseFocus = "承接上一段的结果，继续压缩场景数量，推动核心冲突向结尾闭环靠拢。"
        case .medium:
            baseFocus = "承接上一章的后果，推进主线目标、关系变化或阶段反转，避免支线发散。"
        case .long:
            baseFocus = "承接上一章留下的行动后果、人物状态和在途线索，推进当前卷目标，并保留长期伏笔的延展空间。"
        }

        guard !ending.isEmpty else { return baseFocus }
        return "\(baseFocus)\n\n上一章结尾参考：\(ending)"
    }

    private static func abbreviatedCount(_ value: Int) -> String {
        switch value {
        case 10_000...:
            let normalized = Double(value) / 10_000
            return String(format: normalized >= 10 ? "%.0fw" : "%.1fw", normalized)
        case 1_000...:
            let normalized = Double(value) / 1_000
            return String(format: normalized >= 10 ? "%.0fk" : "%.1fk", normalized)
        default:
            return "\(value)"
        }
    }

    private func makeProjectIdentifier(from title: String) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let base = slug.isEmpty ? "project" : slug
        var candidate = base
        var suffix = 2

        while recentProjects.contains(where: { $0.id == candidate }) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        return candidate
    }

    static let defaultRecentProjects: [NovelProject] = []
}
