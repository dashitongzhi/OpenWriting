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
    @ObservationIgnored let projectPersistence: ProjectPersistenceActor
    @ObservationIgnored let aiService: any AIWritingServicing
    @ObservationIgnored let credentialStore: any CredentialStoring
    @ObservationIgnored let writingSkillCatalog: any WritingSkillCatalogProviding
    @ObservationIgnored private let commerceProvider: any CommerceEntitlementProviding
    @ObservationIgnored let cloudStore = ICloudProjectStore()
    @ObservationIgnored var cloudSaveTask: Task<Void, Never>?
    @ObservationIgnored var cloudSaveGeneration: UInt64 = 0
    @ObservationIgnored var isCloudSynchronizationInProgress = false
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
    var isWritingFocusModeEnabled: Bool {
        didSet {
            persistWritingDeskDisplayPreferences()
        }
    }
    var draftEditorFontSize: Double {
        didSet {
            draftEditorFontSize = min(max(draftEditorFontSize, 13), 24)
            persistWritingDeskDisplayPreferences()
        }
    }
    var draftEditorLineSpacing: Double {
        didSet {
            draftEditorLineSpacing = min(max(draftEditorLineSpacing, 2), 14)
            persistWritingDeskDisplayPreferences()
        }
    }
    var hasAcceptedAIDataTransfer: Bool {
        didSet {
            userDefaults.set(hasAcceptedAIDataTransfer, forKey: StorageKey.hasAcceptedAIDataTransfer)
            if hasAcceptedAIDataTransfer {
                refreshIdleValidationMessage()
            } else {
                connectionStatus = .needsAttention
                validationMessage = "启用 AI 功能前需要先同意数据使用告知。"
            }
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
    var commerceEntitlement: CommerceEntitlementSnapshot

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

    var writingSkills: [WritingSkill] {
        didSet {
            persistWritingSkills(writingSkills)
        }
    }

    var publishedWritingSkills: [WritingSkill] {
        didSet {
            persistPublishedWritingSkills(publishedWritingSkills)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        projectStore: ProjectFileStore? = nil,
        aiService: any AIWritingServicing = DefaultAIWritingService(),
        credentialStore: any CredentialStoring = SecurityKeychainCredentialStore(),
        writingSkillCatalog: (any WritingSkillCatalogProviding)? = nil,
        commerceProvider: any CommerceEntitlementProviding = DeferredAppleCommerceProvider()
    ) {
        let projectStore = projectStore ?? ProjectFileStore()
        Self.migrateLegacyUserDefaultsIfNeeded(userDefaults, projectStore: projectStore)
        Self.migrateRetiredOpenAICompatibleDefaults(userDefaults)
        ModelConnectionConfigurationStore.clearBundledCustomDefaultsIfNeeded(userDefaults)
        Self.migrateLegacyEmailScopeIfNeeded(userDefaults, projectStore: projectStore)
        Self.migrateAPIKeysToKeychainIfNeeded(userDefaults, credentialStore: credentialStore)
        self.userDefaults = userDefaults
        self.projectStore = projectStore
        self.projectPersistence = ProjectPersistenceActor(store: projectStore.independentCopy())
        self.aiService = aiService
        self.credentialStore = credentialStore
        self.writingSkillCatalog = writingSkillCatalog ?? BundledWritingSkillCatalog()
        self.commerceProvider = commerceProvider
        let resolvedActiveAccount = Self.loadActiveAppleAccount(from: userDefaults)
        let resolvedStorageScope = resolvedActiveAccount?.userID
        let resolvedProvider = ModelConnectionConfigurationStore.loadSelectedProvider(userDefaults: userDefaults)
        self.activeAccount = resolvedActiveAccount
        self.selectedProvider = resolvedProvider
        self.modelName = Self.loadModelName(for: resolvedProvider, userDefaults: userDefaults)
        self.apiKey = resolvedProvider.requiresAPIKey
            ? ModelConnectionConfigurationStore.loadAPIKeyFromKeychain(
                for: resolvedProvider,
                credentialStore: credentialStore
            ) ?? ""
            : ""
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
        self.isWritingFocusModeEnabled = Self.boolValue(
            forKey: StorageKey.isWritingFocusModeEnabled,
            userDefaults: userDefaults
        ) ?? false
        let storedDraftEditorFontSize = Self.doubleValue(
            forKey: StorageKey.draftEditorFontSize,
            userDefaults: userDefaults
        ) ?? 16
        self.draftEditorFontSize = min(max(storedDraftEditorFontSize, 13), 24)
        let storedDraftEditorLineSpacing = Self.doubleValue(
            forKey: StorageKey.draftEditorLineSpacing,
            userDefaults: userDefaults
        ) ?? 5
        self.draftEditorLineSpacing = min(max(storedDraftEditorLineSpacing, 2), 14)
        self.hasAcceptedAIDataTransfer = Self.boolValue(
            forKey: StorageKey.hasAcceptedAIDataTransfer,
            userDefaults: userDefaults
        ) ?? false
        self.currentProjectSnapshotTimestamp = Self.doubleValue(
            forKey: Self.projectSnapshotTimestampStorageKey(for: resolvedStorageScope),
            userDefaults: userDefaults
        ) ?? 0
        self.recentProjects = Self.loadRecentProjects(
            for: resolvedStorageScope,
            from: userDefaults,
            projectStore: projectStore
        ) ?? Self.defaultRecentProjects
        self.writingSkills = Self.loadWritingSkills(from: userDefaults) ?? []
        self.publishedWritingSkills = Self.loadPublishedWritingSkills(from: userDefaults) ?? []
        self.connectionStatus = .idle
        self.validationMessage = Self.emptyConfigurationMessage
        self.commerceEntitlement = .localDefault()
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
            await refreshCommerceEntitlements()
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

    var hasPaidCommerceAccess: Bool {
        commerceEntitlement.grantsPaidAccess
    }

    func refreshCommerceEntitlements() async {
        commerceEntitlement = await commerceProvider.currentEntitlements(accountID: activeAccount?.userID)
    }

    func purchaseCommerceProduct(_ request: CommercePurchaseRequest) async -> CommercePurchaseOutcome {
        let outcome = await commerceProvider.purchase(request, accountID: activeAccount?.userID)
        if case let .completed(snapshot) = outcome {
            commerceEntitlement = snapshot
        }
        return outcome
    }

    func restoreCommercePurchases() async {
        commerceEntitlement = await commerceProvider.restorePurchases(accountID: activeAccount?.userID)
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
                title: "已安装 Skill",
                value: "\(writingSkills.count)",
                detail: "进入 Skill 市场",
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

        let provider = selectedProvider
        let providerTitle = provider.title
        validationTask = Task { @MainActor in
            do {
                let resolvedModel = try await aiService.validateConnection(configuration: configuration)
                guard !Task.isCancelled else { return }

                connectionStatus = .ready
                validationMessage = providerTitle == ModelProvider.openAICompatible.title
                    ? "已连接 OpenWriting 提供模型"
                    : "已连接 \(resolvedModel)"
            } catch {
                guard !Task.isCancelled else { return }

                connectionStatus = .needsAttention
                validationMessage = Self.validationFailureMessage(for: error, provider: provider)
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

    @discardableResult
    func importProjectBackup(_ project: NovelProject) -> NovelProject {
        let timestamp = Self.currentTimestampLabel()
        let importedProject: NovelProject

        if recentProjects.contains(where: { $0.id == project.id }) {
            let importedTitle = "\(project.title)（导入备份）"
            importedProject = project.importedBackupCopy(
                id: makeProjectIdentifier(from: importedTitle),
                title: importedTitle,
                updatedAt: timestamp
            )
        } else {
            var project = project
            project.updatedAt = timestamp
            importedProject = project
        }

        recentProjects.insert(importedProject, at: 0)
        openProjectSpace(for: importedProject.id, scrollToProject: true)
        return importedProject
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

    // MARK: - 结构化伏笔管理

    func addForeshadowEntry(_ entry: ForeshadowEntry, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.foreshadowList.add(entry)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func removeForeshadowEntry(id: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.foreshadowList.remove(id: id)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func updateForeshadowEntry(_ entry: ForeshadowEntry, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.foreshadowList.update(entry)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func advanceForeshadow(id: String, to chapter: Int, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.foreshadowList.advanceForeshadow(id: id, to: chapter)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func resolveForeshadow(id: String, at chapter: Int, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.foreshadowList.resolveForeshadow(id: id, at: chapter)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    /// 基于文本foreshadowNotes创建结构化伏笔条目
    func migrateForeshadowNotesToStructured(projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            let text = project.foreshadowNotes
            guard !text.isEmpty else { return }

            var newEntries: [ForeshadowEntry] = []
            let lines = text.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                // 解析格式：[状态] 标题 — 章节
                var title = trimmed
                var status: ForeshadowStatus = .active
                var chapterNum = project.currentChapterNumber

                // 检测状态前缀
                if trimmed.hasPrefix("[") {
                    let statusEnd = trimmed.firstIndex(of: "]")
                    if let end = statusEnd {
                        let startIndex = trimmed.index(after: trimmed.startIndex)
                        let statusStr = String(trimmed[startIndex..<end])
                        switch statusStr {
                        case "新增": status = .active
                        case "推进": status = .advanced
                        case "待回收": status = .active
                        case "已回收": status = .resolved
                        case "废弃": status = .retconned
                        default: status = .active
                        }
                        let afterBracket = trimmed[trimmed.index(after: end)...].trimmingCharacters(in: .whitespaces)
                        if afterBracket.hasPrefix("-") || afterBracket.hasPrefix(" ") {
                            title = String(afterBracket.dropFirst()).trimmingCharacters(in: .whitespaces)
                        } else {
                            title = afterBracket
                        }
                    }
                }

                // 检测章节引用
                let chapterPatterns = ["第", "章", "卷"]
                for pattern in chapterPatterns {
                    if let range = trimmed.range(of: pattern) {
                        let afterPattern = trimmed[range.upperBound...]
                        let digits = afterPattern.prefix(while: { $0.isNumber })
                        if !digits.isEmpty, let num = Int(digits) {
                            chapterNum = num
                            break
                        }
                    }
                }

                if !title.isEmpty {
                    let entry = ForeshadowEntry(
                        title: title,
                        description: "",
                        firstChapter: chapterNum,
                        volumeNumber: project.currentVolumeNumber,
                        status: status,
                        importance: .minor,
                        threads: [],
                        lastAdvancedChapter: status == .advanced ? chapterNum : 0,
                        plantedChapter: chapterNum
                    )
                    newEntries.append(entry)
                }
            }

            if !newEntries.isEmpty {
                for entry in newEntries {
                    project.foreshadowList.add(entry)
                }
            }

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
        reviewedChapter: ChapterReviewTarget? = nil,
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
                project.appendAntiPatterns(from: review)
                let reviewTarget = reviewedChapter ?? ChapterReviewTarget(
                    volumeNumber: project.currentVolumeNumber,
                    chapterNumber: project.currentChapterNumber,
                    chapterTitle: project.currentChapterTitle
                )
                let report = QualityReviewReport(
                    volumeNumber: reviewTarget.volumeNumber,
                    chapterNumber: reviewTarget.chapterNumber,
                    chapterTitle: reviewTarget.chapterTitle,
                    unifiedResult: review
                )
                project.qualityReviewReports.removeAll {
                    $0.resolvedVolumeNumber == report.resolvedVolumeNumber
                        && $0.chapterNumber == report.chapterNumber
                }
                project.qualityReviewReports.insert(report, at: 0)
                project.qualityReviewReports = Array(project.qualityReviewReports.prefix(80))
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
            func recordChapterTreeDecision(_ decision: ChapterTreeSectionMergeDecision, label: String) {
                switch decision {
                case .accepted:
                    outcome.acceptedSections += 1
                    outcome.acceptedSectionLabels.append(label)
                case .protected:
                    outcome.protectedSections += 1
                    outcome.protectedSectionLabels.append(label)
                case .ignored:
                    outcome.ignoredSectionLabels.append(label)
                }
            }

            let outlineDecision = mergeChapterTreeSection(
                current: &project.outlineSummary,
                replacement: refresh.outlineSummary,
                baseline: baseline?.outlineSummary
            )
            if outlineDecision.accepted {
                project.outlineSummaryUpdatedAt = timestamp
            }
            recordChapterTreeDecision(outlineDecision, label: "章节树总结")

            let structureDecision = mergeChapterTreeSection(
                current: &project.structureNotes,
                replacement: refresh.structureNotes,
                baseline: baseline?.structureNotes
            )
            recordChapterTreeDecision(structureDecision, label: "章节骨架")

            let sceneDecision = mergeChapterTreeSection(
                current: &project.sceneProgressNotes,
                replacement: refresh.sceneProgressNotes,
                baseline: baseline?.sceneProgressNotes
            )
            recordChapterTreeDecision(sceneDecision, label: "场景推进")

            let characterDecision = mergeChapterTreeSection(
                current: &project.characterArcNotes,
                replacement: refresh.characterArcNotes,
                baseline: baseline?.characterArcNotes
            )
            recordChapterTreeDecision(characterDecision, label: "角色弧线")

            let foreshadowDecision = mergeChapterTreeSection(
                current: &project.foreshadowNotes,
                replacement: refresh.foreshadowNotes,
                baseline: baseline?.foreshadowNotes
            )
            recordChapterTreeDecision(foreshadowDecision, label: "伏笔回收")

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

    func storageHealthReport(for projectID: NovelProject.ID) -> StorageHealthReport {
        var report = projectStore.storageHealthReport(
            for: projectID,
            scope: currentStorageScope
        )

        if let activeProjectID,
           activeProjectID != projectID,
           recentProjects.contains(where: { $0.id == projectID }) {
            let conflictIssue = ProjectStorageIssue(
                id: "cloud-selection-\(projectID)",
                kind: .cloudSelectionConflict,
                status: .warning,
                projectID: projectID,
                chapterID: nil,
                title: "当前项目选择与本地活跃项不同",
                detail: "iCloud 或本机选择仍指向另一个项目。同步前建议确认是否要切换活跃项目。",
                recoveryActions: [.exportDiagnostics, .markCloudConflict]
            )
            report.issues.append(conflictIssue)
            if report.status == .passed {
                report.status = .warning
                report.summary = "存储文件健康，但项目选择存在同步提醒。"
                report.nextAction = "确认活跃项目后再继续同步或写作。"
            }
        }

        return report
    }

    @discardableResult
    func recoverStorageIssue(
        _ issue: ProjectStorageIssue,
        action: StorageRecoveryAction
    ) -> StorageRecoveryResult? {
        do {
            let result = try projectStore.recoverStorageIssue(
                issue,
                action: action,
                project: project(for: issue.projectID),
                scope: currentStorageScope
            )

            if result.didChangeStore {
                if let reloadedProjects = Self.loadRecentProjects(
                    for: currentStorageScope,
                    from: userDefaults,
                    projectStore: projectStore
                ) {
                    let preservedActiveProjectID = activeProjectID
                    let preservedSelectedProjectID = selectedProjectID
                    isHydratingAccountScopedData = true
                    recentProjects = reloadedProjects
                    if let preservedActiveProjectID,
                       recentProjects.contains(where: { $0.id == preservedActiveProjectID }) {
                        activeProjectID = preservedActiveProjectID
                        selectedProjectID = preservedSelectedProjectID.flatMap { selectedID in
                            recentProjects.contains(where: { $0.id == selectedID }) ? selectedID : nil
                        } ?? preservedActiveProjectID
                    } else {
                        normalizeProjectSelection()
                    }
                    isHydratingAccountScopedData = false
                }
                noteLocalProjectMutation()
                scheduleCloudSnapshotSave()
            }

            setCloudSyncStatus(
                title: "存储恢复",
                symbolName: result.didChangeStore ? "wrench.and.screwdriver" : "doc.text.magnifyingglass",
                message: result.message
            )
            return result
        } catch {
            setCloudSyncStatus(
                title: "恢复失败",
                symbolName: "exclamationmark.triangle",
                message: error.localizedDescription
            )
            return nil
        }
    }

    @discardableResult
    func ensureContinuationChapterDraftsLoaded(
        for projectID: NovelProject.ID,
        limit: Int = 3
    ) -> [ChapterDraft] {
        guard let project = project(for: projectID) else { return [] }
        let currentVolumeNumber = max(project.currentVolumeNumber, 1)
        let currentChapterNumber = max(project.currentChapterNumber, 1)
        let previousMetadata = project.sortedChapterCatalog
            .filter { metadata in
                metadata.volumeNumber < currentVolumeNumber
                    || (metadata.volumeNumber == currentVolumeNumber && metadata.chapterNumber < currentChapterNumber)
            }
            .prefix(max(limit, 0))

        for metadata in previousMetadata {
            ensureChapterDraftLoaded(metadata.id, for: projectID)
        }

        return self.project(for: projectID)?
            .previousChapterDraftsForContinuation
            .prefix(max(limit, 0))
            .map { $0 } ?? []
    }

    func hydratedProjectsForPersistenceSnapshot(_ projects: [NovelProject]) -> [NovelProject] {
        projects.map { project in
            var hydratedProject = project
            let storedDraftReport = projectStore.loadChapterDraftReport(
                for: project.id,
                scope: currentStorageScope
            )

            var draftByID = Dictionary(uniqueKeysWithValues: storedDraftReport.drafts.map { ($0.id, $0) })
            for chapterDraft in project.chapterDrafts {
                draftByID[chapterDraft.id] = chapterDraft
            }

            if !project.chapterCatalog.isEmpty {
                let retainedChapterIDs = Set(project.chapterCatalog.map(\.id))
                    .union(project.chapterDrafts.map(\.id))
                draftByID = draftByID.filter { retainedChapterIDs.contains($0.key) }
            }

            hydratedProject.chapterDrafts = draftByID.values.sorted(by: ChapterDraft.sortDescending)
            let hydratedChapterIDs = Set(hydratedProject.chapterDrafts.map(\.id))
            let catalogChapterIDs = Set(project.chapterCatalog.map(\.id))
            if !hydratedProject.chapterDrafts.isEmpty,
               catalogChapterIDs.isSubset(of: hydratedChapterIDs) {
                hydratedProject.chapterCatalog = hydratedProject.chapterDrafts
                    .map(ChapterDraftMetadata.init)
                    .sorted(by: ChapterDraftMetadata.sortDescending)
            } else if !storedDraftReport.isComplete, !project.chapterCatalog.isEmpty {
                hydratedProject.chapterCatalog = project.chapterCatalog
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
            project.writtenChapters = max(project.writtenChapters, project.savedChapterCount, normalizedChapterNumber)
            project.updatedAt = timestamp
        }

        guard result != nil else { return nil }
        guard persistRecentProjects(recentProjects, for: currentStorageScope) else {
            return nil
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
            project.writtenChapters = max(project.writtenChapters, project.savedChapterCount, chapterDraft.chapterNumber)
            project.updatedAt = Self.currentTimestampLabel()
        }
    }

    func beginNextChapter(after chapterDraft: ChapterDraft, for projectID: NovelProject.ID) {
        if let project = project(for: projectID),
           let existingMetadata = Self.nextExistingChapterMetadata(after: chapterDraft, in: project) {
            ensureChapterDraftLoaded(existingMetadata.id, for: projectID)
        }

        updateProject(projectID) { project in
            if let existingDraft = Self.nextExistingChapterDraft(after: chapterDraft, in: project.chapterDrafts) {
                project.currentVolumeNumber = max(existingDraft.volumeNumber, 1)
                project.currentChapterNumber = max(existingDraft.chapterNumber, 1)
                project.currentChapterTitle = existingDraft.chapterTitle
                project.draftText = existingDraft.content
            } else {
                let nextChapterNumber = max(chapterDraft.chapterNumber + 1, 1)
                let nextVolumeNumber = max(chapterDraft.volumeNumber, 1)
                project.currentVolumeNumber = nextVolumeNumber
                project.currentChapterNumber = nextChapterNumber
                project.currentChapterTitle = "待命名章节"
                project.draftText = ""
                project.chapterFocus = Self.defaultNextChapterFocus(
                    after: chapterDraft,
                    project: project
                )
            }

            project.writtenChapters = max(project.writtenChapters, project.savedChapterCount, chapterDraft.chapterNumber)
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

            if hasMeaningfulChange {
                Self.markLongformChapterNeedsRecommit(
                    updated,
                    in: &project,
                    reason: "已保存章节被手动修改，需重新保存并通过质量审查后才能恢复后台提交链。"
                )
            }

            project.writtenChapters = max(project.writtenChapters, project.savedChapterCount, chapterNumber)
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

            Self.markLongformChapterNeedsRecommit(
                restored,
                in: &project,
                reason: "章节版本已回滚，需重新保存并通过质量审查后才能恢复后台提交链。"
            )

            project.writtenChapters = max(project.writtenChapters, project.savedChapterCount, restored.chapterNumber)
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
            return true
        case .custom, .anthropic:
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
        guard hasAcceptedAIDataTransfer else {
            validationMessage = "启用 AI 功能前需要先同意数据使用告知。"
            return
        }

        switch selectedProvider {
        case .openAICompatible:
            validationMessage = "OpenWriting 提供模型由服务器后端托管，可点击“测试连接”检查可用性。"
        case .custom:
            validationMessage = hasEnteredConnectionInfo
                ? "自定义 OpenAI 配置已保存，可点击“测试连接”以重新检查。"
                : Self.emptyConfigurationMessage
        case .anthropic:
            validationMessage = hasEnteredConnectionInfo
                ? "自定义 Anthropic 配置已保存，可点击“测试连接”以重新检查。"
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
        guard hasAcceptedAIDataTransfer else {
            connectionStatus = .needsAttention
            validationMessage = "启用 AI 功能前需要先同意数据使用告知。"
            return nil
        }

        let trimmedKey = selectedProvider.requiresAPIKey
            ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard hasValidBaseURL else {
            connectionStatus = .needsAttention
            validationMessage = "Base URL 需要是完整的 http 或 https 地址。"
            return nil
        }

        guard !selectedProvider.requiresAPIKey || !trimmedKey.isEmpty else {
            connectionStatus = .needsAttention
            validationMessage = "API Key 不能为空。"
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
            modelName: trimmedModelName,
            apiFormat: selectedProvider.apiFormat,
            additionalHeaders: selectedProvider == .openAICompatible
                ? Self.serverManagedAdditionalHeaders(
                    accountID: activeAccount?.userID,
                    userDefaults: userDefaults
                )
                : [:]
        )
    }

    func updateProject(_ projectID: NovelProject.ID, mutate: (inout NovelProject) -> Void) {
        guard let index = recentProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var updatedProject = recentProjects[index]
        mutate(&updatedProject)
        recentProjects[index] = updatedProject
    }

    static func currentTimestampLabel() -> String {
        PersistedTimestampCodec.displayLabel(for: Date(), style: .project)
    }

    static func boundedPromptContext(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.suffix(limit))
    }

    private static func trimChapterVersionHistory(_ chapterDraft: inout ChapterDraft) {
        guard chapterDraft.versionHistory.count > maxChapterVersionHistoryCount else { return }
        chapterDraft.versionHistory = Array(chapterDraft.versionHistory.prefix(maxChapterVersionHistoryCount))
    }

    private static func markLongformChapterNeedsRecommit(
        _ chapterDraft: ChapterDraft,
        in project: inout NovelProject,
        reason: String
    ) {
        guard project.storyLength.supportsVolumePlanning else { return }

        var contractProject = project
        contractProject.currentVolumeNumber = max(chapterDraft.volumeNumber, 1)
        contractProject.currentChapterNumber = max(chapterDraft.chapterNumber, 1)
        contractProject.currentChapterTitle = chapterDraft.chapterTitle
        contractProject.draftText = chapterDraft.content

        let contract = LongformStorySystem.buildRuntimeContract(for: contractProject)
        let commit = LongformStorySystem.buildCommit(
            project: contractProject,
            chapterDraft: chapterDraft,
            review: nil,
            reviewFailureReason: reason,
            extractedMemoryItems: [],
            contract: contract
        )
        LongformStorySystem.apply(commit: commit, contract: contract, to: &project)
    }

    private static func nextExistingChapterMetadata(
        after chapterDraft: ChapterDraft,
        in project: NovelProject
    ) -> ChapterDraftMetadata? {
        let currentVolume = max(chapterDraft.volumeNumber, 1)
        let currentChapter = max(chapterDraft.chapterNumber, 1)
        return project.sortedChapterCatalog
            .filter {
                $0.volumeNumber > currentVolume
                    || ($0.volumeNumber == currentVolume && $0.chapterNumber > currentChapter)
            }
            .sorted(by: chapterPositionAscending)
            .first
    }

    private static func nextExistingChapterDraft(
        after chapterDraft: ChapterDraft,
        in chapterDrafts: [ChapterDraft]
    ) -> ChapterDraft? {
        let currentVolume = max(chapterDraft.volumeNumber, 1)
        let currentChapter = max(chapterDraft.chapterNumber, 1)
        return chapterDrafts
            .filter {
                $0.volumeNumber > currentVolume
                    || ($0.volumeNumber == currentVolume && $0.chapterNumber > currentChapter)
            }
            .sorted(by: chapterPositionAscending)
            .first
    }

    private static func chapterPositionAscending(_ lhs: ChapterDraftMetadata, _ rhs: ChapterDraftMetadata) -> Bool {
        if lhs.volumeNumber != rhs.volumeNumber {
            return lhs.volumeNumber < rhs.volumeNumber
        }
        if lhs.chapterNumber != rhs.chapterNumber {
            return lhs.chapterNumber < rhs.chapterNumber
        }
        return lhs.savedAtDate < rhs.savedAtDate
    }

    private static func chapterPositionAscending(_ lhs: ChapterDraft, _ rhs: ChapterDraft) -> Bool {
        if lhs.volumeNumber != rhs.volumeNumber {
            return lhs.volumeNumber < rhs.volumeNumber
        }
        if lhs.chapterNumber != rhs.chapterNumber {
            return lhs.chapterNumber < rhs.chapterNumber
        }
        return lhs.savedAtDate < rhs.savedAtDate
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

    nonisolated static func searchTokens(from query: String) -> [String] {
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

    nonisolated static func searchScore(in text: String, tokens: [String]) -> Int {
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

    nonisolated static func searchExcerpt(from text: String, tokens: [String], limit: Int) -> String {
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

    private static func defaultNextChapterFocus(after chapterDraft: ChapterDraft, project: NovelProject) -> String {
        let trimmedEnding = chapterDraft.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ending = trimmedEnding.count > 180
            ? String(trimmedEnding.suffix(180))
            : trimmedEnding

        let baseFocus: String
        switch project.storyLength {
        case .short:
            baseFocus = "承接上一段的结果，继续压缩场景数量，推动核心冲突向结尾闭环靠拢。"
        case .medium:
            baseFocus = "承接上一章的后果，推进主线目标、关系变化或阶段反转，避免支线发散。"
        case .long:
            baseFocus = "承接上一章留下的行动后果、人物状态和在途线索，推进当前卷目标，并保留长期伏笔的延展空间。"
        }

        var sections = [baseFocus]
        let runtime = project.longformRuntimeState

        if let latestCommit = runtime.latestCommit,
           latestCommit.volumeNumber == max(chapterDraft.volumeNumber, 1),
           latestCommit.chapterNumber == max(chapterDraft.chapterNumber, 1) {
            var commitLines: [String] = []
            let coveredNodes = latestCommit.coveredNodes
                .prefix(3)
                .joined(separator: "；")
            if !coveredNodes.isEmpty {
                commitLines.append("上一章已完成节点：\(coveredNodes)")
            }

            let eventSummary = latestCommit.acceptedEvents
                .prefix(4)
                .map { "\($0.subject)-\($0.field)：\($0.value)" }
                .joined(separator: "；")
            if !eventSummary.isEmpty {
                commitLines.append("上一章沉淀状态：\(eventSummary)")
            }

            if !commitLines.isEmpty {
                sections.append(commitLines.joined(separator: "\n"))
            }
        }

        let qualityTrend = project.longformQualityTrend
        if qualityTrend.hasSignals {
            var qualityLines: [String] = []
            if let averageScore = qualityTrend.averageScore {
                qualityLines.append("近期审查均分 \(averageScore)/100，下一章要主动拉高稳定性。")
            }

            let priorityIssues = qualityTrend.priorityIssues
                .prefix(3)
                .joined(separator: "；")
            if !priorityIssues.isEmpty {
                qualityLines.append("优先避免旧问题：\(priorityIssues)")
            }

            let antiPatterns = qualityTrend.antiPatterns
                .prefix(3)
                .joined(separator: "；")
            if !antiPatterns.isEmpty {
                qualityLines.append("避免重复 AI 味：\(antiPatterns)")
            }

            if !qualityLines.isEmpty {
                sections.append("质量修复方向：\n" + qualityLines.joined(separator: "\n"))
            }
        }

        let health = project.longformRuntimeHealth
        let healthHints = health.issues
            .filter { $0.status != .passed && $0.title != "长篇合同尚未落盘" }
            .prefix(3)
            .map { "\($0.title)：\($0.repairHint)" }
            .joined(separator: "\n")
        if !healthHints.isEmpty {
            sections.append("后台提醒：\n\(healthHints)")
        }

        if !ending.isEmpty {
            sections.append("上一章结尾参考：\(ending)")
        }

        return sections.joined(separator: "\n\n")
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
