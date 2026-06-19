import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

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
                .background(ScrollTopBounceLockView())
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
                subtitle: "先从当前项目和章节树开始，把创作推进接回主线。"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("先选中一本正在推进的作品。", systemImage: "checkmark.circle")
                    Label("在设置里确认模型连接和外观模式。", systemImage: "gearshape")
                    Label("回到写作台继续正文、素材和章节结构。", systemImage: "square.grid.2x2")
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
                WorkspaceMetricBadge(label: "全书字数", value: "\(activeProject?.manuscriptWordCount ?? 0)")
                WorkspaceMetricBadge(label: "当前章", value: "\(activeProject?.draftWordCount ?? 0)")
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
                eyebrow: "当前资源焦点",
                title: appState.activeWorkspaceName,
                subtitle: activeProject?.summary ?? "把人物、地点、组织、世界观素材和写作 Skill 集中收纳。",
                trailing: activeProject?.genre ?? "创作资源"
            )

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "素材总数", value: "\(activeProject?.referenceDocuments.count ?? 0)")
                WorkspaceMetricBadge(label: "Skill", value: "\(appState.writingSkills.count)")
                WorkspaceMetricBadge(label: "已启用", value: "\(appState.enabledWritingSkills.count)")
            }

            WorkspaceChecklist(
                title: "优先建库",
                items: [
                    "先把人物、地点、组织和世界观素材分开归类",
                    "把常用文风、结构、修订规则整理成可启用 Skill",
                    "需要续写时再从创作资源回到写作台调用这些资料"
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
            return "创作资源"
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
            return "优先补齐对当前创作最有用的素材与写作 Skill。"
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
    @State private var exportStatusMessage = "本地导出会生成项目备份、分章 Markdown、全书 Markdown、DOCX 和 EPUB。"

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        DashboardPanel(
            title: "项目列表",
            subtitle: exportStatusMessage
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button("导入备份") {
                            importProjectBackup()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.coolAccent)

                        Text("选择 OpenWriting 导出的文件夹，验证完整后会作为项目恢复。")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button("导入备份") {
                            importProjectBackup()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.coolAccent)

                        Text("选择 OpenWriting 导出的文件夹，验证完整后会作为项目恢复。")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

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
                        onExport: {
                            exportProject(project)
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

    private func exportProject(_ project: NovelProject) {
        let panel = NSSavePanel()
        panel.title = "导出《\(project.title)》"
        panel.nameFieldStringValue = "\(project.title)-OpenWriting-Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let exportProject = appState.hydratedProjectForFullText(project.id) ?? project
            let summary = try ProjectExportService.exportProject(exportProject, to: url)
            exportStatusMessage = "已导出 \(summary.fileCount) 个文件到 \(summary.directoryURL.path)。"
            NSWorkspace.shared.activateFileViewerSelecting([summary.directoryURL])
        } catch {
            exportStatusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importProjectBackup() {
        let panel = NSOpenPanel()
        panel.title = "导入 OpenWriting 备份"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let report = try ProjectExportService.validateExport(at: url)
            let importedProject = appState.importProjectBackup(report.project)
            exportStatusMessage = "已验证 \(report.manifestFileCount) 个备份文件，并恢复《\(importedProject.title)》。"
        } catch {
            exportStatusMessage = "导入备份失败：\(error.localizedDescription)"
        }
    }
}

private struct LibraryWorkspacePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState

    @State private var selectedDocumentID: ReferenceDocument.ID?
    @State private var selectedCategory: ReferenceMaterialCategory?
    @State private var selectedResourceMode: LibraryResourceMode = .materials
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
        VStack(alignment: .leading, spacing: 16) {
            Picker("资源类型", selection: $selectedResourceMode) {
                ForEach(LibraryResourceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            switch selectedResourceMode {
            case .materials:
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
            case .skills:
                WritingSkillLibraryView(appState: appState)
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
            let documents = try ReferenceDocumentImporting.documents(from: urls)
            appState.importReferenceDocuments(documents, for: project.id)
            selectedDocumentID = documents.first?.id
            selectedCategory = documents.first?.category
            libraryStatusMessage = "已为《\(project.title)》导入 \(documents.count) 份素材，并自动放入对应分类。"
        } catch {
            libraryStatusMessage = "导入素材失败：\(error.localizedDescription)"
        }
    }

}

private enum LibraryResourceMode: String, CaseIterable, Identifiable {
    case materials
    case skills

    var id: Self { self }

    var title: String {
        switch self {
        case .materials:
            return "素材库"
        case .skills:
            return "Skill 广场"
        }
    }

    var symbolName: String {
        switch self {
        case .materials:
            return "books.vertical"
        case .skills:
            return "wand.and.stars"
        }
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
    let onExport: () -> Void
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
                        WorkspaceMetricBadge(label: "全书字数", value: "\(project.manuscriptWordCount)")
                        WorkspaceMetricBadge(label: "完成度", value: project.completionStatusLabel)
                        WorkspaceMetricBadge(label: "目录检查", value: project.chapterIntegrityStatusLabel)
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

                Button("导出") {
                    onExport()
                }
                .buttonStyle(.borderless)

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
