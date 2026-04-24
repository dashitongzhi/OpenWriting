import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct HomeDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    let openSettings: () -> Void
    @State private var heroMinY: CGFloat = 0
    @State private var heroRestingMinY: CGFloat?
    @State private var isNewProjectSheetPresented = false
    @State private var isImportingWorldbuilding = false
    @State private var homeImportStatusMessage = ""

    private let contentTopPadding: CGFloat = 18
    private let contentHorizontalPadding: CGFloat = 32
    private let contentBottomPadding: CGFloat = 32
    private let homeWorkbenchPanelHeight: CGFloat = 548

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    private var supportedImportTypes: [UTType] {
        [.plainText, .utf8PlainText, .text, .sourceCode]
    }

    init(appState: AppState, openSettings: @escaping () -> Void = {}) {
        self.appState = appState
        self.openSettings = openSettings
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
        .sheet(isPresented: $isNewProjectSheetPresented) {
            NewProjectSheet { title, length in
                appState.createProject(named: title, length: length)
            }
        }
        .fileImporter(
            isPresented: $isImportingWorldbuilding,
            allowedContentTypes: supportedImportTypes,
            allowsMultipleSelection: true,
            onCompletion: handleWorldbuildingImport
        )
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("OpenWriting")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(3)
                .foregroundStyle(palette.textSecondary)

            Text("把灵感、设定与结构，变成成真正的作品！")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("首页现在承担当天的起手台角色：顶部工具栏保留系统风格的全局操作与设置入口，左侧边栏负责工作区导航，主区直接接通创作概览、项目续写、设定导入和写作骨架入口。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: 720, alignment: .leading)
                .lineSpacing(4)

            HStack(spacing: 12) {
                Button("新建小说项目", action: presentNewProjectSheet)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(palette.coolAccent)

                Button("导入世界观", action: presentWorldbuildingImport)
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
                CurrentProjectSnapshotCard(
                    project: activeProject,
                    action: openProjectsWorkspace
                )
            }

            Text(homeWorkspaceHint)
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
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
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
                subtitle: "把关键指标、当前焦点和今日写作节奏一起固定在首页。",
                fixedHeight: homeWorkbenchPanelHeight
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    statGrid
                    homeRadarFooter
                }
            }
        } secondary: {
            DashboardPanel(
                title: "快速开始",
                subtitle: "把最常用的动作排成一条清晰顺手的入口。",
                fixedHeight: homeWorkbenchPanelHeight
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    quickStartSection
                    homeQuickStartFooter
                }
            }
        }
    }

    private var bottomWorkbenchSection: some View {
        DashboardSplitSection {
            DashboardPanel(
                title: "最近项目",
                subtitle: "继续你昨天停下的那一章，把最近推进重新接上。",
                fixedHeight: homeWorkbenchPanelHeight
            ) {
                recentProjectsSection
            }
        } secondary: {
            DashboardPanel(
                title: "写作骨架",
                subtitle: "把人物、结构和灵感入口收进同一张工作卡。",
                fixedHeight: homeWorkbenchPanelHeight
            ) {
                homeWritingSkeletonSection
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
        Button(action: openSettings) {
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
        .buttonStyle(.plain)
        .help("打开设置，检查模型连接")
    }

    private var statusBackground: Color {
        switch appState.connectionStatus {
        case .idle:
            return palette.panelBase.opacity(palette.isDark ? 0.9 : 0.75)
        case .checking:
            return palette.coolAccent.opacity(palette.isDark ? 0.24 : 0.18)
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
        case .checking:
            return palette.coolAccent
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
                Button {
                    appState.navigate(to: stat.destination)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(stat.title, systemImage: stat.symbolName)
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
                .buttonStyle(.plain)
                .help(stat.detail)
            }
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuickActionRow(
                title: "新建作品骨架",
                subtitle: "先输入一句 logline，再自动拆出角色、冲突和三幕结构。",
                symbolName: "wand.and.stars",
                action: presentNewProjectSheet
            )

            QuickActionRow(
                title: "继续上次写作",
                subtitle: "直接回到最近一次停下的章节和世界观笔记。",
                symbolName: "arrow.clockwise",
                action: continueWriting
            )

            QuickActionRow(
                title: "导入设定资料",
                subtitle: "支持把已有大纲、角色卡和碎片灵感整理进素材库。",
                symbolName: "square.and.arrow.down",
                action: presentWorldbuildingImport
            )
        }
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.recentProjects.isEmpty {
                homeEmptyRecentProjectCard(
                    title: "还没有项目",
                    detail: "新建一本书后，这里会固定显示最近推进、当前章节和创作状态。",
                    actionTitle: "新建项目",
                    action: presentNewProjectSheet
                )

                homeEmptyRecentProjectCard(
                    title: "准备好继续写作",
                    detail: "项目创建完成后，这里会优先展示最近更新的作品，方便你直接接着写。",
                    actionTitle: "打开项目空间",
                    action: openProjectsWorkspace
                )
            } else {
                ForEach(appState.recentProjects.prefix(2)) { project in
                    recentProjectCard(for: project)
                }
            }

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "全部项目", value: "\(appState.recentProjects.count)")
                WorkspaceMetricBadge(label: "已创作章节", value: "\(appState.totalWrittenChapters) 章")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button("查看全部项目", action: openProjectsWorkspace)
                        .buttonStyle(.bordered)

                    Button("继续当前写作", action: continueWriting)
                        .buttonStyle(.borderedProminent)
                        .tint(palette.coolAccent)

                    Button("导入设定资料", action: presentWorldbuildingImport)
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button("查看全部项目", action: openProjectsWorkspace)
                        .buttonStyle(.bordered)

                    Button("继续当前写作", action: continueWriting)
                        .buttonStyle(.borderedProminent)
                        .tint(palette.coolAccent)

                    Button("导入设定资料", action: presentWorldbuildingImport)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func recentProjectCard(for project: NovelProject) -> some View {
        Button {
            appState.openProjectSpace(for: project.id, scrollToProject: true)
        } label: {
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
                    .lineLimit(2)
                    .lineSpacing(3)

                HStack(spacing: 10) {
                    ProjectChapterPill(
                        label: "当前创作",
                        value: project.currentChapterSummary
                    )

                    ProjectChapterPill(
                        label: "已创作",
                        value: "\(project.writtenChapters) 章"
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148, alignment: .topLeading)
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
        .buttonStyle(.plain)
        .help("打开 \(project.title) 并定位到项目空间")
    }

    private func homeEmptyRecentProjectCard(
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)

                        Text("等待创建")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()

                    Text("空白项目卡")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .lineSpacing(3)

                HStack(spacing: 10) {
                    ProjectChapterPill(
                        label: "当前创作",
                        value: "未开始"
                    )

                    ProjectChapterPill(
                        label: "已创作",
                        value: "0 章"
                    )
                }

                HStack {
                    Spacer()

                    Label(actionTitle, systemImage: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.coolAccent)
                }
            }
            .contentShape(Rectangle())
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148, alignment: .topLeading)
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
        .buttonStyle(.plain)
    }

    private var homeRadarFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    homeMiniMetricCard(
                        title: "当前作品",
                        value: activeProject?.title ?? appState.activeWorkspaceName,
                        detail: activeProject?.genre ?? "工作区",
                        symbolName: SidebarItem.projects.symbolName,
                        action: openProjectsWorkspace
                    )

                    homeMiniMetricCard(
                        title: "当前章节",
                        value: activeProject?.currentChapterLabel ?? "未开始",
                        detail: activeProject?.currentChapterTitle ?? "等待落笔",
                        symbolName: SidebarItem.writingDesk.symbolName,
                        action: continueWriting
                    )

                    homeMiniMetricCard(
                        title: "已创作章节",
                        value: "\(activeProject?.writtenChapters ?? 0) 章",
                        detail: "打开章节树查看结构",
                        symbolName: SidebarItem.outline.symbolName,
                        action: openOutlineWorkspace
                    )

                    homeMiniMetricCard(
                        title: "设定资料",
                        value: "\(appState.totalReferenceDocumentCount) 份",
                        detail: "补齐世界观与角色库",
                        symbolName: SidebarItem.library.symbolName,
                        action: openLibraryWorkspace
                    )
                }

                VStack(spacing: 12) {
                    homeMiniMetricCard(
                        title: "当前作品",
                        value: activeProject?.title ?? appState.activeWorkspaceName,
                        detail: activeProject?.genre ?? "工作区",
                        symbolName: SidebarItem.projects.symbolName,
                        action: openProjectsWorkspace
                    )

                    HStack(spacing: 12) {
                        homeMiniMetricCard(
                            title: "当前章节",
                            value: activeProject?.currentChapterLabel ?? "未开始",
                            detail: activeProject?.currentChapterTitle ?? "等待落笔",
                            symbolName: SidebarItem.writingDesk.symbolName,
                            action: continueWriting
                        )

                        homeMiniMetricCard(
                            title: "已创作章节",
                            value: "\(activeProject?.writtenChapters ?? 0) 章",
                            detail: "打开章节树查看结构",
                            symbolName: SidebarItem.outline.symbolName,
                            action: openOutlineWorkspace
                        )

                        homeMiniMetricCard(
                            title: "设定资料",
                            value: "\(appState.totalReferenceDocumentCount) 份",
                            detail: "补齐世界观与角色库",
                            symbolName: SidebarItem.library.symbolName,
                            action: openLibraryWorkspace
                        )
                    }
                }
            }

            Text("把首页当作当天写作的起跑线：先看当前章节，再回到当前项目、章节树和设定资料继续推进。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
        }
    }

    private var writingPillarsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(appState.writingPillars) { pillar in
                Button {
                    switch appState.navigationDestination(for: pillar) {
                    case .projects:
                        appState.openProjectSpace()
                    case .writingDesk:
                        appState.openWritingDesk()
                    case .outline:
                        appState.openOutline()
                    case .library:
                        appState.openLibrary()
                    case .home:
                        appState.selectedSidebarItem = .home
                    }
                } label: {
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
                .buttonStyle(.plain)
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

    private var homeQuickStartFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日推荐路径")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button(action: openProjectsWorkspace) {
                        workflowStepTag(index: "01", title: "项目空间")
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.textSecondary)

                    Button(action: openOutlineWorkspace) {
                        workflowStepTag(index: "02", title: "章节树")
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.textSecondary)

                    Button(action: continueWriting) {
                        workflowStepTag(index: "03", title: "继续写作")
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button(action: openProjectsWorkspace) {
                        workflowStepTag(index: "01", title: "项目空间")
                    }
                    .buttonStyle(.plain)
                    Button(action: openOutlineWorkspace) {
                        workflowStepTag(index: "02", title: "章节树")
                    }
                    .buttonStyle(.plain)
                    Button(action: continueWriting) {
                        workflowStepTag(index: "03", title: "继续写作")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var homeWritingSkeletonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            writingPillarsSection

            VStack(alignment: .leading, spacing: 12) {
                Text("灵感入口")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(appState.inspirationSignals) { signal in
                            Button(action: openLibraryWorkspace) {
                                homeSignalChip(signal.title)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.inspirationSignals) { signal in
                            Button(action: openLibraryWorkspace) {
                                homeSignalChip(signal.title)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("人物关系图、世界观卡片和章节节奏盘会在下一步继续拆进项目空间。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button("项目空间", action: openProjectsWorkspace)
                        .buttonStyle(.bordered)
                    Button("章节树", action: openOutlineWorkspace)
                        .buttonStyle(.bordered)
                    Button("素材库", action: openLibraryWorkspace)
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button("项目空间", action: openProjectsWorkspace)
                        .buttonStyle(.bordered)
                    Button("章节树", action: openOutlineWorkspace)
                        .buttonStyle(.bordered)
                    Button("素材库", action: openLibraryWorkspace)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func homeMiniMetricCard(
        title: String,
        value: String,
        detail: String,
        symbolName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(palette.panelBase.opacity(palette.isDark ? 0.84 : 0.70))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(detail)
    }

    private func workflowStepTag(index: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(index)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(palette.coolAccent.opacity(0.92))
                )

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(palette.panelBase.opacity(palette.isDark ? 0.88 : 0.70))
        )
        .overlay(
            Capsule()
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    private func homeSignalChip(_ title: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(palette.warmAccent)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(palette.panelBase.opacity(palette.isDark ? 0.88 : 0.72))
        )
        .overlay(
            Capsule()
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
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

    private func presentNewProjectSheet() {
        isNewProjectSheetPresented = true
    }

    private var homeWorkspaceHint: String {
        if !homeImportStatusMessage.isEmpty {
            return homeImportStatusMessage
        }

        return "下一步建议：从首页进入“项目空间”，再把角色卡、章节树和写作面板串成完整流。"
    }

    private func presentWorldbuildingImport() {
        isImportingWorldbuilding = true
    }

    private func openLibraryWorkspace() {
        appState.openLibrary()
    }

    private func openProjectsWorkspace() {
        appState.openProjectSpace()
    }

    private func openOutlineWorkspace() {
        appState.openOutline()
    }

    private func continueWriting() {
        appState.continueWriting()
    }

    private func handleWorldbuildingImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else {
            homeImportStatusMessage = "当前还没有可接收设定资料的项目，先新建一个项目。"
            presentNewProjectSheet()
            return
        }

        do {
            let urls = try result.get()
            let documents = try urls.map(loadReferenceDocument)
            guard !documents.isEmpty else { return }

            appState.importReferenceDocuments(documents, for: project.id)
            appState.openWritingDesk(for: project.id)
            homeImportStatusMessage = "已为《\(project.title)》导入 \(documents.count) 份设定资料，接下来可以在写作台继续使用。"
        } catch {
            homeImportStatusMessage = "导入设定资料失败：\(error.localizedDescription)"
        }
    }

    private func loadReferenceDocument(from url: URL) throws -> ReferenceDocument {
        let content = try loadText(from: url)
        return ReferenceDocument(
            title: url.deletingPathExtension().lastPathComponent,
            content: content,
            importedAt: timestampLabel()
        )
    }

    private func loadText(from url: URL) throws -> String {
        try TextFileDecoding.loadText(from: url, usingSecurityScopedAccess: true)
    }

    private func timestampLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

struct PlaceholderWorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: SidebarItem
    @Bindable var appState: AppState
    @State private var isNewProjectSheetPresented = false

    private let contentTopPadding: CGFloat = 18
    private let contentHorizontalPadding: CGFloat = 32
    private let contentBottomPadding: CGFloat = 32

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    private var workspaceHeaderHeight: CGFloat? {
        472
    }

    private var workspaceHeaderAlignment: VerticalAlignment {
        .top
    }

    private var featuredQuote: LiteraryQuote? {
        LiteraryQuoteLibrary.quote(for: item, seed: appState.quoteSeed)
    }

    private var shouldShowFeaturedQuote: Bool {
        item != .home && item != .writingDesk
    }

    init(item: SidebarItem, appState: AppState) {
        self.item = item
        self.appState = appState
    }

    var body: some View {
        ZStack {
            PageBackground()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        DashboardSplitSection(alignment: workspaceHeaderAlignment) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(item.title)
                                    .font(.system(size: 42, weight: .bold, design: .serif))
                                    .foregroundStyle(palette.textPrimary)

                                Text(item.summary)
                                    .font(.title3)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineSpacing(4)

                                if shouldShowFeaturedQuote, let featuredQuote {
                                    writingQuotePanel(featuredQuote)
                                }

                                HStack(spacing: 10) {
                                    PillTag(text: item.title)
                                    PillTag(text: appState.activeWorkspaceName)
                                }

                                if let activeProject {
                                    workspaceContextStrip(for: activeProject)
                                }

                                if item == .projects {
                                    Spacer(minLength: 0)

                                    Button {
                                        isNewProjectSheetPresented = true
                                    } label: {
                                        Label("新建项目", systemImage: "plus")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .tint(palette.coolAccent)
                                }
                            }
                            .padding(24)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: workspaceHeaderHeight,
                                maxHeight: workspaceHeaderHeight,
                                alignment: .topLeading
                            )
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
                            WorkspaceUtilityCard(
                                appState: appState,
                                item: item,
                                fixedHeight: workspaceHeaderHeight
                            )
                        }

                        workspaceDetailSection
                    }
                    .padding(.top, contentTopPadding)
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.bottom, contentBottomPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(item)
                .background(TopAnchorBounceLockView())
                .onAppear {
                    scrollToExplicitProject(using: proxy, animated: false)
                }
                .onChange(of: item) {
                    scrollToExplicitProject(using: proxy, animated: false)
                }
                .onChange(of: appState.projectSpaceSelectionPulse) {
                    scrollToExplicitProject(using: proxy, animated: true)
                }
            }
        }
        .sheet(isPresented: $isNewProjectSheetPresented) {
            NewProjectSheet { title, length in
                appState.createProject(named: title, length: length)
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

    private func writingQuotePanel(_ quote: LiteraryQuote) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("写作引句", systemImage: "quote.opening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
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
                        .lineLimit(3)
                        .lineSpacing(4)

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
        .padding(16)
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

                Text("已创作 \(project.writtenChapters) 章")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(14)
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

    @ViewBuilder
    private var workspaceDetailSection: some View {
        if item == .projects {
            ProjectsWorkspacePanel(appState: appState)
        } else if item == .outline {
            OutlineWorkspacePanel(appState: appState)
        } else if item == .library {
            LibraryWorkspacePanel(appState: appState)
        } else {
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
    }

    private func scrollToExplicitProject(using proxy: ScrollViewProxy, animated: Bool) {
        guard item == .projects else { return }
        guard let projectID = appState.projectSpaceScrollTarget else { return }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.24)) {
                    proxy.scrollTo(projectID, anchor: .center)
                }
            } else {
                proxy.scrollTo(projectID, anchor: .center)
            }

            appState.clearProjectSpaceScrollTarget()
        }
    }
}

private struct CurrentProjectSnapshotCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let project: NovelProject
    let action: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
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

                        HStack(spacing: 8) {
                            Text(project.genre)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(palette.coolAccent)

                            Text(project.storyLengthTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(palette.panelBase.opacity(palette.isDark ? 0.88 : 0.72))
                                )
                        }
                    }

                    Text(project.summary)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(3)
                        .lineSpacing(3)

                    HStack(spacing: 14) {
                        Label(project.updatedAt, systemImage: "clock")
                        Label("已创作 \(project.writtenChapters) 章", systemImage: "text.book.closed")
                    }
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)

                    HStack(spacing: 10) {
                        ProjectChapterPill(
                            label: "当前创作",
                            value: project.currentChapterSummary
                        )

                        ProjectChapterPill(
                            label: "已创作",
                            value: "\(project.writtenChapters) 章"
                        )
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
        .buttonStyle(.plain)
        .help("打开当前项目并定位到项目空间")
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
        case .checking:
            return palette.coolAccent
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
    let fixedHeight: CGFloat?
    let content: Content

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    init(
        title: String,
        subtitle: String,
        fixedHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.fixedHeight = fixedHeight
        self.content = content()
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

            if fixedHeight != nil {
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .topLeading)
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
    let action: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
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

                Spacer(minLength: 0)
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
        .buttonStyle(.plain)
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
    let alignment: VerticalAlignment
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    init(
        alignment: VerticalAlignment = .top,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.alignment = alignment
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: alignment, spacing: 22) {
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
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.snapBackToTopIfNeeded()
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
    let fixedHeight: CGFloat?

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            utilityHeader

            switch item {
            case .projects:
                projectUtilityContent
            case .writingDesk:
                writingDeskUtilityContent
            case .outline:
                outlineUtilityContent
            case .library:
                libraryUtilityContent
            case .home:
                EmptyView()
            }
        }
        .padding(22)
        .frame(
            maxWidth: .infinity,
            minHeight: fixedHeight ?? 370,
            maxHeight: fixedHeight,
            alignment: .topLeading
        )
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
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
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
                WorkspaceMetricBadge(label: "已创作章节", value: "\(activeProject?.writtenChapters ?? 0) 章")
            }

            WorkspaceChecklist(
                title: "续写顺序建议",
                items: appState.recentProjects.prefix(3).map { "\($0.title) · \($0.updatedAt)" }
            )

            Button("进入写作台") {
                appState.openWritingDesk(for: activeProject?.id)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.coolAccent)
        }
    }

    private var writingDeskUtilityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let activeProject {
                utilityFeatureCard(
                    eyebrow: "当前章节",
                    title: activeProject.currentChapterSummary,
                    subtitle: activeProject.chapterFocus,
                    trailing: activeProject.updatedAt
                )
            }

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "正文词数", value: "\(activeProject?.draftWordCount ?? 0)")
                WorkspaceMetricBadge(label: "已创作章节", value: "\(activeProject?.writtenChapters ?? 0) 章")
            }

            WorkspaceChecklist(
                title: "写作入口",
                items: [
                    "在正文区直接续写当前章节",
                    "右侧随时调整本章目标和节奏",
                    "需要结构梳理时再切回章节树或项目空间"
                ]
            )
        }
    }

    private var outlineUtilityContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let activeProject {
                utilityFeatureCard(
                    eyebrow: "结构分布",
                    title: activeProject.currentChapterSummary,
                    subtitle: "围绕当前章节继续拆分场景、角色弧线和伏笔回收。",
                    trailing: activeProject.title
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        WorkspaceMetricBadge(label: "结构节点", value: "\(activeProject.structureNodeCount)")
                        WorkspaceMetricBadge(label: "场景推进", value: activeProject.sceneProgressStatusLabel)
                        WorkspaceMetricBadge(label: "角色弧线", value: activeProject.characterArcStatusLabel)
                        WorkspaceMetricBadge(label: "伏笔回收", value: activeProject.foreshadowStatusLabel)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            WorkspaceMetricBadge(label: "结构节点", value: "\(activeProject.structureNodeCount)")
                            WorkspaceMetricBadge(label: "场景推进", value: activeProject.sceneProgressStatusLabel)
                        }

                        HStack(spacing: 10) {
                            WorkspaceMetricBadge(label: "角色弧线", value: activeProject.characterArcStatusLabel)
                            WorkspaceMetricBadge(label: "伏笔回收", value: activeProject.foreshadowStatusLabel)
                        }
                    }
                }

                WorkspaceChecklist(
                    title: "章节树建议",
                    items: [
                        activeProject.hasStructureNotes ? "继续补齐卷章与节点之间的承接关系" : "先把全书章节骨架按卷章写出来",
                        activeProject.hasSceneProgressNotes ? "检查当前章节场景目标是否足够具体" : "把当前章节拆成 3 到 5 个场景推进点",
                        activeProject.hasOutlineSummary ? "AI 总结已生成，可补写到全局记忆" : "补完结构后再调用 AI 做一次结构总览"
                    ],
                    compact: true
                )
            } else {
                utilityFeatureCard(
                    eyebrow: "结构分布",
                    title: "等待选中书籍",
                    subtitle: "先在项目空间或首页选中一本书，再回到章节树整理结构。",
                    trailing: "章节树"
                )

                HStack(spacing: 12) {
                    WorkspaceMetricBadge(label: "角色弧线", value: "待选中")
                    WorkspaceMetricBadge(label: "伏笔回收", value: "待选中")
                }

                WorkspaceChecklist(
                    title: "章节树建议",
                    items: [
                        "先选中一本当前要整理的书",
                        "再补章节骨架、场景推进和角色弧线",
                        "最后调用 AI 汇总结构建议"
                    ],
                    compact: true
                )
            }
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
                WorkspaceMetricBadge(label: "素材总数", value: "\(activeProject?.referenceDocuments.count ?? 0)")
                WorkspaceMetricBadge(label: "分类数", value: "\(activeProject?.materialCategoriesWithContent.count ?? 0)")
            }

            WorkspaceChecklist(
                title: "优先建库",
                items: [
                    "先把人物、地点、组织和世界观素材分开归类",
                    "剧情草案和外部考据单独存放，避免和风格参考混杂",
                    "需要续写时再从素材库回到写作台调用这些资料"
                ]
            )
        }
    }

    private var itemUtilityTitle: String {
        switch item {
        case .projects:
            return "项目推进"
        case .writingDesk:
            return "正文创作"
        case .outline:
            return "结构导航"
        case .library:
            return "素材整理"
        case .home:
            return "工作卡"
        }
    }

    private var itemUtilitySubtitle: String {
        switch item {
        case .projects:
            return "把正在写的项目、最近更新和续写顺序放在同一张卡里。"
        case .writingDesk:
            return "直接回到当前章节，在原生编辑器里继续写正文。"
        case .outline:
            return "快速看结构分布、章节推进和回收节点。"
        case .library:
            return "优先补齐对当前创作最有用的人物与世界观资料。"
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

private struct ProjectsWorkspacePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    @State private var pendingDeletionProject: NovelProject?
    @State private var chapterBrowserProjectID: NovelProject.ID?

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        DashboardPanel(
            title: "项目列表",
            subtitle: "这里集中展示最近项目，创建新项目后也会立刻出现在这里。"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if appState.recentProjects.isEmpty {
                    Text("还没有项目。先用上方第一张卡片底部的“新建项目”开始一本书，创建后会立刻出现在这里。")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(appState.recentProjects) { project in
                    ProjectSpaceProjectRow(
                        project: project,
                        isSelected: appState.selectedProjectID == project.id,
                        onSelect: {
                            appState.selectProject(project.id)
                        },
                        onViewChapters: {
                            chapterBrowserProjectID = project.id
                        },
                        onDelete: {
                            pendingDeletionProject = project
                        }
                    )
                    .id(project.id)
                }
            }
        }
        .confirmationDialog(
            "删除项目",
            isPresented: Binding(
                get: { pendingDeletionProject != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionProject = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletionProject {
                Button("删除《\(pendingDeletionProject.title)》", role: .destructive) {
                    appState.deleteProject(pendingDeletionProject.id)
                    self.pendingDeletionProject = nil
                }
            }

            Button("取消", role: .cancel) {
                pendingDeletionProject = nil
            }
        } message: {
            if let pendingDeletionProject {
                Text("《\(pendingDeletionProject.title)》会从当前账号下的项目列表中移除，章节草稿、素材库和结构记录也会一起删除。")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { chapterBrowserProjectID != nil },
                set: { isPresented in
                    if !isPresented {
                        chapterBrowserProjectID = nil
                    }
                }
            )
        ) {
            if let chapterBrowserProjectID {
                ProjectSavedChaptersSheet(
                    appState: appState,
                    projectID: chapterBrowserProjectID
                )
            }
        }
    }
}

private struct LibraryWorkspacePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState

    @State private var selectedDocumentID: ReferenceDocument.ID?
    @State private var selectedCategory: ReferenceMaterialCategory?
    @State private var isImportingMaterials = false
    @State private var libraryStatusMessage = "素材库会按分类集中管理当前项目的用户素材。"

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    private var supportedImportTypes: [UTType] {
        [.plainText, .utf8PlainText, .text, .sourceCode]
    }

    var body: some View {
        Group {
            if let project = activeProject {
                libraryPanel(for: project)
            } else {
                DashboardPanel(
                    title: "素材库",
                    subtitle: "当前还没有选中的项目，先去项目空间选择一本书，再把素材按分类整理起来。"
                ) {
                    Button("前往项目空间") {
                        appState.openProjectSpace()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task(id: activeProject?.id) {
            selectedDocumentID = activeProject?.referenceDocuments.first?.id
            selectedCategory = nil
            libraryStatusMessage = "素材库会按分类集中管理当前项目的用户素材。"
        }
        .onChange(of: activeProject?.referenceDocuments) { _, documents in
            syncSelection(with: documents ?? [])
        }
        .fileImporter(
            isPresented: $isImportingMaterials,
            allowedContentTypes: supportedImportTypes,
            allowsMultipleSelection: true,
            onCompletion: handleMaterialImport
        )
    }

    private func libraryPanel(for project: NovelProject) -> some View {
        let selectedDocument = selectedDocument(for: project)

        return DashboardPanel(
            title: "分类素材库",
            subtitle: "把人物、地点、组织、世界观、剧情草案和外部考据按分类存放。写作台导入的参考资料也会自动进入这里。"
        ) {
            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "当前项目", value: project.title)
                WorkspaceMetricBadge(label: "素材总数", value: "\(project.referenceDocuments.count)")
                WorkspaceMetricBadge(label: "已用分类", value: "\(project.materialCategoriesWithContent.count)")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button("导入素材") {
                        isImportingMaterials = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.coolAccent)

                    Button("回写作台") {
                        appState.openWritingDesk(for: project.id)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button("导入素材") {
                        isImportingMaterials = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.coolAccent)

                    Button("回写作台") {
                        appState.openWritingDesk(for: project.id)
                    }
                    .buttonStyle(.bordered)
                }
            }

            categoryFilterRow(for: project)

            if project.referenceDocuments.isEmpty {
                WorkspaceChecklist(
                    title: "开始整理素材",
                    items: [
                        "从首页、写作台或这里导入文本资料",
                        "系统会先自动给素材分配一个分类",
                        "你可以在右侧预览里再手动调整到更准确的分类"
                    ]
                )
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        libraryDocumentList(for: project)
                            .frame(width: 360)

                        libraryDocumentDetail(selectedDocument, project: project)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        libraryDocumentList(for: project)
                        libraryDocumentDetail(selectedDocument, project: project)
                    }
                }
            }

            Label(libraryStatusMessage, systemImage: "books.vertical")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func categoryFilterRow(for project: NovelProject) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                LibraryCategoryChip(
                    title: "全部",
                    count: project.referenceDocuments.count,
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                ForEach(ReferenceMaterialCategory.allCases) { category in
                    LibraryCategoryChip(
                        title: category.title,
                        count: project.referenceDocuments(in: category).count,
                        isSelected: selectedCategory == category,
                        symbolName: category.symbolName
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func libraryDocumentList(for project: NovelProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selectedCategory == nil ? "分类列表" : "\(selectedCategory?.title ?? "")素材")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(displayedCategories(for: project), id: \.self) { category in
                        let documents = project.referenceDocuments(in: category)
                        if !documents.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(category.title, systemImage: category.symbolName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)

                                    Spacer()

                                    Text("\(documents.count) 份")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(palette.textSecondary)
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(documents) { document in
                                        Button {
                                            selectedDocumentID = document.id
                                        } label: {
                                            LibraryDocumentRow(
                                                document: document,
                                                isSelected: document.id == selectedDocument(for: project)?.id
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 260)
        }
    }

    private func libraryDocumentDetail(_ document: ReferenceDocument?, project: NovelProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let document {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(palette.textPrimary)

                        Text(document.category.summary)
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(document.importedAt)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)

                        Text("\(document.wordCount) 字")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                Picker("素材分类", selection: categoryBinding(for: document, projectID: project.id)) {
                    ForEach(ReferenceMaterialCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbolName)
                            .tag(category)
                    }
                }
                .pickerStyle(.menu)

                ScrollView {
                    Text(document.content)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(18)
                }
                .frame(minHeight: 320)
                .background(
                    DashboardInsetPanelBackground(cornerRadius: 22, palette: palette)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(palette.stroke, lineWidth: 1)
                )
            } else {
                WorkspaceChecklist(
                    title: "查看素材详情",
                    items: [
                        "从左侧挑一份素材查看正文",
                        "在这里修改素材分类，让库更清晰",
                        "需要继续写作时，再回写作台调用这些资料"
                    ]
                )
            }
        }
    }

    private func displayedCategories(for project: NovelProject) -> [ReferenceMaterialCategory] {
        if let selectedCategory {
            return project.referenceDocuments(in: selectedCategory).isEmpty ? [] : [selectedCategory]
        }

        return project.materialCategoriesWithContent
    }

    private func selectedDocument(for project: NovelProject) -> ReferenceDocument? {
        let visibleDocuments = displayedCategories(for: project)
            .flatMap { project.referenceDocuments(in: $0) }

        guard !visibleDocuments.isEmpty else { return nil }

        if let selectedDocumentID,
           let document = visibleDocuments.first(where: { $0.id == selectedDocumentID }) {
            return document
        }

        return visibleDocuments.first
    }

    private func categoryBinding(for document: ReferenceDocument, projectID: NovelProject.ID) -> Binding<ReferenceMaterialCategory> {
        Binding(
            get: {
                appState.project(for: projectID)?
                    .referenceDocuments
                    .first(where: { $0.id == document.id })?
                    .category ?? document.category
            },
            set: { newCategory in
                appState.updateReferenceDocumentCategory(newCategory, documentID: document.id, for: projectID)
                if selectedCategory != nil {
                    selectedCategory = newCategory
                }
                libraryStatusMessage = "已将《\(document.title)》归类到\(newCategory.title)。"
            }
        )
    }

    private func syncSelection(with documents: [ReferenceDocument]) {
        if let selectedDocumentID,
           documents.contains(where: { $0.id == selectedDocumentID }) {
            return
        }

        selectedDocumentID = documents.first?.id
    }

    private func handleMaterialImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else { return }

        do {
            let urls = try result.get()
            let documents = try urls.map(loadReferenceDocument)
            appState.importReferenceDocuments(documents, for: project.id)
            selectedDocumentID = documents.first?.id
            selectedCategory = documents.first?.category
            libraryStatusMessage = "已为《\(project.title)》导入 \(documents.count) 份素材，并自动放入对应分类。"
        } catch {
            libraryStatusMessage = "导入素材失败：\(error.localizedDescription)"
        }
    }

    private func loadReferenceDocument(from url: URL) throws -> ReferenceDocument {
        let content = try loadText(from: url)
        return ReferenceDocument(
            title: url.deletingPathExtension().lastPathComponent,
            content: content,
            importedAt: timestampLabel()
        )
    }

    private func loadText(from url: URL) throws -> String {
        try TextFileDecoding.loadText(from: url, usingSecurityScopedAccess: true)
    }

    private func timestampLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

private struct LibraryCategoryChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let count: Int
    let isSelected: Bool
    var symbolName: String?
    let action: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    init(
        title: String,
        count: Int,
        isSelected: Bool,
        symbolName: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.symbolName = symbolName
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.caption.weight(.semibold))
                }

                Text(title)
                    .font(.caption.weight(.semibold))

                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected ? palette.badgeFillSelected : palette.badgeFill)
                    )
            }
            .foregroundStyle(isSelected ? .white : palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? palette.coolAccent : palette.panelBase.opacity(palette.isDark ? 0.82 : 0.72))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? palette.coolAccent : palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryDocumentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let document: ReferenceDocument
    let isSelected: Bool

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(document.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(document.importedAt)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }

            Text(document.previewText)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            HStack {
                Label(document.category.title, systemImage: document.category.symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.coolAccent)

                Spacer()

                Text("\(document.wordCount) 字")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? palette.selectedPanel : palette.panelBase.opacity(palette.isDark ? 0.82 : 0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isSelected ? palette.coolAccent.opacity(0.36) : palette.stroke,
                    lineWidth: 1
                )
        )
    }
}

private struct ProjectSpaceProjectRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let project: NovelProject
    let isSelected: Bool
    let onSelect: () -> Void
    let onViewChapters: () -> Void
    let onDelete: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(palette.textPrimary)

                            Text(project.genre)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? palette.coolAccent : palette.textSecondary)
                        }

                        Spacer()

                        if isSelected {
                            Text("当前工作区")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.coolAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(palette.coolAccent.opacity(palette.isDark ? 0.16 : 0.10))
                                )
                        }

                        Text(project.updatedAt)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Text(project.summary)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)

                    HStack(spacing: 12) {
                        ProjectChapterPill(
                            label: "当前创作",
                            value: project.currentChapterSummary
                        )
                        WorkspaceMetricBadge(label: "已创作章节", value: "\(project.writtenChapters) 章")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack {
                Button(project.savedChapterCount == 0 ? "暂无章节" : "查看章节") {
                    onViewChapters()
                }
                .buttonStyle(.borderless)
                .disabled(project.savedChapterCount == 0)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label("删除项目", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.red)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(stroke)
        .shadow(color: isSelected ? palette.shadow.opacity(palette.isDark ? 0.40 : 0.18) : .clear, radius: 12, y: 8)
    }

    private var background: some View {
        GlassPanelBackground(
            cornerRadius: 24,
            palette: palette,
            tint: LinearGradient(
                colors: [
                    (isSelected ? palette.coolAccent : palette.warmAccent).opacity(palette.isDark ? 0.14 : 0.08),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var stroke: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                isSelected
                    ? palette.coolAccent.opacity(palette.isDark ? 0.48 : 0.36)
                    : palette.stroke,
                lineWidth: isSelected ? 1.4 : 1
            )
    }
}

struct ProjectChapterPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var projectTitle = ""
    @State private var selectedLength: NovelLength = .long
    let onCreate: (String, NovelLength) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建项目")
                .font(.title2.weight(.semibold))

            Text("先输入项目名称，再选择短篇、中篇或长篇模式，系统会带上对应的结构模板和写作辅助。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                Text("项目名称")
                    .font(.subheadline.weight(.semibold))

                TextField("例如：雾港纪事", text: $projectTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .onSubmit(createProject)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("创作模式")
                    .font(.subheadline.weight(.semibold))

                Picker("创作模式", selection: $selectedLength) {
                    ForEach(NovelLength.allCases) { length in
                        Text(length.title).tag(length)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(selectedLength.title)
                            .font(.headline.weight(.bold))

                        Text(selectedLength.targetRangeSummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(selectedLength.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedLength.creationChecklist, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("创建", action: createProject)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            DispatchQueue.main.async {
                isNameFieldFocused = true
            }
        }
    }

    private func createProject() {
        let trimmedTitle = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        onCreate(trimmedTitle, selectedLength)
        dismiss()
    }
}

struct WorkspaceMetricBadge: View {
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

struct WorkspaceChecklist: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let items: [String]
    let compact: Bool

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    init(title: String, items: [String], compact: Bool = false) {
        self.title = title
        self.items = items
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(palette.coolAccent)
                            .frame(width: compact ? 7 : 8, height: compact ? 7 : 8)
                            .padding(.top, compact ? 5 : 6)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(compact ? 14 : 16)
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
                .fill(palette.glassUnderlay)

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
                            palette.glassHighlightStrong,
                            .clear,
                            palette.glassHighlightSoft
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

private struct DashboardInsetPanelBackground: View {
    let cornerRadius: CGFloat
    let palette: DashboardPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.insetPanel)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.glassHighlightStrong.opacity(palette.isDark ? 0.55 : 0.80),
                            .clear,
                            palette.glassHighlightSoft.opacity(palette.isDark ? 0.65 : 0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

struct DashboardPalette {
    let isDark: Bool
    let backgroundTop: Color
    let backgroundBottom: Color
    let panelBase: Color
    let panelSecondary: Color
    let insetPanel: Color
    let selectedPanel: Color
    let textPrimary: Color
    let textSecondary: Color
    let warmAccent: Color
    let coolAccent: Color
    let successAccent: Color
    let badgeFill: Color
    let badgeFillSelected: Color
    let glassUnderlay: Color
    let glassHighlightStrong: Color
    let glassHighlightSoft: Color
    let stroke: Color
    let shadow: Color

    init(colorScheme: ColorScheme) {
        isDark = colorScheme == .dark

        if isDark {
            backgroundTop = Color(red: 0.04, green: 0.04, blue: 0.05)
            backgroundBottom = Color(red: 0.10, green: 0.10, blue: 0.12)
            panelBase = Color(red: 0.12, green: 0.12, blue: 0.14)
            panelSecondary = Color(red: 0.07, green: 0.07, blue: 0.09)
            insetPanel = Color(red: 0.09, green: 0.09, blue: 0.11).opacity(0.98)
            selectedPanel = Color(red: 0.17, green: 0.19, blue: 0.23).opacity(0.96)
            textPrimary = Color.white.opacity(0.96)
            textSecondary = Color.white.opacity(0.70)
            warmAccent = Color(red: 1.00, green: 0.53, blue: 0.33)
            coolAccent = Color(red: 0.26, green: 0.72, blue: 0.98)
            successAccent = Color(red: 0.43, green: 0.84, blue: 0.66)
            badgeFill = Color.white.opacity(0.10)
            badgeFillSelected = Color.white.opacity(0.16)
            glassUnderlay = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.96)
            glassHighlightStrong = Color.white.opacity(0.06)
            glassHighlightSoft = Color.white.opacity(0.015)
            stroke = Color.white.opacity(0.12)
            shadow = Color.black.opacity(0.52)
        } else {
            backgroundTop = Color(red: 0.98, green: 0.96, blue: 0.93)
            backgroundBottom = Color(red: 0.92, green: 0.95, blue: 0.99)
            panelBase = Color.white.opacity(0.70)
            panelSecondary = Color(red: 0.94, green: 0.96, blue: 0.99).opacity(0.72)
            insetPanel = Color.white.opacity(0.82)
            selectedPanel = Color.white.opacity(0.82)
            textPrimary = Color(red: 0.12, green: 0.13, blue: 0.20)
            textSecondary = Color(red: 0.30, green: 0.34, blue: 0.43)
            warmAccent = Color(red: 0.92, green: 0.55, blue: 0.30)
            coolAccent = Color(red: 0.27, green: 0.56, blue: 0.92)
            successAccent = Color(red: 0.26, green: 0.68, blue: 0.52)
            badgeFill = Color.white.opacity(0.18)
            badgeFillSelected = Color.white.opacity(0.32)
            glassUnderlay = Color.white.opacity(0.44)
            glassHighlightStrong = Color.white.opacity(0.38)
            glassHighlightSoft = Color.white.opacity(0.12)
            stroke = Color.white.opacity(0.58)
            shadow = Color.black.opacity(0.10)
        }
    }
}


private struct HeroMinYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension String {
    var trimmedForWorkspace: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonWhitespaceCount: Int {
        unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }
}
