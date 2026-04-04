import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var selectedProvider: ModelProvider = .openAICompatible
    var apiKey = ""
    var baseURL = "https://api.openai.com/v1"
    var autoValidateOnLaunch = true
    var connectionStatus: ConnectionStatus = .idle
    var validationMessage = "填入 API Key 与 Base URL 后即可验证。"

    let activeWorkspaceName = "雾港纪事"
    let dashboardStats: [DashboardStat] = [
        DashboardStat(title: "活跃项目", value: "04", detail: "多线并行创作"),
        DashboardStat(title: "本月字数", value: "84k", detail: "含草稿与扩写"),
        DashboardStat(title: "提示词包", value: "18", detail: "角色与世界观模板")
    ]

    let recentProjects: [NovelProject] = [
        NovelProject(
            title: "雾港纪事",
            genre: "海港悬疑",
            summary: "一座被潮汐与钟楼控制节奏的城市，正在吞没每个说谎的人。",
            updatedAt: "今天 18:20",
            progress: 0.72,
            chapters: 18
        ),
        NovelProject(
            title: "玻璃山来信",
            genre: "成长奇幻",
            summary: "失忆的制图师追查一封寄给未来自己的信，逐渐拼回山脉的真实形状。",
            updatedAt: "昨天 21:40",
            progress: 0.48,
            chapters: 9
        ),
        NovelProject(
            title: "零号日落",
            genre: "近未来科幻",
            summary: "当城市开始共享黄昏，主角必须在同一晚里做出三次不同的人生选择。",
            updatedAt: "周一 09:10",
            progress: 0.31,
            chapters: 6
        )
    ]

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

    var activeProject: NovelProject? {
        recentProjects.first(where: { $0.title == activeWorkspaceName }) ?? recentProjects.first
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

    private var hasValidBaseURL: Bool {
        guard let components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        let scheme = components.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && components.host != nil
    }
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
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

struct NovelProject: Identifiable {
    let id = UUID()
    let title: String
    let genre: String
    let summary: String
    let updatedAt: String
    let progress: Double
    let chapters: Int
}

struct StoryPillar: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct InspirationSignal: Identifiable {
    let id = UUID()
    let title: String
    let description: String
}
