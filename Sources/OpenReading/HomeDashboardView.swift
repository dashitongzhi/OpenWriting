import Observation
import SwiftUI

struct HomeDashboardView: View {
    @Bindable var appState: AppState
    @State private var heroMinY: CGFloat = 0
    @State private var heroRestingMinY: CGFloat?

    private let columns = [
        GridItem(.flexible(minimum: 320), spacing: 20, alignment: .top),
        GridItem(.flexible(minimum: 320), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        DashboardPanel(
                            title: "创作雷达",
                            subtitle: "把关键指标放在首页，而不是埋在二级页面。"
                        ) {
                            statGrid
                        }

                        DashboardPanel(
                            title: "模型连接",
                            subtitle: "模型供应商和凭证已经收进原生设置窗口。"
                        ) {
                            ModelConnectionSummaryCard(appState: appState)
                        }

                        DashboardPanel(
                            title: "快速开始",
                            subtitle: "把最常用的三条动作直接放在首页。"
                        ) {
                            quickStartSection
                        }

                        DashboardPanel(
                            title: "最近项目",
                            subtitle: "继续你昨天停下的那一章。"
                        ) {
                            recentProjectsSection
                        }

                        DashboardPanel(
                            title: "写作骨架",
                            subtitle: "把人物、结构和模型协作摆在同一屏。"
                        ) {
                            writingPillarsSection
                        }

                        DashboardPanel(
                            title: "灵感入口",
                            subtitle: "让首页直接指向可执行的创作动作。"
                        ) {
                            inspirationSection
                        }
                    }
                }
                .padding(32)
            }
            .coordinateSpace(name: "dashboardScroll")
        }
        .onPreferenceChange(HeroMinYPreferenceKey.self) { minY in
            heroMinY = minY

            if let restingMinY = heroRestingMinY {
                if minY > restingMinY {
                    heroRestingMinY = minY
                }
            } else {
                heroRestingMinY = minY
            }
        }
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Text("OpenReading")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(2.6)
                    .foregroundStyle(.secondary)

                Text("把灵感、设定与长篇结构，整理成真正可写的小说工作台。")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.13, green: 0.15, blue: 0.24))
                    .fixedSize(horizontal: false, vertical: true)

                Text("这是首版 macOS 主页原型：顶部工具栏只保留系统风格的全局操作与设置入口，左侧边栏负责工作区导航，主区同时展示创作概览、最近项目和模型状态，为后续章节编辑器与 AI 工作流预留结构。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 700, alignment: .leading)

                HStack(spacing: 12) {
                    Button("新建长篇项目") {}
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Button("导入世界观") {}
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                statusBadge

                Text("当前工作区")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(appState.activeWorkspaceName)
                    .font(.title2.weight(.semibold))

                Text("下一步建议：从首页进入“项目空间”，再把角色卡、章节树和写作面板串成完整流。")
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 10) {
                    PillTag(text: "长篇写作")
                    PillTag(text: "本地原型")
                    PillTag(text: "AI 协作")
                }
            }
            .frame(width: 310, alignment: .leading)
            .padding(22)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.94, blue: 0.88),
                            Color(red: 0.92, green: 0.95, blue: 0.99)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 26, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
        .opacity(heroOpacity)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HeroMinYPreferenceKey.self,
                    value: proxy.frame(in: .named("dashboardScroll")).minY
                )
            }
        }
    }

    private var heroOpacity: CGFloat {
        let fadeDistance: CGFloat = 220
        let travel = heroTravelDistance
        let progress = min(max(travel / fadeDistance, 0), 1)
        return 1 - progress
    }

    private var heroTravelDistance: CGFloat {
        guard let restingMinY = heroRestingMinY else {
            return 0
        }

        return max(0, restingMinY - heroMinY)
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: appState.connectionStatus.symbolName)
            Text(appState.connectionStatus.label)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusBackground, in: Capsule())
        .foregroundStyle(statusForeground)
    }

    private var statusBackground: Color {
        switch appState.connectionStatus {
        case .idle:
            return Color.black.opacity(0.06)
        case .ready:
            return Color(red: 0.20, green: 0.58, blue: 0.43).opacity(0.18)
        case .needsAttention:
            return Color(red: 0.90, green: 0.55, blue: 0.28).opacity(0.2)
        }
    }

    private var statusForeground: Color {
        switch appState.connectionStatus {
        case .idle:
            return Color.primary
        case .ready:
            return Color(red: 0.15, green: 0.43, blue: 0.32)
        case .needsAttention:
            return Color(red: 0.55, green: 0.28, blue: 0.12)
        }
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 120), spacing: 14),
                GridItem(.flexible(minimum: 120), spacing: 14),
                GridItem(.flexible(minimum: 120), spacing: 14)
            ],
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(appState.dashboardStats) { stat in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stat.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(stat.value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(stat.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuickActionRow(
                title: "新建作品骨架",
                subtitle: "先输入一句 logline，再自动拆出角色、冲突和三幕结构。",
                symbolName: "wand.and.stars"
            )

            QuickActionRow(
                title: "继续上次写作",
                subtitle: "直接回到最近一次停下的章节和世界观笔记。",
                symbolName: "arrow.clockwise"
            )

            QuickActionRow(
                title: "导入设定资料",
                subtitle: "支持把已有大纲、角色卡和碎片灵感整理进素材库。",
                symbolName: "square.and.arrow.down"
            )
        }
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(appState.recentProjects) { project in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title)
                                .font(.headline)

                            Text(project.genre)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(project.updatedAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(project.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        ProgressView(value: project.progress)
                            .tint(Color(red: 0.85, green: 0.47, blue: 0.22))

                        Text("\(Int(project.progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text("已规划 \(project.chapters) 章")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var writingPillarsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(appState.writingPillars) { pillar in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color(red: 0.26, green: 0.33, blue: 0.53))
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(pillar.title)
                            .font(.headline)

                        Text(pillar.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var inspirationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(appState.inspirationSignals) { signal in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.58, blue: 0.37),
                                    Color(red: 0.52, green: 0.66, blue: 0.86)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal.title)
                            .font(.headline)

                        Text(signal.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(14)
                .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

struct PlaceholderWorkspaceView: View {
    let item: SidebarItem
    @Bindable var appState: AppState

    var body: some View {
        ZStack {
            PageBackground()

            VStack(alignment: .leading, spacing: 20) {
                Text(item.title)
                    .font(.system(size: 34, weight: .bold, design: .serif))

                Text(item.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                DashboardPanel(
                    title: "下一步规划",
                    subtitle: "主页已经先把信息架构立住，下面这些区域可以继续扩展。"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("保留当前侧边栏结构，方便后续把页面逐个补齐。", systemImage: "checkmark.circle")
                        Label("模型连接已收进原生设置窗口，和外观模式一起管理。", systemImage: "gearshape")
                        Label("项目页下一步建议优先接章节编辑器与项目列表。", systemImage: "square.grid.2x2")
                    }
                    .font(.subheadline)
                }

                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct ModelConnectionSummaryCard: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: appState.connectionStatus.symbolName)
                    .foregroundStyle(statusColor)

                Text(appState.connectionStatus.label)
                    .font(.headline)

                Spacer()

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
            }

            summaryRow(label: "接口类型", value: appState.selectedProvider.title)
            summaryRow(
                label: "Base URL",
                value: appState.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : appState.baseURL
            )
            summaryRow(
                label: "API Key",
                value: appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : "已填写"
            )

            Text(appState.validationMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("跟随 Apple 的原生偏好结构，供应商选择和凭证录入都放在设置窗口，不再占用首页编辑空间。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .idle:
            return .secondary
        case .ready:
            return Color(red: 0.18, green: 0.56, blue: 0.42)
        case .needsAttention:
            return Color(red: 0.83, green: 0.45, blue: 0.20)
        }
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}

struct DashboardPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
    }
}

struct QuickActionRow: View {
    let title: String
    let subtitle: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct PillTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.64), in: Capsule())
    }
}

struct PageBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 0.91),
                    Color(red: 0.92, green: 0.95, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.88, green: 0.62, blue: 0.39).opacity(0.30))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -240, y: -220)

            Circle()
                .fill(Color(red: 0.45, green: 0.60, blue: 0.84).opacity(0.26))
                .frame(width: 400, height: 400)
                .blur(radius: 130)
                .offset(x: 340, y: -160)

            Circle()
                .fill(Color(red: 0.22, green: 0.28, blue: 0.48).opacity(0.16))
                .frame(width: 500, height: 500)
                .blur(radius: 160)
                .offset(x: 340, y: 320)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    AppRootView(appState: AppState())
}

private struct HeroMinYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
