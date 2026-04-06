import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppState {
    private enum StorageKey {
        static let selectedProvider = "OpenReading.selectedProvider"
        static let baseURL = "OpenReading.baseURL"
        static let autoValidateOnLaunch = "OpenReading.autoValidateOnLaunch"
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
        self.apiKey = Self.loadAPIKeyFromKeychain() ?? ""
        self.baseURL = userDefaults.string(forKey: StorageKey.baseURL) ?? "https://api.openai.com/v1"
        self.autoValidateOnLaunch = userDefaults.object(forKey: StorageKey.autoValidateOnLaunch) as? Bool ?? true
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
        hasValidBaseURL && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        connectionStatus = .ready
        validationMessage = "配置格式已通过，可继续接入真实模型请求。"
    }

    func createProject(named title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectTitle = trimmedTitle.isEmpty ? "未命名计划" : trimmedTitle
        let draftProject = NovelProject(
            id: makeProjectIdentifier(from: projectTitle),
            title: projectTitle,
            genre: "待设定",
            summary: "从一句 logline 开始，继续补齐角色目标、核心冲突和三幕结构。",
            updatedAt: "刚刚创建",
            currentChapterTitle: "开篇设定",
            currentChapterNumber: 1,
            writtenChapters: 1
        )

        recentProjects.insert(draftProject, at: 0)
        openProjectSpace(for: draftProject.id)
    }

    func continueWriting() {
        openProjectSpace(for: activeProject?.id ?? recentProjects.first?.id)
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

    private func persistBaseURL() {
        userDefaults.set(baseURL, forKey: StorageKey.baseURL)
    }

    private func persistAutoValidatePreference() {
        userDefaults.set(autoValidateOnLaunch, forKey: StorageKey.autoValidateOnLaunch)
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
            writtenChapters: 18
        ),
        NovelProject(
            id: "glass-mountain-letters",
            title: "玻璃山来信",
            genre: "成长奇幻",
            summary: "失忆的制图师追查一封寄给未来自己的信，逐渐拼回山脉的真实形状。",
            updatedAt: "昨天 21:40",
            currentChapterTitle: "向玻璃山回信",
            currentChapterNumber: 9,
            writtenChapters: 9
        ),
        NovelProject(
            id: "zero-sunset",
            title: "零号日落",
            genre: "近未来科幻",
            summary: "当城市开始共享黄昏，主角必须在同一晚里做出三次不同的人生选择。",
            updatedAt: "周一 09:10",
            currentChapterTitle: "黄昏拷贝体",
            currentChapterNumber: 6,
            writtenChapters: 6
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
    let updatedAt: String
    let currentChapterTitle: String
    let currentChapterNumber: Int
    let writtenChapters: Int

    var currentChapterLabel: String {
        "第 \(currentChapterNumber) 章"
    }

    var currentChapterSummary: String {
        "\(currentChapterLabel) · \(currentChapterTitle)"
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
