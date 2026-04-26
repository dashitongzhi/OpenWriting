import AuthenticationServices
import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppState {
    enum StorageKey {
        static let selectedProvider = "OpenWriting.selectedProvider"
        static let modelName = "OpenWriting.modelName"
        static let apiKey = "OpenWriting.apiKey"
        static let baseURL = "OpenWriting.baseURL"
        static let customModelName = "OpenWriting.custom.modelName"
        static let customBaseURL = "OpenWriting.custom.baseURL"
        static let autoValidateOnLaunch = "OpenWriting.autoValidateOnLaunch"
        static let showWritingDeskCachePanel = "OpenWriting.showWritingDeskCachePanel"
        static let showWritingDeskTimeline = "OpenWriting.showWritingDeskTimeline"
        static let legacyActiveAccountEmail = "OpenWriting.activeAccountEmail"
        static let activeAppleUserID = "OpenWriting.activeAppleUserID"
        static let activeAppleUserEmail = "OpenWriting.activeAppleUserEmail"
        static let activeAppleUserName = "OpenWriting.activeAppleUserName"
        static let activeProjectID = "OpenWriting.activeProjectID"
        static let recentProjects = "OpenWriting.recentProjects"
        static let projectSnapshotTimestamp = "OpenWriting.projectSnapshotTimestamp"
        static let didMigrateLegacyDefaults = "OpenWriting.didMigrateLegacyDefaults"
        static let didMigrateLegacyEmailScope = "OpenWriting.didMigrateLegacyEmailScope"
    }

    enum LegacyStorageKey {
        private static let prefix = "Open" + "Reading"

        static let selectedProvider = "\(prefix).selectedProvider"
        static let modelName = "\(prefix).modelName"
        static let baseURL = "\(prefix).baseURL"
        static let apiKey = "\(prefix).apiKey"
        static let autoValidateOnLaunch = "\(prefix).autoValidateOnLaunch"
        static let showWritingDeskCachePanel = "\(prefix).showWritingDeskCachePanel"
        static let showWritingDeskTimeline = "\(prefix).showWritingDeskTimeline"
        static let activeProjectID = "\(prefix).activeProjectID"
        static let recentProjects = "\(prefix).recentProjects"
    }

    enum KeychainKey {
        static let service = "CHZ.Kral.OpenWriting.ModelConnection"
        static let openWAccount = "apiKey.openw"
        static let customAccount = "apiKey.custom"
    }

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
        recentProjects.reduce(0) { $0 + $1.draftWordCount }
    }

    var totalReferenceDocumentCount: Int {
        recentProjects.reduce(0) { $0 + $1.referenceDocuments.count }
    }

    var totalWrittenChapters: Int {
        recentProjects.reduce(0) { $0 + $1.writtenChapters }
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
                project.chapterDrafts[existingIndex].chapterTitle = normalizedChapterTitle
                project.chapterDrafts[existingIndex].content = trimmedDraft
                project.chapterDrafts[existingIndex].savedAt = timestamp
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

            project.chapterDrafts[existingIndex].chapterTitle = normalizedTitle
            project.chapterDrafts[existingIndex].content = trimmedContent
            project.chapterDrafts[existingIndex].savedAt = timestamp

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

    private func refreshIdleValidationMessage() {
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

    private func persistSelectedProvider() {
        userDefaults.set(selectedProvider.rawValue, forKey: StorageKey.selectedProvider)
    }

    private func persistModelName() {
        userDefaults.set(modelName, forKey: Self.modelNameStorageKey(for: selectedProvider))
    }

    private func persistBaseURL() {
        userDefaults.set(baseURL, forKey: Self.baseURLStorageKey(for: selectedProvider))
    }

    private func persistConnectionSettings(for provider: ModelProvider) {
        userDefaults.set(modelName, forKey: Self.modelNameStorageKey(for: provider))
        userDefaults.set(baseURL, forKey: Self.baseURLStorageKey(for: provider))

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            Self.deleteAPIKeyFromKeychain(for: provider)
        } else {
            Self.saveAPIKeyToKeychain(trimmedKey, for: provider)
        }
    }

    private func loadConnectionSettings(for provider: ModelProvider) {
        isApplyingProviderConfiguration = true
        modelName = Self.loadModelName(for: provider, userDefaults: userDefaults)
        baseURL = Self.loadBaseURL(for: provider, userDefaults: userDefaults)
        apiKey = Self.loadAPIKeyFromKeychain(for: provider) ?? ""
        isApplyingProviderConfiguration = false
        refreshIdleValidationMessage()
    }

    private func persistAutoValidatePreference() {
        userDefaults.set(autoValidateOnLaunch, forKey: StorageKey.autoValidateOnLaunch)
    }

    private func persistWritingDeskDisplayPreferences() {
        userDefaults.set(showWritingDeskCachePanel, forKey: StorageKey.showWritingDeskCachePanel)
        userDefaults.set(showWritingDeskTimeline, forKey: StorageKey.showWritingDeskTimeline)
    }

    private func persistActiveProjectID() {
        let key = Self.activeProjectIDStorageKey(for: currentStorageScope)
        if let activeProjectID {
            userDefaults.set(activeProjectID, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func persistRecentProjects(_ projects: [NovelProject], for scope: String?) {
        do {
            try projectStore.saveProjects(projects, for: scope)
            Self.clearLegacyRecentProjectsFromUserDefaults(for: scope, userDefaults: userDefaults)
        } catch {
            return
        }
    }

    private func scheduleRecentProjectsPersistence(snapshot: [NovelProject], for scope: String?) {
        let storageKey = Self.recentProjectsStorageKey(for: scope)
        recentProjectsPersistTasks[storageKey]?.cancel()
        recentProjectsPersistTasks[storageKey] = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.persistRecentProjects(snapshot, for: scope)
            recentProjectsPersistTasks.removeValue(forKey: storageKey)
        }
    }

    private func updateProject(_ projectID: NovelProject.ID, mutate: (inout NovelProject) -> Void) {
        guard let index = recentProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var updatedProject = recentProjects[index]
        mutate(&updatedProject)
        recentProjects[index] = updatedProject
    }

    private func persistAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            Self.deleteAPIKeyFromKeychain(for: selectedProvider)
            return
        }

        Self.saveAPIKeyToKeychain(trimmedKey, for: selectedProvider)
    }

    private func persistActiveAccountProfile() {
        if let activeAccount {
            userDefaults.set(activeAccount.userID, forKey: StorageKey.activeAppleUserID)

            if activeAccount.email.isEmpty {
                userDefaults.removeObject(forKey: StorageKey.activeAppleUserEmail)
            } else {
                userDefaults.set(activeAccount.email, forKey: StorageKey.activeAppleUserEmail)
            }

            if activeAccount.fullName.isEmpty {
                userDefaults.removeObject(forKey: StorageKey.activeAppleUserName)
            } else {
                userDefaults.set(activeAccount.fullName, forKey: StorageKey.activeAppleUserName)
            }
        } else {
            userDefaults.removeObject(forKey: StorageKey.activeAppleUserID)
            userDefaults.removeObject(forKey: StorageKey.activeAppleUserEmail)
            userDefaults.removeObject(forKey: StorageKey.activeAppleUserName)
        }
    }

    private func persistProjectSnapshotTimestamp() {
        let key = Self.projectSnapshotTimestampStorageKey(for: currentStorageScope)

        if currentProjectSnapshotTimestamp > 0 {
            userDefaults.set(currentProjectSnapshotTimestamp, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func stringValue(forKey key: String, userDefaults: UserDefaults) -> String? {
        userDefaults.string(forKey: key)
    }

    private static func modelNameStorageKey(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return StorageKey.modelName
        case .custom:
            return StorageKey.customModelName
        }
    }

    private static func baseURLStorageKey(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return StorageKey.baseURL
        case .custom:
            return StorageKey.customBaseURL
        }
    }

    private static func keychainAccount(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return KeychainKey.openWAccount
        case .custom:
            return KeychainKey.customAccount
        }
    }

    private static func defaultModelName(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return "gpt-5.4-mini"
        case .custom:
            return ""
        }
    }

    private static func defaultBaseURL(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return "https://ai.xxread.top/v1"
        case .custom:
            return ""
        }
    }

    private static func loadModelName(for provider: ModelProvider, userDefaults: UserDefaults) -> String {
        stringValue(forKey: modelNameStorageKey(for: provider), userDefaults: userDefaults) ?? defaultModelName(for: provider)
    }

    private static func loadBaseURL(for provider: ModelProvider, userDefaults: UserDefaults) -> String {
        stringValue(forKey: baseURLStorageKey(for: provider), userDefaults: userDefaults) ?? defaultBaseURL(for: provider)
    }

    private static func boolValue(forKey key: String, userDefaults: UserDefaults) -> Bool? {
        if let value = userDefaults.object(forKey: key) as? Bool {
            return value
        }

        return nil
    }

    static func doubleValue(forKey key: String, userDefaults: UserDefaults) -> Double? {
        if let value = userDefaults.object(forKey: key) as? Double {
            return value
        }

        if let value = userDefaults.object(forKey: key) as? NSNumber {
            return value.doubleValue
        }

        return nil
    }

    static func dataValue(forKey key: String, userDefaults: UserDefaults) -> Data? {
        userDefaults.data(forKey: key)
    }

    private static func normalizedBaseURLString(from rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              var components = URLComponents(string: trimmedValue)
        else {
            return nil
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            components.path = "/v1"
        } else {
            components.path = "/" + trimmedPath
        }

        return components.url?.absoluteString
    }

    private static func validationFailureMessage(for error: Error) -> String {
        let resolvedMessage = (error as NSError).localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedMessage.isEmpty {
            return "连接校验失败，请检查 Base URL、模型 ID 和 API Key。"
        }

        return "连接校验失败：\(resolvedMessage)"
    }

    private static func loadAPIKeyFromKeychain(for provider: ModelProvider) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKey.service,
            kSecAttrAccount: keychainAccount(for: provider),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    @discardableResult
    private static func saveAPIKeyToKeychain(_ apiKey: String, for provider: ModelProvider) -> Bool {
        let encodedValue = Data(apiKey.utf8)
        let account = keychainAccount(for: provider)
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKey.service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: encodedValue
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var addQuery = baseQuery
        addQuery[kSecValueData] = encodedValue
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteAPIKeyFromKeychain(for provider: ModelProvider) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKey.service,
            kSecAttrAccount: keychainAccount(for: provider)
        ]

        SecItemDelete(query as CFDictionary)
    }

    var currentStorageScope: String? {
        activeAccount?.userID
    }

    private static func migrateLegacyUserDefaultsIfNeeded(
        _ userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) {
        guard !userDefaults.bool(forKey: StorageKey.didMigrateLegacyDefaults) else { return }

        copyStringValue(from: LegacyStorageKey.selectedProvider, to: StorageKey.selectedProvider, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.modelName, to: StorageKey.modelName, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.baseURL, to: StorageKey.baseURL, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.autoValidateOnLaunch, to: StorageKey.autoValidateOnLaunch, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.showWritingDeskCachePanel, to: StorageKey.showWritingDeskCachePanel, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.showWritingDeskTimeline, to: StorageKey.showWritingDeskTimeline, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.activeProjectID, to: StorageKey.activeProjectID, userDefaults: userDefaults)

        if !projectStore.hasProjects(for: nil),
           let legacyProjectsData = userDefaults.data(forKey: LegacyStorageKey.recentProjects),
           let legacyProjects = decodeProjects(from: legacyProjectsData),
           (try? projectStore.saveProjects(legacyProjects, for: nil)) != nil {
            userDefaults.removeObject(forKey: LegacyStorageKey.recentProjects)
        }

        // API Key intentionally stays out of automatic legacy migration so app launch never
        // touches old keychain entries or triggers repeated password prompts.
        userDefaults.set(true, forKey: StorageKey.didMigrateLegacyDefaults)
    }

    private static func migrateAPIKeysToKeychainIfNeeded(_ userDefaults: UserDefaults) {
        if let storedOpenWKey = stringValue(forKey: StorageKey.apiKey, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !storedOpenWKey.isEmpty,
           loadAPIKeyFromKeychain(for: .openAICompatible) == nil {
            saveAPIKeyToKeychain(storedOpenWKey, for: .openAICompatible)
        }
        userDefaults.removeObject(forKey: StorageKey.apiKey)

        if let legacyAPIKey = stringValue(forKey: LegacyStorageKey.apiKey, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyAPIKey.isEmpty,
           loadAPIKeyFromKeychain(for: .openAICompatible) == nil {
            saveAPIKeyToKeychain(legacyAPIKey, for: .openAICompatible)
        }
        userDefaults.removeObject(forKey: LegacyStorageKey.apiKey)
    }

    private static func migrateLegacyEmailScopeIfNeeded(
        _ userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) {
        guard !userDefaults.bool(forKey: StorageKey.didMigrateLegacyEmailScope) else { return }
        defer { userDefaults.set(true, forKey: StorageKey.didMigrateLegacyEmailScope) }

        guard let legacyEmail = stringValue(forKey: StorageKey.legacyActiveAccountEmail, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !legacyEmail.isEmpty
        else {
            return
        }

        copyAccountScopedProjectData(
            from: legacyEmail,
            to: nil,
            userDefaults: userDefaults,
            projectStore: projectStore
        )
        userDefaults.removeObject(forKey: StorageKey.legacyActiveAccountEmail)
    }

    static func copyAccountScopedProjectData(
        from sourceScope: String?,
        to targetScope: String?,
        userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) {
        if !projectStore.hasProjects(for: targetScope),
           let recentProjects = loadRecentProjects(
                for: sourceScope,
                from: userDefaults,
                projectStore: projectStore
           ) {
            try? projectStore.saveProjects(recentProjects, for: targetScope)
        }

        let sourceActiveProjectKey = activeProjectIDStorageKey(for: sourceScope)
        let targetActiveProjectKey = activeProjectIDStorageKey(for: targetScope)
        if userDefaults.string(forKey: targetActiveProjectKey) == nil,
           let activeProjectID = userDefaults.string(forKey: sourceActiveProjectKey) {
            userDefaults.set(activeProjectID, forKey: targetActiveProjectKey)
        }

        let sourceTimestampKey = projectSnapshotTimestampStorageKey(for: sourceScope)
        let targetTimestampKey = projectSnapshotTimestampStorageKey(for: targetScope)
        if userDefaults.object(forKey: targetTimestampKey) == nil,
           let timestamp = userDefaults.object(forKey: sourceTimestampKey) {
            userDefaults.set(timestamp, forKey: targetTimestampKey)
        }
    }

    private static func copyStringValue(from legacyKey: String, to currentKey: String, userDefaults: UserDefaults) {
        guard userDefaults.string(forKey: currentKey) == nil, let value = userDefaults.string(forKey: legacyKey) else {
            return
        }

        userDefaults.set(value, forKey: currentKey)
    }

    private static func copyBoolValue(from legacyKey: String, to currentKey: String, userDefaults: UserDefaults) {
        guard userDefaults.object(forKey: currentKey) == nil, let value = userDefaults.object(forKey: legacyKey) as? Bool else {
            return
        }

        userDefaults.set(value, forKey: currentKey)
    }

    private static func defaultProjectSummary(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "围绕一个核心冲突或情绪爆点，完成一次清晰、集中、可回收的短篇叙事闭环。"
        case .medium:
            return "以一条主线带动少量副线，在有限篇幅内完成角色变化、冲突升级与阶段回收。"
        case .long:
            return "从一句 logline 起步，逐步补齐分卷目标、长期冲突、角色弧线与伏笔回收，支撑连续长篇创作。"
        }
    }

    private static func defaultChapterFocus(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "尽快写出开场钩子、核心冲突和会在结尾回收的关键决定。"
        case .medium:
            return "先立稳主角目标、当前阶段阻力和第一轮关系变化，再推进本章转折。"
        case .long:
            return "先写出开篇场景的情绪、主角目标和第一个冲突钩子，并给长期主线留出延展空间。"
        }
    }

    private static func defaultWordTargetText(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "全文建议 6000-15000 字；单次生成建议 700-1000 字；尽量在 1-3 个关键场景内完成闭环。"
        case .medium:
            return "全文建议 30000-120000 字；按 8-20 章推进；单章建议 1600-2400 字。"
        case .long:
            return "全文建议 300000 字以上；按分卷/阶段推进；单章建议 1800-2600 字，关键节点可适当上浮。"
        }
    }

    private static func defaultContinuityNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "优先维持单一视角、情绪线和结尾闭环，避免引入过多未来才回收的信息。"
        case .medium:
            return "优先维持主线推进、主要关系线变化和阶段回收节奏，不要让中段散掉。"
        case .long:
            return "先把主角动机、长期冲突来源、章节语气和世界规则稳定下来，再逐步扩展分卷目标与长期伏笔。"
        }
    }

    private static func defaultSpecialRequirements(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "优先保证冲突集中、信息有效、结尾回收，不要把故事拖成散文式铺陈。"
        case .medium:
            return "控制支线数量，确保每章都服务于主线推进、关系变化或关键伏笔。"
        case .long:
            return "不要一次性说透长期线索，保持阶段推进、持续悬念和卷末回收节奏。"
        }
    }

    private static func defaultStructureNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            1. 开场快速建立主角处境与核心冲突
            2. 中段持续加压，逼出选择或代价
            3. 结尾完成事件或情绪闭环
            """
        case .medium:
            return """
            1. 前段建立主角目标、阻力和主要关系
            2. 中段升级冲突并制造一次明显反转
            3. 尾段完成阶段回收，并为最终落点蓄力
            """
        case .long:
            return """
            1. 第一卷负责开篇钩子、主角目标与世界规则落地
            2. 中期分卷持续升级敌我关系、代价与伏笔
            3. 大后期集中回收长期伏笔并推动终局决战
            """
        }
    }

    private static func defaultSceneProgressNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            1. 第一场直接落冲突或异常
            2. 第二场把问题逼到不可回避
            3. 最后一场完成揭示、决定或代价
            """
        case .medium:
            return """
            1. 开场先交代本阶段目标和当下阻力
            2. 中段安排一次推进失败或关系变形
            3. 结尾留下能驱动下一章的结果或新问题
            """
        case .long:
            return """
            1. 开场先落当前章目标、风险和人物态度
            2. 中段推进线索、关系或局势，并制造信息增量
            3. 结尾抛出下一章必须追的缺口，不提前透支真相
            """
        }
    }

    private static func defaultCharacterArcNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            主角：在一次关键选择中完成情绪或认知转变
            对手/陪衬人物：负责施压、映照或引发主角变化
            """
        case .medium:
            return """
            主角：从当前缺口出发，完成一轮明显的阶段成长
            核心配角：推动关系变化或揭示主角盲点
            对抗方：持续施压，但不要抢走主线焦点
            """
        case .long:
            return """
            主角：拆成阶段成长，不要一卷走完整条弧线
            核心配角：分别承担关系线、功能线和价值观碰撞
            长期对抗方：持续制造压力和误导，逐步显露真面目
            """
        }
    }

    private static func defaultForeshadowNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            1. 只保留必须在文末回收的关键伏笔
            2. 伏笔最好与主角决定或结尾反转直接相关
            """
        case .medium:
            return """
            1. 保留主线伏笔和 1-2 条关系线伏笔
            2. 明确哪些要在中段回收，哪些留到结尾
            """
        case .long:
            return """
            1. 区分本卷伏笔、跨卷伏笔和长期误导信息
            2. 记录每条伏笔第一次出现、下一次推进和最终回收节点
            """
        }
    }

    private static func defaultVolumePlanNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return ""
        case .medium:
            return """
            阶段一：建立主线目标、主要阻力和人物关系底色
            阶段二：加压、反转并逼出新的选择
            阶段三：回收主线冲突，完成角色变化
            """
        case .long:
            return """
            第一卷：开篇钩子、主角目标、世界规则、卷末第一次反转
            第二卷：扩大冲突范围，推进敌我关系和长期伏笔
            第三卷及以后：按阶段升级代价与真相，逐步回收长期线索
            """
        }
    }

    private static func defaultActiveThreadsNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return ""
        case .medium:
            return """
            主线：当前阶段最重要的目标与阻力
            关系线：本阶段最需要推进或制造变化的关系
            伏笔线：本阶段必须继续提一次的关键埋点
            """
        case .long:
            return """
            主线：当前卷最重要的推进目标与阻力
            支线：此刻仍在进行、且不能失踪的角色线/任务线
            伏笔线：下一次必须露面的长期埋点与误导信息
            回收线：最近 3 章内需要兑现、解释或翻面的旧伏笔
            """
        }
    }

    private static func defaultOutlineGenerationProfile(for length: NovelLength) -> OutlineGenerationProfile {
        switch length {
        case .short:
            return OutlineGenerationProfile(
                storyFlow: "围绕一次核心事件，完成起因、升级、决定和结尾回收。",
                worldDescription: "只保留支撑本次冲突的必要背景和规则。",
                protagonistTraits: "性格鲜明、动机明确、能在短时间内做出关键决定。",
                expectedLength: "全文约 0.6 万到 1.5 万字",
                endingPreference: "收束明确、情绪或事件完成闭环",
                sellingPoints: "冲突集中、结尾有效回收",
                keyEvents: "",
                storyPacing: "短促、聚焦、尽快进入正题",
                motivations: "",
                relationshipMap: "",
                antagonistPortrait: "",
                foreshadowingNotes: ""
            )
        case .medium:
            return OutlineGenerationProfile(
                storyFlow: "按起始、升级、反转、收束四段推进主线，并保留少量副线。",
                worldDescription: "把主线相关的背景、规则和对抗面说明白，但不要铺得过宽。",
                protagonistTraits: "主角有明确欲望、阶段成长空间和能推动剧情的主动性。",
                expectedLength: "全文约 3 万到 12 万字",
                endingPreference: "主线完成阶段闭环，人物获得清晰变化",
                sellingPoints: "主线集中、关系推进明显、阶段回收清楚",
                keyEvents: "",
                storyPacing: "稳步推进，中段需要明显升级或反转",
                motivations: "",
                relationshipMap: "",
                antagonistPortrait: "",
                foreshadowingNotes: ""
            )
        case .long:
            return OutlineGenerationProfile(
                storyFlow: "按分卷/阶段推进主线，每卷都要有独立目标、升级和卷末回收点。",
                worldDescription: "把长期主线需要用到的背景、规则、势力和限制说明清楚。",
                protagonistTraits: "主角具备长期成长空间、阶段欲望变化和可持续的行动驱动力。",
                expectedLength: "全文约 30 万字以上，按分卷连载推进",
                endingPreference: "终局收束明确，长期伏笔能分阶段回收",
                sellingPoints: "分卷推进、长期伏笔、角色弧线和世界状态持续演化",
                keyEvents: "",
                storyPacing: "长线连载节奏，卷内有高潮，卷末有明显翻面或升级",
                motivations: "",
                relationshipMap: "",
                antagonistPortrait: "",
                foreshadowingNotes: ""
            )
        }
    }

    private static func currentTimestampLabel() -> String {
        PersistedTimestampCodec.displayLabel(for: Date(), style: .project)
    }

    private static func normalizedChapterTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名章节" : trimmed
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
