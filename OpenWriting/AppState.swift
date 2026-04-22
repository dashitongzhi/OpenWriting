import AuthenticationServices
import Foundation
import Observation

enum NovelLength: String, CaseIterable, Codable, Identifiable {
    case short
    case medium
    case long

    var id: Self { self }

    var title: String {
        switch self {
        case .short:
            return "短篇"
        case .medium:
            return "中篇"
        case .long:
            return "长篇"
        }
    }

    var summary: String {
        switch self {
        case .short:
            return "适合单一冲突闭环、强情绪转折或一次真相揭示。"
        case .medium:
            return "适合一条主线搭配少量副线，让人物变化完整展开。"
        case .long:
            return "适合分卷连载、长线伏笔、多角色弧线和世界状态持续演化。"
        }
    }

    var targetRangeSummary: String {
        switch self {
        case .short:
            return "全文约 0.6 万到 1.5 万字"
        case .medium:
            return "全文约 3 万到 12 万字"
        case .long:
            return "全文约 30 万字以上"
        }
    }

    var creationChecklist: [String] {
        switch self {
        case .short:
            return [
                "主线尽量单一，角色和场景控制在必要范围内",
                "开场尽快给出钩子，中段加压，结尾形成闭环",
                "不依赖复杂章节树，重点盯住节奏和回收"
            ]
        case .medium:
            return [
                "主线之外最多保留 1 到 2 条副线，避免信息发散",
                "按阶段推进角色关系和主要冲突，适合 8 到 20 章规模",
                "中段需要反转或升级，尾段要完成阶段回收"
            ]
        case .long:
            return [
                "先定分卷目标，再拆当前卷章节点和卷末回收点",
                "持续维护在途线索、人物长期状态和未回收伏笔",
                "避免单章透支底牌，关键真相分阶段揭示"
            ]
        }
    }

    var promptDirective: String {
        switch self {
        case .short:
            return "按短篇模式创作：冲突集中、场景精简、结尾要形成明确闭环。"
        case .medium:
            return "按中篇模式创作：允许阶段推进和关系变化，但要持续围绕主线，不要支线蔓延。"
        case .long:
            return "按长篇模式创作：强调分卷推进、长期伏笔、角色长期变化和阶段性回收，避免一次性把底牌说透。"
        }
    }

    var outlineDirective: String {
        switch self {
        case .short:
            return "大纲要突出单次事件闭环、关键转折和结尾回收点。"
        case .medium:
            return "大纲要明确阶段推进、主要转折和主副线配比。"
        case .long:
            return "大纲必须明确分卷/阶段目标、卷末回收、长期反派压力和多条在途线索的衔接。"
        }
    }

    var continuityDirective: String {
        switch self {
        case .short:
            return "重点维护叙事视角、情绪线和结尾闭环，不要拖出无必要的远期悬念。"
        case .medium:
            return "重点维护主线推进、关系线变化和阶段伏笔回收，避免中段散掉。"
        case .long:
            return "重点维护分卷目标、在途线索、人物长期状态和跨章信息一致性。"
        }
    }

    var supportsThreadTracking: Bool {
        self != .short
    }

    var supportsVolumePlanning: Bool {
        self == .long
    }
}

@MainActor
@Observable
final class AppState {
    private enum StorageKey {
        static let selectedProvider = "OpenWriting.selectedProvider"
        static let modelName = "OpenWriting.modelName"
        static let apiKey = "OpenWriting.apiKey"
        static let baseURL = "OpenWriting.baseURL"
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

    private enum LegacyStorageKey {
        private static let prefix = "Open" + "Reading"

        static let selectedProvider = "\(prefix).selectedProvider"
        static let modelName = "\(prefix).modelName"
        static let baseURL = "\(prefix).baseURL"
        static let autoValidateOnLaunch = "\(prefix).autoValidateOnLaunch"
        static let showWritingDeskCachePanel = "\(prefix).showWritingDeskCachePanel"
        static let showWritingDeskTimeline = "\(prefix).showWritingDeskTimeline"
        static let activeProjectID = "\(prefix).activeProjectID"
        static let recentProjects = "\(prefix).recentProjects"
    }

    private static let emptyConfigurationMessage = "填入 API Key 与 Base URL 后即可验证。"

    private let userDefaults: UserDefaults
    @ObservationIgnored private let cloudStore = ICloudProjectStore()
    @ObservationIgnored private var cloudSaveTask: Task<Void, Never>?
    @ObservationIgnored private var isHydratingAccountScopedData = false

    var selectedProvider: ModelProvider {
        didSet {
            persistSelectedProvider()
            markConfigurationAsEdited()
        }
    }
    var modelName: String {
        didSet {
            persistModelName()
            markConfigurationAsEdited()
        }
    }
    var apiKey: String {
        didSet {
            persistAPIKey()
            markConfigurationAsEdited()
        }
    }
    var baseURL: String {
        didSet {
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

    private var activeProjectID: NovelProject.ID? {
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
            persistRecentProjects()
            guard !isHydratingAccountScopedData else { return }
            noteLocalProjectMutation()
            scheduleCloudSnapshotSave()
        }
    }
    var cloudSyncTitle = "本机保存"
    var cloudSyncSymbolName = "icloud.slash"
    var cloudSyncStatusMessage = "登录 Apple ID 后即可通过 iCloud 同步项目。"

    private var currentProjectSnapshotTimestamp: TimeInterval {
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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        Self.migrateLegacyUserDefaultsIfNeeded(userDefaults)
        Self.migrateLegacyEmailScopeIfNeeded(userDefaults)
        let resolvedActiveAccount = Self.loadActiveAppleAccount(from: userDefaults)
        let resolvedStorageScope = resolvedActiveAccount?.userID
        self.activeAccount = resolvedActiveAccount
        self.selectedProvider = ModelProvider(
            rawValue: Self.stringValue(
                forKey: StorageKey.selectedProvider,
                userDefaults: userDefaults
            ) ?? ""
        ) ?? .openAICompatible
        self.modelName = Self.stringValue(
            forKey: StorageKey.modelName,
            userDefaults: userDefaults
        ) ?? "gpt-4.1-mini"
        self.apiKey = Self.stringValue(
            forKey: StorageKey.apiKey,
            userDefaults: userDefaults
        ) ?? ""
        self.baseURL = Self.stringValue(
            forKey: StorageKey.baseURL,
            userDefaults: userDefaults
        ) ?? "https://api.openai.com/v1"
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
        self.recentProjects = Self.loadRecentProjects(for: resolvedStorageScope, from: userDefaults) ?? Self.defaultRecentProjects
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
        hasValidBaseURL &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func validateConfiguration() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard hasValidBaseURL else {
            connectionStatus = .needsAttention
            validationMessage = "Base URL 需要是完整的 http 或 https 地址。"
            return
        }

        guard !trimmedKey.isEmpty else {
            connectionStatus = .needsAttention
            validationMessage = "API Key 不能为空。"
            return
        }

        guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionStatus = .needsAttention
            validationMessage = "模型名称不能为空。"
            return
        }

        connectionStatus = .ready
        validationMessage = "配置格式已通过，可继续接入真实模型请求。"
    }

    var aiConfiguration: AIConnectionConfiguration? {
        guard
            let resolvedBaseURL = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return AIConnectionConfiguration(
            baseURL: resolvedBaseURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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

    func bindAppleAccount(_ profile: AppleAccountProfile) {
        let normalizedProfile = Self.normalizedAppleAccount(profile)
        let targetScope = normalizedProfile.userID

        if Self.loadRecentProjects(for: targetScope, from: userDefaults) == nil {
            Self.copyAccountScopedProjectData(from: currentStorageScope, to: targetScope, userDefaults: userDefaults)
        }

        activeAccount = normalizedProfile
        currentProjectSnapshotTimestamp = Self.doubleValue(
            forKey: Self.projectSnapshotTimestampStorageKey(for: targetScope),
            userDefaults: userDefaults
        ) ?? 0
        reloadAccountScopedProjects()

        Task { @MainActor in
            _ = await refreshActiveAppleCredentialState()
            await synchronizeWithICloud(forcePull: false)
        }
    }

    func logoutAccount() {
        guard activeAccount != nil else { return }
        cloudSaveTask?.cancel()
        activeAccount = nil
        currentProjectSnapshotTimestamp = Self.doubleValue(
            forKey: Self.projectSnapshotTimestampStorageKey(for: nil),
            userDefaults: userDefaults
        ) ?? 0
        reloadAccountScopedProjects()

        Task { @MainActor in
            await refreshCloudAvailability()
        }
    }

    func refreshICloudProjects() async {
        await synchronizeWithICloud(forcePull: true)
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
        guard let components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        let scheme = components.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && components.host != nil
    }

    private var hasEnteredConnectionInfo: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizeProjectSelection() {
        let fallbackProjectID = recentProjects.first?.id

        if let activeProjectID, recentProjects.contains(where: { $0.id == activeProjectID }) {
            selectedProjectID = activeProjectID
        } else {
            activeProjectID = fallbackProjectID
            selectedProjectID = fallbackProjectID
        }
    }

    private func refreshIdleValidationMessage() {
        connectionStatus = .idle
        validationMessage = hasEnteredConnectionInfo
            ? "配置已保存，可点击“验证配置”以重新检查。"
            : Self.emptyConfigurationMessage
    }

    private func markConfigurationAsEdited() {
        refreshIdleValidationMessage()
    }

    private func persistSelectedProvider() {
        userDefaults.set(selectedProvider.rawValue, forKey: StorageKey.selectedProvider)
    }

    private func persistModelName() {
        userDefaults.set(modelName, forKey: StorageKey.modelName)
    }

    private func persistBaseURL() {
        userDefaults.set(baseURL, forKey: StorageKey.baseURL)
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

    private func persistRecentProjects() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(recentProjects) else { return }
        userDefaults.set(data, forKey: Self.recentProjectsStorageKey(for: currentStorageScope))
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
            userDefaults.removeObject(forKey: StorageKey.apiKey)
            return
        }

        userDefaults.set(trimmedKey, forKey: StorageKey.apiKey)
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

    private func reloadAccountScopedProjects() {
        isHydratingAccountScopedData = true
        recentProjects = Self.loadRecentProjects(for: currentStorageScope, from: userDefaults) ?? Self.defaultRecentProjects
        activeProjectID = Self.stringValue(
            forKey: Self.activeProjectIDStorageKey(for: currentStorageScope),
            userDefaults: userDefaults
        )
        selectedProjectID = activeProjectID
        normalizeProjectSelection()
        isHydratingAccountScopedData = false
    }

    private static func loadRecentProjects(for scope: String?, from userDefaults: UserDefaults) -> [NovelProject]? {
        guard let data = dataValue(
            forKey: recentProjectsStorageKey(for: scope),
            userDefaults: userDefaults
        ) else {
            return nil
        }

        guard let decodedProjects = try? JSONDecoder().decode([NovelProject].self, from: data) else {
            return nil
        }

        return decodedProjects.filter { !builtInProjectIDs.contains($0.id) }
    }

    private static func stringValue(forKey key: String, userDefaults: UserDefaults) -> String? {
        userDefaults.string(forKey: key)
    }

    private static func boolValue(forKey key: String, userDefaults: UserDefaults) -> Bool? {
        if let value = userDefaults.object(forKey: key) as? Bool {
            return value
        }

        return nil
    }

    private static func doubleValue(forKey key: String, userDefaults: UserDefaults) -> Double? {
        if let value = userDefaults.object(forKey: key) as? Double {
            return value
        }

        if let value = userDefaults.object(forKey: key) as? NSNumber {
            return value.doubleValue
        }

        return nil
    }

    private static func dataValue(forKey key: String, userDefaults: UserDefaults) -> Data? {
        userDefaults.data(forKey: key)
    }

    private var currentStorageScope: String? {
        activeAccount?.userID
    }

    private func noteLocalProjectMutation() {
        currentProjectSnapshotTimestamp = Date().timeIntervalSince1970
    }

    private func scheduleCloudSnapshotSave() {
        cloudSaveTask?.cancel()

        guard let scope = currentStorageScope else {
            Task { @MainActor in
                await refreshCloudAvailability()
            }
            return
        }

        let snapshot = AccountProjectSnapshot(
            activeProjectID: activeProjectID,
            recentProjects: recentProjects,
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

    private func refreshCloudAvailability() async {
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

    private func refreshActiveAppleCredentialState() async -> Bool {
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

    private func synchronizeWithICloud(forcePull: Bool) async {
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
                let snapshot = AccountProjectSnapshot(
                    activeProjectID: activeProjectID,
                    recentProjects: recentProjects,
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

    private func applyCloudSnapshot(_ snapshot: AccountProjectSnapshot) {
        currentProjectSnapshotTimestamp = snapshot.updatedAt.timeIntervalSince1970
        isHydratingAccountScopedData = true
        recentProjects = snapshot.recentProjects
        activeProjectID = snapshot.activeProjectID
        selectedProjectID = snapshot.activeProjectID
        normalizeProjectSelection()
        isHydratingAccountScopedData = false
    }

    private func setCloudSyncStatus(title: String, symbolName: String, message: String) {
        cloudSyncTitle = title
        cloudSyncSymbolName = symbolName
        cloudSyncStatusMessage = message
    }

    private func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
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

    private static func activeProjectIDStorageKey(for scope: String?) -> String {
        scopedStorageKey(base: StorageKey.activeProjectID, scope: scope)
    }

    private static func recentProjectsStorageKey(for scope: String?) -> String {
        scopedStorageKey(base: StorageKey.recentProjects, scope: scope)
    }

    private static func projectSnapshotTimestampStorageKey(for scope: String?) -> String {
        scopedStorageKey(base: StorageKey.projectSnapshotTimestamp, scope: scope)
    }

    private static func scopedStorageKey(base: String, scope: String?) -> String {
        guard let scope = normalizedStorageScope(scope) else {
            return base
        }

        return "\(base).\(sanitizedStorageComponent(scope))"
    }

    private static func normalizedStorageScope(_ scope: String?) -> String? {
        guard let scope else { return nil }
        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func normalizedAppleAccount(_ profile: AppleAccountProfile) -> AppleAccountProfile {
        AppleAccountProfile(
            userID: profile.userID.trimmingCharacters(in: .whitespacesAndNewlines),
            email: profile.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            fullName: profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func loadActiveAppleAccount(from userDefaults: UserDefaults) -> AppleAccountProfile? {
        guard let userID = stringValue(forKey: StorageKey.activeAppleUserID, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
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

    private static func sanitizedStorageComponent(_ value: String) -> String {
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

    private static func migrateLegacyUserDefaultsIfNeeded(_ userDefaults: UserDefaults) {
        guard !userDefaults.bool(forKey: StorageKey.didMigrateLegacyDefaults) else { return }

        copyStringValue(from: LegacyStorageKey.selectedProvider, to: StorageKey.selectedProvider, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.modelName, to: StorageKey.modelName, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.baseURL, to: StorageKey.baseURL, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.autoValidateOnLaunch, to: StorageKey.autoValidateOnLaunch, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.showWritingDeskCachePanel, to: StorageKey.showWritingDeskCachePanel, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.showWritingDeskTimeline, to: StorageKey.showWritingDeskTimeline, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.activeProjectID, to: StorageKey.activeProjectID, userDefaults: userDefaults)
        copyDataValue(from: LegacyStorageKey.recentProjects, to: StorageKey.recentProjects, userDefaults: userDefaults)

        // API Key intentionally stays out of automatic legacy migration so app launch never
        // touches old keychain entries or triggers repeated password prompts.
        userDefaults.set(true, forKey: StorageKey.didMigrateLegacyDefaults)
    }

    private static func migrateLegacyEmailScopeIfNeeded(_ userDefaults: UserDefaults) {
        guard !userDefaults.bool(forKey: StorageKey.didMigrateLegacyEmailScope) else { return }
        defer { userDefaults.set(true, forKey: StorageKey.didMigrateLegacyEmailScope) }

        guard let legacyEmail = stringValue(forKey: StorageKey.legacyActiveAccountEmail, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !legacyEmail.isEmpty
        else {
            return
        }

        copyAccountScopedProjectData(from: legacyEmail, to: nil, userDefaults: userDefaults)
        userDefaults.removeObject(forKey: StorageKey.legacyActiveAccountEmail)
    }

    private static func copyAccountScopedProjectData(from sourceScope: String?, to targetScope: String?, userDefaults: UserDefaults) {
        let sourceRecentProjectsKey = recentProjectsStorageKey(for: sourceScope)
        let targetRecentProjectsKey = recentProjectsStorageKey(for: targetScope)
        if userDefaults.data(forKey: targetRecentProjectsKey) == nil,
           let recentProjectsData = userDefaults.data(forKey: sourceRecentProjectsKey) {
            userDefaults.set(recentProjectsData, forKey: targetRecentProjectsKey)
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

    private static func copyDataValue(from legacyKey: String, to currentKey: String, userDefaults: UserDefaults) {
        guard userDefaults.data(forKey: currentKey) == nil, let value = userDefaults.data(forKey: legacyKey) else {
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "今天 HH:mm"
        return formatter.string(from: Date())
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

    private static let builtInProjectIDs: Set<String> = [
        "fog-harbor-chronicle",
        "glass-mountain-letters",
        "zero-sunset"
    ]

    private static let defaultRecentProjects: [NovelProject] = []
}

enum ModelProvider: String, CaseIterable, Identifiable {
    case openAICompatible
    case deepSeek
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .openAICompatible:
            return "OpenAI 兼容"
        case .deepSeek:
            return "DeepSeek"
        case .custom:
            return "自定义"
        }
    }
}

enum ConnectionStatus {
    case idle
    case ready
    case needsAttention

    var label: String {
        switch self {
        case .idle:
            return "等待配置"
        case .ready:
            return "配置就绪"
        case .needsAttention:
            return "需要检查"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "circle.dashed"
        case .ready:
            return "checkmark.seal.fill"
        case .needsAttention:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct DashboardStat: Identifiable {
    let title: String
    let value: String
    let detail: String
    let symbolName: String
    let destination: SidebarItem

    var id: String { title }
}

enum ChapterDraftSaveResult {
    case created(ChapterDraft)
    case updated(ChapterDraft)

    var chapterDraft: ChapterDraft {
        switch self {
        case let .created(chapterDraft), let .updated(chapterDraft):
            return chapterDraft
        }
    }

    var isUpdate: Bool {
        switch self {
        case .created:
            return false
        case .updated:
            return true
        }
    }
}

struct ChapterDraft: Identifiable, Codable, Hashable {
    let id: String
    var chapterNumber: Int
    var chapterTitle: String
    var content: String
    var savedAt: String

    init(
        id: String = UUID().uuidString,
        chapterNumber: Int,
        chapterTitle: String,
        content: String,
        savedAt: String
    ) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.content = content
        self.savedAt = savedAt
    }

    var chapterLabel: String {
        "第 \(chapterNumber) 章"
    }

    var chapterSummary: String {
        "\(chapterLabel) · \(chapterTitle)"
    }

    var wordCount: Int {
        content
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }

    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }

    nonisolated static func sortDescending(_ lhs: ChapterDraft, _ rhs: ChapterDraft) -> Bool {
        if lhs.chapterNumber == rhs.chapterNumber {
            return lhs.savedAt > rhs.savedAt
        }

        return lhs.chapterNumber > rhs.chapterNumber
    }
}

struct OutlineGenerationProfile: Codable, Hashable {
    var storyFlow: String
    var worldDescription: String
    var protagonistTraits: String
    var expectedLength: String
    var endingPreference: String
    var sellingPoints: String
    var keyEvents: String
    var storyPacing: String
    var motivations: String
    var relationshipMap: String
    var antagonistPortrait: String
    var foreshadowingNotes: String

    static let empty = OutlineGenerationProfile(
        storyFlow: "",
        worldDescription: "",
        protagonistTraits: "",
        expectedLength: "",
        endingPreference: "",
        sellingPoints: "",
        keyEvents: "",
        storyPacing: "",
        motivations: "",
        relationshipMap: "",
        antagonistPortrait: "",
        foreshadowingNotes: ""
    )

    var completedRequiredFieldCount: Int {
        [
            storyFlow,
            worldDescription,
            protagonistTraits,
            expectedLength,
            endingPreference
        ]
        .filter { Self.hasContent($0) }
        .count
    }

    var filledOptionalFieldCount: Int {
        [
            sellingPoints,
            keyEvents,
            storyPacing,
            motivations,
            relationshipMap,
            antagonistPortrait,
            foreshadowingNotes
        ]
        .filter { Self.hasContent($0) }
        .count
    }

    var missingRequiredFieldLabels: [String] {
        var labels: [String] = []

        if !Self.hasContent(storyFlow) {
            labels.append("总体流程")
        }

        if !Self.hasContent(worldDescription) {
            labels.append("世界观描述")
        }

        if !Self.hasContent(protagonistTraits) {
            labels.append("主角性格标签")
        }

        if !Self.hasContent(expectedLength) {
            labels.append("预期字数")
        }

        if !Self.hasContent(endingPreference) {
            labels.append("结局偏好")
        }

        return labels
    }

    var hasMinimumRequirements: Bool {
        missingRequiredFieldLabels.isEmpty
    }

    var minimumRequirementSummary: String {
        if hasMinimumRequirements {
            return "最简可用的 5 项已准备完成，可以直接生成大纲。"
        }

        return "还差 \(missingRequiredFieldLabels.joined(separator: "、"))。"
    }

    private static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GlobalMemorySnapshot: Codable, Hashable {
    enum Section: String, CaseIterable {
        case recentDevelopments = "前情推进"
        case characterRelations = "人物关系"
        case identityChanges = "身份变化"
        case injuries = "伤势状态"
        case factions = "阵营立场"
        case locations = "关键地点"
        case items = "关键道具"
        case worldState = "世界状态"
        case unresolvedForeshadowing = "未回收伏笔"
    }

    var recentDevelopments: String
    var characterRelations: String
    var identityChanges: String
    var injuries: String
    var factions: String
    var locations: String
    var items: String
    var worldState: String
    var unresolvedForeshadowing: String

    static let empty = GlobalMemorySnapshot(
        recentDevelopments: "",
        characterRelations: "",
        identityChanges: "",
        injuries: "",
        factions: "",
        locations: "",
        items: "",
        worldState: "",
        unresolvedForeshadowing: ""
    )

    var populatedSectionCount: Int {
        Section.allCases
            .map(value(for:))
            .filter { Self.hasContent($0) }
            .count
    }

    var hasStructuredContent: Bool {
        populatedSectionCount > 0
    }

    var formattedText: String {
        Section.allCases
            .map { section in
                "\(section.rawValue)：\n\(formattedValue(for: section))"
            }
            .joined(separator: "\n\n")
    }

    func value(for section: Section) -> String {
        switch section {
        case .recentDevelopments:
            return recentDevelopments
        case .characterRelations:
            return characterRelations
        case .identityChanges:
            return identityChanges
        case .injuries:
            return injuries
        case .factions:
            return factions
        case .locations:
            return locations
        case .items:
            return items
        case .worldState:
            return worldState
        case .unresolvedForeshadowing:
            return unresolvedForeshadowing
        }
    }

    mutating func setValue(_ value: String, for section: Section) {
        switch section {
        case .recentDevelopments:
            recentDevelopments = value
        case .characterRelations:
            characterRelations = value
        case .identityChanges:
            identityChanges = value
        case .injuries:
            injuries = value
        case .factions:
            factions = value
        case .locations:
            locations = value
        case .items:
            items = value
        case .worldState:
            worldState = value
        case .unresolvedForeshadowing:
            unresolvedForeshadowing = value
        }
    }

    static func parse(from text: String) -> GlobalMemorySnapshot {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return .empty }

        var snapshot = GlobalMemorySnapshot.empty
        var currentSection: Section?

        for rawLine in trimmedText.components(separatedBy: CharacterSet.newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let matchedSection = matchedSection(for: line) {
                currentSection = matchedSection
                let header = matchedSection.rawValue
                let remainder = line
                    .replacingOccurrences(of: header, with: "", options: [.anchored])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "：: "))

                if !remainder.isEmpty {
                    append(remainder, to: matchedSection, in: &snapshot)
                }

                continue
            }

            if let currentSection {
                append(line, to: currentSection, in: &snapshot)
            }
        }

        if !snapshot.hasStructuredContent {
            snapshot.recentDevelopments = trimmedText
        }

        return snapshot
    }

    private func formattedValue(for section: Section) -> String {
        let trimmed = value(for: section).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.placeholder(for: section) : trimmed
    }

    private static func append(_ line: String, to section: Section, in snapshot: inout GlobalMemorySnapshot) {
        let existing = snapshot.value(for: section).trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            snapshot.setValue(line, for: section)
        } else {
            snapshot.setValue(existing + "\n" + line, for: section)
        }
    }

    private static func matchedSection(for line: String) -> Section? {
        Section.allCases.first { section in
            line.hasPrefix(section.rawValue)
        }
    }

    private static func placeholder(for section: Section) -> String {
        switch section {
        case .recentDevelopments:
            return "- 待补当前长期记忆中的前情推进。"
        case .characterRelations:
            return "- 暂无人际关系的新变化。"
        case .identityChanges:
            return "- 暂无身份或立场变化。"
        case .injuries:
            return "- 暂无明确伤势变化。"
        case .factions:
            return "- 暂无阵营归属更新。"
        case .locations:
            return "- 暂无关键地点状态更新。"
        case .items:
            return "- 暂无关键道具变化。"
        case .worldState:
            return "- 暂无世界状态的新变化。"
        case .unresolvedForeshadowing:
            return "- 暂无新增待回收伏笔。"
        }
    }

    private static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct NovelProject: Identifiable, Codable {
    let id: String
    let title: String
    let genre: String
    let summary: String
    var storyLength: NovelLength
    var updatedAt: String
    var currentChapterTitle: String
    var currentChapterNumber: Int
    var writtenChapters: Int
    var chapterFocus: String
    var draftText: String
    var outlineText: String
    var outlineGenerationProfile: OutlineGenerationProfile
    var structureNotes: String
    var sceneProgressNotes: String
    var characterArcNotes: String
    var foreshadowNotes: String
    var volumePlanNotes: String
    var activeThreadsNotes: String
    var outlineSummary: String
    var outlineSummaryUpdatedAt: String
    var referenceContextText: String
    var specialRequirements: String
    var wordTargetText: String
    var continuityNotes: String
    var globalMemorySnapshot: GlobalMemorySnapshot
    var globalMemoryUpdatedAt: String
    var referenceDocuments: [ReferenceDocument]
    var chapterDrafts: [ChapterDraft]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case genre
        case summary
        case storyLength
        case updatedAt
        case currentChapterTitle
        case currentChapterNumber
        case writtenChapters
        case chapterFocus
        case draftText
        case outlineText
        case outlineGenerationProfile
        case structureNotes
        case sceneProgressNotes
        case characterArcNotes
        case foreshadowNotes
        case volumePlanNotes
        case activeThreadsNotes
        case outlineSummary
        case outlineSummaryUpdatedAt
        case referenceContextText
        case specialRequirements
        case wordTargetText
        case continuityNotes
        case globalMemorySnapshot
        case globalMemoryUpdatedAt
        case referenceDocuments
        case chapterDrafts
        case chapters
    }

    init(
        id: String,
        title: String,
        genre: String,
        summary: String,
        storyLength: NovelLength = .long,
        updatedAt: String,
        currentChapterTitle: String,
        currentChapterNumber: Int,
        writtenChapters: Int,
        chapterFocus: String,
        draftText: String,
        outlineText: String,
        outlineGenerationProfile: OutlineGenerationProfile = .empty,
        structureNotes: String = "",
        sceneProgressNotes: String = "",
        characterArcNotes: String = "",
        foreshadowNotes: String = "",
        volumePlanNotes: String = "",
        activeThreadsNotes: String = "",
        outlineSummary: String = "",
        outlineSummaryUpdatedAt: String = "",
        referenceContextText: String,
        specialRequirements: String,
        wordTargetText: String,
        continuityNotes: String,
        globalMemorySnapshot: GlobalMemorySnapshot = .empty,
        globalMemoryUpdatedAt: String = "",
        referenceDocuments: [ReferenceDocument],
        chapterDrafts: [ChapterDraft] = []
    ) {
        self.id = id
        self.title = title
        self.genre = genre
        self.summary = summary
        self.storyLength = storyLength
        self.updatedAt = updatedAt
        self.currentChapterTitle = currentChapterTitle
        self.currentChapterNumber = currentChapterNumber
        self.writtenChapters = writtenChapters
        self.chapterFocus = chapterFocus
        self.draftText = draftText
        self.outlineText = outlineText
        self.outlineGenerationProfile = outlineGenerationProfile
        self.structureNotes = structureNotes
        self.sceneProgressNotes = sceneProgressNotes
        self.characterArcNotes = characterArcNotes
        self.foreshadowNotes = foreshadowNotes
        self.volumePlanNotes = volumePlanNotes
        self.activeThreadsNotes = activeThreadsNotes
        self.outlineSummary = outlineSummary
        self.outlineSummaryUpdatedAt = outlineSummaryUpdatedAt
        self.referenceContextText = referenceContextText
        self.specialRequirements = specialRequirements
        self.wordTargetText = wordTargetText
        self.continuityNotes = continuityNotes
        let normalizedGlobalMemory = globalMemorySnapshot.hasStructuredContent
            ? globalMemorySnapshot
            : GlobalMemorySnapshot.parse(from: continuityNotes)
        self.globalMemorySnapshot = normalizedGlobalMemory
        self.globalMemoryUpdatedAt = globalMemoryUpdatedAt
        self.referenceDocuments = referenceDocuments
        self.chapterDrafts = chapterDrafts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        genre = try container.decode(String.self, forKey: .genre)
        summary = try container.decode(String.self, forKey: .summary)
        storyLength = try container.decodeIfPresent(NovelLength.self, forKey: .storyLength) ?? .long
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        currentChapterTitle = try container.decodeIfPresent(String.self, forKey: .currentChapterTitle) ?? "开篇设定"
        currentChapterNumber = try container.decodeIfPresent(Int.self, forKey: .currentChapterNumber) ?? 1
        writtenChapters = try container.decodeIfPresent(Int.self, forKey: .writtenChapters)
            ?? container.decodeIfPresent(Int.self, forKey: .chapters)
            ?? max(currentChapterNumber, 1)
        chapterFocus = try container.decodeIfPresent(String.self, forKey: .chapterFocus)
            ?? "继续补齐当前章节的目标、冲突和场景节奏。"
        draftText = try container.decodeIfPresent(String.self, forKey: .draftText) ?? ""
        outlineText = try container.decodeIfPresent(String.self, forKey: .outlineText) ?? ""
        outlineGenerationProfile = try container.decodeIfPresent(OutlineGenerationProfile.self, forKey: .outlineGenerationProfile) ?? .empty
        structureNotes = try container.decodeIfPresent(String.self, forKey: .structureNotes) ?? ""
        sceneProgressNotes = try container.decodeIfPresent(String.self, forKey: .sceneProgressNotes) ?? ""
        characterArcNotes = try container.decodeIfPresent(String.self, forKey: .characterArcNotes) ?? ""
        foreshadowNotes = try container.decodeIfPresent(String.self, forKey: .foreshadowNotes) ?? ""
        volumePlanNotes = try container.decodeIfPresent(String.self, forKey: .volumePlanNotes) ?? ""
        activeThreadsNotes = try container.decodeIfPresent(String.self, forKey: .activeThreadsNotes) ?? ""
        outlineSummary = try container.decodeIfPresent(String.self, forKey: .outlineSummary) ?? ""
        outlineSummaryUpdatedAt = try container.decodeIfPresent(String.self, forKey: .outlineSummaryUpdatedAt) ?? ""
        referenceContextText = try container.decodeIfPresent(String.self, forKey: .referenceContextText) ?? ""
        specialRequirements = try container.decodeIfPresent(String.self, forKey: .specialRequirements) ?? ""
        wordTargetText = try container.decodeIfPresent(String.self, forKey: .wordTargetText) ?? ""
        continuityNotes = try container.decodeIfPresent(String.self, forKey: .continuityNotes) ?? ""
        globalMemorySnapshot = try container.decodeIfPresent(GlobalMemorySnapshot.self, forKey: .globalMemorySnapshot)
            ?? GlobalMemorySnapshot.parse(from: continuityNotes)
        globalMemoryUpdatedAt = try container.decodeIfPresent(String.self, forKey: .globalMemoryUpdatedAt) ?? ""
        referenceDocuments = try container.decodeIfPresent([ReferenceDocument].self, forKey: .referenceDocuments) ?? []
        chapterDrafts = try container.decodeIfPresent([ChapterDraft].self, forKey: .chapterDrafts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(genre, forKey: .genre)
        try container.encode(summary, forKey: .summary)
        try container.encode(storyLength, forKey: .storyLength)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(currentChapterTitle, forKey: .currentChapterTitle)
        try container.encode(currentChapterNumber, forKey: .currentChapterNumber)
        try container.encode(writtenChapters, forKey: .writtenChapters)
        try container.encode(chapterFocus, forKey: .chapterFocus)
        try container.encode(draftText, forKey: .draftText)
        try container.encode(outlineText, forKey: .outlineText)
        try container.encode(outlineGenerationProfile, forKey: .outlineGenerationProfile)
        try container.encode(structureNotes, forKey: .structureNotes)
        try container.encode(sceneProgressNotes, forKey: .sceneProgressNotes)
        try container.encode(characterArcNotes, forKey: .characterArcNotes)
        try container.encode(foreshadowNotes, forKey: .foreshadowNotes)
        try container.encode(volumePlanNotes, forKey: .volumePlanNotes)
        try container.encode(activeThreadsNotes, forKey: .activeThreadsNotes)
        try container.encode(outlineSummary, forKey: .outlineSummary)
        try container.encode(outlineSummaryUpdatedAt, forKey: .outlineSummaryUpdatedAt)
        try container.encode(referenceContextText, forKey: .referenceContextText)
        try container.encode(specialRequirements, forKey: .specialRequirements)
        try container.encode(wordTargetText, forKey: .wordTargetText)
        try container.encode(continuityNotes, forKey: .continuityNotes)
        try container.encode(globalMemorySnapshot, forKey: .globalMemorySnapshot)
        try container.encode(globalMemoryUpdatedAt, forKey: .globalMemoryUpdatedAt)
        try container.encode(referenceDocuments, forKey: .referenceDocuments)
        try container.encode(chapterDrafts, forKey: .chapterDrafts)
    }

    var currentChapterLabel: String {
        "第 \(currentChapterNumber) 章"
    }

    var currentChapterSummary: String {
        "\(currentChapterLabel) · \(currentChapterTitle)"
    }

    var storyLengthTitle: String {
        storyLength.title
    }

    var savedChapterCount: Int {
        chapterDrafts.count
    }

    var sortedChapterDrafts: [ChapterDraft] {
        chapterDrafts.sorted(by: ChapterDraft.sortDescending)
    }

    var hasSavedCurrentChapter: Bool {
        chapterDrafts.contains(where: { $0.chapterNumber == currentChapterNumber })
    }

    var materialCategoriesWithContent: [ReferenceMaterialCategory] {
        ReferenceMaterialCategory.allCases.filter { category in
            referenceDocuments.contains(where: { $0.category == category })
        }
    }

    func referenceDocuments(in category: ReferenceMaterialCategory) -> [ReferenceDocument] {
        referenceDocuments.filter { $0.category == category }
    }

    var hasOutline: Bool {
        !outlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasStructureNotes: Bool {
        !structureNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSceneProgressNotes: Bool {
        !sceneProgressNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCharacterArcNotes: Bool {
        !characterArcNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasForeshadowNotes: Bool {
        !foreshadowNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasVolumePlanNotes: Bool {
        !volumePlanNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasActiveThreadsNotes: Bool {
        !activeThreadsNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasContinuityNotes: Bool {
        !continuityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasGlobalMemory: Bool {
        hasContinuityNotes || globalMemorySnapshot.hasStructuredContent
    }

    var hasOutlineSummary: Bool {
        !outlineSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var outlineStatusLabel: String {
        hasOutline ? "已导入" : "待补充"
    }

    var structureStatusLabel: String {
        hasStructureNotes ? "\(structureNodeCount) 节点" : "待拆分"
    }

    var sceneProgressStatusLabel: String {
        hasSceneProgressNotes ? "\(sceneProgressNodeCount) 场景" : "待拆分"
    }

    var characterArcStatusLabel: String {
        hasCharacterArcNotes ? "\(characterArcNodeCount) 条" : "待补充"
    }

    var foreshadowStatusLabel: String {
        hasForeshadowNotes ? "\(foreshadowNodeCount) 条" : "待标记"
    }

    var volumePlanStatusLabel: String {
        guard storyLength.supportsVolumePlanning else { return "非分卷模式" }
        return hasVolumePlanNotes ? "\(volumePlanNodeCount) 节点" : "待规划"
    }

    var activeThreadsStatusLabel: String {
        guard storyLength.supportsThreadTracking else { return "单篇闭环" }
        return hasActiveThreadsNotes ? "\(activeThreadNodeCount) 条" : "待记录"
    }

    var continuityStatusLabel: String {
        hasGlobalMemory ? "已记录" : "待补充"
    }

    var globalMemoryStatusLabel: String {
        hasGlobalMemory ? (globalMemoryUpdatedAt.isEmpty ? "已更新" : globalMemoryUpdatedAt) : "待生成"
    }

    var outlineSummaryStatusLabel: String {
        hasOutlineSummary ? (outlineSummaryUpdatedAt.isEmpty ? "已生成" : outlineSummaryUpdatedAt) : "待生成"
    }

    var referenceStatusLabel: String {
        referenceDocuments.isEmpty ? "未导入" : "\(referenceDocuments.count) 份"
    }

    var structureNodeCount: Int {
        Self.outlineNodeCount(in: hasStructureNotes ? structureNotes : outlineText)
    }

    var sceneProgressNodeCount: Int {
        Self.outlineNodeCount(in: sceneProgressNotes)
    }

    var characterArcNodeCount: Int {
        Self.outlineNodeCount(in: characterArcNotes)
    }

    var foreshadowNodeCount: Int {
        Self.outlineNodeCount(in: foreshadowNotes)
    }

    var volumePlanNodeCount: Int {
        Self.outlineNodeCount(in: volumePlanNotes)
    }

    var activeThreadNodeCount: Int {
        Self.outlineNodeCount(in: activeThreadsNotes)
    }

    var draftWordCount: Int {
        draftText
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }

    var draftParagraphCount: Int {
        let paragraphs = draftText
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.count
    }

    var draftPreview: String {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "正文还没有展开，可以先写下当前场景的起笔句。" }
        guard trimmed.count > 120 else { return trimmed }
        return String(trimmed.suffix(120))
    }

    var draftContinuationCache: String {
        let source = previousChapterDraftForContinuation?.content ?? ""
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > 400 else { return trimmed }
        return String(trimmed.suffix(400))
    }

    var draftContinuationCacheCount: Int {
        draftContinuationCache.count
    }

    var previousChapterDraftForContinuation: ChapterDraft? {
        let sortedDrafts = sortedChapterDrafts

        if let directPrevious = sortedDrafts.first(where: { $0.chapterNumber == currentChapterNumber - 1 }) {
            return directPrevious
        }

        return sortedDrafts
            .filter { $0.chapterNumber < currentChapterNumber }
            .max { $0.chapterNumber < $1.chapterNumber }
    }

    private static func outlineNodeCount(in text: String) -> Int {
        text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }
}

struct ReferenceDocument: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let content: String
    let importedAt: String
    var category: ReferenceMaterialCategory

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case importedAt
        case category
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        importedAt: String,
        category: ReferenceMaterialCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.importedAt = importedAt
        self.category = category ?? ReferenceMaterialCategory.infer(fromTitle: title, content: content)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        importedAt = try container.decode(String.self, forKey: .importedAt)
        category = try container.decodeIfPresent(ReferenceMaterialCategory.self, forKey: .category)
            ?? ReferenceMaterialCategory.infer(fromTitle: title, content: content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(importedAt, forKey: .importedAt)
        try container.encode(category, forKey: .category)
    }

    var wordCount: Int {
        content
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }

    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 140 else { return trimmed }
        return String(trimmed.prefix(140)) + "…"
    }
}

enum ReferenceMaterialCategory: String, CaseIterable, Codable, Identifiable {
    case character
    case location
    case organization
    case worldbuilding
    case plot
    case research
    case reference

    var id: Self { self }

    var title: String {
        switch self {
        case .character:
            return "人物"
        case .location:
            return "地点"
        case .organization:
            return "组织"
        case .worldbuilding:
            return "世界观"
        case .plot:
            return "剧情"
        case .research:
            return "考据"
        case .reference:
            return "参考"
        }
    }

    var symbolName: String {
        switch self {
        case .character:
            return "person.crop.circle"
        case .location:
            return "map"
        case .organization:
            return "building.2"
        case .worldbuilding:
            return "globe.asia.australia"
        case .plot:
            return "timeline.selection"
        case .research:
            return "magnifyingglass"
        case .reference:
            return "book.closed"
        }
    }

    var summary: String {
        switch self {
        case .character:
            return "角色设定、关系卡、人物小传"
        case .location:
            return "地点、地图、场景空间信息"
        case .organization:
            return "组织、家族、阵营与势力资料"
        case .worldbuilding:
            return "世界规则、历史、制度与背景"
        case .plot:
            return "剧情节点、大纲补充与场景草案"
        case .research:
            return "考据、资料摘录与外部研究"
        case .reference:
            return "风格参考与暂未细分的素材"
        }
    }

    static func infer(fromTitle title: String, content: String) -> ReferenceMaterialCategory {
        let source = "\(title)\n\(content)".lowercased()

        if source.contains(anyOf: ["角色", "人物", "主角", "配角", "反派", "小传", "关系"]) {
            return .character
        }

        if source.contains(anyOf: ["地点", "地图", "城市", "港口", "山脉", "村", "街区", "场景"]) {
            return .location
        }

        if source.contains(anyOf: ["组织", "家族", "阵营", "公司", "宗门", "议会", "协会"]) {
            return .organization
        }

        if source.contains(anyOf: ["世界观", "设定", "规则", "历史", "神话", "纪年", "文明"]) {
            return .worldbuilding
        }

        if source.contains(anyOf: ["剧情", "大纲", "章节", "场景推进", "转折", "主线", "支线"]) {
            return .plot
        }

        if source.contains(anyOf: ["资料", "考据", "研究", "参考文献", "访谈", "历史原型"]) {
            return .research
        }

        return .reference
    }
}

struct StoryPillar: Identifiable {
    let title: String
    let detail: String

    var id: String { title }
}

struct InspirationSignal: Identifiable {
    let title: String
    let description: String

    var id: String { title }
}

private extension String {
    func contains(anyOf keywords: [String]) -> Bool {
        keywords.contains(where: { contains($0.lowercased()) })
    }
}
