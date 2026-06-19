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
            .background(ScrollTopBounceLockView())
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

            Text("把灵感、设定与结构，变成真正的作品！")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("把今天要写的章节、项目资料和 AI 协作状态放在一个起手台里。先确认作品方向，再回到正文继续推进。")
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
                PillTag(text: "章节结构")
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

            QuickActionRow(
                title: "导入写作 Skill",
                subtitle: "把文风、结构和修订策略整理成可启用的创作能力。",
                symbolName: "wand.and.stars",
                action: openLibraryWorkspace
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
                WorkspaceMetricBadge(label: "已保存字数", value: "\(appState.totalSavedChapterWordCount)")
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
                        label: "全书字数",
                        value: "\(project.manuscriptWordCount)"
                    )

                    ProjectChapterPill(
                        label: "完成度",
                        value: project.completionStatusLabel
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
                        title: "创作资源",
                        value: "\(appState.totalReferenceDocumentCount) 份",
                        detail: "整理素材与写作 Skill",
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
                            title: "创作资源",
                            value: "\(appState.totalReferenceDocumentCount) 份",
                            detail: "整理素材与写作 Skill",
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
                    Button("创作资源", action: openLibraryWorkspace)
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button("项目空间", action: openProjectsWorkspace)
                        .buttonStyle(.bordered)
                    Button("章节树", action: openOutlineWorkspace)
                        .buttonStyle(.bordered)
                    Button("创作资源", action: openLibraryWorkspace)
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
            let documents = try ReferenceDocumentImporting.documents(from: urls)
            guard !documents.isEmpty else { return }

            appState.importReferenceDocuments(documents, for: project.id)
            appState.openWritingDesk(for: project.id)
            homeImportStatusMessage = "已为《\(project.title)》导入 \(documents.count) 份设定资料，接下来可以在写作台继续使用。"
        } catch {
            homeImportStatusMessage = "导入设定资料失败：\(error.localizedDescription)"
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
