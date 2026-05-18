import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let emptyConfigurationMessage = "自定义模型需填写 Base URL、模型 ID 与 API Key 后再测试连接。"
    private static let maxChapterVersionHistoryCount = 12

    let userDefaults: UserDefaults
    let projectStore: ProjectFileStore
    @ObservationIgnored let cloudStore = ICloudProjectStore()
    @ObservationIgnored var cloudSaveTask: Task<Void, Never>?
    @ObservationIgnored var recentProjectsPersistTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var isHydratingAccountScopedData = false
    @ObservationIgnored var isApplyingProviderConfiguration = false
    @ObservationIgnored var validationTask: Task<Void, Never>?
    @ObservationIgnored private var cachedManagers: AppStateManagers?

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

    /// 便捷访问所有专业化管理器
    var managers: AppStateManagers {
        if let cached = cachedManagers {
            return cached
        }
        let managers = AppStateManagers(appState: self)
        cachedManagers = managers
        return managers
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

        // MAJOR #4: Clean up orphaned UserDefaults keys for this project
        let keysToRemove = [
            "memoryBuckets_\(projectID)",
            "strandWeave_\(projectID)",
            "lastReview_\(projectID)",
            "antiPatterns_\(projectID)",
        ]
        for key in keysToRemove {
            userDefaults.removeObject(forKey: key)
        }

        // Clear in-memory cache for this project
        NovelProject.clearIntegrationCache(for: projectID)

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

    func updateCurrentVolumeNumber(_ number: Int, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.currentVolumeNumber = max(number, 1)
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

    func updateGenreTemplate(_ templateID: GenreTemplate.ID, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.genreTemplateId = templateID
            if let template = GenreTemplateLibrary.allTemplates.first(where: { $0.id == templateID }) {
                let config = template.strandConfig
                var strandState = project.strandWeaveState
                strandState.questTarget = config.questTarget
                strandState.fireTarget = config.fireTarget
                strandState.constellationTarget = config.constellationTarget
                strandState.questMaxConsecutive = config.questMaxConsecutive
                strandState.fireMaxGap = config.fireMaxGap
                strandState.constellationMaxGap = config.constellationMaxGap
                project.strandWeaveState = strandState
            }
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func applyEnhancedWritingUpdate(
        _ context: MemoryUpdateContext?,
        review: ChapterReviewResult?,
        for projectID: NovelProject.ID
    ) {
        updateProject(projectID) { project in
            if let context {
                project.strandWeaveState = context.strandState
                let mergedAntiPatterns = Set(project.accumulatedAntiPatterns).union(context.antiPatterns)
                project.accumulatedAntiPatterns = Array(mergedAntiPatterns.prefix(50))
            }

            if let review {
                project.lastReviewResult = review
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

    @discardableResult
    func ensureChapterDraftLoaded(_ chapterDraftID: ChapterDraft.ID, for projectID: NovelProject.ID) -> ChapterDraft? {
        if let project = project(for: projectID),
           let loadedDraft = project.chapterDrafts.first(where: { $0.id == chapterDraftID }) {
            return loadedDraft
        }

        guard let loadedDraft = projectStore.loadChapterDraft(
            chapterDraftID,
            for: projectID,
            scope: currentStorageScope
        ) else { return nil }

        updateProject(projectID) { project in
            if !project.chapterDrafts.contains(where: { $0.id == loadedDraft.id }) {
                project.chapterDrafts.append(loadedDraft)
            }
            Self.upsertChapterMetadata(ChapterDraftMetadata(chapterDraft: loadedDraft), in: &project)
        }

        return loadedDraft
    }

    @discardableResult
    func ensureAllChapterDraftsLoaded(for projectID: NovelProject.ID) -> [ChapterDraft] {
        guard let project = project(for: projectID) else { return [] }
        let missingIDs = project.chapterCatalog
            .map(\.id)
            .filter { chapterID in
                !project.chapterDrafts.contains(where: { $0.id == chapterID })
            }

        let loadedDrafts = missingIDs.compactMap {
            projectStore.loadChapterDraft($0, for: projectID, scope: currentStorageScope)
        }

        if !loadedDrafts.isEmpty {
            updateProject(projectID) { project in
                for loadedDraft in loadedDrafts where !project.chapterDrafts.contains(where: { $0.id == loadedDraft.id }) {
                    project.chapterDrafts.append(loadedDraft)
                    Self.upsertChapterMetadata(ChapterDraftMetadata(chapterDraft: loadedDraft), in: &project)
                }
                project.chapterDrafts.sort(by: ChapterDraft.sortDescending)
            }
        }

        return self.project(for: projectID)?.chapterDrafts.sorted(by: ChapterDraft.sortDescending)
            ?? project.chapterDrafts.sorted(by: ChapterDraft.sortDescending)
    }

    func hydratedProjectForFullText(_ projectID: NovelProject.ID) -> NovelProject? {
        let loadedChapters = ensureAllChapterDraftsLoaded(for: projectID)
        guard var project = project(for: projectID) else { return nil }
        project.chapterDrafts = loadedChapters
        return project
    }

    func hydratedProjectsForPersistenceSnapshot(_ projects: [NovelProject]) -> [NovelProject] {
        projects.map { project in
            var hydratedProject = project
            let storedDrafts = projectStore.loadChapterDrafts(
                for: project.id,
                scope: currentStorageScope
            )

            var draftByID = Dictionary(uniqueKeysWithValues: storedDrafts.map { ($0.id, $0) })
            for chapterDraft in project.chapterDrafts {
                draftByID[chapterDraft.id] = chapterDraft
            }

            if !project.chapterCatalog.isEmpty {
                let retainedChapterIDs = Set(project.chapterCatalog.map(\.id))
                    .union(project.chapterDrafts.map(\.id))
                draftByID = draftByID.filter { retainedChapterIDs.contains($0.key) }
            }

            hydratedProject.chapterDrafts = draftByID.values.sorted(by: ChapterDraft.sortDescending)
            if !hydratedProject.chapterDrafts.isEmpty {
                hydratedProject.chapterCatalog = hydratedProject.chapterDrafts
                    .map(ChapterDraftMetadata.init)
                    .sorted(by: ChapterDraftMetadata.sortDescending)
            }
            return hydratedProject
        }
    }

    func saveCurrentChapterDraft(for projectID: NovelProject.ID) -> ChapterDraftSaveResult? {
        var result: ChapterDraftSaveResult?

        if let project = project(for: projectID),
           let existingMetadata = project.chapterCatalog.first(where: {
               $0.volumeNumber == max(project.currentVolumeNumber, 1)
                   && $0.chapterNumber == max(project.currentChapterNumber, 1)
           }) {
            ensureChapterDraftLoaded(existingMetadata.id, for: projectID)
        }

        updateProject(projectID) { project in
            let trimmedDraft = project.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDraft.isEmpty else { return }

            let normalizedVolumeNumber = max(project.currentVolumeNumber, 1)
            let normalizedChapterNumber = max(project.currentChapterNumber, 1)
            let normalizedChapterTitle = Self.normalizedChapterTitle(project.currentChapterTitle)
            let timestamp = Self.currentTimestampLabel()

            if let existingIndex = project.chapterDrafts.firstIndex(where: {
                $0.volumeNumber == normalizedVolumeNumber && $0.chapterNumber == normalizedChapterNumber
            }) {
                let hasMeaningfulChange = project.chapterDrafts[existingIndex].chapterTitle != normalizedChapterTitle
                    || project.chapterDrafts[existingIndex].content != trimmedDraft
                let previousSnapshot = hasMeaningfulChange
                    ? project.chapterDrafts[existingIndex].versionSnapshot(reason: "保存前自动版本", savedAt: timestamp)
                    : nil
                project.chapterDrafts[existingIndex].volumeNumber = normalizedVolumeNumber
                project.chapterDrafts[existingIndex].chapterTitle = normalizedChapterTitle
                project.chapterDrafts[existingIndex].content = trimmedDraft
                project.chapterDrafts[existingIndex].savedAt = timestamp
                if let previousSnapshot {
                    project.chapterDrafts[existingIndex].versionHistory.insert(previousSnapshot, at: 0)
                    Self.trimChapterVersionHistory(&project.chapterDrafts[existingIndex])
                }
                let updatedChapterDraft = project.chapterDrafts[existingIndex]
                Self.upsertChapterMetadata(ChapterDraftMetadata(chapterDraft: updatedChapterDraft), in: &project)
                project.chapterDrafts.sort(by: ChapterDraft.sortDescending)
                result = .updated(updatedChapterDraft)
            } else {
                let chapterDraft = ChapterDraft(
                    volumeNumber: normalizedVolumeNumber,
                    chapterNumber: normalizedChapterNumber,
                    chapterTitle: normalizedChapterTitle,
                    content: trimmedDraft,
                    savedAt: timestamp
                )
                project.chapterDrafts.append(chapterDraft)
                Self.upsertChapterMetadata(ChapterDraftMetadata(chapterDraft: chapterDraft), in: &project)
                project.chapterDrafts.sort(by: ChapterDraft.sortDescending)
                result = .created(chapterDraft)
            }

            project.currentVolumeNumber = normalizedVolumeNumber
            project.currentChapterNumber = normalizedChapterNumber
            project.currentChapterTitle = normalizedChapterTitle
            project.writtenChapters = max(project.writtenChapters, project.chapterDrafts.count, normalizedChapterNumber)
            project.updatedAt = timestamp
        }

        return result
    }

    func loadChapterDraft(_ chapterDraftID: ChapterDraft.ID, for projectID: NovelProject.ID) {
        guard let loadedDraft = ensureChapterDraftLoaded(chapterDraftID, for: projectID) else { return }

        updateProject(projectID) { project in
            let chapterDraft = loadedDraft
            project.currentVolumeNumber = max(chapterDraft.volumeNumber, 1)
            project.currentChapterNumber = max(chapterDraft.chapterNumber, 1)
            project.currentChapterTitle = chapterDraft.chapterTitle
            project.draftText = chapterDraft.content
            project.writtenChapters = max(project.writtenChapters, project.chapterDrafts.count, chapterDraft.chapterNumber)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func beginNextChapter(after chapterDraft: ChapterDraft, for projectID: NovelProject.ID) {
        if let project = project(for: projectID),
           let existingMetadata = project.chapterCatalog.first(where: {
               $0.volumeNumber == max(chapterDraft.volumeNumber, 1)
                   && $0.chapterNumber == max(chapterDraft.chapterNumber + 1, 1)
           }) {
            ensureChapterDraftLoaded(existingMetadata.id, for: projectID)
        }

        updateProject(projectID) { project in
            let nextChapterNumber = max(chapterDraft.chapterNumber + 1, 1)
            let nextVolumeNumber = max(chapterDraft.volumeNumber, 1)

            if let existingDraft = project.chapterDrafts.first(where: {
                $0.volumeNumber == nextVolumeNumber && $0.chapterNumber == nextChapterNumber
            }) {
                project.currentVolumeNumber = max(existingDraft.volumeNumber, 1)
                project.currentChapterNumber = nextChapterNumber
                project.currentChapterTitle = existingDraft.chapterTitle
                project.draftText = existingDraft.content
            } else {
                project.currentVolumeNumber = nextVolumeNumber
                project.currentChapterNumber = nextChapterNumber
                project.currentChapterTitle = "待命名章节"
                project.chapterFocus = Self.defaultNextChapterFocus(
                    after: chapterDraft,
                    storyLength: project.storyLength
                )
                project.draftText = ""
            }

            project.writtenChapters = max(project.writtenChapters, project.chapterDrafts.count, chapterDraft.chapterNumber)
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
        ensureChapterDraftLoaded(chapterDraftID, for: projectID)

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
                Self.trimChapterVersionHistory(&project.chapterDrafts[existingIndex])
            }

            let chapterNumber = project.chapterDrafts[existingIndex].chapterNumber
            let volumeNumber = project.chapterDrafts[existingIndex].volumeNumber
            let updated = project.chapterDrafts[existingIndex]
            Self.upsertChapterMetadata(ChapterDraftMetadata(chapterDraft: updated), in: &project)
            project.chapterDrafts.sort(by: ChapterDraft.sortDescending)

            if project.currentVolumeNumber == volumeNumber,
               project.currentChapterNumber == chapterNumber {
                project.currentChapterTitle = normalizedTitle
                project.draftText = trimmedContent
            }

            project.writtenChapters = max(project.writtenChapters, project.chapterDrafts.count, chapterNumber)
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
        ensureChapterDraftLoaded(chapterDraftID, for: projectID)

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
            Self.trimChapterVersionHistory(&project.chapterDrafts[existingIndex])

            let restored = project.chapterDrafts[existingIndex]
            Self.upsertChapterMetadata(ChapterDraftMetadata(chapterDraft: restored), in: &project)
            project.chapterDrafts.sort(by: ChapterDraft.sortDescending)

            if project.currentVolumeNumber == restored.volumeNumber,
               project.currentChapterNumber == restored.chapterNumber {
                project.currentChapterTitle = restored.chapterTitle
                project.draftText = restored.content
            }

            project.writtenChapters = max(project.writtenChapters, project.chapterDrafts.count, restored.chapterNumber)
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

    // MARK: - Memory Buckets Auto-Population

    /// Extract structured memory items from a chapter draft and upsert them
    /// into the project's MemoryBuckets. Runs keyword-based extraction
    /// for characters, relationships, locations, foreshadowing, and timeline.
    func extractAndStoreMemoryItems(
        from chapterContent: String,
        chapterNumber: Int,
        for projectID: NovelProject.ID
    ) {
        let (characters, relationships, locations, foreshadowing, timeline, storyFacts) =
            extractStructuredMemory(from: chapterContent, chapterNumber: chapterNumber)

        let allItems = characters + relationships + locations + foreshadowing + timeline + storyFacts
        guard !allItems.isEmpty else { return }

        updateProject(projectID) { project in
            var buckets = project.memoryBuckets
            for item in allItems {
                buckets.upsert(item)
            }
            buckets.compact(currentChapter: chapterNumber)
            project.memoryBuckets = buckets
        }
    }

    /// Append locally-detected AI-flavor anti-patterns from a chapter draft.
    /// These accumulate across chapters and are injected into writing prompts.
    func appendLocalAntiPatterns(
        from chapterContent: String,
        for projectID: NovelProject.ID
    ) {
        let localPatterns = ChapterQualityReviewer.quickAIFlavorCheck(text: chapterContent)
        guard !localPatterns.isEmpty else { return }

        updateProject(projectID) { project in
            project.appendAntiPatterns(from: localPatterns)
        }
    }

    /// Keyword-based extraction of structured memory items from Chinese chapter text.
    private func extractStructuredMemory(
        from text: String,
        chapterNumber: Int
    ) -> (
        characters: [MemoryItem],
        relationships: [MemoryItem],
        locations: [MemoryItem],
        foreshadowing: [MemoryItem],
        timeline: [MemoryItem],
        storyFacts: [MemoryItem]
    ) {
        let nonNameWords: Set<String> = [
            // Pronouns & demonstratives
            "什么", "怎么", "那个", "这个", "他们", "我们", "你们", "自己",
            "别人", "大家", "哪个", "哪些", "任何", "某个", "某些", "每个",
            "谁", "哪", "哪位", "哪边", "哪儿", "哪里",
            // Common verbs
            "知道", "没有", "觉得", "需要", "希望", "认为", "相信", "明白",
            "看见", "听到", "感到", "想起", "发现", "决定", "开始", "结束",
            "离开", "回来", "过来", "出去", "起来", "下来", "上去", "出来",
            "告诉", "说道", "回答", "笑道", "说话", "问道", "叹道", "怒道",
            "冷声道", "轻声道", "淡淡道", "大声道", "低声道", "急道", "惊道",
            "道", "说", "答", "叫", "喊", "笑", "哭", "叹", "问", "怒",
            "想", "看", "听", "走", "来", "去", "到", "回", "出", "入",
            "站", "坐", "躺", "拿", "放", "拉", "推", "打", "挡",
            // Adverbs & conjunctions
            "已经", "不是", "可能", "可以", "应该", "还是", "就是", "只是",
            "不过", "因为", "所以", "但是", "如果", "虽然", "或者", "然后",
            "忽然", "突然", "居然", "竟然", "果然", "依然", "仍然", "当然",
            "自然", "显然", "似乎", "仿佛", "好像", "大概", "也许", "或许",
            "几乎", "简直", "根本", "实在", "确实", "真正", "完全", "非常",
            "特别", "尤其", "甚至", "至少", "至多", "反正", "总之", "否则",
            "于是", "接着", "随后", "随即", "马上", "立刻", "立即", "赶紧",
            "连忙", "急忙", "急忙", "渐渐", "慢慢", "悄悄", "偷偷", "默默",
            // Time & location words
            "现在", "刚才", "此时", "这时", "那时", "这里", "那里", "到处",
            "时候", "一下", "一点", "一些", "许多", "很多", "所有", "全部",
            "刚才", "方才", "之前", "之后", "以后", "以前", "将来", "未来",
            "昨天", "今天", "明天", "前天", "后天",
            // Measure words & particles
            "一个", "两个", "几个", "那些", "这些", "每个", "各种", "各位",
            "本人", "自身", "对方", "彼此", "互相", "一起", "一同", "单独",
            // Sentence-final particles & fillers
            "的话", "罢了", "而已", "算了", "好吧", "对了", "行了", "够了"
        ]

        // --- Characters from dialogue (supports both "" and "" quotes) ---
        var characterFrequency: [String: Int] = [:]
        if let regex = try? NSRegularExpression(pattern: "[\u{201C}\u{0022}]([^\u{201C}\u{201D}\u{0022}\n]{1,20})[\u{201D}\u{0022}]") {
            let nsText = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                if match.numberOfRanges >= 2 {
                    let contextStart = max(0, match.range.location - 10)
                    let contextLength = min(match.range.location - contextStart, 20)
                    let context = nsText.substring(with: NSRange(location: contextStart, length: contextLength))
                    let candidates = extractNamesFromContext(context, excluding: nonNameWords)
                    for name in candidates {
                        characterFrequency[name, default: 0] += 1
                    }
                }
            }
        }

        // --- Characters from action patterns ---
        let actionPatterns = ["道：", "笑道", "怒道", "冷声道", "道，", "说道："]
        for pattern in actionPatterns {
            var searchStart = text.startIndex
            while let range = text.range(of: pattern, range: searchStart..<text.endIndex) {
                let contextStart = text.index(range.lowerBound, offsetBy: -min(10, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
                let context = String(text[contextStart..<range.lowerBound])
                let candidates = extractNamesFromContext(context, excluding: nonNameWords)
                for name in candidates {
                    characterFrequency[name, default: 0] += 2
                }
                searchStart = range.upperBound
            }
        }

        let characterNames = characterFrequency
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { $0.key }

        let characterItems = characterNames.map { name in
            MemoryItem(
                category: .characterState,
                subject: name,
                field: "出场",
                value: "在第\(chapterNumber)章中出场并有对白或行动",
                sourceChapter: chapterNumber
            )
        }

        // --- Relationships from co-occurrence in dialogue/action ---
        var relationshipPairs: [String: Int] = [:]
        let allNames = Set(characterNames)
        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for paragraph in paragraphs {
            let present = allNames.filter { paragraph.contains($0) }
            if present.count >= 2 {
                let sorted = present.sorted()
                for i in 0..<sorted.count {
                    for j in (i+1)..<sorted.count {
                        let key = "\(sorted[i])↔\(sorted[j])"
                        relationshipPairs[key, default: 0] += 1
                    }
                }
            }
        }

        let relationshipItems = relationshipPairs
            .filter { $0.value >= 1 }
            .prefix(10)
            .map { (pair, count) -> MemoryItem in
                return MemoryItem(
                    category: .relationship,
                    subject: pair,
                    field: count >= 3 ? "密切互动" : "互动",
                    value: "第\(chapterNumber)章中共同出现\(count)次",
                    sourceChapter: chapterNumber
                )
            }

        // --- Locations ---
        var locationFrequency: [String: Int] = [:]
        let locationMarkers = [
            "在(.{2,8}?)[，。,.]", "来到(.{2,8}?)[，。,.]",
            "到达(.{2,8}?)[，。,.]", "离开(.{2,8}?)[，。,.]",
            "进入(.{2,8}?)[，。,.]", "走出(.{2,8}?)[，。,.]"
        ]
        let nonLocationWords: Set<String> = [
            "这里", "那里", "此时", "这时", "什么", "自己", "对方", "面前",
            "身后", "旁边", "外面", "里面", "上面", "下面", "前面", "后面",
            "之间", "其中", "之后", "之前", "以后", "以前"
        ]

        for pattern in locationMarkers {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsText = text as NSString
                for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                    if match.numberOfRanges >= 2 {
                        let location = nsText.substring(with: match.range(at: 1))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if location.count >= 2 && location.count <= 8 && !nonLocationWords.contains(location) {
                            locationFrequency[location, default: 0] += 1
                        }
                    }
                }
            }
        }

        let locationItems = locationFrequency
            .filter { $0.value >= 1 }
            .prefix(8)
            .map { (location, _) -> MemoryItem in
                MemoryItem(
                    category: .worldRule,
                    subject: location,
                    field: "地点",
                    value: "在第\(chapterNumber)章中出现",
                    sourceChapter: chapterNumber
                )
            }

        // --- Foreshadowing / Open Loops ---
        var foreshadowItems: [MemoryItem] = []
        let mysteryPatterns = [
            ("暗示线索", ["暗示", "似乎", "仿佛", "好像"]),
            ("悬疑伏笔", ["疑团", "谜团", "悬念", "蹊跷", "奇怪"]),
            ("未解之谜", ["不知", "不解", "未明", "不明", "无法解释"]),
            ("隐藏信息", ["秘密", "隐瞒", "隐藏", "藏着", "背后的真相"]),
            ("预兆", ["预感", "预兆", "不祥", "隐隐"])
        ]

        for (field, markers) in mysteryPatterns {
            for marker in markers {
                var searchStart = text.startIndex
                while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
                    let ctxStart = text.index(range.lowerBound, offsetBy: -min(8, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
                    let ctxEnd = text.index(range.upperBound, offsetBy: min(20, text.distance(from: range.upperBound, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
                    let context = String(text[ctxStart..<ctxEnd])
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if context.count >= 4 {
                        foreshadowItems.append(MemoryItem(
                            category: .openLoop,
                            subject: String(context.prefix(30)),
                            field: field,
                            value: context,
                            status: .tentative,
                            sourceChapter: chapterNumber
                        ))
                    }
                    searchStart = range.upperBound
                }
            }
        }

        // --- Timeline ---
        var timelineItems: [MemoryItem] = []
        let timeMarkers = [
            "黎明", "清晨", "早上", "上午", "中午", "下午",
            "傍晚", "黄昏", "晚上", "深夜", "午夜", "凌晨",
            "日出", "日落", "天亮", "天黑",
            "三天后", "第二天", "次日", "当日", "当晚",
            "一周后", "一个月后", "一年后", "数日后", "数月后",
            "数年后", "半月后", "两周后", "数年后", "多年后",
            "片刻后", "半晌", "一炷香", "一盏茶",
            "过了许久", "过了很久", "不知过了多久",
            "日复一日", "年复一年", "转眼间", "不知不觉",
            "那一年", "这一年", "那日", "这日", "翌日"
        ]

        for marker in timeMarkers {
            if text.contains(marker) {
                timelineItems.append(MemoryItem(
                    category: .timeline,
                    subject: marker,
                    field: "时间标记",
                    value: "第\(chapterNumber)章提及「\(marker)」",
                    sourceChapter: chapterNumber
                ))
            }
        }

        // --- Story Facts from plot-significant patterns ---
        var storyFactItems: [MemoryItem] = []
        let factPatterns = [
            ("关键转折", ["决定", "选择", "放弃", "离开", "归来", "背叛"]),
            ("能力揭示", ["觉醒", "突破", "领悟", "解锁", "获得"]),
            ("重要信息", ["真相", "发现", "揭露", "得知", "原来"])
        ]

        for (field, markers) in factPatterns {
            for marker in markers {
                var count = 0
                var searchStart = text.startIndex
                while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
                    count += 1
                    searchStart = range.upperBound
                }
                if count >= 2 {
                    storyFactItems.append(MemoryItem(
                        category: .storyFact,
                        subject: marker,
                        field: field,
                        value: "第\(chapterNumber)章中出现\(count)次",
                        sourceChapter: chapterNumber
                    ))
                }
            }
        }

        return (
            characters: Array(characterItems.prefix(10)),
            relationships: Array(relationshipItems.prefix(8)),
            locations: Array(locationItems.prefix(6)),
            foreshadowing: Array(foreshadowItems.prefix(8)),
            timeline: Array(timelineItems.prefix(6)),
            storyFacts: Array(storyFactItems.prefix(8))
        )
    }

    /// Extract likely character names from a short context string.
    private func extractNamesFromContext(_ context: String, excluding nonNames: Set<String>) -> [String] {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: "，。、；：！？… \t\n\"'")
        let tokens = trimmed.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && $0.count <= 6 }

        var names: [String] = []
        for token in tokens {
            guard !nonNames.contains(token) else { continue }
            let isCapitalized = token.unicodeScalars.first.map { CharacterSet.uppercaseLetters.contains($0) } ?? false
            let allChinese = token.unicodeScalars.allSatisfy { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            if isCapitalized || (allChinese && token.count >= 2 && token.count <= 4) {
                names.append(token)
            }
        }
        return names
    }

    func searchLongformProject(_ query: String, in projectID: NovelProject.ID, limit: Int = 60) -> [LongformSearchResult] {
        guard let project = hydratedProjectForFullText(projectID) else { return [] }
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

    private static func trimChapterVersionHistory(_ chapterDraft: inout ChapterDraft) {
        guard chapterDraft.versionHistory.count > maxChapterVersionHistoryCount else { return }
        chapterDraft.versionHistory = Array(chapterDraft.versionHistory.prefix(maxChapterVersionHistoryCount))
    }

    private static func upsertChapterMetadata(_ metadata: ChapterDraftMetadata, in project: inout NovelProject) {
        if let existingIndex = project.chapterCatalog.firstIndex(where: { $0.id == metadata.id }) {
            project.chapterCatalog[existingIndex] = metadata
        } else {
            project.chapterCatalog.append(metadata)
        }
        project.chapterCatalog.sort(by: ChapterDraftMetadata.sortDescending)
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
