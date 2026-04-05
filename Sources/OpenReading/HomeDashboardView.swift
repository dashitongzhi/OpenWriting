import AppKit
import Observation
import SwiftUI

struct HomeDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    @State private var heroMinY: CGFloat = 0
    @State private var heroRestingMinY: CGFloat?

    private let contentTopPadding: CGFloat = 18
    private let contentHorizontalPadding: CGFloat = 32
    private let contentBottomPadding: CGFloat = 32

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroSection
                    topWorkbenchSection
                    bottomWorkbenchSection
                }
                .padding(.top, contentTopPadding)
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.bottom, contentBottomPadding)
            }
            .background(TopAnchorBounceLockView())
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                heroCopy
                    .frame(maxWidth: .infinity, alignment: .leading)

                heroScenePanel
                    .frame(width: 372)
            }

            VStack(alignment: .leading, spacing: 22) {
                heroCopy
                heroScenePanel
            }
        }
        .padding(30)
        .background(
            GlassPanelBackground(
                cornerRadius: 34,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.warmAccent.opacity(palette.isDark ? 0.26 : 0.20),
                        palette.coolAccent.opacity(palette.isDark ? 0.24 : 0.18),
                        palette.successAccent.opacity(palette.isDark ? 0.16 : 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(panelStroke(cornerRadius: 34))
        .shadow(color: palette.shadow, radius: palette.isDark ? 34 : 24, y: palette.isDark ? 22 : 14)
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

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("OpenReading")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(3)
                .foregroundStyle(palette.textSecondary)

            Text("把灵感、设定与长篇结构，整理成真正可写的小说工作台。")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("这是首版 macOS 主页原型：顶部工具栏只保留系统风格的全局操作与设置入口，左侧边栏负责工作区导航，主区同时展示创作概览、最近项目和模型状态，为后续章节编辑器与 AI 工作流预留结构。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: 720, alignment: .leading)
                .lineSpacing(4)

            HStack(spacing: 12) {
                Button("新建长篇项目") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(palette.coolAccent)

                Button("导入世界观") {}
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(palette.textPrimary.opacity(0.9))
            }
        }
    }

    private var heroScenePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusBadge

            VStack(alignment: .leading, spacing: 6) {
                Text("当前工作区")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                Text(appState.activeWorkspaceName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
            }

            if let activeProject {
                CurrentProjectSnapshotCard(project: activeProject)
            }

            Text("下一步建议：从首页进入“项目空间”，再把角色卡、章节树和写作面板串成完整流。")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)

            HStack(spacing: 10) {
                PillTag(text: "长篇写作")
                PillTag(text: "本地原型")
                PillTag(text: "AI 协作")
            }
        }
        .padding(24)
        .frame(minHeight: 340)
        .background(
            GlassPanelBackground(
                cornerRadius: 28,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.coolAccent.opacity(palette.isDark ? 0.24 : 0.16),
                        palette.warmAccent.opacity(palette.isDark ? 0.18 : 0.14),
                        .clear
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            )
        )
        .overlay(panelStroke(cornerRadius: 28))
    }

    private var topWorkbenchSection: some View {
        DashboardSplitSection {
            DashboardPanel(
                title: "创作雷达",
                subtitle: "把关键指标放在首页，而不是埋在二级页面。"
            ) {
                statGrid
            }
        } secondary: {
            VStack(spacing: 22) {
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
            }
        }
    }

    private var bottomWorkbenchSection: some View {
        DashboardSplitSection {
            DashboardPanel(
                title: "最近项目",
                subtitle: "继续你昨天停下的那一章。"
            ) {
                recentProjectsSection
            }
        } secondary: {
            VStack(spacing: 22) {
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
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(statusBackground, in: Capsule())
        .foregroundStyle(statusForeground)
    }

    private var statusBackground: Color {
        switch appState.connectionStatus {
        case .idle:
            return palette.panelBase.opacity(palette.isDark ? 0.9 : 0.75)
        case .ready:
            return palette.successAccent.opacity(palette.isDark ? 0.24 : 0.18)
        case .needsAttention:
            return palette.warmAccent.opacity(palette.isDark ? 0.24 : 0.20)
        }
    }

    private var statusForeground: Color {
        switch appState.connectionStatus {
        case .idle:
            return palette.textPrimary
        case .ready:
            return palette.successAccent
        case .needsAttention:
            return palette.warmAccent
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(stat.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textSecondary)

                    Text(stat.value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)

                    Text(stat.detail)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    GlassPanelBackground(
                        cornerRadius: 20,
                        palette: palette,
                        tint: LinearGradient(
                            colors: [
                                palette.coolAccent.opacity(palette.isDark ? 0.18 : 0.10),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(panelStroke(cornerRadius: 20))
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
                                .foregroundStyle(palette.textPrimary)

                            Text(project.genre)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.textSecondary)
                        }

                        Spacer()

                        Text(project.updatedAt)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Text(project.summary)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)

                    HStack {
                        ProgressView(value: project.progress)
                            .tint(palette.warmAccent)

                        Text("\(Int(project.progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                    }

                    Text("已规划 \(project.chapters) 章")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary.opacity(0.8))
                }
                .padding(18)
                .background(
                    GlassPanelBackground(
                        cornerRadius: 22,
                        palette: palette,
                        tint: LinearGradient(
                            colors: [
                                palette.warmAccent.opacity(palette.isDark ? 0.14 : 0.09),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(panelStroke(cornerRadius: 22))
            }
        }
    }

    private var writingPillarsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(appState.writingPillars) { pillar in
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [palette.coolAccent, palette.successAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 36)
                        .shadow(color: palette.coolAccent.opacity(0.35), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(pillar.title)
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)

                        Text(pillar.detail)
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                            .lineSpacing(3)
                    }
                }
                .padding(16)
                .background(
                    GlassPanelBackground(
                        cornerRadius: 22,
                        palette: palette,
                        tint: LinearGradient(
                            colors: [
                                palette.coolAccent.opacity(palette.isDark ? 0.12 : 0.08),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(panelStroke(cornerRadius: 22))
            }
        }
    }

    private var inspirationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(appState.inspirationSignals) { signal in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.warmAccent.opacity(0.94),
                                    palette.coolAccent.opacity(0.96),
                                    palette.successAccent.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.95))
                        )
                        .rotation3DEffect(.degrees(14), axis: (x: 1, y: -1, z: 0))
                        .shadow(color: palette.coolAccent.opacity(0.34), radius: 18, y: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal.title)
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)

                        Text(signal.description)
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()
                }
                .padding(16)
                .background(
                    GlassPanelBackground(
                        cornerRadius: 22,
                        palette: palette,
                        tint: LinearGradient(
                            colors: [
                                palette.successAccent.opacity(palette.isDark ? 0.12 : 0.08),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(panelStroke(cornerRadius: 22))
            }
        }
    }

    private func panelStroke(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(palette.isDark ? 0.16 : 0.76),
                        palette.coolAccent.opacity(palette.isDark ? 0.16 : 0.10),
                        Color.white.opacity(palette.isDark ? 0.08 : 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

struct PlaceholderWorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: SidebarItem
    @Bindable var appState: AppState

    private let contentTopPadding: CGFloat = 18
    private let contentHorizontalPadding: CGFloat = 32
    private let contentBottomPadding: CGFloat = 32

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    private var featuredQuote: LiteraryQuote? {
        LiteraryQuoteLibrary.quote(for: item, seed: appState.quoteSeed)
    }

    var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DashboardSplitSection {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(item.title)
                                .font(.system(size: 42, weight: .bold, design: .serif))
                                .foregroundStyle(palette.textPrimary)

                            Text(item.summary)
                                .font(.title3)
                                .foregroundStyle(palette.textSecondary)
                                .lineSpacing(4)

                            if let featuredQuote {
                                writingQuotePanel(featuredQuote)
                            }

                            Spacer(minLength: 18)

                            HStack(spacing: 10) {
                                PillTag(text: item.title)
                                PillTag(text: appState.activeWorkspaceName)
                            }

                            if let activeProject {
                                workspaceContextStrip(for: activeProject)
                            }
                        }
                        .padding(30)
                        .frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading)
                        .background(
                            GlassPanelBackground(
                                cornerRadius: 32,
                                palette: palette,
                                tint: LinearGradient(
                                    colors: [
                                        palette.warmAccent.opacity(palette.isDark ? 0.18 : 0.12),
                                        palette.coolAccent.opacity(palette.isDark ? 0.18 : 0.12),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(panelStroke(cornerRadius: 32))
                    } secondary: {
                        WorkspaceUtilityCard(appState: appState, item: item)
                            .frame(minHeight: 260)
                    }

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
                        .foregroundStyle(palette.textPrimary)
                    }
                }
                .padding(.top, contentTopPadding)
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.bottom, contentBottomPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(TopAnchorBounceLockView())
        }
    }

    private func panelStroke(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(palette.isDark ? 0.16 : 0.76),
                        palette.coolAccent.opacity(palette.isDark ? 0.16 : 0.10),
                        Color.white.opacity(palette.isDark ? 0.08 : 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private func writingQuotePanel(_ quote: LiteraryQuote) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("写作引句", systemImage: "quote.opening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                Spacer()

                Text("\(LiteraryQuoteLibrary.totalCount) 条名言库")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.coolAccent)
            }

            ZStack(alignment: .topLeading) {
                Text("“")
                    .font(.system(size: 78, weight: .bold, design: .serif))
                    .foregroundStyle(palette.coolAccent.opacity(palette.isDark ? 0.28 : 0.18))
                    .offset(x: -4, y: -18)

                VStack(alignment: .leading, spacing: 12) {
                    Text(quote.text)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(quote.author)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)

                        Text("·")
                            .foregroundStyle(palette.textSecondary)

                        Text(quote.country)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textSecondary)
                    }

                    if !quote.source.isEmpty {
                        Text(quote.source)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.panelBase.opacity(palette.isDark ? 0.84 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    private func workspaceContextStrip(for project: NovelProject) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)

                Text(project.genre)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.coolAccent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(project.updatedAt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                Text("已规划 \(project.chapters) 章")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.panelBase.opacity(palette.isDark ? 0.84 : 0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

private struct CurrentProjectSnapshotCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let project: NovelProject

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            coverView

            VStack(alignment: .leading, spacing: 10) {
                Text("当前创作")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(palette.textPrimary)

                    Text(project.genre)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.coolAccent)
                }

                Text(project.summary)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
                    .lineSpacing(3)

                HStack(spacing: 14) {
                    Label(project.updatedAt, systemImage: "clock")
                    Label("已规划 \(project.chapters) 章", systemImage: "text.book.closed")
                }
                .font(.caption)
                .foregroundStyle(palette.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("创作进度")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)

                        Spacer()

                        Text("\(Int(project.progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                    }

                    ProgressView(value: project.progress)
                        .tint(palette.warmAccent)
                }
            }
        }
        .padding(18)
        .background(
            GlassPanelBackground(
                cornerRadius: 24,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.warmAccent.opacity(palette.isDark ? 0.12 : 0.08),
                        palette.coolAccent.opacity(palette.isDark ? 0.10 : 0.06),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    private var coverView: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.coolAccent.opacity(0.95),
                            palette.warmAccent.opacity(0.88),
                            palette.successAccent.opacity(0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(palette.isDark ? 0.20 : 0.08),
                            .clear
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(project.title.prefix(2))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))

                Text(project.genre)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(width: 112, height: 148)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(palette.isDark ? 0.18 : 0.42), lineWidth: 1)
        )
        .shadow(color: palette.shadow.opacity(0.45), radius: 14, y: 10)
    }
}

struct ModelConnectionSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: appState.connectionStatus.symbolName)
                    .foregroundStyle(statusColor)

                Text(appState.connectionStatus.label)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.coolAccent)
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
                .foregroundStyle(palette.textSecondary)

            Text("跟随 Apple 的原生偏好结构，供应商选择和凭证录入都放在设置窗口，不再占用首页编辑空间。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
        }
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .idle:
            return palette.textSecondary
        case .ready:
            return palette.successAccent
        case .needsAttention:
            return palette.warmAccent
        }
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }
}

struct DashboardPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(palette.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GlassPanelBackground(
                cornerRadius: 28,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.coolAccent.opacity(palette.isDark ? 0.10 : 0.06),
                        palette.warmAccent.opacity(palette.isDark ? 0.08 : 0.05),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.15 : 0.72),
                            palette.coolAccent.opacity(palette.isDark ? 0.15 : 0.08),
                            Color.white.opacity(palette.isDark ? 0.08 : 0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: palette.shadow.opacity(palette.isDark ? 0.92 : 0.28), radius: palette.isDark ? 28 : 18, y: palette.isDark ? 18 : 10)
    }
}

struct QuickActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let symbolName: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.coolAccent.opacity(0.92),
                            palette.successAccent.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: symbolName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                )
                .rotation3DEffect(.degrees(18), axis: (x: 1, y: -1, z: 0))
                .shadow(color: palette.coolAccent.opacity(0.28), radius: 12, y: 8)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(
            GlassPanelBackground(
                cornerRadius: 22,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.successAccent.opacity(palette.isDark ? 0.10 : 0.06),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

struct PillTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(palette.panelBase.opacity(palette.isDark ? 0.9 : 0.74))
            )
            .overlay(
                Capsule()
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
    }
}

struct PageBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.warmAccent.opacity(palette.isDark ? 0.24 : 0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: -260, y: -240)

            Circle()
                .fill(palette.coolAccent.opacity(palette.isDark ? 0.22 : 0.18))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 360, y: -120)

            Circle()
                .fill(palette.successAccent.opacity(palette.isDark ? 0.18 : 0.12))
                .frame(width: 460, height: 460)
                .blur(radius: 150)
                .offset(x: 320, y: 300)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.02 : 0.24),
                            palette.coolAccent.opacity(palette.isDark ? 0.06 : 0.10),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 760, height: 420)
                .rotationEffect(.degrees(-18))
                .rotation3DEffect(.degrees(28), axis: (x: 1, y: 0.2, z: 0))
                .offset(x: 220, y: -240)
                .blur(radius: 1)
        }
        .ignoresSafeArea()
    }
}

private struct DashboardSplitSection<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                primary
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                secondary
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 22) {
                primary
                secondary
            }
        }
    }
}

private struct TopAnchorBounceLockView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private var liveScrollEndObserver: NSObjectProtocol?

        func attachIfNeeded(from view: NSView) {
            guard let discoveredScrollView = view.enclosingScrollView else { return }
            guard scrollView !== discoveredScrollView else { return }

            detach()
            scrollView = discoveredScrollView

            liveScrollEndObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: discoveredScrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.snapBackToTopIfNeeded()
                }
            }
        }

        func detach() {
            if let liveScrollEndObserver {
                NotificationCenter.default.removeObserver(liveScrollEndObserver)
            }

            liveScrollEndObserver = nil
            scrollView = nil
        }

        private func snapBackToTopIfNeeded() {
            guard let scrollView, let documentView = scrollView.documentView else { return }

            let clipView = scrollView.contentView
            let targetTopY = topOriginY(for: scrollView, documentView: documentView)
            let currentY = clipView.bounds.origin.y

            let needsSnapBack: Bool
            if documentView.isFlipped {
                needsSnapBack = currentY < targetTopY - 0.5
            } else {
                needsSnapBack = currentY > targetTopY + 0.5
            }

            guard needsSnapBack else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clipView.animator().setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: targetTopY))
            }

            scrollView.reflectScrolledClipView(clipView)
        }

        private func topOriginY(for scrollView: NSScrollView, documentView: NSView) -> CGFloat {
            if documentView.isFlipped {
                return 0
            }

            let visibleHeight = scrollView.contentView.bounds.height
            let documentHeight = documentView.bounds.height
            return max(0, documentHeight - visibleHeight)
        }
    }
}

private struct WorkspaceUtilityCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    let item: SidebarItem

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            utilityHeader

            switch item {
            case .projects:
                projectUtilityContent
            case .outline:
                outlineUtilityContent
            case .library:
                libraryUtilityContent
            case .prompts:
                promptsUtilityContent
            case .home:
                EmptyView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading)
        .background(
            GlassPanelBackground(
                cornerRadius: 32,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.coolAccent.opacity(palette.isDark ? 0.16 : 0.12),
                        palette.warmAccent.opacity(palette.isDark ? 0.16 : 0.12),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
        .shadow(color: palette.shadow, radius: palette.isDark ? 28 : 18, y: palette.isDark ? 18 : 10)
    }

    private var utilityHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.coolAccent, palette.successAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .rotation3DEffect(.degrees(18), axis: (x: 1, y: -1, z: 0))
                    .shadow(color: palette.coolAccent.opacity(0.28), radius: 14, y: 10)

                Image(systemName: item.symbolName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(itemUtilityTitle)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(palette.textPrimary)

                Text(itemUtilitySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
            }
        }
    }

    private var projectUtilityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let activeProject {
                utilityFeatureCard(
                    eyebrow: "当前推进",
                    title: activeProject.title,
                    subtitle: activeProject.summary,
                    trailing: activeProject.updatedAt
                )
            }

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "活跃项目", value: "\(appState.recentProjects.count)")
                WorkspaceMetricBadge(label: "当前进度", value: "\(Int((activeProject?.progress ?? 0) * 100))%")
            }

            WorkspaceChecklist(
                title: "续写顺序建议",
                items: appState.recentProjects.prefix(3).map { "\($0.title) · \($0.updatedAt)" }
            )
        }
    }

    private var outlineUtilityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let activeProject {
                let firstActEnd = max(3, activeProject.chapters / 3)
                let secondActEnd = max(firstActEnd + 3, (activeProject.chapters * 2) / 3)

                utilityFeatureCard(
                    eyebrow: "结构分布",
                    title: "已规划 \(activeProject.chapters) 章",
                    subtitle: "开篇 1-\(firstActEnd) · 推进 \(firstActEnd + 1)-\(secondActEnd) · 收束 \(secondActEnd + 1)-\(activeProject.chapters)",
                    trailing: activeProject.title
                )
            }

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "角色弧线", value: "同步")
                WorkspaceMetricBadge(label: "伏笔回收", value: "待标记")
            }

            WorkspaceChecklist(
                title: "章节树建议",
                items: [
                    "先给每章补上场景目标",
                    "为关键冲突标出转折点",
                    "把伏笔放进可追踪节点"
                ]
            )
        }
    }

    private var libraryUtilityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            utilityFeatureCard(
                eyebrow: "当前素材焦点",
                title: appState.activeWorkspaceName,
                subtitle: activeProject?.summary ?? "把人物、地点、组织和世界观素材集中收纳。",
                trailing: activeProject?.genre ?? "世界观整理"
            )

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "灵感入口", value: "\(appState.inspirationSignals.count)")
                WorkspaceMetricBadge(label: "写作支柱", value: "\(appState.writingPillars.count)")
            }

            WorkspaceChecklist(
                title: "优先建库",
                items: appState.inspirationSignals.map(\.title)
            )
        }
    }

    private var promptsUtilityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            utilityFeatureCard(
                eyebrow: "当前模型",
                title: appState.selectedProvider.title,
                subtitle: appState.validationMessage,
                trailing: appState.connectionStatus.label
            )

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "接口类型", value: appState.selectedProvider.title)
                WorkspaceMetricBadge(label: "状态", value: appState.connectionStatus.label)
            }

            WorkspaceChecklist(
                title: "推荐工作流",
                items: [
                    "设定补完：补人物、地点与规则细节",
                    "章节续写：延展当前场景的推进节奏",
                    "对白润色：统一角色语气和信息密度"
                ]
            )
        }
    }

    private var itemUtilityTitle: String {
        switch item {
        case .projects:
            return "项目推进"
        case .outline:
            return "结构导航"
        case .library:
            return "素材整理"
        case .prompts:
            return "AI 工作流"
        case .home:
            return "工作卡"
        }
    }

    private var itemUtilitySubtitle: String {
        switch item {
        case .projects:
            return "把正在写的项目、最近更新和续写顺序放在同一张卡里。"
        case .outline:
            return "快速看结构分布、章节推进和回收节点。"
        case .library:
            return "优先补齐对当前创作最有用的人物与世界观资料。"
        case .prompts:
            return "把模型状态和最常用的写作工作流放在眼前。"
        case .home:
            return "首页概览。"
        }
    }

    private func utilityFeatureCard(eyebrow: String, title: String, subtitle: String, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                Spacer()

                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.coolAccent)
                    .lineLimit(1)
            }

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.textPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GlassPanelBackground(
                cornerRadius: 24,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.warmAccent.opacity(palette.isDark ? 0.10 : 0.08),
                        palette.coolAccent.opacity(palette.isDark ? 0.10 : 0.06),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

private struct WorkspaceMetricBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.panelBase.opacity(palette.isDark ? 0.82 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

private struct WorkspaceChecklist: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let items: [String]

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(palette.coolAccent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.panelSecondary.opacity(palette.isDark ? 0.82 : 0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

private struct DimensionalSceneView: View {
    enum SceneStyle {
        case hero
        case workspace
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var animateScene = false
    let style: SceneStyle

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style == .hero ? 34 : 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.04 : 0.32),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.coolAccent.opacity(palette.isDark ? 0.34 : 0.28),
                            palette.successAccent.opacity(palette.isDark ? 0.22 : 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: style == .hero ? 180 : 150, height: style == .hero ? 140 : 122)
                .rotation3DEffect(.degrees(animateScene ? 40 : 24), axis: (x: 1, y: -1, z: 0))
                .offset(x: animateScene ? 42 : 26, y: animateScene ? -46 : -28)
                .shadow(color: palette.coolAccent.opacity(0.36), radius: 26, y: 16)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.panelBase.opacity(0.96),
                            palette.panelSecondary.opacity(0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: style == .hero ? 220 : 180, height: style == .hero ? 160 : 136)
                .rotation3DEffect(.degrees(animateScene ? -18 : -10), axis: (x: 1, y: 0.3, z: 0))
                .offset(x: animateScene ? -24 : -10, y: animateScene ? 18 : 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(palette.isDark ? 0.16 : 0.46), lineWidth: 1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.82 : 0.95),
                            palette.warmAccent.opacity(0.82),
                            palette.coolAccent.opacity(0.08)
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 120
                    )
                )
                .frame(width: style == .hero ? 132 : 110, height: style == .hero ? 132 : 110)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(palette.isDark ? 0.24 : 0.58), lineWidth: 1)
                )
                .offset(x: animateScene ? -88 : -68, y: animateScene ? -70 : -48)
                .shadow(color: palette.warmAccent.opacity(0.36), radius: 22, y: 16)

            VStack(spacing: 12) {
                SceneSlab(width: style == .hero ? 148 : 130, height: 18, palette: palette)
                    .offset(x: style == .hero ? 84 : 56)

                SceneSlab(width: style == .hero ? 188 : 164, height: 18, palette: palette)
                    .offset(x: style == .hero ? 18 : 12)

                SceneSlab(width: style == .hero ? 124 : 110, height: 18, palette: palette)
                    .offset(x: style == .hero ? 62 : 46)
            }
            .offset(y: style == .hero ? 76 : 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !animateScene else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                animateScene = true
            }
        }
    }
}

private struct SceneSlab: View {
    let width: CGFloat
    let height: CGFloat
    let palette: DashboardPalette

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(palette.isDark ? 0.14 : 0.74),
                        palette.panelBase.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
    }
}

private struct GlassPanelBackground: View {
    let cornerRadius: CGFloat
    let palette: DashboardPalette
    let tint: LinearGradient

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.panelBase.opacity(palette.isDark ? 0.94 : 0.76),
                            palette.panelSecondary.opacity(palette.isDark ? 0.86 : 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.10 : 0.38),
                            .clear,
                            Color.white.opacity(palette.isDark ? 0.02 : 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

private struct DashboardPalette {
    let isDark: Bool
    let backgroundTop: Color
    let backgroundBottom: Color
    let panelBase: Color
    let panelSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let warmAccent: Color
    let coolAccent: Color
    let successAccent: Color
    let stroke: Color
    let shadow: Color

    init(colorScheme: ColorScheme) {
        isDark = colorScheme == .dark

        if isDark {
            backgroundTop = Color(red: 0.04, green: 0.04, blue: 0.05)
            backgroundBottom = Color(red: 0.10, green: 0.10, blue: 0.12)
            panelBase = Color(red: 0.12, green: 0.12, blue: 0.14)
            panelSecondary = Color(red: 0.07, green: 0.07, blue: 0.09)
            textPrimary = Color.white.opacity(0.96)
            textSecondary = Color.white.opacity(0.70)
            warmAccent = Color(red: 1.00, green: 0.53, blue: 0.33)
            coolAccent = Color(red: 0.26, green: 0.72, blue: 0.98)
            successAccent = Color(red: 0.43, green: 0.84, blue: 0.66)
            stroke = Color.white.opacity(0.12)
            shadow = Color.black.opacity(0.52)
        } else {
            backgroundTop = Color(red: 0.98, green: 0.96, blue: 0.93)
            backgroundBottom = Color(red: 0.92, green: 0.95, blue: 0.99)
            panelBase = Color.white.opacity(0.70)
            panelSecondary = Color(red: 0.94, green: 0.96, blue: 0.99).opacity(0.72)
            textPrimary = Color(red: 0.12, green: 0.13, blue: 0.20)
            textSecondary = Color(red: 0.30, green: 0.34, blue: 0.43)
            warmAccent = Color(red: 0.92, green: 0.55, blue: 0.30)
            coolAccent = Color(red: 0.27, green: 0.56, blue: 0.92)
            successAccent = Color(red: 0.26, green: 0.68, blue: 0.52)
            stroke = Color.white.opacity(0.58)
            shadow = Color.black.opacity(0.10)
        }
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
