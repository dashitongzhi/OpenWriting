import SwiftUI

// MARK: - Home Dashboard Workspace Panels
//
// Extracted workspace panels from HomeDashboardView.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Projects Workspace Panel

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
                if appState.recentProjects.isEmpty {
                    Text("还没有项目。先用上方第一张卡片底部的"新建项目"开始一本书，创建后会立刻出现在这里。")
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
}

// MARK: - Library Workspace Panel

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
                DashboardPanel(
                    title: "素材库",
                    subtitle: libraryStatusMessage
                ) {
                    libraryContent(for: project)
                }
            } else {
                DashboardPanel(
                    title: "素材库",
                    subtitle: "当前没有打开的项目，无法使用素材库。"
                ) {
                    emptyLibraryView
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingMaterials,
            allowedContentTypes: supportedImportTypes,
            allowsMultipleSelection: true,
            onCompletion: handleMaterialsImport
        )
    }

    @ViewBuilder
    private func libraryContent(for project: NovelProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if project.referenceDocuments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("还没有素材文档。")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)

                    Text("从本地导入角色卡、大纲片段或风格参考文本，AI 写作时会从中获取上下文。")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)

                    Button {
                        isImportingMaterials = true
                    } label: {
                        Label("导入素材", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text("共 \(project.referenceDocuments.count) 份文档")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)

                    Spacer()

                    Button {
                        isImportingMaterials = true
                    } label: {
                        Label("导入", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach(project.referenceDocuments) { doc in
                    ReferenceDocumentRow(document: doc)
                }
            }
        }
    }

    private var emptyLibraryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("打开一个项目后，才能使用素材库功能。")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)

            Text("建议优先完成项目创建或打开现有项目。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleMaterialsImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else { return }

        do {
            let urls = try result.get()
            let documents = try ReferenceDocumentImporting.documents(from: urls)
            guard !documents.isEmpty else { return }

            appState.importReferenceDocuments(documents, for: project.id)
            libraryStatusMessage = "已导入 \(documents.count) 份素材文档。"
        } catch {
            libraryStatusMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Reference Document Row

private struct ReferenceDocumentRow: View {
    let document: ReferenceDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text("\(document.content.count) 字")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

// MARK: - Placeholder Workspace View

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
                Text(""")
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

// MARK: - Workspace Utility Card

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
                        palette.warmAccent.opacity(palette.isDark ? 0.16 : 0.10),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(panelStroke(cornerRadius: 32))
    }

    private var utilityHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快捷入口")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            Text("从这里快速通往核心工作区。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var projectUtilityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let project = activeProject {
                Text("《\(project.title)》")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Text(project.genre)
                    .font(.subheadline)
                    .foregroundStyle(palette.coolAccent)

                HStack(spacing: 10) {
                    Button("打开写作台") {
                        appState.openWritingDesk(for: project.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.coolAccent)

                    Button("章节树") {
                        appState.openOutline(for: project.id)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("当前没有打开的项目。")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)

                Button("新建项目") {
                    // Handled by parent
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.coolAccent)
            }
        }
    }

    @ViewBuilder
    private var writingDeskUtilityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("写作台")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            Text("创作核心区，支持 AI 续写、润色和质量管理。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
        }
    }

    @ViewBuilder
    private var outlineUtilityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("章节树")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            Text("管理卷章结构、查看写作进度和草稿状态。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
        }
    }

    @ViewBuilder
    private var libraryUtilityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("素材库")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            Text("集中管理参考文档、角色设定和世界观资料。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
        }
    }

    private func panelStroke(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(palette.isDark ? 0.14 : 0.72),
                        palette.coolAccent.opacity(palette.isDark ? 0.12 : 0.08),
                        Color.white.opacity(palette.isDark ? 0.06 : 0.38)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}