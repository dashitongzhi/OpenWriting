import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppState {
    private enum StorageKey {
        static let selectedProvider = "OpenWriting.selectedProvider"
        static let modelName = "OpenWriting.modelName"
        static let baseURL = "OpenWriting.baseURL"
        static let autoValidateOnLaunch = "OpenWriting.autoValidateOnLaunch"
        static let showWritingDeskCachePanel = "OpenWriting.showWritingDeskCachePanel"
        static let showWritingDeskTimeline = "OpenWriting.showWritingDeskTimeline"
        static let activeProjectID = "OpenWriting.activeProjectID"
        static let recentProjects = "OpenWriting.recentProjects"
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

    private enum KeychainKey {
        static let service = "OpenWriting.ModelConnection"
        static let account = "apiKey"
    }

    private enum LegacyKeychainKey {
        static let service = ("Open" + "Reading") + ".ModelConnection"
        static let account = "apiKey"
    }

    private static let emptyConfigurationMessage = "填入 API Key 与 Base URL 后即可验证。"

    private let userDefaults: UserDefaults

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
        }
    }

    var recentProjects: [NovelProject] {
        didSet {
            persistRecentProjects()
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
        ),
        StoryPillar(
            title: "模型协作",
            detail: "为设定补完、风格延展、对白优化分别准备独立提示工作流。"
        )
    ]

    let inspirationSignals: [InspirationSignal] = [
        InspirationSignal(title: "人物关系图", description: "适合先搭冲突，再落章节。"),
        InspirationSignal(title: "世界观卡片", description: "把地点、组织和规则集中收纳。"),
        InspirationSignal(title: "章节节奏盘", description: "观察高潮、低潮与信息释放的密度。")
    ]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.selectedProvider = ModelProvider(
            rawValue: Self.stringValue(
                forKey: StorageKey.selectedProvider,
                legacyKey: LegacyStorageKey.selectedProvider,
                userDefaults: userDefaults
            ) ?? ""
        ) ?? .openAICompatible
        self.modelName = Self.stringValue(
            forKey: StorageKey.modelName,
            legacyKey: LegacyStorageKey.modelName,
            userDefaults: userDefaults
        ) ?? "gpt-4.1-mini"
        self.apiKey = Self.loadAPIKeyFromKeychain() ?? ""
        self.baseURL = Self.stringValue(
            forKey: StorageKey.baseURL,
            legacyKey: LegacyStorageKey.baseURL,
            userDefaults: userDefaults
        ) ?? "https://api.openai.com/v1"
        self.autoValidateOnLaunch = Self.boolValue(
            forKey: StorageKey.autoValidateOnLaunch,
            legacyKey: LegacyStorageKey.autoValidateOnLaunch,
            userDefaults: userDefaults
        ) ?? true
        self.showWritingDeskCachePanel = Self.boolValue(
            forKey: StorageKey.showWritingDeskCachePanel,
            legacyKey: LegacyStorageKey.showWritingDeskCachePanel,
            userDefaults: userDefaults
        ) ?? true
        self.showWritingDeskTimeline = Self.boolValue(
            forKey: StorageKey.showWritingDeskTimeline,
            legacyKey: LegacyStorageKey.showWritingDeskTimeline,
            userDefaults: userDefaults
        ) ?? true
        self.recentProjects = Self.loadRecentProjects(from: userDefaults) ?? Self.defaultRecentProjects
        self.connectionStatus = .idle
        self.validationMessage = Self.emptyConfigurationMessage
        self.activeProjectID = Self.stringValue(
            forKey: StorageKey.activeProjectID,
            legacyKey: LegacyStorageKey.activeProjectID,
            userDefaults: userDefaults
        )
        self.selectedProjectID = Self.stringValue(
            forKey: StorageKey.activeProjectID,
            legacyKey: LegacyStorageKey.activeProjectID,
            userDefaults: userDefaults
        )

        normalizeProjectSelection()

        if autoValidateOnLaunch, hasEnteredConnectionInfo {
            validateConfiguration()
        } else {
            refreshIdleValidationMessage()
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

    func createProject(named title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectTitle = trimmedTitle.isEmpty ? "未命名计划" : trimmedTitle
        let draftProject = NovelProject(
            id: makeProjectIdentifier(from: projectTitle),
            title: projectTitle,
            genre: "待设定",
            summary: "从一句 logline 开始，继续补齐角色目标、核心冲突和三幕结构。",
            updatedAt: Self.currentTimestampLabel(),
            currentChapterTitle: "开篇设定",
            currentChapterNumber: 1,
            writtenChapters: 1,
            chapterFocus: "先写出开篇场景的情绪、主角目标和第一个冲突钩子。",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "例如：本章 1800-2200 字；全书约 80 万字；关键情节可上浮 20%",
            continuityNotes: "先把主角动机、冲突来源和章节语气稳定下来，再逐步扩展世界观。",
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

    func openPrompts() {
        selectedSidebarItem = .prompts
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
        case .prompts:
            openPrompts()
        }
    }

    func selectProject(_ projectID: NovelProject.ID) {
        activeProjectID = projectID
        selectedProjectID = projectID
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

    func updateContinuityNotes(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.continuityNotes = text
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

    func appendOutlineSummaryToContinuity(for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            let summary = project.outlineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return }

            let stampedSummary = "章节树总结（\(project.outlineSummaryUpdatedAt.isEmpty ? Self.currentTimestampLabel() : project.outlineSummaryUpdatedAt)）\n\(summary)"
            if project.continuityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project.continuityNotes = stampedSummary
            } else {
                project.continuityNotes += "\n\n" + stampedSummary
            }

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
        case "模型协作":
            return .prompts
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
        if let activeProjectID {
            userDefaults.set(activeProjectID, forKey: StorageKey.activeProjectID)
        } else {
            userDefaults.removeObject(forKey: StorageKey.activeProjectID)
        }
    }

    private func persistRecentProjects() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(recentProjects) else { return }
        userDefaults.set(data, forKey: StorageKey.recentProjects)
    }

    private func updateProject(_ projectID: NovelProject.ID, mutate: (inout NovelProject) -> Void) {
        guard let index = recentProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var updatedProject = recentProjects[index]
        mutate(&updatedProject)
        recentProjects[index] = updatedProject
    }

    private func persistAPIKey() {
        let query = Self.apiKeyQuery
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            SecItemDelete(query as CFDictionary)
            SecItemDelete(Self.legacyAPIKeyQuery as CFDictionary)
            return
        }

        let encodedKey = Data(trimmedKey.utf8)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let attributes = [kSecValueData as String: encodedKey] as CFDictionary
            SecItemUpdate(query as CFDictionary, attributes)
            return
        }

        var newItem = query
        newItem[kSecValueData as String] = encodedKey
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(newItem as CFDictionary, nil)
    }

    private static var apiKeyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: KeychainKey.account
        ]
    }

    private static var legacyAPIKeyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LegacyKeychainKey.service,
            kSecAttrAccount as String: LegacyKeychainKey.account
        ]
    }

    private static func loadAPIKeyFromKeychain() -> String? {
        loadAPIKey(using: apiKeyQuery) ?? loadAPIKey(using: legacyAPIKeyQuery)
    }

    private static func loadRecentProjects(from userDefaults: UserDefaults) -> [NovelProject]? {
        guard let data = dataValue(
            forKey: StorageKey.recentProjects,
            legacyKey: LegacyStorageKey.recentProjects,
            userDefaults: userDefaults
        ) else {
            return nil
        }

        return try? JSONDecoder().decode([NovelProject].self, from: data)
    }

    private static func stringValue(forKey key: String, legacyKey: String, userDefaults: UserDefaults) -> String? {
        userDefaults.string(forKey: key) ?? userDefaults.string(forKey: legacyKey)
    }

    private static func boolValue(forKey key: String, legacyKey: String, userDefaults: UserDefaults) -> Bool? {
        if let value = userDefaults.object(forKey: key) as? Bool {
            return value
        }

        return userDefaults.object(forKey: legacyKey) as? Bool
    }

    private static func dataValue(forKey key: String, legacyKey: String, userDefaults: UserDefaults) -> Data? {
        userDefaults.data(forKey: key) ?? userDefaults.data(forKey: legacyKey)
    }

    private static func loadAPIKey(using query: [String: Any]) -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard
            status == errSecSuccess,
            let data = item as? Data,
            let apiKey = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return apiKey
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

    private static let defaultRecentProjects: [NovelProject] = [
        NovelProject(
            id: "fog-harbor-chronicle",
            title: "雾港纪事",
            genre: "海港悬疑",
            summary: "一座被潮汐与钟楼控制节奏的城市，正在吞没每个说谎的人。",
            updatedAt: "今天 18:20",
            currentChapterTitle: "钟楼退潮",
            currentChapterNumber: 18,
            writtenChapters: 18,
            chapterFocus: "让主角在钟楼退潮的片刻发现新的证词，并把港口谎言与失踪案并到同一条线索里。",
            draftText: "钟楼的钟声在退潮前第三次敲响，雾像一张被谁悄悄掀开的幕布，沿着码头的木板一层层退开。\n\n顾临站在潮痕线外，靴底沾着盐粒。她知道这座城总在钟声之后说真话，但真话从不完整。今天留下来的，是一枚被海水反复冲刷却还带着体温的铜纽扣。\n\n她把纽扣放进掌心，抬头望向钟楼。那扇面朝港口的小窗刚刚关上，像有人在她看见之前，先一步把秘密收了回去。",
            outlineText: "第一卷：港雾与钟楼\n1. 失踪案在退潮夜启动\n2. 顾临发现钟楼与谎言节律有关\n3. 港务局、钟楼守夜人和失踪名单逐渐并线\n4. 第一卷结尾揭开钟楼记录真话的方式",
            structureNotes: "第一卷：港雾与钟楼\n第 16 章：潮位异常第一次被公开提起\n第 17 章：港务局旧档案出现缺页\n第 18 章：铜纽扣与守夜人证词并线\n第 19 章：守夜人身份与钟楼记录方式反转",
            sceneProgressNotes: "1. 开场先让顾临确认退潮时钟楼异常静止\n2. 中段让铜纽扣和旧证词对上时间差\n3. 结尾把视线抛向钟楼小窗后的守夜人",
            characterArcNotes: "顾临：从冷静观察转向主动试探港务局\n守夜人：表面沉默，内里开始暴露防御性\n港务局记录员：从旁观配合转向刻意遮掩",
            foreshadowNotes: "铜纽扣：第 18 章出现，第 21 章对应失踪名单\n钟楼缺页：第 17 章露头，第 19 章解释来源\n港口谎言节律：第一卷末尾回收到钟声记录机制",
            outlineSummary: "当前结构判断：第一卷已经把“潮汐、钟楼、失踪案”三条线并到同一节奏里，结构重心很稳。第 18 章的位置适合作为中段证词翻面的节点，需要继续把线索导向守夜人。\n\n本章推进建议：先让顾临确认退潮异常，再把铜纽扣与旧证词做一次并线。结尾不要一次性揭露守夜人真相，只给出足以推动下一章追查的缺口。\n\n角色弧线提醒：顾临正在从观察者转向行动者，这一步需要在本章体现。守夜人不能过早露出底牌，要让他的防御感先于真相出现。\n\n伏笔与回收：铜纽扣和钟楼缺页都已经具备继续回收的条件，但仍要保留一层解释延迟。港口谎言节律要继续通过钟声和潮位间接提示。\n\n下一步整理动作：继续补第 19 到 21 章的节点关系，明确守夜人与港务局的连接，再把第一卷结尾的揭示顺序写清。",
            outlineSummaryUpdatedAt: "今天 18:26",
            referenceContextText: "保持海雾、潮声、金属与钟楼的意象，风格克制、悬疑感慢慢推进。",
            specialRequirements: "不要让线索一次性说透，继续保留港口谎言的回声感。",
            wordTargetText: "本章建议 1800-2200 字，重点放在证词出现与线索并线。",
            continuityNotes: "顾临说话克制、观察敏锐，不轻易下判断。海港城市本身像有生命的旁观者，叙事要保留潮湿、冷白和金属感。",
            referenceDocuments: [
                ReferenceDocument(title: "港口气氛参考", content: "海雾、潮声、木栈桥与铜钟的意象要反复出现，让城市像一座会呼吸的谜宫。", importedAt: "示例素材")
            ]
        ),
        NovelProject(
            id: "glass-mountain-letters",
            title: "玻璃山来信",
            genre: "成长奇幻",
            summary: "失忆的制图师追查一封寄给未来自己的信，逐渐拼回山脉的真实形状。",
            updatedAt: "昨天 21:40",
            currentChapterTitle: "向玻璃山回信",
            currentChapterNumber: 9,
            writtenChapters: 9,
            chapterFocus: "把“未来来信”的内容和制图师记忆缺口对应起来，推进她上山的决定。",
            draftText: "信纸在灯下泛出很浅的银光，像山脊上的雪线。陆遥盯着最后那句“请在山雾到来之前回信”，忽然意识到这不是提醒，而像一次迟到多年的邀请。\n\n她摊开地图，把自己重新标在玻璃山以南的旧驿站。那里明明早该废弃，却在信封背面的速写里，被画成一座仍有人居住的小屋。",
            outlineText: "第一幕：收到未来来信并确认地图异常\n第二幕：沿着旧驿站与山径上行，逐步恢复记忆\n第三幕：在玻璃山顶完成回信，也理解山脉真实形状",
            structureNotes: "第一幕：来信触发上山动机\n第 7 章：确认旧驿站仍有人居住\n第 8 章：地图坐标出现偏移\n第 9 章：回信决定正式成立\n第 10 章：进入山路并恢复第一段记忆",
            sceneProgressNotes: "1. 先对照来信和旧地图差异\n2. 再让陆遥确认驿站位置仍在使用\n3. 结尾落到“必须上山”这一决定",
            characterArcNotes: "陆遥：从迟疑观察转向主动回应未来自己\n未来来信的‘她’：保持神秘，但要让语气显出熟悉感",
            foreshadowNotes: "旧驿站灯光：第 9 章看见，第 11 章解释是谁点亮\n地图偏移：第 8 章出现，第 10 章成为上山依据",
            referenceContextText: "保持玻璃、雪线和失真地图的视觉感，句子可稍微更轻更空灵。",
            specialRequirements: "让记忆恢复通过景物和动作显现，不要直接解释。",
            wordTargetText: "本章建议 1600-2000 字，推进上山决定即可。",
            continuityNotes: "文本要有玻璃、雪线和失真地图的视觉感。陆遥偏内省，情绪波动要通过景物和动作慢慢显出来。",
            referenceDocuments: [
                ReferenceDocument(title: "山脉意象参考", content: "玻璃山的质感像被风吹亮的冰层，远看透明，近看却遍布细密裂纹。", importedAt: "示例素材")
            ]
        ),
        NovelProject(
            id: "zero-sunset",
            title: "零号日落",
            genre: "近未来科幻",
            summary: "当城市开始共享黄昏，主角必须在同一晚里做出三次不同的人生选择。",
            updatedAt: "周一 09:10",
            currentChapterTitle: "黄昏拷贝体",
            currentChapterNumber: 6,
            writtenChapters: 6,
            chapterFocus: "写清第一次见到“拷贝体”的震撼感，并让主角意识到今晚的选择会被重复三次。",
            draftText: "天边那道橘金色迟迟不肯沉下去，像有人把整座城按在同一秒里反复播放。沈渡在轻轨站台看见了第二个自己。\n\n那个人站在对面，衣角、姿势、甚至抬头看时间的动作都和他分毫不差。唯一不同的是，对方的手背上多了一道刚愈合的伤，像某个还没来得及发生在他身上的决定。",
            outlineText: "序章：共享黄昏开始覆盖整座城\n第一幕：沈渡发现时间复制现象\n第二幕：每次黄昏都会产生一个不同选择的自己\n第三幕：必须决定保留哪个版本的人生",
            structureNotes: "序章：共享黄昏的规则第一次出现\n第 4 章：城市开始出现同步停滞\n第 5 章：沈渡意识到选择会被复制\n第 6 章：第一次见到拷贝体\n第 7 章：规则验证与代价显形",
            sceneProgressNotes: "1. 先建立黄昏停滞的生理不适\n2. 再让沈渡和拷贝体形成镜面对视\n3. 结尾确认今晚的选择会被重复",
            characterArcNotes: "沈渡：理性压制恐惧，但身体反应先失控\n拷贝体：像被延迟执行的另一种选择，不要写得像纯反派",
            foreshadowNotes: "手背伤痕：第 6 章出现，第 8 章解释是哪次选择留下\n共享黄昏规则：第 4 章提出，第 7 章确认可复制三次",
            referenceContextText: "科技感要克制，把黄昏残影和轻轨金属光泽写得更冷一些。",
            specialRequirements: "优先强化第一次遇到拷贝体的生理反应和理性压制恐惧的矛盾。",
            wordTargetText: "本章建议 1800 字左右，重点是建立规则与惊异感。",
            continuityNotes: "城市科技感要克制，重点是时间错位带来的陌生和压迫。沈渡的第一反应是理性压制恐惧，但身体会先于语言暴露异常。",
            referenceDocuments: [
                ReferenceDocument(title: "近未来城市场景", content: "黄昏停留太久后，玻璃幕墙和轻轨金属边缘会出现像复制残影一样的重影。", importedAt: "示例素材")
            ]
        )
    ]
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

    static func sortDescending(_ lhs: ChapterDraft, _ rhs: ChapterDraft) -> Bool {
        if lhs.chapterNumber == rhs.chapterNumber {
            return lhs.savedAt > rhs.savedAt
        }

        return lhs.chapterNumber > rhs.chapterNumber
    }
}

struct NovelProject: Identifiable, Codable {
    let id: String
    let title: String
    let genre: String
    let summary: String
    var updatedAt: String
    var currentChapterTitle: String
    var currentChapterNumber: Int
    var writtenChapters: Int
    var chapterFocus: String
    var draftText: String
    var outlineText: String
    var structureNotes: String
    var sceneProgressNotes: String
    var characterArcNotes: String
    var foreshadowNotes: String
    var outlineSummary: String
    var outlineSummaryUpdatedAt: String
    var referenceContextText: String
    var specialRequirements: String
    var wordTargetText: String
    var continuityNotes: String
    var referenceDocuments: [ReferenceDocument]
    var chapterDrafts: [ChapterDraft]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case genre
        case summary
        case updatedAt
        case currentChapterTitle
        case currentChapterNumber
        case writtenChapters
        case chapterFocus
        case draftText
        case outlineText
        case structureNotes
        case sceneProgressNotes
        case characterArcNotes
        case foreshadowNotes
        case outlineSummary
        case outlineSummaryUpdatedAt
        case referenceContextText
        case specialRequirements
        case wordTargetText
        case continuityNotes
        case referenceDocuments
        case chapterDrafts
        case chapters
    }

    init(
        id: String,
        title: String,
        genre: String,
        summary: String,
        updatedAt: String,
        currentChapterTitle: String,
        currentChapterNumber: Int,
        writtenChapters: Int,
        chapterFocus: String,
        draftText: String,
        outlineText: String,
        structureNotes: String = "",
        sceneProgressNotes: String = "",
        characterArcNotes: String = "",
        foreshadowNotes: String = "",
        outlineSummary: String = "",
        outlineSummaryUpdatedAt: String = "",
        referenceContextText: String,
        specialRequirements: String,
        wordTargetText: String,
        continuityNotes: String,
        referenceDocuments: [ReferenceDocument],
        chapterDrafts: [ChapterDraft] = []
    ) {
        self.id = id
        self.title = title
        self.genre = genre
        self.summary = summary
        self.updatedAt = updatedAt
        self.currentChapterTitle = currentChapterTitle
        self.currentChapterNumber = currentChapterNumber
        self.writtenChapters = writtenChapters
        self.chapterFocus = chapterFocus
        self.draftText = draftText
        self.outlineText = outlineText
        self.structureNotes = structureNotes
        self.sceneProgressNotes = sceneProgressNotes
        self.characterArcNotes = characterArcNotes
        self.foreshadowNotes = foreshadowNotes
        self.outlineSummary = outlineSummary
        self.outlineSummaryUpdatedAt = outlineSummaryUpdatedAt
        self.referenceContextText = referenceContextText
        self.specialRequirements = specialRequirements
        self.wordTargetText = wordTargetText
        self.continuityNotes = continuityNotes
        self.referenceDocuments = referenceDocuments
        self.chapterDrafts = chapterDrafts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        genre = try container.decode(String.self, forKey: .genre)
        summary = try container.decode(String.self, forKey: .summary)
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
        structureNotes = try container.decodeIfPresent(String.self, forKey: .structureNotes) ?? ""
        sceneProgressNotes = try container.decodeIfPresent(String.self, forKey: .sceneProgressNotes) ?? ""
        characterArcNotes = try container.decodeIfPresent(String.self, forKey: .characterArcNotes) ?? ""
        foreshadowNotes = try container.decodeIfPresent(String.self, forKey: .foreshadowNotes) ?? ""
        outlineSummary = try container.decodeIfPresent(String.self, forKey: .outlineSummary) ?? ""
        outlineSummaryUpdatedAt = try container.decodeIfPresent(String.self, forKey: .outlineSummaryUpdatedAt) ?? ""
        referenceContextText = try container.decodeIfPresent(String.self, forKey: .referenceContextText) ?? ""
        specialRequirements = try container.decodeIfPresent(String.self, forKey: .specialRequirements) ?? ""
        wordTargetText = try container.decodeIfPresent(String.self, forKey: .wordTargetText) ?? ""
        continuityNotes = try container.decodeIfPresent(String.self, forKey: .continuityNotes) ?? ""
        referenceDocuments = try container.decodeIfPresent([ReferenceDocument].self, forKey: .referenceDocuments) ?? []
        chapterDrafts = try container.decodeIfPresent([ChapterDraft].self, forKey: .chapterDrafts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(genre, forKey: .genre)
        try container.encode(summary, forKey: .summary)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(currentChapterTitle, forKey: .currentChapterTitle)
        try container.encode(currentChapterNumber, forKey: .currentChapterNumber)
        try container.encode(writtenChapters, forKey: .writtenChapters)
        try container.encode(chapterFocus, forKey: .chapterFocus)
        try container.encode(draftText, forKey: .draftText)
        try container.encode(outlineText, forKey: .outlineText)
        try container.encode(structureNotes, forKey: .structureNotes)
        try container.encode(sceneProgressNotes, forKey: .sceneProgressNotes)
        try container.encode(characterArcNotes, forKey: .characterArcNotes)
        try container.encode(foreshadowNotes, forKey: .foreshadowNotes)
        try container.encode(outlineSummary, forKey: .outlineSummary)
        try container.encode(outlineSummaryUpdatedAt, forKey: .outlineSummaryUpdatedAt)
        try container.encode(referenceContextText, forKey: .referenceContextText)
        try container.encode(specialRequirements, forKey: .specialRequirements)
        try container.encode(wordTargetText, forKey: .wordTargetText)
        try container.encode(continuityNotes, forKey: .continuityNotes)
        try container.encode(referenceDocuments, forKey: .referenceDocuments)
        try container.encode(chapterDrafts, forKey: .chapterDrafts)
    }

    var currentChapterLabel: String {
        "第 \(currentChapterNumber) 章"
    }

    var currentChapterSummary: String {
        "\(currentChapterLabel) · \(currentChapterTitle)"
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

    var hasContinuityNotes: Bool {
        !continuityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    var continuityStatusLabel: String {
        hasContinuityNotes ? "已记录" : "待补充"
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

    init(id: String = UUID().uuidString, title: String, content: String, importedAt: String) {
        self.id = id
        self.title = title
        self.content = content
        self.importedAt = importedAt
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
