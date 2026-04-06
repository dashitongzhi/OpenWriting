import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppState {
    private enum StorageKey {
        static let selectedProvider = "OpenReading.selectedProvider"
        static let modelName = "OpenReading.modelName"
        static let baseURL = "OpenReading.baseURL"
        static let autoValidateOnLaunch = "OpenReading.autoValidateOnLaunch"
        static let showWritingDeskCachePanel = "OpenReading.showWritingDeskCachePanel"
        static let showWritingDeskTimeline = "OpenReading.showWritingDeskTimeline"
        static let activeProjectID = "OpenReading.activeProjectID"
        static let recentProjects = "OpenReading.recentProjects"
    }

    private enum KeychainKey {
        static let service = "OpenReading.ModelConnection"
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
            rawValue: userDefaults.string(forKey: StorageKey.selectedProvider) ?? ""
        ) ?? .openAICompatible
        self.modelName = userDefaults.string(forKey: StorageKey.modelName) ?? "gpt-4.1-mini"
        self.apiKey = Self.loadAPIKeyFromKeychain() ?? ""
        self.baseURL = userDefaults.string(forKey: StorageKey.baseURL) ?? "https://api.openai.com/v1"
        self.autoValidateOnLaunch = userDefaults.object(forKey: StorageKey.autoValidateOnLaunch) as? Bool ?? true
        self.showWritingDeskCachePanel = userDefaults.object(forKey: StorageKey.showWritingDeskCachePanel) as? Bool ?? true
        self.showWritingDeskTimeline = userDefaults.object(forKey: StorageKey.showWritingDeskTimeline) as? Bool ?? true
        self.recentProjects = Self.loadRecentProjects(from: userDefaults) ?? Self.defaultRecentProjects
        self.connectionStatus = .idle
        self.validationMessage = Self.emptyConfigurationMessage
        self.activeProjectID = userDefaults.string(forKey: StorageKey.activeProjectID)
        self.selectedProjectID = userDefaults.string(forKey: StorageKey.activeProjectID)

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
                detail: "多线并行创作"
            ),
            DashboardStat(title: "本月字数", value: "84k", detail: "含草稿与扩写"),
            DashboardStat(title: "提示词包", value: "18", detail: "角色与世界观模板")
        ]
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
        openProjectSpace(for: draftProject.id)
    }

    func continueWriting() {
        openWritingDesk(for: activeProject?.id ?? recentProjects.first?.id)
    }

    func openProjectSpace(for projectID: NovelProject.ID? = nil) {
        selectedSidebarItem = .projects

        let resolvedProjectID = projectID ?? activeProject?.id ?? recentProjects.first?.id
        guard let resolvedProjectID else { return }

        activeProjectID = resolvedProjectID
        selectedProjectID = resolvedProjectID
        projectSpaceScrollTarget = resolvedProjectID
        projectSpaceSelectionPulse += 1
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

    func selectProject(_ projectID: NovelProject.ID) {
        activeProjectID = projectID
        selectedProjectID = projectID
    }

    func updateDraftText(_ text: String, for projectID: NovelProject.ID) {
        updateProject(projectID) { project in
            project.draftText = text
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

    private static func loadAPIKeyFromKeychain() -> String? {
        var query = apiKeyQuery
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

    private static func loadRecentProjects(from userDefaults: UserDefaults) -> [NovelProject]? {
        guard let data = userDefaults.data(forKey: StorageKey.recentProjects) else {
            return nil
        }

        return try? JSONDecoder().decode([NovelProject].self, from: data)
    }

    private static func currentTimestampLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "今天 HH:mm"
        return formatter.string(from: Date())
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

    var id: String { title }
}

struct NovelProject: Identifiable, Codable {
    let id: String
    let title: String
    let genre: String
    let summary: String
    var updatedAt: String
    let currentChapterTitle: String
    let currentChapterNumber: Int
    let writtenChapters: Int
    var chapterFocus: String
    var draftText: String
    var outlineText: String
    var referenceContextText: String
    var specialRequirements: String
    var wordTargetText: String
    var continuityNotes: String
    var referenceDocuments: [ReferenceDocument]

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
        case referenceContextText
        case specialRequirements
        case wordTargetText
        case continuityNotes
        case referenceDocuments
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
        referenceContextText: String,
        specialRequirements: String,
        wordTargetText: String,
        continuityNotes: String,
        referenceDocuments: [ReferenceDocument]
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
        self.referenceContextText = referenceContextText
        self.specialRequirements = specialRequirements
        self.wordTargetText = wordTargetText
        self.continuityNotes = continuityNotes
        self.referenceDocuments = referenceDocuments
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
        referenceContextText = try container.decodeIfPresent(String.self, forKey: .referenceContextText) ?? ""
        specialRequirements = try container.decodeIfPresent(String.self, forKey: .specialRequirements) ?? ""
        wordTargetText = try container.decodeIfPresent(String.self, forKey: .wordTargetText) ?? ""
        continuityNotes = try container.decodeIfPresent(String.self, forKey: .continuityNotes) ?? ""
        referenceDocuments = try container.decodeIfPresent([ReferenceDocument].self, forKey: .referenceDocuments) ?? []
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
        try container.encode(referenceContextText, forKey: .referenceContextText)
        try container.encode(specialRequirements, forKey: .specialRequirements)
        try container.encode(wordTargetText, forKey: .wordTargetText)
        try container.encode(continuityNotes, forKey: .continuityNotes)
        try container.encode(referenceDocuments, forKey: .referenceDocuments)
    }

    var currentChapterLabel: String {
        "第 \(currentChapterNumber) 章"
    }

    var currentChapterSummary: String {
        "\(currentChapterLabel) · \(currentChapterTitle)"
    }

    var hasOutline: Bool {
        !outlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasContinuityNotes: Bool {
        !continuityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var outlineStatusLabel: String {
        hasOutline ? "已导入" : "待补充"
    }

    var continuityStatusLabel: String {
        hasContinuityNotes ? "已记录" : "待补充"
    }

    var referenceStatusLabel: String {
        referenceDocuments.isEmpty ? "未导入" : "\(referenceDocuments.count) 份"
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
