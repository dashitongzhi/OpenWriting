import Observation
import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct WritingDeskView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    let openSettings: () -> Void

    @FocusState private var focusedArea: FocusArea?
    @State private var isImportingReferences = false
    @State private var isImportingOutline = false
    @State private var isImportingRequirements = false
    @State private var isOutlineGeneratorPresented = false
    @State private var isDraftPolishSheetPresented = false
    @State private var isSelectionPolishPopoverPresented = false
    @State private var aiSuggestion = ""
    @State private var aiStatusMessage = "准备就绪，可先补大纲、参考文本和特殊要求，再开始当前章节写作。"
    @State private var saveMessage = "自动保存已开启，可按章节收录"
    @State private var chapterNavigationSearchText = ""
    @State private var isChapterNavigatorPresented = false
    @State private var isGenerating = false
    @State private var isSavingChapter = false
    @State private var outlineGenerationTask: Task<Void, Never>?
    @State private var writingGenerationTask: Task<Void, Never>?
    @State private var outlineGenerationToken: UUID?
    @State private var writingGenerationToken: UUID?
    @State private var projectContextRefreshTokens: [NovelProject.ID: UUID] = [:]
    @State private var isCacheCollapsed = false
    @State private var autoScrollLocked = false
    @State private var areConfigurationCardsCollapsed = false
    @State private var pendingScrollAnchor: WritingDeskScrollAnchor?
    @State private var timingSnapshot = AIWriterTimingSnapshot.idle
    @State private var writingProgressTask: Task<Void, Never>?
    @State private var writingStopTask: Task<Void, Never>?
    @State private var writingRunState = WritingRunState.idle
    @State private var draftSelection = WritingDeskDraftSelection.empty
    @State private var draftSelectionActionPoint: CGPoint?
    @State private var draftEditorFocusToken = UUID()
    @State private var draftPolishInstruction = ""
    @State private var selectionPolishInstruction = ""
    @State private var selectionPolishTarget: WritingDeskDraftSelection?
    @State private var selectionPolishAnchorPoint: CGPoint?
    @State private var activeDraftPolishMode: DraftPolishMode?
    @State private var pendingDraftPolishReview: DraftPolishReview?
    @State private var pendingDraftPolishReviewAnchorPoint: CGPoint?
    @State private var latestChapterReview: ChapterReviewResult?
    @State private var latestChapterReviewDraftContext: ChapterSaveValidationContext?
    @State private var latestReviewedAISuggestionText = ""
    @State private var latestAISuggestionAcceptanceContext: AISuggestionAcceptanceContext?
    @State private var latestStrandWarning: StrandWeaveState.PacingWarning?
    @State private var pendingChapterLoad: ChapterDraftMetadata?
    @State private var qualityReviewDashboardPresentation: QualityReviewDashboardPresentation?
    @State private var operationAlert: WritingDeskOperationAlert?
    @State private var isFindReplacePresented = false
    @State private var findQuery = ""
    @State private var replacementText = ""
    @State private var findStatusMessage = ""

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }
    @State private var thinkingMode = AIWriterThinkingMode.writing
    @State private var thinkingStepIndex = 0
    @State private var rewriteDirection = AIRewriteDirection.freshTake

    private let contentTopPadding: CGFloat = 18
    private let contentHorizontalPadding: CGFloat = 32
    private let contentBottomPadding: CGFloat = 32
    private let workspaceSpacing: CGFloat = 22

    private enum FocusArea: Hashable {
        case draft
        case ai
    }

    private struct WritingDeskOperationAlert: Identifiable {
        let id = UUID()
        var title: String
        var message: String
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
        GeometryReader { geometry in
            ZStack {
                PageBackground()
                writingDeskViewport(in: geometry.size)
            }
        }
        .task(id: activeProject.map { writingSessionKey(for: $0) }) {
            resetSessionState()
        }
        .fileImporter(
            isPresented: $isImportingReferences,
            allowedContentTypes: supportedImportTypes,
            allowsMultipleSelection: true,
            onCompletion: handleReferenceImport
        )
        .fileImporter(
            isPresented: $isImportingOutline,
            allowedContentTypes: supportedImportTypes,
            allowsMultipleSelection: false,
            onCompletion: handleOutlineImport
        )
        .fileImporter(
            isPresented: $isImportingRequirements,
            allowedContentTypes: supportedImportTypes,
            allowsMultipleSelection: false,
            onCompletion: handleRequirementsImport
        )
        .sheet(isPresented: $isOutlineGeneratorPresented) {
            if let activeProject {
                WritingDeskOutlineGeneratorSheet(
                    projectTitle: activeProject.title,
                    storyLength: activeProject.storyLength,
                    profile: outlineGenerationProfileBinding(for: activeProject.id),
                    isGenerating: isGenerating,
                    onGenerate: {
                        generateOutline(for: appState.project(for: activeProject.id) ?? activeProject)
                    }
                )
            }
        }
        .sheet(isPresented: $isDraftPolishSheetPresented) {
            if let activeProject {
                DraftPolishSheet(
                    projectTitle: activeProject.title,
                    instruction: $draftPolishInstruction,
                    isProcessing: isGenerating || isSavingChapter,
                    onSubmit: {
                        polishEntireDraft(for: activeProject)
                    }
                )
            }
        }
        .sheet(item: $pendingChapterLoad) { metadata in
            if let activeProject {
                ChapterLoadDiffSheet(
                    project: activeProject,
                    targetMetadata: metadata,
                    onOverwrite: {
                        loadChapterFromNavigator(metadata, for: activeProject)
                    },
                    onSaveFirst: {
                        pendingChapterLoad = nil
                        saveCurrentChapterDraft(for: activeProject)
                    },
                    onCancel: {
                        pendingChapterLoad = nil
                    }
                )
            }
        }
        .sheet(item: $qualityReviewDashboardPresentation) { presentation in
            QualityReviewDashboardView(
                result: presentation.review,
                chapterTitle: presentation.chapterTitle,
                minimumAcceptedScore: presentation.minimumAcceptedScore
            )
            .frame(minWidth: 760, idealWidth: 860, minHeight: 720, idealHeight: 820)
        }
        .alert(item: $operationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .onChange(of: draftSelection) { _, selection in
            if !selection.hasSelection && selectionPolishTarget == nil {
                isSelectionPolishPopoverPresented = false
            }
        }
        .onChange(of: isSelectionPolishPopoverPresented) { _, isPresented in
            if !isPresented {
                selectionPolishTarget = nil
                selectionPolishAnchorPoint = nil
                selectionPolishInstruction = ""
            }
        }
        .onChange(of: findQuery) { _, _ in
            findStatusMessage = ""
        }
    }

    @ViewBuilder
    private func writingDeskViewport(in size: CGSize) -> some View {
        if let activeProject {
            if appState.isWritingFocusModeEnabled {
                focusedWritingWorkspace(for: activeProject, containerSize: size)
            } else if areConfigurationCardsCollapsed {
                collapsedWritingDeskWorkspace(for: activeProject, containerSize: size)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: workspaceSpacing) {
                            writingDeskConfigurationRow(for: activeProject)
                            writingDeskStatusStrip(for: activeProject)
                            writingDeskCreationRow(for: activeProject)
                        }
                        .padding(.top, contentTopPadding)
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.bottom, contentBottomPadding)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(ScrollTopBounceLockView())
                    .onChange(of: pendingScrollAnchor) { _, target in
                        guard let target else { return }

                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(target.rawValue, anchor: target == .cache ? .bottom : .top)
                        }

                        pendingScrollAnchor = nil
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: workspaceSpacing) {
                emptyState
            }
            .padding(.top, contentTopPadding)
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.bottom, contentBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func focusedWritingWorkspace(for project: NovelProject, containerSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("专注写作", systemImage: "rectangle.compress.vertical")
                    .font(.headline)

                Text(project.currentChapterSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    appState.isWritingFocusModeEnabled = false
                } label: {
                    Label("退出专注", systemImage: "rectangle.expand.vertical")
                }
                .buttonStyle(.bordered)
                .help("恢复完整写作台")
            }

            writingDeskDraftColumn(
                for: project,
                layout: WritingDeskCollapsedLayout(
                    containerSize: containerSize,
                    topPadding: contentTopPadding + 44,
                    bottomPadding: contentBottomPadding,
                    spacing: workspaceSpacing,
                    showCachePanel: false,
                    showTimeline: false,
                    reservesConfigurationCards: false
                )
            )
        }
        .padding(.top, contentTopPadding)
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.bottom, contentBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func collapsedWritingDeskWorkspace(for project: NovelProject, containerSize: CGSize) -> some View {
        let layout = WritingDeskCollapsedLayout(
            containerSize: containerSize,
            topPadding: contentTopPadding,
            bottomPadding: contentBottomPadding,
            spacing: workspaceSpacing,
            showCachePanel: appState.showWritingDeskCachePanel,
            showTimeline: appState.showWritingDeskTimeline
        )

        return VStack(alignment: .leading, spacing: workspaceSpacing) {
            writingDeskConfigurationRow(for: project, isCollapsed: true)
            writingDeskStatusStrip(for: project)
            writingDeskCreationRow(for: project, layout: layout)
        }
        .padding(.top, contentTopPadding)
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.bottom, contentBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func writingDeskConfigurationRow(for project: NovelProject, isCollapsed: Bool = false) -> some View {
        let cards = HStack(alignment: .top, spacing: workspaceSpacing) {
            writingDeskOutlineCard(for: project, isCollapsed: isCollapsed)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            writingDeskReferenceCard(for: project, isCollapsed: isCollapsed)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            writingDeskRequirementsCard(for: project, isCollapsed: isCollapsed)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        return Group {
            if isCollapsed {
                cards
                    .frame(height: WritingDeskCollapsedLayout.configurationCardHeight, alignment: .topLeading)
            } else {
                ViewThatFits(in: .horizontal) {
                    cards

                    VStack(alignment: .leading, spacing: workspaceSpacing) {
                        writingDeskOutlineCard(for: project)
                        writingDeskReferenceCard(for: project)
                        writingDeskRequirementsCard(for: project)
                    }
                }
            }
        }
    }

    private func writingDeskStatusStrip(for project: NovelProject) -> some View {
        let review = displayedChapterReview(for: project)
        let minimumScore = LongformStorySystem.minimumAcceptedScore(for: project.storyLength)
        let qualityTrend = project.longformQualityTrend
        let storageHealth = appState.storageHealthReport(for: project.id)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                WritingDeskStatusPill(
                    title: "保存",
                    value: saveMessage,
                    symbolName: "tray.and.arrow.down",
                    tint: .secondary
                )

                WritingDeskStatusPill(
                    title: "同步",
                    value: appState.cloudSyncTitle,
                    symbolName: appState.cloudSyncSymbolName,
                    tint: appState.cloudSyncTitle.contains("失败") ? .red : palette.activeAccent
                )

                WritingDeskStatusPill(
                    title: "质量",
                    value: review.map { "\($0.overallScore)/100 · 最低 \(minimumScore)" } ?? "待审查",
                    symbolName: review?.passes(minimumScore: minimumScore) == true ? "checkmark.seal.fill" : "exclamationmark.circle",
                    tint: review?.passes(minimumScore: minimumScore) == true ? palette.readyAccent : palette.warningAccent
                )

                WritingDeskStatusPill(
                    title: "质量债",
                    value: "\(qualityTrend.qualityDebtTargets.count + qualityTrend.revisionHints.count) 项",
                    symbolName: "list.bullet.clipboard",
                    tint: qualityTrend.qualityDebtTargets.isEmpty && qualityTrend.revisionHints.isEmpty ? .secondary : palette.warningAccent
                )

                WritingDeskStatusPill(
                    title: "存储",
                    value: storageHealth.status.displayName,
                    symbolName: storageHealth.status == .blocked ? "externaldrive.badge.exclamationmark" : "externaldrive",
                    tint: storageHealthColor(storageHealth.status)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    WritingDeskStatusPill(
                        title: "保存",
                        value: saveMessage,
                        symbolName: "tray.and.arrow.down",
                        tint: .secondary
                    )
                    WritingDeskStatusPill(
                        title: "同步",
                        value: appState.cloudSyncTitle,
                        symbolName: appState.cloudSyncSymbolName,
                        tint: palette.activeAccent
                    )
                }

                HStack(spacing: 8) {
                    WritingDeskStatusPill(
                        title: "质量",
                        value: review.map { "\($0.overallScore)/100" } ?? "待审查",
                        symbolName: "checklist",
                        tint: review?.passes(minimumScore: minimumScore) == true ? palette.readyAccent : palette.warningAccent
                    )
                    WritingDeskStatusPill(
                        title: "存储",
                        value: storageHealth.status.displayName,
                        symbolName: "externaldrive",
                        tint: storageHealthColor(storageHealth.status)
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.panelBase.opacity(palette.isDark ? 0.64 : 0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.editorBorder, lineWidth: 1)
        )
    }

    private func writingDeskCreationRow(for project: NovelProject, layout: WritingDeskCollapsedLayout? = nil) -> some View {
        let horizontalLayout = HStack(alignment: .top, spacing: workspaceSpacing) {
            writingDeskDraftColumn(for: project, layout: layout)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            writingDeskAIColumn(for: project, layout: layout)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }

        return Group {
            if let layout {
                horizontalLayout
                    .frame(height: layout.creationRowHeight, alignment: .top)
            } else {
                horizontalLayout
            }
        }
    }

    private func writingDeskOutlineCard(for project: NovelProject, isCollapsed: Bool = false) -> some View {
        WritingDeskSectionCard(
            title: "大纲设定",
            badgeText: isCollapsed ? (project.hasOutline ? "已导入" : "未导入") : nil,
            actions: configurationActions(
                importAction: {
                    isImportingOutline = true
                },
                supplementalActions: [
                    WritingDeskToolbarAction(
                        symbolName: "wand.and.stars",
                        accessibilityLabel: "填写大纲生成参数"
                    ) {
                        isOutlineGeneratorPresented = true
                    }
                ]
            ),
            isCollapsed: isCollapsed
        ) {
            HStack(alignment: .center, spacing: 10) {
                PillTag(text: project.title)
                PillTag(text: project.storyLengthTitle)
                PillTag(text: project.currentChapterSummary)
            }

            writingDeskOutlineGeneratorControls(for: project)

            WritingDeskTextSurface(
                text: outlineBinding(for: project.id),
                placeholder: "输入小说大纲、卷章结构或本章计划…",
                minHeight: 210
            )

            Text(project.hasOutline ? "当前大纲已接入，AI 会优先参考这里的结构。" : "可直接粘贴大纲，或从文本文件导入。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func writingDeskReferenceCard(for project: NovelProject, isCollapsed: Bool = false) -> some View {
        WritingDeskSectionCard(
            title: "参考文本",
            badgeText: isCollapsed ? "\(project.referenceDocuments.count) 份" : nil,
            actions: configurationActions(importAction: {
                isImportingReferences = true
            }),
            isCollapsed: isCollapsed
        ) {
            WritingDeskTextSurface(
                text: referenceContextBinding(for: project.id),
                placeholder: "输入风格参考、上下文片段或你希望 AI 靠近的语气样文…",
                minHeight: 210
            )

            Text(referenceImportSummary(for: project))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func writingDeskRequirementsCard(for project: NovelProject, isCollapsed: Bool = false) -> some View {
        WritingDeskSectionCard(
            title: "特殊要求",
            badgeText: isCollapsed ? "字数设定" : nil,
            actions: configurationActions(importAction: {
                isImportingRequirements = true
            }),
            isCollapsed: isCollapsed
        ) {
            WritingDeskTextSurface(
                text: specialRequirementsBinding(for: project.id),
                placeholder: "输入本章特殊要求、语气限制、不能违背的设定或必须保留的伏笔…",
                minHeight: 152
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("字数设定")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                WritingDeskTextSurface(
                    text: wordTargetBinding(for: project.id),
                    placeholder: "例如：本章 1800-2200 字；全书约 80 万字；关键情节可上浮 20%",
                    minHeight: 84
                )
            }

            Text("这些约束会和全局记忆一起送进 AI，写作时会持续参考。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("当前模式：\(project.storyLengthTitle) · \(project.storyLength.summary)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func writingDeskDraftColumn(for project: NovelProject, layout: WritingDeskCollapsedLayout? = nil) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            WritingDeskSectionCard(
                title: "草稿箱",
                badgeText: "\(project.draftWordCount) 字",
                actions: [
                    WritingDeskToolbarAction(
                        symbolName: "magnifyingglass",
                        accessibilityLabel: isFindReplacePresented ? "关闭查找替换" : "打开查找替换",
                        isEnabled: true
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isFindReplacePresented.toggle()
                        }
                        if isFindReplacePresented {
                            focusDraftEditor()
                        }
                    },
                    WritingDeskToolbarAction(
                        symbolName: "sparkles",
                        accessibilityLabel: "润色整篇草稿",
                        isEnabled: !isGenerating && !isSavingChapter && canUseAI && !project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        draftPolishInstruction = ""
                        isDraftPolishSheetPresented = true
                    }
                ],
                fillContentHeight: layout != nil
            ) {
                HStack(alignment: .center, spacing: 10) {
                    PillTag(text: project.title)
                    PillTag(text: project.currentChapterSummary)
                    PillTag(text: project.savedChapterCount == 0 ? "未收录章节" : "已收录 \(project.savedChapterCount) 章")

                    Spacer(minLength: 0)

                    Button {
                        isChapterNavigatorPresented.toggle()
                    } label: {
                        Label("目录", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(project.chapterCatalog.isEmpty)
                    .help(project.chapterCatalog.isEmpty ? "还没有可查看的已保存章节" : "打开章节目录")
                    .popover(isPresented: $isChapterNavigatorPresented, arrowEdge: .bottom) {
                        WritingDeskChapterNavigator(
                            project: project,
                            searchText: $chapterNavigationSearchText,
                            onSelectChapter: { metadata in
                                requestChapterLoadFromNavigator(metadata, for: project)
                            }
                        )
                        .frame(width: 420)
                    }
                }

                writingDeskChapterControls(for: project)

                if isFindReplacePresented {
                    draftFindReplaceBar(for: project)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ZStack(alignment: .topLeading) {
                    WritingDeskDraftEditor(
                        text: draftBinding(for: project.id),
                        selection: $draftSelection,
                        selectionActionPoint: $draftSelectionActionPoint,
                        focusToken: draftEditorFocusToken,
                        fontSize: appState.draftEditorFontSize,
                        lineSpacing: appState.draftEditorLineSpacing
                    )
                    .frame(
                        minHeight: layout?.draftEditorHeight ?? 720,
                        maxHeight: layout?.draftEditorHeight,
                        alignment: .topLeading
                    )
                    .overlay(alignment: .topLeading) {
                        if project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("从当前章节的第一句开始写，或先让右侧 AI 作家为你生成一段可接续的草稿。")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 22)
                                .allowsHitTesting(false)
                        }
                    }
                    .zIndex(0)

                    if let activeDraftPolishMode {
                        DraftPolishProgressBadge(mode: activeDraftPolishMode)
                            .padding(16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .zIndex(20)
                    }

                    GeometryReader { proxy in
                        if pendingDraftPolishReview == nil,
                           activeDraftPolishMode == nil,
                           !isSelectionPolishPopoverPresented,
                           activeSelectionPolishSelection.hasSelection,
                           let actionPoint = activeSelectionPolishActionPoint {
                            DraftSelectionPolishToolbar(
                                isEnabled: !isGenerating && !isSavingChapter && canUseAI,
                                action: {
                                    selectionPolishTarget = activeSelectionPolishSelection
                                    selectionPolishAnchorPoint = actionPoint
                                    selectionPolishInstruction = ""
                                    isSelectionPolishPopoverPresented = true
                                }
                            )
                            .position(selectionPolishButtonPosition(in: proxy.size, anchor: actionPoint))
                            .zIndex(40)
                        }
                    }
                    .zIndex(40)

                    GeometryReader { proxy in
                        if pendingDraftPolishReview == nil,
                           activeDraftPolishMode == nil,
                           isSelectionPolishPopoverPresented,
                           activeSelectionPolishSelection.hasSelection,
                           let actionPoint = activeSelectionPolishActionPoint {
                            DraftSelectionPolishRequestPanel(
                                selectedText: activeSelectionPolishSelection.text,
                                instruction: $selectionPolishInstruction,
                                isEnabled: canUseAI,
                                onCancel: {
                                    isSelectionPolishPopoverPresented = false
                                },
                                onSubmit: {
                                    polishDraftSelection(for: project)
                                }
                            )
                            .frame(width: min(420, max(320, proxy.size.width - 32)))
                            .position(selectionPolishRequestPosition(in: proxy.size, anchor: actionPoint))
                            .zIndex(80)
                        }
                    }
                    .zIndex(80)

                    GeometryReader { proxy in
                        Color.clear
                            .frame(width: 1, height: 1)
                            .position(draftPolishPanelAnchorPosition(in: proxy.size, anchor: pendingDraftPolishReviewAnchorPoint))
                            .popover(isPresented: draftPolishReviewPopoverBinding(for: project.id), arrowEdge: .top) {
                                if let review = pendingDraftPolishReview, review.projectID == project.id {
                                    DraftPolishResultPanel(
                                        review: review,
                                        onKeep: {
                                            keepDraftPolishReview(review)
                                        },
                                        onReplace: {
                                            replaceDraftPolishReview(review)
                                        },
                                        onDiscard: {
                                            discardDraftPolishReview(review)
                                        },
                                        onCopy: {
                                            copyDraftPolishReview(review)
                                        }
                                    )
                                    .frame(width: min(520, max(360, proxy.size.width - 48)))
                                }
                            }
                    }
                    .zIndex(120)
                }
                .id(WritingDeskScrollAnchor.draft.rawValue)
                .zIndex(1000)

                HStack {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(project.updatedAt)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: layout?.draftPrimaryCardHeight, alignment: .top)

            if appState.showWritingDeskCachePanel {
                WritingDeskSectionCard(
                    title: "缓存区",
                    badgeText: isCacheCollapsed ? "已收起" : "\(project.draftContinuationCacheCount)/400 字",
                    headerTapAction: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isCacheCollapsed.toggle()
                        }
                    },
                    fillContentHeight: layout != nil
                ) {
                    if isCacheCollapsed {
                        Text("点击上方标题可重新展开缓存区。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        WritingDeskCacheSurface(
                            text: project.draftContinuationCache,
                            placeholder: "保存过上一章后，这里会显示上一已保存章节的末尾 400 字，作为 AI 续写当前章节时的近端参考。",
                            minHeight: layout?.cacheEditorHeight ?? 152
                        )
                        .id(WritingDeskScrollAnchor.cache.rawValue)

                        HStack {
                            Spacer()

                            Text(project.draftContinuationCache.isEmpty ? "上一章还没有可用缓存" : "缓存区展示上一已保存章节的结尾，并会作为 AI 续写当前章节的近端参考")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: layout?.cacheCardHeight, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func draftFindReplaceBar(for project: NovelProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    draftFindFields(for: project)
                    draftFindActions(for: project)
                }

                VStack(alignment: .leading, spacing: 10) {
                    draftFindFields(for: project)
                    draftFindActions(for: project)
                }
            }

            Text(findStatusMessage.isEmpty ? draftFindSummary(for: project) : findStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.editorBorder, lineWidth: 1)
        )
    }

    private func draftFindFields(for project: NovelProject) -> some View {
        HStack(spacing: 10) {
            TextField("查找正文", text: $findQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    findNextInDraft(for: project)
                }

            TextField("替换为", text: $replacementText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func draftFindActions(for project: NovelProject) -> some View {
        HStack(spacing: 8) {
            Button {
                findNextInDraft(for: project)
            } label: {
                Label("下一处", systemImage: "arrow.down")
            }
            .disabled(findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                replaceNextInDraft(for: project)
            } label: {
                Label("替换", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                replaceAllInDraft(for: project)
            } label: {
                Label("全部替换", systemImage: "text.badge.checkmark")
            }
            .disabled(findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func writingDeskAIColumn(for project: NovelProject, layout: WritingDeskCollapsedLayout? = nil) -> some View {
        WritingDeskSectionCard(
            title: "AI 作家",
            statusLabel: aiStatusLabel,
            statusColor: aiStatusColor,
            actions: writingDeskAIActions(for: project),
            fillContentHeight: layout != nil
        ) {
                if appState.showWritingDeskTimeline {
                    WritingDeskTimelineRow(snapshot: timingSnapshot)
                }

                if !appState.hasAcceptedAIDataTransfer {
                    aiDataTransferConsentPanel
                }

                genreTemplateSelector(for: project)
                strandWeaveIndicator(for: project)
                nextChapterBriefPanel(for: project)
            qualityDebtPanel(for: project)
            longformRuntimePanel(for: project)
            storageHealthPanel(for: project)

            Text(aiStatusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Group {
                if writingRunState == .requesting || writingRunState == .stopping {
                    AIWriterThinkingSurface(state: currentThinkingState)
                } else {
                    TextEditor(text: $aiSuggestion)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .padding(18)
                        .overlay(alignment: .topLeading) {
                            if aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("这里会显示 AI 按当前大纲与要求生成的候选稿。满意就接受进草稿箱，不满意就直接重写。")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 22)
                                    .allowsHitTesting(false)
                            }
                        }
                        .focused($focusedArea, equals: .ai)
                }
            }
            .frame(
                minHeight: layout?.aiEditorHeight ?? 918,
                maxHeight: layout?.aiEditorHeight,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(palette.editorBorder, lineWidth: 1)
            )
            .id(WritingDeskScrollAnchor.ai.rawValue)

            if !aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Picker("重写方向", selection: $rewriteDirection) {
                    ForEach(AIRewriteDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let blockingMessage = blockedAISuggestionAcceptanceMessage(for: project) {
                Text(blockingMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button("接受放入草稿箱") {
                        acceptAISuggestionIntoDraft(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!canAcceptAISuggestion(for: project))

                    Button("重写这一版") {
                        rewriteSuggestion(for: project)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating || isSavingChapter || !canUseAI)

                    Button("清空结果") {
                        aiSuggestion = ""
                        if latestChapterReviewDraftContext == nil {
                            latestChapterReview = nil
                        }
                        latestReviewedAISuggestionText = ""
                        latestAISuggestionAcceptanceContext = nil
                        aiStatusMessage = "AI 结果区已清空。"
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button("接受放入草稿箱") {
                        acceptAISuggestionIntoDraft(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!canAcceptAISuggestion(for: project))

                    Button("重写这一版") {
                        rewriteSuggestion(for: project)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating || isSavingChapter || !canUseAI)

                    Button("清空结果") {
                        aiSuggestion = ""
                        if latestChapterReviewDraftContext == nil {
                            latestChapterReview = nil
                        }
                        latestReviewedAISuggestionText = ""
                        latestAISuggestionAcceptanceContext = nil
                        aiStatusMessage = "AI 结果区已清空。"
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let presentation = displayedChapterReviewPresentation(for: project) {
                ChapterQualityReviewPanel(
                    review: presentation.review,
                    minimumAcceptedScore: presentation.minimumAcceptedScore,
                    onOpenFullReport: {
                        qualityReviewDashboardPresentation = presentation
                    }
                )
            }
        }
        .frame(height: layout?.aiCardHeight, alignment: .top)
    }

    private var aiDataTransferConsentPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(palette.warningAccent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 6) {
                Text("AI 功能需要先确认数据使用告知")
                    .font(.subheadline.weight(.semibold))

                Text("续写、润色、审查和记忆整理会把必要的写作上下文发送到当前模型服务。本地写作、保存和导出不受影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                appState.hasAcceptedAIDataTransfer = true
                aiStatusMessage = "已同意 AI 数据使用告知，可以测试连接或开始写作。"
            } label: {
                Label("同意并启用", systemImage: "checkmark.shield")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.warningAccent.opacity(0.35), lineWidth: 1)
        )
    }

    private func genreTemplateSelector(for project: NovelProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("题材模板")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("题材模板", selection: genreTemplateBinding(for: project.id)) {
                ForEach(GenreTemplateLibrary.allTemplates) { template in
                    Text(template.name).tag(template.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text(project.genreTemplate.coreSellingPoint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private func writingSessionKey(for project: NovelProject) -> WritingDeskSessionKey {
        WritingDeskSessionKey(
            projectID: project.id,
            volumeNumber: max(project.currentVolumeNumber, 1),
            chapterNumber: max(project.currentChapterNumber, 1)
        )
    }

    private func displayedChapterReview(for project: NovelProject) -> ChapterReviewResult? {
        displayedChapterReviewPresentation(for: project)?.review
    }

    private func displayedChapterReviewPresentation(for project: NovelProject) -> QualityReviewDashboardPresentation? {
        let minimumAcceptedScore = LongformStorySystem.minimumAcceptedScore(for: project.storyLength)

        if let latestChapterReview {
            let normalizedSuggestion = aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let reviewedSuggestion = latestReviewedAISuggestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedSuggestion.isEmpty, reviewedSuggestion == normalizedSuggestion {
                return QualityReviewDashboardPresentation(
                    review: latestChapterReview,
                    chapterTitle: project.currentChapterSummary,
                    minimumAcceptedScore: minimumAcceptedScore
                )
            }

            if latestChapterReviewDraftContext == ChapterWritingSessionPolicy.chapterSaveValidationContext(for: project) {
                return QualityReviewDashboardPresentation(
                    review: latestChapterReview,
                    chapterTitle: project.currentChapterSummary,
                    minimumAcceptedScore: minimumAcceptedScore
                )
            }
        }

        let currentVolume = max(project.currentVolumeNumber, 1)
        let currentChapter = max(project.currentChapterNumber, 1)
        let matchingReport = project.qualityReviewReports.sorted { $0.reviewedAt > $1.reviewedAt }
            .first {
                $0.resolvedVolumeNumber == currentVolume
                    && $0.chapterNumber == currentChapter
            }
        guard let report = matchingReport,
            let review = report.unifiedResult
        else { return nil }

        return QualityReviewDashboardPresentation(
            review: review,
            chapterTitle: report.chapterTitle,
            minimumAcceptedScore: minimumAcceptedScore
        )
    }

    private func strandWeaveIndicator(for project: NovelProject) -> some View {
        let state = project.strandWeaveState
        let ratios = state.ratios
        let warning = latestStrandWarning ?? state.checkRedLines(currentChapter: project.currentChapterNumber).first

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Strand Weave")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Q \(strandPercent(ratios[.quest])) · F \(strandPercent(ratios[.fire])) · C \(strandPercent(ratios[.constellation]))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                StrandRatioBar(label: "Quest", value: ratios[.quest] ?? 0, color: palette.activeAccent)
                StrandRatioBar(label: "Fire", value: ratios[.fire] ?? 0, color: palette.warningAccent)
                StrandRatioBar(label: "Constellation", value: ratios[.constellation] ?? 0, color: palette.readyAccent)
            }

            if let warning {
                Label(warning.message, systemImage: warning.isCritical ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(warning.isCritical ? palette.warningAccent : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private func strandPercent(_ value: Double?) -> String {
        "\(Int(((value ?? 0) * 100).rounded()))%"
    }

    private func nextChapterBriefPanel(for project: NovelProject) -> some View {
        let brief = project.longformNextChapterBrief
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下一章 brief", systemImage: "arrow.forward.doc.on.clipboard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(brief.hasActionableSignals ? "已约束" : "基础")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(brief.hasActionableSignals ? palette.activeAccent : .secondary)
            }

            Text(brief.chapterGoal)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            WritingDeskBriefRows(
                rows: [
                    ("必须延续", brief.mandatoryContinuities),
                    ("伏笔推进", brief.foreshadowingPromises),
                    ("禁止违反", brief.forbiddenContradictions),
                    ("风险", brief.risks)
                ]
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private func qualityDebtPanel(for project: NovelProject) -> some View {
        let trend = project.longformQualityTrend
        let debts = Array((trend.qualityDebtTargets + trend.revisionHints + trend.priorityIssues).prefix(6))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("质量债", systemImage: debts.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let averageScore = trend.averageScore {
                    Text("最近 \(averageScore)/100")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(averageScore >= trend.minimumAcceptedScore ? palette.readyAccent : palette.warningAccent)
                } else {
                    Text("待积累")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if debts.isEmpty {
                Text("暂无未解决质量债。保存并审查章节后，这里会显示下一章必须修复的问题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                ForEach(Array(debts.enumerated()), id: \.offset) { _, debt in
                    Text("· \(debt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private func storageHealthPanel(for project: NovelProject) -> some View {
        let report = appState.storageHealthReport(for: project.id)
        let sortedIssues = report.issues.sorted(by: storageIssueDisplayPrecedence)
        let visibleIssues = Array(sortedIssues.prefix(3))
        let hiddenIssueCount = max(sortedIssues.count - visibleIssues.count, 0)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("存储健康", systemImage: report.status == .blocked ? "externaldrive.badge.exclamationmark" : "externaldrive")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(report.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(storageHealthColor(report.status))
            }

            Text(report.summary)
                .font(.caption)
                .foregroundStyle(storageHealthColor(report.status))
                .lineLimit(2)

            Text(report.nextAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if visibleIssues.isEmpty {
                Text("项目索引、metadata、章节目录和正文文件一致。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(visibleIssues) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("· \(issue.title)：\(issue.detail)")
                            .font(.caption)
                            .foregroundStyle(issue.status == .blocked ? .red : .orange)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            ForEach(issue.recoveryActions.prefix(3), id: \.self) { action in
                                Button {
                                    performStorageRecovery(issue: issue, action: action)
                                } label: {
                                    Label(action.title, systemImage: storageRecoverySymbol(for: action))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("\(action.title)：\(issue.title)")
                            }
                        }
                    }
                }

                if hiddenIssueCount > 0 {
                    Text("另有 \(hiddenIssueCount) 个存储提醒；优先处理上方阻断项后重新检查。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            let metricSummary = report.metrics
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: " · ")
            if !metricSummary.isEmpty {
                Text(metricSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private func longformRuntimePanel(for project: NovelProject) -> some View {
        let runtime = project.longformRuntimeState
        let commit = runtime.latestCommit
        let contract = runtime.latestContract
        let writeGate = runtime.latestWriteGate
        let health = project.longformRuntimeHealth
        let qualityTrend = project.longformQualityTrend
        let statusText: String
        let statusColor: Color
        let statusIcon: String
        switch health.status {
        case .passed:
            statusText = "健康"
            statusColor = .green
            statusIcon = "checkmark.seal.fill"
        case .warning:
            statusText = "需关注"
            statusColor = .orange
            statusIcon = "exclamationmark.circle.fill"
        case .blocked:
            statusText = "被阻断"
            statusColor = .red
            statusIcon = "exclamationmark.triangle.fill"
        }

        let gateStatusText: String
        let gateStatusColor: Color
        if let writeGate {
            switch writeGate.overallStatus {
            case .passed:
                gateStatusText = "门禁通过"
                gateStatusColor = .green
            case .warning:
                gateStatusText = "门禁有提醒"
                gateStatusColor = .orange
            case .blocked:
                gateStatusText = "门禁阻断"
                gateStatusColor = .red
            }
        } else if let commit {
            gateStatusText = commit.isAccepted ? "已通过" : "需修订"
            gateStatusColor = commit.isAccepted ? .green : .orange
        } else {
            gateStatusText = contract == nil ? "待生成" : "合同就绪"
            gateStatusColor = contract == nil ? .secondary : .blue
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("长篇后台", systemImage: statusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("健康诊断：\(health.summary)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)

                Text("下一步：\(health.nextAction)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                let visibleHealthIssues = health.issues
                    .filter { $0.status != .passed }
                    .prefix(2)
                ForEach(Array(visibleHealthIssues)) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("· \(issue.title)：\(issue.detail)")
                            .font(.caption)
                            .foregroundStyle(issue.status == .blocked ? .red : .orange)
                            .lineLimit(2)
                        Text("  \(issue.repairHint)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                let metricSummary = health.metrics
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: " · ")
                if !metricSummary.isEmpty {
                    Text(metricSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if qualityTrend.hasSignals {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("质量趋势")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let averageScore = qualityTrend.averageScore {
                            Text("最近均分 \(averageScore)/100\(qualityTrend.lowScoreCount > 0 ? " · \(qualityTrend.lowScoreCount) 次偏低" : "")")
                                .font(.caption)
                                .foregroundStyle(averageScore >= qualityTrend.minimumAcceptedScore ? Color.secondary : Color.orange)
                                .lineLimit(1)
                        }

                        let priorityItems = qualityTrend.priorityIssues.prefix(2)
                        ForEach(Array(priorityItems), id: \.self) { issue in
                            Text("· \(issue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if let commit {
                Text("\(commit.volumeNumber > 1 ? "第 \(commit.volumeNumber) 卷 · " : "")第 \(commit.chapterNumber) 章《\(commit.chapterTitle)》")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let writeGate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(gateStatusText)：\(writeGate.summary)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(gateStatusColor)

                        ForEach(Array(writeGate.checks.filter { $0.status != .passed }.prefix(3))) { check in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("· \(check.stage.displayName)：\(check.message)")
                                    .font(.caption)
                                    .foregroundStyle(check.status == .blocked ? .red : .orange)
                                    .lineLimit(2)

                                if let detail = check.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !detail.isEmpty {
                                    Text("  \(detail)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }

                let rejectionReasons = commit.rejectionReasons ?? []
                if !rejectionReasons.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rejectionReasons.prefix(3)), id: \.self) { reason in
                            Text("· \(reason)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                } else if !commit.missedNodes.isEmpty {
                    Text("漏写节点：\(commit.missedNodes.prefix(2).joined(separator: "；"))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else {
                    Text("节点 \(commit.coveredNodes.count)/\(commit.plannedNodes.count) · 事件 \(commit.acceptedEvents.count) · 记忆 \(commit.extractedMemoryItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let revisionHints = commit.revisionHints ?? []
                if !revisionHints.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("修订建议")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(revisionHints.prefix(3)), id: \.self) { hint in
                            Text("· \(hint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                let projectionMessages = LongformStorySystem.projectionStatusMessages(for: commit)
                let actionableProjectionMessages = projectionMessages
                    .filter { $0.status != .passed }
                if !actionableProjectionMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("后台投影提示")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(actionableProjectionMessages.prefix(3))) { projection in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("· \(projection.message)")
                                    .font(.caption)
                                    .foregroundStyle(projection.status == .blocked ? .red : .orange)
                                    .lineLimit(2)

                                if let recoveryHint = projection.recoveryHint {
                                    Text("  \(recoveryHint)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                } else if !projectionMessages.isEmpty {
                    Text("后台投影：\(projectionMessages.prefix(4).map(\.message).joined(separator: "；"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            } else {
                Text("保存章节后会自动形成合同、提交、记忆和节奏投影。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private var emptyState: some View {
        DashboardPanel(
            title: "写作台",
            subtitle: "当前还没有可写的项目，先去项目空间创建一个项目。"
        ) {
            Button("前往项目空间") {
                appState.openProjectSpace()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var aiStatusLabel: String {
        if writingRunState == .requesting {
            return "写作中"
        }

        if writingRunState == .stopping {
            return "停止中"
        }

        if isSavingChapter {
            return "保存中"
        }

        if isGenerating {
            return "生成中"
        }

        if !appState.hasAcceptedAIDataTransfer {
            return "待授权"
        }

        return appState.aiConfiguration == nil ? "待配置" : "就绪"
    }

    private var aiStatusColor: Color {
        if writingRunState == .stopping {
            return palette.warningAccent
        }

        if writingRunState == .requesting {
            return palette.activeAccent
        }

        if isGenerating || isSavingChapter {
            return palette.warningAccent
        }

        return !appState.hasAcceptedAIDataTransfer || appState.aiConfiguration == nil
            ? palette.warningAccent
            : palette.readyAccent
    }

    private var canUseAI: Bool {
        appState.aiConfiguration != nil
    }

    private func storageHealthColor(_ status: StorageHealthStatus) -> Color {
        switch status {
        case .passed: return palette.readyAccent
        case .warning: return palette.warningAccent
        case .blocked: return .red
        }
    }

    private func storageIssueDisplayPrecedence(_ lhs: ProjectStorageIssue, _ rhs: ProjectStorageIssue) -> Bool {
        let lhsRank = storageIssueStatusRank(lhs.status)
        let rhsRank = storageIssueStatusRank(rhs.status)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func storageIssueStatusRank(_ status: StorageHealthStatus) -> Int {
        switch status {
        case .blocked: return 0
        case .warning: return 1
        case .passed: return 2
        }
    }

    private func storageRecoverySymbol(for action: StorageRecoveryAction) -> String {
        switch action {
        case .exportDiagnostics: return "doc.text.magnifyingglass"
        case .rebuildChapterCatalog: return "arrow.triangle.2.circlepath"
        case .preserveMissingChapterPlaceholder: return "bookmark"
        case .recoverMetadataShell: return "shippingbox"
        case .markCloudConflict: return "icloud.and.arrow.down"
        }
    }

    private var currentThinkingState: AIWriterThinkingState {
        AIWriterThinkingState(
            title: writingRunState == .stopping ? "正在停止本次写作" : thinkingMode.title,
            subtitle: writingRunState == .stopping ? "已经发出停止请求，本次结果不会保留，也不会写入任何记录。" : thinkingMode.subtitle,
            messages: thinkingMode.messages,
            activeIndex: min(thinkingStepIndex, max(thinkingMode.messages.count - 1, 0)),
            isStopping: writingRunState == .stopping
        )
    }

    private var activeSelectionPolishSelection: WritingDeskDraftSelection {
        if let selectionPolishTarget, selectionPolishTarget.hasSelection {
            return selectionPolishTarget
        }

        return draftSelection
    }

    private var activeSelectionPolishActionPoint: CGPoint? {
        selectionPolishAnchorPoint ?? draftSelectionActionPoint
    }

    private func writingDeskAIActions(for project: NovelProject) -> [WritingDeskToolbarAction] {
        var actions: [WritingDeskToolbarAction] = []

        let hasConfiguration = canUseAI
        let hasBusyNonWritingTask = isGenerating && writingRunState == .idle

        switch writingRunState {
        case .idle:
            actions.append(
                WritingDeskToolbarAction(
                    symbolName: "play.fill",
                    accessibilityLabel: "开启写作",
                    isEnabled: !hasBusyNonWritingTask && !isSavingChapter && hasConfiguration,
                    isPrimary: true
                ) {
                    startWriting(for: project)
                }
            )
        case .requesting:
            actions.append(
                WritingDeskToolbarAction(
                    symbolName: "stop.fill",
                    accessibilityLabel: "停止写作",
                    isEnabled: true,
                    isPrimary: true,
                    tintColor: .red
                ) {
                    stopWriting()
                }
            )
        case .stopping:
            actions.append(
                WritingDeskToolbarAction(
                    symbolName: "stop.circle.fill",
                    accessibilityLabel: "正在停止写作",
                    isEnabled: false,
                    isPrimary: true,
                    tintColor: .red
                ) {}
            )
        }

        actions.append(
            WritingDeskToolbarAction(
                symbolName: "arrow.clockwise",
                accessibilityLabel: "重写当前候选稿",
                isEnabled: writingRunState == .idle && !isSavingChapter && !hasBusyNonWritingTask && hasConfiguration && !aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                rewriteSuggestion(for: project)
            }
        )

        actions.append(
            WritingDeskToolbarAction(
                symbolName: autoScrollLocked ? "lock.fill" : "lock.open.fill",
                accessibilityLabel: autoScrollLocked ? "解锁自动滑动" : "锁定自动滑动"
            ) {
                autoScrollLocked.toggle()
                aiStatusMessage = autoScrollLocked ? "已锁定自动滑动，生成后不会自动跳转模块。" : "已恢复自动滑动，生成后会自动定位到结果区域。"
            }
        )

        return actions
    }

    private func writingDeskChapterControls(for project: NovelProject) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                if project.storyLength.supportsVolumePlanning || project.currentVolumeNumber > 1 {
                    WritingDeskInlineField(title: "卷号") {
                        TextField("卷号", value: volumeNumberBinding(for: project.id), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 76)
                    }
                }

                WritingDeskInlineField(title: "章节号") {
                    TextField("章节号", value: chapterNumberBinding(for: project.id), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                }

                WritingDeskInlineField(title: "章节标题（可改）") {
                    TextField("保存后可手动改标题", text: chapterTitleBinding(for: project.id))
                        .textFieldStyle(.roundedBorder)
                }

                Button(project.hasSavedCurrentChapter ? "更新当前章" : "AI 拟标题并保存") {
                    saveCurrentChapterDraft(for: project)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingChapter || isGenerating || project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("保存并下一章") {
                    saveCurrentChapterDraft(for: project, advanceToNextChapter: true)
                }
                .buttonStyle(.bordered)
                .disabled(isSavingChapter || isGenerating || project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 12) {
                    if project.storyLength.supportsVolumePlanning || project.currentVolumeNumber > 1 {
                        WritingDeskInlineField(title: "卷号") {
                            TextField("卷号", value: volumeNumberBinding(for: project.id), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 76)
                        }
                    }

                    WritingDeskInlineField(title: "章节号") {
                        TextField("章节号", value: chapterNumberBinding(for: project.id), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 88)
                    }

                    Button(project.hasSavedCurrentChapter ? "更新当前章" : "AI 拟标题并保存") {
                        saveCurrentChapterDraft(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingChapter || isGenerating || project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("保存并下一章") {
                        saveCurrentChapterDraft(for: project, advanceToNextChapter: true)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSavingChapter || isGenerating || project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                WritingDeskInlineField(title: "章节标题（可改）") {
                    TextField("保存后可手动改标题", text: chapterTitleBinding(for: project.id))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func writingDeskOutlineGeneratorControls(for project: NovelProject) -> some View {
        let profile = project.outlineGenerationProfile

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("最简可用项 \(profile.completedRequiredFieldCount)/5 · 扩展项 \(profile.filledOptionalFieldCount)/7")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(profile.minimumRequirementSummary)
                    .font(.caption)
                    .foregroundStyle(profile.hasMinimumRequirements ? .secondary : palette.warningAccent)

                Text("提示词会按“小说框架 / 主要世界观 / 核心人物设定 / 输出控制参数”4 组拼接。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button("填写生成参数") {
                        isOutlineGeneratorPresented = true
                    }
                    .buttonStyle(.bordered)

                    Button(isGenerating ? "正在生成…" : "生成大纲") {
                        generateOutline(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || isSavingChapter)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button("填写生成参数") {
                        isOutlineGeneratorPresented = true
                    }
                    .buttonStyle(.bordered)

                    Button(isGenerating ? "正在生成…" : "生成大纲") {
                        generateOutline(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || isSavingChapter)
                }
            }
        }
    }

    private func outlineBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.outlineText ?? "" },
            set: { appState.updateOutlineText($0, for: projectID) }
        )
    }

    private func outlineGenerationProfileBinding(for projectID: NovelProject.ID) -> Binding<OutlineGenerationProfile> {
        Binding(
            get: { appState.project(for: projectID)?.outlineGenerationProfile ?? .empty },
            set: { appState.updateOutlineGenerationProfile($0, for: projectID) }
        )
    }

    private func referenceContextBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.referenceContextText ?? "" },
            set: { appState.updateReferenceContextText($0, for: projectID) }
        )
    }

    private func specialRequirementsBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.specialRequirements ?? "" },
            set: { appState.updateSpecialRequirements($0, for: projectID) }
        )
    }

    private func wordTargetBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.wordTargetText ?? "" },
            set: { appState.updateWordTargetText($0, for: projectID) }
        )
    }

    private func chapterTitleBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.currentChapterTitle ?? "" },
            set: { appState.updateCurrentChapterTitle($0, for: projectID) }
        )
    }

    private func chapterNumberBinding(for projectID: NovelProject.ID) -> Binding<Int> {
        Binding(
            get: { max(appState.project(for: projectID)?.currentChapterNumber ?? 1, 1) },
            set: { appState.updateCurrentChapterNumber($0, for: projectID) }
        )
    }

    private func volumeNumberBinding(for projectID: NovelProject.ID) -> Binding<Int> {
        Binding(
            get: { max(appState.project(for: projectID)?.currentVolumeNumber ?? 1, 1) },
            set: { appState.updateCurrentVolumeNumber($0, for: projectID) }
        )
    }

    private func genreTemplateBinding(for projectID: NovelProject.ID) -> Binding<GenreTemplate.ID> {
        Binding(
            get: {
                guard let project = appState.project(for: projectID) else {
                    return GenreTemplateLibrary.defaultTemplate.id
                }
                return project.genreTemplate.id
            },
            set: { appState.updateGenreTemplate($0, for: projectID) }
        )
    }

    private func draftBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.draftText ?? "" },
            set: { appState.updateDraftText($0, for: projectID) }
        )
    }

    private func generateOutline(for project: NovelProject) {
        let latestProject = appState.hydratedProjectForFullText(project.id)
            ?? appState.project(for: project.id)
            ?? project
        let profile = latestProject.outlineGenerationProfile
        let requestContext = ChapterWritingSessionPolicy.outlineGenerationContext(for: latestProject, profile: profile)
        let promptProject = appState.projectWithActiveWritingSkills(latestProject)

        guard profile.hasMinimumRequirements else {
            aiStatusMessage = "生成大纲前还差：\(profile.missingRequiredFieldLabels.joined(separator: "、"))。"
            isOutlineGeneratorPresented = true
            return
        }

        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不可用，请先到设置里检查模型选择。"
            return
        }

        outlineGenerationTask?.cancel()
        let requestToken = UUID()
        outlineGenerationToken = requestToken
        isGenerating = true
        aiStatusMessage = "AI 正在根据总体流程、世界观、主角底色、预期字数和结局偏好生成大纲…"
        timingSnapshot = .queued

        outlineGenerationTask = Task {
            let startedAt = Date()

            do {
                let outline = try await appState.aiService.generateStoryOutline(
                    configuration: configuration,
                    project: promptProject,
                    profile: profile
                )

                let total = Date().timeIntervalSince(startedAt)

                await MainActor.run {
                    guard outlineGenerationToken == requestToken else {
                        return
                    }

                    let currentContext = appState.project(for: project.id).map {
                        ChapterWritingSessionPolicy.outlineGenerationContext(for: $0, profile: $0.outlineGenerationProfile)
                    }
                    guard currentContext == requestContext else {
                        clearOutlineGenerationRequest(token: requestToken)
                        isGenerating = false
                        timingSnapshot = .idle
                        aiStatusMessage = "生成期间你已经改过大纲参数或本地大纲，旧结果已丢弃，当前内容保持不变。"
                        revealWritingDeskWindow(for: project.id)
                        return
                    }

                    appState.updateOutlineText(outline, for: project.id)
                    clearOutlineGenerationRequest(token: requestToken)
                    isGenerating = false
                    timingSnapshot = AIWriterTimingSnapshot.completed(total: total)
                    aiStatusMessage = "大纲已生成并回填到大纲设定，可以继续微调后直接开始写作。"
                    revealWritingDeskWindow(for: project.id)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard outlineGenerationToken == requestToken else {
                        return
                    }

                    clearOutlineGenerationRequest(token: requestToken)
                    isGenerating = false
                    timingSnapshot = .idle
                }
            } catch {
                await MainActor.run {
                    guard outlineGenerationToken == requestToken else {
                        return
                    }

                    clearOutlineGenerationRequest(token: requestToken)
                    isGenerating = false
                    timingSnapshot = .idle
                    AppLogger.ai.error("Outline generation failed: \(error.localizedDescription, privacy: .public)")
                    presentAIError(error, title: "大纲生成失败", fallbackAction: "请检查模型配置后重试。")
                    revealWritingDeskWindow(for: project.id)
                }
            }
        }
    }

    private func startWriting(for project: NovelProject, rejectedSuggestion: String? = nil) {
        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不可用，请先到设置里检查模型选择。"
            return
        }

        appState.ensureContinuationChapterDraftsLoaded(for: project.id)
        let latestProject = appState.project(for: project.id) ?? project
        if let blockingMessage = writingPreflightBlockingMessage(
            for: latestProject,
            allowsCurrentChapterRepair: true
        ) {
            aiStatusMessage = blockingMessage
            revealWritingDeskWindow(for: project.id)
            return
        }

        if let activeToken = writingGenerationToken {
            let task = writingGenerationTask
            clearWritingGenerationRequest(token: activeToken)
            task?.cancel()
        }

        let requestContext = ChapterWritingSessionPolicy.draftGenerationContext(
            for: latestProject,
            rewriteDirection: rewriteDirection,
            rejectedSuggestion: rejectedSuggestion
        )
        let promptProject = appState.projectWithActiveWritingSkills(latestProject)
        writingStopTask?.cancel()
        writingStopTask = nil
        isGenerating = true
        writingRunState = .requesting
        thinkingMode = rejectedSuggestion == nil ? .writing : .rewriting
        thinkingStepIndex = 0
        aiSuggestion = ""
        if latestChapterReviewDraftContext == nil {
            latestChapterReview = nil
        }
        latestReviewedAISuggestionText = ""
        latestAISuggestionAcceptanceContext = nil
        aiStatusMessage = rejectedSuggestion == nil
            ? "AI 正在根据大纲、参考文本、特殊要求和字数要求创作候选稿…"
            : "AI 正在重写这一版候选稿，会保留当前约束，但换一种写法重新生成…"
        timingSnapshot = .queued
        startWritingProgressMonitor()

        writingGenerationTask?.cancel()
        let requestToken = UUID()
        writingGenerationToken = requestToken

        writingGenerationTask = Task {
            let startedAt = Date()

            do {
                let enhancedResult = try await appState.aiService.continueChapterEnhanced(
                    configuration: configuration,
                    project: promptProject,
                    mode: latestProject.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .advanceChapter : .continueScene,
                    additionalInstruction: generationInstruction(rejecting: rejectedSuggestion),
                    length: ChapterWritingSessionPolicy.preferredLength(for: latestProject),
                    enableReview: true
                )

                let total = Date().timeIntervalSince(startedAt)

                await MainActor.run {
                    guard writingGenerationToken == requestToken else {
                        return
                    }

                    let currentContext = appState.project(for: project.id).map {
                        ChapterWritingSessionPolicy.draftGenerationContext(
                            for: $0,
                            rewriteDirection: rewriteDirection,
                            rejectedSuggestion: rejectedSuggestion
                        )
                    }
                    guard currentContext == requestContext else {
                        clearWritingGenerationRequest(token: requestToken)
                        isGenerating = false
                        timingSnapshot = .idle
                        aiStatusMessage = "生成期间写作上下文已经变化，旧候选稿已丢弃，请按当前内容重新生成。"
                        revealWritingDeskWindow(for: project.id)
                        return
                    }

                    guard enhancedResult.validation.isReady else {
                        clearWritingGenerationRequest(token: requestToken)
                        isGenerating = false
                        writingRunState = .idle
                        stopWritingProgressMonitor(resetSnapshot: true)
                        aiStatusMessage = enhancedResult.validation.readySummary
                        revealWritingDeskWindow(for: project.id)
                        return
                    }

                    aiSuggestion = enhancedResult.text
                    latestChapterReview = enhancedResult.review
                    latestChapterReviewDraftContext = nil
                    latestReviewedAISuggestionText = enhancedResult.review == nil ? "" : enhancedResult.text
                    latestAISuggestionAcceptanceContext = ChapterWritingSessionPolicy.acceptanceContext(for: latestProject)
                    latestStrandWarning = enhancedResult.strandWarning
                    clearWritingGenerationRequest(token: requestToken)
                    isGenerating = false
                    writingRunState = .idle
                    stopWritingProgressMonitor()
                    timingSnapshot = AIWriterTimingSnapshot.completed(total: total)
                    aiStatusMessage = enhancedResult.summary.isEmpty
                        ? "候选稿已生成。满意可接受进草稿箱，不满意可继续重写。"
                        : enhancedResult.summary
                    revealWritingDeskWindow(for: project.id)
                    focusAIEditor()
                    requestAutoScroll(to: .ai)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard writingGenerationToken == requestToken else {
                        return
                    }

                    clearWritingGenerationRequest(token: requestToken)
                    isGenerating = false
                    writingRunState = .idle
                    stopWritingProgressMonitor(resetSnapshot: true)
                }
            } catch {
                await MainActor.run {
                    guard writingGenerationToken == requestToken else {
                        return
                    }

                    clearWritingGenerationRequest(token: requestToken)
                    isGenerating = false
                    writingRunState = .idle
                    stopWritingProgressMonitor(resetSnapshot: true)
                    AppLogger.ai.error("Chapter generation failed: \(error.localizedDescription, privacy: .public)")
                    presentAIError(error, title: "候选稿生成失败", fallbackAction: "请检查模型配置后重试。")
                    revealWritingDeskWindow(for: project.id)
                }
            }
        }
    }

    private func writingPreflightBlockingMessage(
        for project: NovelProject,
        allowsCurrentChapterRepair: Bool = false
    ) -> String? {
        let validation = PrewriteValidator.validate(project: project)
        var detailCandidates: [String] = []

        let blockers = validation.isReady ? [] : validation.blockingReasons
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let failedChecks = validation.isReady ? [] : validation.checklistItems
            .filter { !$0.passed && $0.isBlocking }
            .map { "\($0.label)：\($0.detail)" }
        detailCandidates.append(contentsOf: blockers + failedChecks)
        detailCandidates.append(
            contentsOf: longformRuntimeHealthBlockingDetails(
                for: project,
                allowsCurrentChapterRepair: allowsCurrentChapterRepair
            )
        )

        guard !detailCandidates.isEmpty else { return nil }

        var seenDetails = Set<String>()
        let details = detailCandidates
            .filter { detail in
                let normalized = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty, !seenDetails.contains(normalized) else {
                    return false
                }
                seenDetails.insert(normalized)
                return true
            }
            .prefix(4)
            .map { "· \($0)" }
            .joined(separator: "\n")

        if details.isEmpty {
            return "写前门禁未通过，暂不生成候选稿。请先补齐大纲、分卷计划、本章目标和记忆。"
        }

        let title = validation.isReady
            ? "长篇后台健康阻断，暂不生成候选稿。"
            : "写前门禁未通过，暂不生成候选稿。"
        return "\(title)\n\(details)"
    }

    private func longformRuntimeHealthBlockingDetails(
        for project: NovelProject,
        allowsCurrentChapterRepair: Bool
    ) -> [String] {
        guard project.storyLength.supportsVolumePlanning else { return [] }

        return project.longformRuntimeHealth.blockingIssues
            .filter { $0.title != "写前门禁未通过" }
            .filter { issue in
                !canRepairCurrentChapter(issue, project: project, allowsCurrentChapterRepair: allowsCurrentChapterRepair)
            }
            .map { issue in
                [issue.title, issue.detail]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "：")
            }
    }

    private func canRepairCurrentChapter(
        _ issue: LongformRuntimeHealthIssue,
        project: NovelProject,
        allowsCurrentChapterRepair: Bool
    ) -> Bool {
        guard allowsCurrentChapterRepair else { return false }

        switch issue.title {
        case "保存章节未进入提交链", "章节内容与提交链不一致":
            let affectedChapters = issue.detail
                .components(separatedBy: "；")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return !affectedChapters.isEmpty && affectedChapters.allSatisfy {
                textReferencesCurrentChapterPosition($0, project: project)
            }
        case "章节目录存在断章":
            let missingChapters = issue.detail
                .components(separatedBy: "；")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return missingChapters.contains {
                textReferencesCurrentChapterPosition($0, project: project)
            }
        case "分卷目录存在断卷":
            let missingVolumes = issue.detail
                .components(separatedBy: "；")
                .compactMap { parsedVolumeNumber(in: $0) }
            return missingVolumes.contains(max(project.currentVolumeNumber, 1))
                && max(project.currentChapterNumber, 1) == 1
        case "最新章节提交被拒":
            guard let latestCommit = project.longformRuntimeState.latestCommit else { return false }
            return latestCommit.status == .rejected
                && latestCommit.volumeNumber == max(project.currentVolumeNumber, 1)
                && latestCommit.chapterNumber == project.currentChapterNumber
        default:
            return false
        }
    }

    private func textReferencesCurrentChapterPosition(_ text: String, project: NovelProject) -> Bool {
        guard let position = parsedChapterPosition(in: text) else { return false }
        return position.volumeNumber == max(project.currentVolumeNumber, 1)
            && position.chapterNumber == max(project.currentChapterNumber, 1)
    }

    private func parsedChapterPosition(in text: String) -> (volumeNumber: Int, chapterNumber: Int)? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let expression = try? NSRegularExpression(pattern: #"第\s*(\d+)\s*卷.*?第\s*(\d+)\s*章"#),
           let match = expression.firstMatch(in: text, range: fullRange),
           match.numberOfRanges >= 3,
           let volumeNumber = Int(nsText.substring(with: match.range(at: 1))),
           let chapterNumber = Int(nsText.substring(with: match.range(at: 2))) {
            return (max(volumeNumber, 1), max(chapterNumber, 1))
        }

        if let expression = try? NSRegularExpression(pattern: #"第\s*(\d+)\s*章"#),
           let match = expression.firstMatch(in: text, range: fullRange),
           match.numberOfRanges >= 2,
           let chapterNumber = Int(nsText.substring(with: match.range(at: 1))) {
            return (1, max(chapterNumber, 1))
        }

        return nil
    }

    private func parsedVolumeNumber(in text: String) -> Int? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let expression = try? NSRegularExpression(pattern: #"第\s*(\d+)\s*卷"#),
              let match = expression.firstMatch(in: text, range: fullRange),
              match.numberOfRanges >= 2,
              let volumeNumber = Int(nsText.substring(with: match.range(at: 1))) else {
            return nil
        }
        return max(volumeNumber, 1)
    }

    private func stopWriting() {
        guard writingRunState == .requesting else { return }

        let activeToken = writingGenerationToken
        let task = writingGenerationTask
        if let activeToken {
            clearWritingGenerationRequest(token: activeToken)
        }

        isGenerating = false
        writingRunState = .stopping
        stopWritingProgressMonitor(markStopping: true)
        aiStatusMessage = "正在停止本次写作，本次结果不会保留。"
        writingStopTask?.cancel()
        writingStopTask = Task {
            for attempt in 0..<3 {
                task?.cancel()
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(180))
                }
            }

            await MainActor.run {
                writingStopTask = nil
                guard writingRunState == .stopping else { return }
                writingGenerationTask = nil
                writingRunState = .idle
                timingSnapshot = .idle
                aiStatusMessage = "已停止本次写作，本次结果不会保留。"
            }
        }
    }

    private func rewriteSuggestion(for project: NovelProject) {
        let rejectedSuggestion = aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        startWriting(for: project, rejectedSuggestion: rejectedSuggestion.isEmpty ? nil : rejectedSuggestion)
    }

    private func acceptAISuggestionIntoDraft(for project: NovelProject) {
        let trimmed = aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let blockingMessage = blockedAISuggestionAcceptanceMessage(for: project) {
            aiStatusMessage = blockingMessage
            return
        }

        appState.appendDraftText(trimmed, for: project.id)
        aiSuggestion = ""
        if latestChapterReviewDraftContext == nil {
            latestChapterReview = nil
        }
        latestReviewedAISuggestionText = ""
        latestAISuggestionAcceptanceContext = nil
        saveMessage = "已接受 AI 候选稿到草稿箱"
        aiStatusMessage = "候选稿已放入草稿箱，可继续编辑或保存当前章。"
        focusDraftEditor()
        requestAutoScroll(to: .draft)
    }

    private func canAcceptAISuggestion(for project: NovelProject) -> Bool {
        !aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && blockedAISuggestionAcceptanceMessage(for: project) == nil
    }

    private func blockedAISuggestionAcceptanceMessage(for project: NovelProject) -> String? {
        guard project.storyLength.supportsVolumePlanning else { return nil }
        let normalizedSuggestion = aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSuggestion.isEmpty else { return nil }
        guard let review = latestChapterReview else {
            return "长篇候选稿还没有可用审查结果，请先重新生成或完成审查后再放入草稿箱。"
        }
        let reviewedText = latestReviewedAISuggestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reviewedText == normalizedSuggestion else {
            return "候选稿已被修改，当前审查结果不再对应这版文本。请先重写生成新的审查结果，或把修改后的正文直接放在草稿箱手动处理。"
        }
        guard let latestAISuggestionAcceptanceContext else {
            return "长篇候选稿缺少生成时上下文记录，请重新生成后再放入草稿箱。"
        }
        guard latestAISuggestionAcceptanceContext == ChapterWritingSessionPolicy.acceptanceContext(for: project) else {
            return "生成候选稿后，草稿、章节位置、记忆或长篇后台合同已经变化。请按当前内容重新生成，避免旧上下文污染新草稿。"
        }

        let contract = LongformStorySystem.buildRuntimeContract(for: project)
        let minimumScore = contract.review.minimumAcceptedScore
        if review.hasBlockingIssues {
            let issueTitle = review.blockingIssues.first?.dimension.displayName ?? "质量审查"
            return "候选稿未通过长篇审查：\(issueTitle)存在阻断问题。请先重写这一版，或手动修订到不阻断后再放入草稿箱。"
        }
        if review.overallScore < minimumScore {
            return "候选稿审查 \(review.overallScore)/100，低于长篇最低通过线 \(minimumScore)。请先重写或修订后再放入草稿箱。"
        }

        let missedNodes = LongformStorySystem.missingMandatoryNodes(
            for: project,
            additionalText: normalizedSuggestion,
            contract: contract
        )
        if !missedNodes.isEmpty {
            return "候选稿尚未覆盖本章合同节点：\(missedNodes.prefix(2).joined(separator: "；"))。请先重写或补齐节点后再放入草稿箱。"
        }
        return nil
    }

    private func polishEntireDraft(for project: NovelProject) {
        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不可用，请先到设置里检查模型选择。"
            return
        }

        let latestProject = appState.project(for: project.id) ?? project
        let trimmedDraft = latestProject.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            aiStatusMessage = "草稿箱里还没有可润色的正文。"
            return
        }

        let instruction = draftPolishInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptProject = appState.projectWithActiveWritingSkills(latestProject)
        isGenerating = true
        activeDraftPolishMode = .full
        pendingDraftPolishReview = nil
        aiStatusMessage = instruction.isEmpty ? "AI 正在润色整篇草稿…" : "AI 正在按你的要求润色整篇草稿…"
        isDraftPolishSheetPresented = false

        Task {
            do {
                let polishedDraft = try await appState.aiService.polishFullDraft(
                    configuration: configuration,
                    project: promptProject,
                    draft: trimmedDraft,
                    instruction: instruction
                )

                await MainActor.run {
                    let normalizedDraft = polishedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalizedDraft.isEmpty else {
                        isGenerating = false
                        activeDraftPolishMode = nil
                        aiStatusMessage = "草稿润色失败：模型返回了空内容，原稿已保留。"
                        return
                    }

                    let originalSelection = draftSelection
                    let blockingMessage = longformDraftPolishBlockingMessage(
                        polishedDraft: normalizedDraft,
                        project: latestProject
                    )
                    let isApplied = blockingMessage == nil
                    if isApplied {
                        appState.updateDraftText(normalizedDraft, for: project.id)
                    }
                    pendingDraftPolishReview = DraftPolishReview(
                        projectID: project.id,
                        mode: .full,
                        originalDraft: latestProject.draftText,
                        polishedDraft: normalizedDraft,
                        polishedText: normalizedDraft,
                        restoredSelection: originalSelection,
                        isApplied: isApplied,
                        blockingMessage: blockingMessage
                    )
                    pendingDraftPolishReviewAnchorPoint = nil
                    saveMessage = blockingMessage == nil ? "润色结果待确认" : "润色结果未写入"
                    aiStatusMessage = blockingMessage ?? "整篇草稿已完成润色并写回正文。可选择保留或舍弃。"
                    isGenerating = false
                    activeDraftPolishMode = nil
                    draftSelection = .empty
                    draftSelectionActionPoint = nil
                    selectionPolishTarget = nil
                    selectionPolishAnchorPoint = nil
                    focusDraftEditor()
                    requestAutoScroll(to: .draft)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    activeDraftPolishMode = nil
                    AppLogger.ai.error("Full draft polish failed: \(error.localizedDescription, privacy: .public)")
                    presentAIError(error, title: "草稿润色失败", fallbackAction: "请检查模型配置后重试。")
                }
            }
        }
    }

    private func polishDraftSelection(for project: NovelProject) {
        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不可用，请先到设置里检查模型选择。"
            return
        }

        let currentSelection = selectionPolishTarget ?? draftSelection
        guard currentSelection.hasSelection else {
            aiStatusMessage = "请先在草稿箱里划词或划句子，再执行润色。"
            return
        }

        let latestProject = appState.project(for: project.id) ?? project
        let promptProject = appState.projectWithActiveWritingSkills(latestProject)
        let instruction = selectionPolishInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectionContext = selectionPolishContext(in: latestProject.draftText, selection: currentSelection.range)
        let reviewAnchorPoint = selectionPolishAnchorPoint ?? draftSelectionActionPoint
        isGenerating = true
        activeDraftPolishMode = .selection
        pendingDraftPolishReview = nil
        aiStatusMessage = instruction.isEmpty ? "AI 正在润色当前选区…" : "AI 正在按你的要求润色当前选区…"
        isSelectionPolishPopoverPresented = false

        Task {
            do {
                let polishedSelection = try await appState.aiService.polishSelection(
                    configuration: configuration,
                    project: promptProject,
                    selectedText: currentSelection.text,
                    instruction: instruction,
                    fullDraft: latestProject.draftText,
                    precedingContext: selectionContext.leading,
                    followingContext: selectionContext.trailing
                )

                await MainActor.run {
                    let normalizedSelection = normalizedSelectionPolishResult(polishedSelection)
                    if let updatedDraft = draftReplacingSelection(
                        normalizedSelection,
                        selection: currentSelection,
                        in: latestProject.draftText
                    ) {
                        let blockingMessage = longformDraftPolishBlockingMessage(
                            polishedDraft: updatedDraft,
                            project: latestProject
                        )
                        let isApplied = blockingMessage == nil
                        if isApplied {
                            applyPolishedSelection(
                                normalizedSelection,
                                selection: currentSelection,
                                for: project.id
                            )
                        }
                        pendingDraftPolishReview = DraftPolishReview(
                            projectID: project.id,
                            mode: .selection,
                            originalDraft: latestProject.draftText,
                            polishedDraft: updatedDraft,
                            polishedText: normalizedSelection,
                            restoredSelection: currentSelection,
                            isApplied: isApplied,
                            blockingMessage: blockingMessage
                        )
                        pendingDraftPolishReviewAnchorPoint = reviewAnchorPoint
                    }
                    saveMessage = pendingDraftPolishReview?.blockingMessage == nil ? "润色结果待确认" : "润色结果未写入"
                    aiStatusMessage = pendingDraftPolishReview?.blockingMessage ?? "当前选区已润色并写回正文。可选择保留或舍弃。"
                    isGenerating = false
                    activeDraftPolishMode = nil
                    selectionPolishTarget = nil
                    selectionPolishAnchorPoint = nil
                    selectionPolishInstruction = ""
                    focusDraftEditor()
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    activeDraftPolishMode = nil
                    AppLogger.ai.error("Selection polish failed: \(error.localizedDescription, privacy: .public)")
                    presentAIError(error, title: "选区润色失败", fallbackAction: "请检查模型配置后重试。")
                }
            }
        }
    }

    private func saveCurrentChapterDraft(
        for project: NovelProject,
        advanceToNextChapter: Bool = false,
        preSaveReview: ChapterReviewResult? = nil,
        validatedConfiguration: AIConnectionConfiguration? = nil
    ) {
        let latestProject = appState.project(for: project.id) ?? project
        let trimmedDraft = latestProject.draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDraft.isEmpty else {
            aiStatusMessage = "草稿箱里还没有可保存的正文。"
            return
        }

        if latestProject.storyLength.supportsVolumePlanning, preSaveReview == nil {
            guard let configuration = validatedConfiguration ?? appState.aiConfiguration else {
                saveLongformChapterWithoutModel(for: latestProject, advanceToNextChapter: advanceToNextChapter)
                return
            }

            if let blockingMessage = writingPreflightBlockingMessage(for: latestProject, allowsCurrentChapterRepair: true) {
                aiStatusMessage = blockingMessage.replacingOccurrences(of: "暂不生成候选稿", with: "暂不保存当前章")
                return
            }

            let contract = LongformStorySystem.buildRuntimeContract(for: latestProject)
            let missedNodes = LongformStorySystem.missingMandatoryNodes(
                for: latestProject,
                additionalText: "",
                contract: contract
            )
            if !missedNodes.isEmpty {
                aiStatusMessage = "长篇保存门禁未通过：当前草稿漏掉本章合同节点：\(missedNodes.prefix(2).joined(separator: "；"))。请补齐后再保存。"
                return
            }

            let saveContext = ChapterWritingSessionPolicy.chapterSaveValidationContext(for: latestProject)
            let reviewProject = appState.projectWithActiveWritingSkills(latestProject)
            isSavingChapter = true
            aiStatusMessage = "长篇章节保存前正在运行质量审查，只有通过后才会收录进已保存章节…"

            Task {
                do {
                    let review = try await ChapterQualityReviewer.reviewChapter(
                        project: reviewProject,
                        chapterDraft: trimmedDraft,
                        memoryContext: reviewProject.enhancedMemoryContext,
                        configuration: configuration
                    )

                    await MainActor.run {
                        guard let currentProject = appState.project(for: project.id),
                              ChapterWritingSessionPolicy.chapterSaveValidationContext(for: currentProject) == saveContext
                        else {
                            isSavingChapter = false
                            aiStatusMessage = "保存审查期间正文或章节位置已经变化，旧审查结果已丢弃。请按当前内容重新保存。"
                            revealWritingDeskWindow(for: project.id)
                            return
                        }

                        latestChapterReview = review
                        latestChapterReviewDraftContext = ChapterWritingSessionPolicy.chapterSaveValidationContext(for: currentProject)
                        appState.applyEnhancedWritingUpdate(
                            nil,
                            review: review,
                            reviewedChapter: ChapterReviewTarget(
                                volumeNumber: currentProject.currentVolumeNumber,
                                chapterNumber: currentProject.currentChapterNumber,
                                chapterTitle: currentProject.currentChapterTitle
                            ),
                            for: project.id
                        )

                        if let blockingMessage = longformChapterSaveBlockingMessage(review: review, project: currentProject) {
                            isSavingChapter = false
                            aiStatusMessage = blockingMessage
                            revealWritingDeskWindow(for: project.id)
                            return
                        }

                        saveCurrentChapterDraft(
                            for: currentProject,
                            advanceToNextChapter: advanceToNextChapter,
                            preSaveReview: review,
                            validatedConfiguration: configuration
                        )
                    }
                } catch {
                    await MainActor.run {
                        isSavingChapter = false
                        aiStatusMessage = "长篇章节保存前审查失败，当前章未收录：\(error.localizedDescription)"
                        revealWritingDeskWindow(for: project.id)
                    }
                }
            }
            return
        }

        isSavingChapter = true

        if latestProject.hasSavedCurrentChapter {
            guard let result = completeChapterDraftSave(for: project, statusPrefix: "已按当前标题更新") else {
                isSavingChapter = false
                return
            }

            guard let configuration = validatedConfiguration ?? appState.aiConfiguration else {
                let longformCommit = applyLocalLongformUpdates(after: result, for: project.id)
                let canAdvance = advanceToNextChapter && (longformCommit?.isAccepted ?? true)
                if advanceToNextChapter {
                    if canAdvance {
                        appState.beginNextChapter(after: result.chapterDraft, for: project.id)
                    }
                    aiStatusMessage = longformSaveMessage(
                        prefix: "已按当前标题更新",
                        chapterSummary: result.chapterDraft.chapterSummary,
                        commit: longformCommit,
                        advancedToNextChapter: canAdvance,
                        suffix: "未配置模型，暂未刷新全局记忆和章节树。"
                    )
                } else {
                    aiStatusMessage = longformSaveMessage(
                        prefix: "已按当前标题更新",
                        chapterSummary: result.chapterDraft.chapterSummary,
                        commit: longformCommit,
                        advancedToNextChapter: false,
                        suffix: "未配置模型，暂未刷新全局记忆和章节树。"
                    )
                }
                isSavingChapter = false
                return
            }

            refreshProjectContextAfterChapterSave(
                for: project,
                saveResult: result,
                configuration: configuration,
                statusPrefix: "已按当前标题更新",
                advanceToNextChapter: advanceToNextChapter,
                preSaveReview: preSaveReview
            )
            return
        }

        guard let configuration = validatedConfiguration ?? appState.aiConfiguration else {
            let fallbackTitle = fallbackChapterTitle(for: latestProject)
            appState.updateCurrentChapterTitle(fallbackTitle, for: project.id)
            if let result = completeChapterDraftSave(for: project, statusPrefix: "模型未配置，已按当前标题保存") {
                let longformCommit = applyLocalLongformUpdates(after: result, for: project.id)
                let canAdvance = advanceToNextChapter && (longformCommit?.isAccepted ?? true)
                if advanceToNextChapter {
                    if canAdvance {
                        appState.beginNextChapter(after: result.chapterDraft, for: project.id)
                    }
                    aiStatusMessage = longformSaveMessage(
                        prefix: "模型未配置，已按当前标题保存",
                        chapterSummary: result.chapterDraft.chapterSummary,
                        commit: longformCommit,
                        advancedToNextChapter: canAdvance,
                        suffix: "暂未刷新全局记忆和章节树。"
                    )
                } else {
                    aiStatusMessage = longformSaveMessage(
                        prefix: "模型未配置，已按当前标题保存",
                        chapterSummary: result.chapterDraft.chapterSummary,
                        commit: longformCommit,
                        advancedToNextChapter: false,
                        suffix: "暂未刷新全局记忆和章节树。"
                    )
                }
            }
            isSavingChapter = false
            return
        }

        aiStatusMessage = "AI 正在根据草稿箱内容拟一个章节标题，并同步保存当前章…"
        let reviewedSaveContext = preSaveReview.map { _ in
            ChapterWritingSessionPolicy.chapterSaveValidationContext(for: latestProject)
        }

        Task {
            do {
                let title = try await appState.aiService.suggestChapterTitle(
                    configuration: configuration,
                    project: latestProject,
                    chapterContent: trimmedDraft
                )

                await MainActor.run {
                    if let reviewedSaveContext {
                        guard let currentProject = appState.project(for: project.id),
                              ChapterWritingSessionPolicy.chapterSaveValidationContext(for: currentProject) == reviewedSaveContext
                        else {
                            isSavingChapter = false
                            aiStatusMessage = "拟标题期间正文、章节位置或长篇上下文已经变化，旧保存审查结果已丢弃。请按当前内容重新保存。"
                            revealWritingDeskWindow(for: project.id)
                            return
                        }
                    }

                    appState.updateCurrentChapterTitle(title, for: project.id)
                    if let result = completeChapterDraftSave(for: project, statusPrefix: "AI 已拟好标题并保存") {
                        refreshProjectContextAfterChapterSave(
                            for: project,
                            saveResult: result,
                            configuration: configuration,
                            statusPrefix: "AI 已拟好标题并保存",
                            advanceToNextChapter: advanceToNextChapter,
                            preSaveReview: preSaveReview
                        )
                    } else {
                        isSavingChapter = false
                        revealWritingDeskWindow(for: project.id)
                    }
                }
            } catch {
                await MainActor.run {
                    if let reviewedSaveContext {
                        guard let currentProject = appState.project(for: project.id),
                              ChapterWritingSessionPolicy.chapterSaveValidationContext(for: currentProject) == reviewedSaveContext
                        else {
                            isSavingChapter = false
                            aiStatusMessage = "拟标题期间正文、章节位置或长篇上下文已经变化，旧保存审查结果已丢弃。请按当前内容重新保存。"
                            revealWritingDeskWindow(for: project.id)
                            return
                        }
                    }

                    let fallbackTitle = fallbackChapterTitle(for: latestProject)
                    appState.updateCurrentChapterTitle(fallbackTitle, for: project.id)
                    if let result = completeChapterDraftSave(
                        for: project,
                        statusPrefix: "AI 拟标题失败，已按当前标题保存",
                        detailMessage: UserFacingError.aiMessage(for: error, fallbackAction: "AI 拟标题失败。")
                    ) {
                        refreshProjectContextAfterChapterSave(
                            for: project,
                            saveResult: result,
                            configuration: configuration,
                            statusPrefix: "AI 拟标题失败，已按当前标题保存",
                            detailMessage: UserFacingError.aiMessage(for: error, fallbackAction: "AI 拟标题失败。"),
                            advanceToNextChapter: advanceToNextChapter,
                            preSaveReview: preSaveReview
                        )
                    } else {
                        isSavingChapter = false
                        revealWritingDeskWindow(for: project.id)
                    }
                }
            }
        }
    }

    private func referenceImportSummary(for project: NovelProject) -> String {
        guard let latestDocument = project.referenceDocuments.first else {
            return "还没有导入参考文件，也可以直接在上面手动粘贴上下文。"
        }

        return "已导入 \(project.referenceDocuments.count) 份 · 最近：\(latestDocument.title) · 共 \(project.referenceDocuments.reduce(0) { $0 + $1.wordCount }) 字。"
    }

    private func generationInstruction(rejecting rejectedSuggestion: String?) -> String {
        ChapterWritingSessionPolicy.generationInstruction(
            rewriteDirection: rewriteDirection,
            rejectedSuggestion: rejectedSuggestion,
            reviewFeedback: rejectedSuggestion.map(rewriteReviewFeedback) ?? ""
        )
    }
    private func rewriteReviewFeedback(for rejectedSuggestion: String) -> String {
        guard let review = latestChapterReview else { return "" }
        let reviewedText = latestReviewedAISuggestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reviewedText == rejectedSuggestion else { return "" }

        var lines: [String] = []
        let summary = review.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(summary.isEmpty ? "- 审查分数：\(review.overallScore)/100。" : "- 审查分数：\(review.overallScore)/100。\(summary)")

        let priorityIssues = (review.blockingIssues + review.nonBlockingIssues.filter { $0.severity == .high })
            .prefix(5)
        for issue in priorityIssues {
            let fixHint = issue.fixHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = issue.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            var issueLine = "- [\(issue.severity.displayName)] \(issue.dimension.displayName)：\(issue.description)"
            if !fixHint.isEmpty {
                issueLine += "；修复：\(fixHint)"
            }
            if !evidence.isEmpty {
                issueLine += "；证据：\(excerpt(from: evidence, limit: 120))"
            }
            lines.append(issueLine)
        }

        if !review.antiPatterns.isEmpty {
            lines.append("- 避免 AI 味反模式：\(review.antiPatterns.prefix(3).joined(separator: "；"))")
        }

        if lines.count == 1 {
            lines.append("- 上一版没有明确阻断项，但重写仍要明显改善承接、推进、对白和信息增量。")
        }

        return lines.joined(separator: "\n")
    }

    private func excerpt(from text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    private func fallbackChapterTitle(for project: NovelProject) -> String {
        let trimmedTitle = project.currentChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? project.currentChapterLabel : trimmedTitle
    }

    private func longformChapterSaveBlockingMessage(review: ChapterReviewResult, project: NovelProject) -> String? {
        guard project.storyLength.supportsVolumePlanning else { return nil }

        let contract = LongformStorySystem.buildRuntimeContract(for: project)
        if review.hasBlockingIssues {
            let issue = review.blockingIssues.first
            let issueTitle = issue?.dimension.displayName ?? "质量审查"
            let fixHint = issue?.fixHint.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suffix = fixHint.isEmpty ? "请先修订后再保存。" : "建议：\(fixHint)"
            return "长篇保存门禁未通过：\(issueTitle)存在阻断问题，当前章未收录。\(suffix)"
        }

        if review.overallScore < contract.review.minimumAcceptedScore {
            return "长篇保存门禁未通过：当前章审查 \(review.overallScore)/100，低于最低通过线 \(contract.review.minimumAcceptedScore)，当前章未收录。请先重写或修订后再保存。"
        }

        let missedNodes = LongformStorySystem.missingMandatoryNodes(
            for: project,
            additionalText: "",
            contract: contract
        )
        if !missedNodes.isEmpty {
            return "长篇保存门禁未通过：当前草稿漏掉本章合同节点：\(missedNodes.prefix(2).joined(separator: "；"))。请补齐后再保存。"
        }

        return nil
    }

    @discardableResult
    private func completeChapterDraftSave(
        for project: NovelProject,
        statusPrefix: String,
        detailMessage: String? = nil
    ) -> ChapterDraftSaveResult? {
        guard let result = appState.saveCurrentChapterDraft(for: project.id) else {
            aiStatusMessage = "草稿箱里还没有可保存的正文。"
            return nil
        }

        let chapterDraft = result.chapterDraft
        saveMessage = result.isUpdate ? "已更新 \(chapterDraft.chapterSummary)" : "已保存 \(chapterDraft.chapterSummary)"

        if let detailMessage {
            aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。\(detailMessage)"
        } else {
            aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。"
        }

        return result
    }

    private func applyLocalLongformUpdates(after saveResult: ChapterDraftSaveResult, for projectID: NovelProject.ID) -> LongformChapterCommit? {
        applyLocalLongformUpdates(after: saveResult, for: projectID, reviewFailureReason: nil)
    }

    private func applyLocalLongformUpdates(
        after saveResult: ChapterDraftSaveResult,
        for projectID: NovelProject.ID,
        reviewFailureReason: String?
    ) -> LongformChapterCommit? {
        let chapterDraft = saveResult.chapterDraft
        let commit = appState.extractAndStoreMemoryItems(
            from: chapterDraft,
            for: projectID,
            reviewFailureReason: reviewFailureReason
        )
        appState.appendLocalAntiPatterns(
            from: chapterDraft.content,
            for: projectID
        )
        return commit
    }

    private func saveLongformChapterWithoutModel(for project: NovelProject, advanceToNextChapter: Bool) {
        isSavingChapter = true

        let fallbackTitle = fallbackChapterTitle(for: project)
        appState.updateCurrentChapterTitle(fallbackTitle, for: project.id)

        guard let result = completeChapterDraftSave(
            for: project,
            statusPrefix: "模型未配置，已先安全保存"
        ) else {
            isSavingChapter = false
            return
        }

        let commit = applyLocalLongformUpdates(
            after: result,
            for: project.id,
            reviewFailureReason: "模型未配置，当前章已安全收录，但尚未完成质量审查、全局记忆刷新和章节树刷新。"
        )
        let canAdvance = advanceToNextChapter && (commit?.isAccepted ?? false)
        if canAdvance {
            appState.beginNextChapter(after: result.chapterDraft, for: project.id)
        }

        aiStatusMessage = longformSaveMessage(
            prefix: "模型未配置，已先安全保存",
            chapterSummary: result.chapterDraft.chapterSummary,
            commit: commit,
            advancedToNextChapter: canAdvance,
            suffix: "请稍后配置模型并重新保存/审查，以恢复质量门禁、全局记忆和章节树刷新。"
        )
        isSavingChapter = false
    }

    private func longformSaveMessage(
        prefix: String,
        chapterSummary: String,
        commit: LongformChapterCommit?,
        advancedToNextChapter: Bool,
        suffix: String
    ) -> String {
        var notes: [String] = []
        if let commit, !commit.isAccepted {
            let reasons = (commit.rejectionReasons ?? commit.missedNodes)
                .prefix(2)
                .joined(separator: "；")
            let reasonText = reasons.isEmpty ? "请检查长篇后台提示" : reasons
            notes.append("长篇后台未通过：\(reasonText)")
            if advancedToNextChapter {
                notes.append("已进入下一章")
            } else {
                notes.append("已停留在本章，建议修订后再进入下一章")
            }
        } else {
            notes.append("已完成本地长篇记忆提交")
            if advancedToNextChapter {
                notes.append("已进入下一章")
            }
        }
        notes.append(suffix)
        return "\(prefix) \(chapterSummary)。\(notes.joined(separator: "；"))"
    }

    private func refreshProjectContextAfterChapterSave(
        for project: NovelProject,
        saveResult: ChapterDraftSaveResult,
        configuration: AIConnectionConfiguration,
        statusPrefix: String,
        detailMessage: String? = nil,
        advanceToNextChapter: Bool = false,
        preSaveReview: ChapterReviewResult? = nil
    ) {
        let chapterDraft = saveResult.chapterDraft
        aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。正在更新全局记忆和章节树…"
        let baselineProject = appState.project(for: project.id) ?? project
        let baseline = ChapterTreeRefreshBaseline(project: baselineProject)
        let baselineLongformContract = LongformStorySystem.buildRuntimeContract(for: baselineProject)
        let refreshToken = UUID()
        projectContextRefreshTokens[project.id] = refreshToken

        Task {
            let latestProject = appState.project(for: project.id) ?? baselineProject
            let latestReviewProject = appState.projectWithActiveWritingSkills(latestProject)

            async let globalMemoryTask: Result<String, Error> = {
                do {
                    return .success(try await appState.aiService.refreshGlobalMemory(
                        configuration: configuration,
                        project: latestProject,
                        savedChapter: chapterDraft
                    ))
                } catch {
                    return .failure(error)
                }
            }()

            async let chapterTreeTask: Result<ChapterTreeRefresh, Error> = {
                do {
                    return .success(try await appState.aiService.refreshChapterTree(
                        configuration: configuration,
                        project: latestProject,
                        savedChapter: chapterDraft
                    ))
                } catch {
                    return .failure(error)
                }
            }()

            async let reviewTask: Result<ChapterReviewResult, Error> = {
                if let preSaveReview {
                    return .success(preSaveReview)
                }

                do {
                    return .success(try await ChapterQualityReviewer.reviewChapter(
                        project: latestReviewProject,
                        chapterDraft: chapterDraft.content,
                        memoryContext: latestReviewProject.enhancedMemoryContext,
                        configuration: configuration
                    ))
                } catch {
                    return .failure(error)
                }
            }()

            let globalMemoryResult = await globalMemoryTask
            let chapterTreeResult = await chapterTreeTask
            let reviewResult = await reviewTask

            await MainActor.run {
                guard projectContextRefreshTokens[project.id] == refreshToken else {
                    return
                }

                let updatedAt = TimestampLabel.project()
                let currentProject = appState.project(for: project.id)
                let normalizedContinuity = currentProject?.continuityNotes
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let shouldApplyGlobalMemory = normalizedContinuity == baseline.continuityNotes
                let preservedLocalGlobalMemory = currentProject != nil && !shouldApplyGlobalMemory

                var chapterTreeApplyOutcome = ChapterTreeRefreshApplyOutcome()

                if case let .success(globalMemory) = globalMemoryResult,
                   shouldApplyGlobalMemory,
                   !globalMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appState.updateContinuityNotes(
                        globalMemory,
                        updatedAt: updatedAt,
                        for: project.id
                    )
                }

                if case let .success(chapterTreeRefresh) = chapterTreeResult {
                    chapterTreeApplyOutcome = appState.applyChapterTreeRefresh(
                        chapterTreeRefresh,
                        baseline: baseline,
                        updatedAt: updatedAt,
                        for: project.id
                    )
                }

                let currentChapterReview: ChapterReviewResult?
                if case let .success(review) = reviewResult {
                    currentChapterReview = review
                    latestChapterReview = review
                    if let reviewedProject = appState.project(for: project.id) {
                        latestChapterReviewDraftContext = ChapterWritingSessionPolicy.chapterSaveValidationContext(for: reviewedProject)
                    } else {
                        latestChapterReviewDraftContext = nil
                    }
                    appState.applyEnhancedWritingUpdate(
                        nil,
                        review: review,
                        reviewedChapter: ChapterReviewTarget(chapterDraft: chapterDraft),
                        for: project.id
                    )
                } else {
                    currentChapterReview = nil
                }
                let reviewFailureReason: String?
                if case let .failure(error) = reviewResult {
                    reviewFailureReason = error.localizedDescription
                } else {
                    reviewFailureReason = nil
                }

                // Auto-populate the background longform chain before moving the UI to the next chapter.
                let chapterContent = chapterDraft.content
                let chapterNum = chapterDraft.chapterNumber
                let longformCommit = appState.extractAndStoreMemoryItems(
                    from: chapterDraft,
                    for: project.id,
                    review: currentChapterReview,
                    reviewFailureReason: reviewFailureReason,
                    contractOverride: baselineLongformContract
                )

                // Also run AI-powered extraction for deeper memory extraction
                if longformCommit?.isAccepted ?? true {
                    appState.runAIMemoryExtraction(
                        from: chapterContent,
                        chapterNumber: chapterNum,
                        volumeNumber: chapterDraft.volumeNumber,
                        expectedCommitID: longformCommit?.id,
                        projectID: project.id
                    )
                }

                let canAdvance = advanceToNextChapter && (longformCommit?.isAccepted ?? true)
                if canAdvance {
                    appState.beginNextChapter(after: chapterDraft, for: project.id)
                }

                // Accumulate locally-detected AI anti-patterns
                appState.appendLocalAntiPatterns(
                    from: chapterContent,
                    for: project.id
                )

                projectContextRefreshTokens.removeValue(forKey: project.id)
                isSavingChapter = false
                aiStatusMessage = chapterSaveRefreshMessage(
                    statusPrefix: statusPrefix,
                    chapterSummary: chapterDraft.chapterSummary,
                    detailMessage: detailMessage,
                    globalMemoryResult: globalMemoryResult,
                    preservedLocalGlobalMemory: preservedLocalGlobalMemory,
                    chapterTreeResult: chapterTreeResult,
                    chapterTreeApplyOutcome: chapterTreeApplyOutcome,
                    reviewResult: reviewResult,
                    longformCommit: longformCommit,
                    advancedToNextChapter: canAdvance
                )
                revealWritingDeskWindow(for: project.id)
            }
        }
    }

    private func chapterSaveRefreshMessage(
        statusPrefix: String,
        chapterSummary: String,
        detailMessage: String?,
        globalMemoryResult: Result<String, Error>,
        preservedLocalGlobalMemory: Bool,
        chapterTreeResult: Result<ChapterTreeRefresh, Error>,
        chapterTreeApplyOutcome: ChapterTreeRefreshApplyOutcome,
        reviewResult: Result<ChapterReviewResult, Error>,
        longformCommit: LongformChapterCommit?,
        advancedToNextChapter: Bool = false
    ) -> String {
        let detailPrefix = detailMessage.map { "\($0) " } ?? ""
        var refreshNotes: [String] = []

        switch globalMemoryResult {
        case let .success(globalMemory) where globalMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            refreshNotes.append("全局记忆返回为空，已保留当前版本")
        case .success:
            if preservedLocalGlobalMemory {
                refreshNotes.append("检测到你刚手动修改了全局记忆，已保留本地版本")
            } else {
                refreshNotes.append("全局记忆已更新")
            }
        case let .failure(error):
            refreshNotes.append("全局记忆更新失败：\(error.localizedDescription)")
        }

        switch chapterTreeResult {
        case let .success(refresh) where !refresh.hasStructuredContent:
            refreshNotes.append("章节树返回为空，已保留当前版本")
        case .success:
            let chapterTreeSummary = chapterTreeApplyOutcome.summaryLabel
            if !chapterTreeSummary.isEmpty {
                refreshNotes.append("章节树刷新结果：\(chapterTreeSummary)")
            } else if chapterTreeApplyOutcome.preservedLocalChanges {
                refreshNotes.append("章节树已刷新，并保留了你刚修改过的 \(chapterTreeApplyOutcome.protectedSections) 个区块")
            } else {
                refreshNotes.append("章节树已同步更新")
            }
        case let .failure(error):
            refreshNotes.append("章节树更新失败：\(error.localizedDescription)")
        }

        switch reviewResult {
        case let .success(review):
            refreshNotes.append("当前章审查 \(review.overallScore)/100")
        case let .failure(error):
            refreshNotes.append("当前章审查失败：\(error.localizedDescription)")
        }

        if let longformCommit, !longformCommit.isAccepted {
            let reasons = (longformCommit.rejectionReasons ?? longformCommit.missedNodes)
                .prefix(2)
                .joined(separator: "；")
            let reasonText = reasons.isEmpty ? "请检查长篇后台提示" : reasons
            refreshNotes.append("长篇后台未通过：\(reasonText)")
            refreshNotes.append("已停留在本章，建议修订后再进入下一章")
        } else if advancedToNextChapter {
            refreshNotes.append("已进入下一章")
        }

        return "\(statusPrefix) \(chapterSummary)。\(detailPrefix)\(refreshNotes.joined(separator: "；"))。"
    }

    private func draftFindSummary(for project: NovelProject) -> String {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "输入关键词后可在当前草稿内查找或替换。" }
        let count = draftMatchRanges(in: project.draftText, query: query).count
        return count == 0 ? "当前草稿未找到“\(query)”." : "当前草稿找到 \(count) 处“\(query)”。"
    }

    private func findNextInDraft(for project: NovelProject) {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        guard let range = nextDraftMatchRange(in: project.draftText, query: query) else {
            findStatusMessage = "当前草稿未找到“\(query)”。"
            return
        }

        draftSelection = WritingDeskDraftSelection(
            range: range,
            text: (project.draftText as NSString).substring(with: range)
        )
        findStatusMessage = "已选中下一处“\(query)”。"
        focusDraftEditor()
    }

    private func replaceNextInDraft(for project: NovelProject) {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        guard let range = nextDraftMatchRange(in: project.draftText, query: query) else {
            findStatusMessage = "当前草稿未找到“\(query)”。"
            return
        }

        let mutableDraft = NSMutableString(string: project.draftText)
        mutableDraft.replaceCharacters(in: range, with: replacementText)
        appState.updateDraftText(mutableDraft as String, for: project.id)
        draftSelection = WritingDeskDraftSelection(
            range: NSRange(
                location: range.location + (replacementText as NSString).length,
                length: 0
            ),
            text: ""
        )
        findStatusMessage = "已替换 1 处“\(query)”。"
        focusDraftEditor()
    }

    private func replaceAllInDraft(for project: NovelProject) {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let ranges = draftMatchRanges(in: project.draftText, query: query)
        guard !ranges.isEmpty else {
            findStatusMessage = "当前草稿未找到“\(query)”。"
            return
        }

        let mutableDraft = NSMutableString(string: project.draftText)
        for range in ranges.reversed() {
            mutableDraft.replaceCharacters(in: range, with: replacementText)
        }
        appState.updateDraftText(mutableDraft as String, for: project.id)
        draftSelection = .empty
        findStatusMessage = "已替换 \(ranges.count) 处“\(query)”。"
        focusDraftEditor()
    }

    private func nextDraftMatchRange(in text: String, query: String) -> NSRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let startLocation = min(draftSelection.range.location + max(draftSelection.range.length, 0), nsText.length)
        let options: NSString.CompareOptions = [.caseInsensitive, .widthInsensitive]
        let trailingRange = NSRange(location: startLocation, length: nsText.length - startLocation)
        let trailingMatch = nsText.range(of: query, options: options, range: trailingRange)
        if trailingMatch.location != NSNotFound {
            return trailingMatch
        }

        let leadingRange = NSRange(location: 0, length: startLocation)
        let leadingMatch = nsText.range(of: query, options: options, range: leadingRange)
        return leadingMatch.location == NSNotFound ? nil : leadingMatch
    }

    private func draftMatchRanges(in text: String, query: String) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        let options: NSString.CompareOptions = [.caseInsensitive, .widthInsensitive]

        while searchRange.length > 0 {
            let match = nsText.range(of: query, options: options, range: searchRange)
            guard match.location != NSNotFound else { break }
            ranges.append(match)

            let nextLocation = match.location + max(match.length, 1)
            guard nextLocation <= nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return ranges
    }

    private func requestAutoScroll(to anchor: WritingDeskScrollAnchor) {
        guard !autoScrollLocked, !areConfigurationCardsCollapsed else { return }
        pendingScrollAnchor = anchor
    }

    private func revealWritingDeskWindow(for projectID: NovelProject.ID) {
        appState.openWritingDesk(for: projectID)
        AppRuntime.shared.windowCoordinator.showMainWindow()
    }

    private func presentAIError(_ error: Error, title: String, fallbackAction: String) {
        let message = UserFacingError.aiMessage(for: error, fallbackAction: fallbackAction)
        aiStatusMessage = message
        operationAlert = WritingDeskOperationAlert(title: title, message: message)
    }

    private func focusDraftEditor() {
        DispatchQueue.main.async {
            draftEditorFocusToken = UUID()
        }
    }

    private func focusAIEditor() {
        DispatchQueue.main.async {
            focusedArea = .ai
        }
    }

    private func resetSessionState() {
        cancelActiveGenerationTasks()
        aiSuggestion = ""
        isGenerating = false
        isSavingChapter = false
        writingRunState = .idle
        projectContextRefreshTokens.removeAll()
        isCacheCollapsed = false
        autoScrollLocked = false
        timingSnapshot = .idle
        draftSelection = .empty
        draftSelectionActionPoint = nil
        selectionPolishTarget = nil
        selectionPolishAnchorPoint = nil
        draftPolishInstruction = ""
        selectionPolishInstruction = ""
        activeDraftPolishMode = nil
        pendingDraftPolishReview = nil
        pendingDraftPolishReviewAnchorPoint = nil
        latestChapterReview = nil
        latestChapterReviewDraftContext = nil
        latestReviewedAISuggestionText = ""
        latestAISuggestionAcceptanceContext = nil
        latestStrandWarning = nil
        pendingChapterLoad = nil
        operationAlert = nil
        findStatusMessage = ""
        isSelectionPolishPopoverPresented = false
        saveMessage = "自动保存已开启，可按章节收录"
        aiStatusMessage = "准备就绪，可先补大纲、参考文本和特殊要求，再开始当前章节写作。"
        focusDraftEditor()
    }

    private func requestChapterLoadFromNavigator(_ metadata: ChapterDraftMetadata, for project: NovelProject) {
        if shouldConfirmChapterLoad(metadata, in: project) {
            pendingChapterLoad = metadata
            return
        }

        loadChapterFromNavigator(metadata, for: project)
    }

    private func loadChapterFromNavigator(_ metadata: ChapterDraftMetadata, for project: NovelProject) {
        appState.loadChapterDraft(metadata.id, for: project.id)
        saveMessage = "已载入 \(metadata.chapterSummary)，可以继续编辑。"
        isChapterNavigatorPresented = false
        pendingChapterLoad = nil
        focusDraftEditor()
    }

    private func performStorageRecovery(issue: ProjectStorageIssue, action: StorageRecoveryAction) {
        if let result = appState.recoverStorageIssue(issue, action: action) {
            if let outputURL = result.outputURL {
                aiStatusMessage = "\(result.message)（\(outputURL.lastPathComponent)）"
            } else {
                aiStatusMessage = result.message
            }
            if result.didChangeStore {
                saveMessage = "存储恢复已完成，已重新检查项目文件。"
            }
        } else {
            aiStatusMessage = appState.cloudSyncStatusMessage
        }
    }

    private func shouldConfirmChapterLoad(_ metadata: ChapterDraftMetadata, in project: NovelProject) -> Bool {
        let currentDraft = project.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentDraft.isEmpty else { return false }

        let currentSavedDraft = project.chapterDrafts.first {
            $0.volumeNumber == max(project.currentVolumeNumber, 1)
                && $0.chapterNumber == max(project.currentChapterNumber, 1)
        }
        let savedText = currentSavedDraft?.content.trimmingCharacters(in: .whitespacesAndNewlines)

        if savedText == currentDraft {
            return false
        }

        if metadata.volumeNumber == max(project.currentVolumeNumber, 1),
           metadata.chapterNumber == max(project.currentChapterNumber, 1) {
            return true
        }

        return true
    }

    private func clearOutlineGenerationRequest(token: UUID) {
        guard outlineGenerationToken == token else { return }
        outlineGenerationToken = nil
        outlineGenerationTask = nil
    }

    private func clearWritingGenerationRequest(token: UUID) {
        guard writingGenerationToken == token else { return }
        writingGenerationToken = nil
        writingGenerationTask = nil
    }

    private func cancelActiveGenerationTasks() {
        outlineGenerationToken = nil
        writingGenerationToken = nil
        outlineGenerationTask?.cancel()
        writingGenerationTask?.cancel()
        writingProgressTask?.cancel()
        writingStopTask?.cancel()
        outlineGenerationTask = nil
        writingGenerationTask = nil
        writingProgressTask = nil
        writingStopTask = nil
    }

    private func startWritingProgressMonitor() {
        writingProgressTask?.cancel()
        let startedAt = Date()

        writingProgressTask = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                let snapshot = AIWriterTimingSnapshot.live(elapsed: elapsed)
                let nextThinkingIndex = min(
                    Int(elapsed / 1.2),
                    max(thinkingMode.messages.count - 1, 0)
                )

                await MainActor.run {
                    guard writingRunState == .requesting else { return }
                    timingSnapshot = snapshot
                    thinkingStepIndex = nextThinkingIndex
                }

                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }

    private func stopWritingProgressMonitor(resetSnapshot: Bool = false, markStopping: Bool = false) {
        writingProgressTask?.cancel()
        writingProgressTask = nil

        if markStopping {
            timingSnapshot = timingSnapshot.stopping()
        } else if resetSnapshot {
            timingSnapshot = .idle
        }
    }

    private func keepDraftPolishReview(_ review: DraftPolishReview) {
        guard pendingDraftPolishReview?.id == review.id else { return }
        if let blockingMessage = review.blockingMessage {
            aiStatusMessage = blockingMessage
            return
        }
        if !review.isApplied {
            appState.updateDraftText(review.polishedDraft, for: review.projectID)
        }

        pendingDraftPolishReview = nil
        pendingDraftPolishReviewAnchorPoint = nil
        saveMessage = review.mode == .full ? "已保留整篇润色结果" : "已保留选区润色结果"
        aiStatusMessage = "润色结果已保留，可继续编辑或保存当前章。"
        focusDraftEditor()
    }

    private func replaceDraftPolishReview(_ review: DraftPolishReview) {
        guard pendingDraftPolishReview?.id == review.id else { return }
        if let blockingMessage = review.blockingMessage {
            aiStatusMessage = blockingMessage
            return
        }

        appState.updateDraftText(review.polishedDraft, for: review.projectID)
        pendingDraftPolishReview = nil
        pendingDraftPolishReviewAnchorPoint = nil
        saveMessage = review.mode == .full ? "已替换为整篇润色结果" : "已替换为选区润色结果"
        aiStatusMessage = "已将草稿内容替换为这次润色结果。"
        focusDraftEditor()
    }

    private func discardDraftPolishReview(_ review: DraftPolishReview) {
        guard pendingDraftPolishReview?.id == review.id else { return }

        if review.isApplied {
            appState.updateDraftText(review.originalDraft, for: review.projectID)
        }
        pendingDraftPolishReview = nil
        pendingDraftPolishReviewAnchorPoint = nil
        draftSelection = review.restoredSelection
        saveMessage = "已舍弃本次润色"
        aiStatusMessage = review.isApplied ? "已恢复到润色前的草稿。" : "已关闭未写入正文的润色结果。"
        focusDraftEditor()
    }

    private func copyDraftPolishReview(_ review: DraftPolishReview) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(review.polishedText, forType: .string)
        saveMessage = "已复制润色结果"
        aiStatusMessage = "润色结果已复制到剪贴板。"
    }

    private func draftPolishReviewPopoverBinding(for projectID: NovelProject.ID) -> Binding<Bool> {
        Binding(
            get: {
                pendingDraftPolishReview?.projectID == projectID
            },
            set: { _ in
                // Keep the review open until the user chooses 保留 / 替换 / 舍弃.
            }
        )
    }

    @discardableResult
    private func applyPolishedSelection(
        _ replacement: String,
        selection: WritingDeskDraftSelection,
        for projectID: NovelProject.ID
    ) -> String? {
        guard let currentDraft = appState.project(for: projectID)?.draftText,
              let range = Range(selection.range, in: currentDraft)
        else {
            return nil
        }

        var updatedDraft = currentDraft
        updatedDraft.replaceSubrange(range, with: replacement)
        appState.updateDraftText(updatedDraft, for: projectID)

        let nsDraft = updatedDraft as NSString
        let replacementLength = (replacement as NSString).length
        let clampedLocation = min(selection.range.location, nsDraft.length)
        draftSelection = WritingDeskDraftSelection(
            range: NSRange(location: clampedLocation, length: replacementLength),
            text: replacement
        )
        return updatedDraft
    }

    private func draftReplacingSelection(
        _ replacement: String,
        selection: WritingDeskDraftSelection,
        in draft: String
    ) -> String? {
        guard let range = Range(selection.range, in: draft) else {
            return nil
        }

        var updatedDraft = draft
        updatedDraft.replaceSubrange(range, with: replacement)
        return updatedDraft
    }

    private func longformDraftPolishBlockingMessage(polishedDraft: String, project: NovelProject) -> String? {
        guard project.storyLength.supportsVolumePlanning else { return nil }

        var projectedProject = project
        projectedProject.draftText = polishedDraft
        let contract = LongformStorySystem.buildRuntimeContract(for: projectedProject)
        let missedNodes = LongformStorySystem.missingMandatoryNodes(
            for: projectedProject,
            additionalText: "",
            contract: contract
        )
        if !missedNodes.isEmpty {
            return "长篇润色结果未写入正文：它漏掉当前章合同节点：\(missedNodes.prefix(2).joined(separator: "；"))。可复制结果手动摘用，或先补齐节点后再保存。"
        }

        let localPatterns = ChapterQualityReviewer.quickAIFlavorCheck(text: polishedDraft)
        let severePatterns = localPatterns.filter {
            $0.contains("连续") || $0.contains("模板表达") || $0.contains("情绪标签化")
        }
        if !severePatterns.isEmpty || localPatterns.count >= 3 {
            let reason = (severePatterns.isEmpty ? localPatterns : severePatterns)
                .prefix(2)
                .joined(separator: "；")
            return "长篇润色结果未写入正文：检测到明显 AI 味风险：\(reason)。可复制结果手动摘用，或换更具体的润色要求重试。"
        }

        return nil
    }

    private func normalizedSelectionPolishResult(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return rawText
        }

        let pairedWrappers = [
            ("```", "```"),
            ("“", "”"),
            ("\"", "\""),
            ("'", "'")
        ]

        for (prefix, suffix) in pairedWrappers {
            if trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix), trimmed.count > prefix.count + suffix.count {
                let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
                let end = trimmed.index(trimmed.endIndex, offsetBy: -suffix.count)
                return String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    private func selectionPolishButtonPosition(in containerSize: CGSize, anchor: CGPoint) -> CGPoint {
        let horizontalPadding: CGFloat = 86
        let verticalPadding: CGFloat = 28
        let preferredX = anchor.x
        let preferredY = anchor.y - 38

        return CGPoint(
            x: min(max(preferredX, horizontalPadding), max(horizontalPadding, containerSize.width - horizontalPadding)),
            y: min(max(preferredY, verticalPadding), max(verticalPadding, containerSize.height - verticalPadding))
        )
    }

    private func selectionPolishRequestPosition(in containerSize: CGSize, anchor: CGPoint) -> CGPoint {
        let horizontalPadding: CGFloat = 210
        let verticalPadding: CGFloat = 128
        let preferredX = anchor.x
        let preferredY = anchor.y + 132

        return CGPoint(
            x: min(max(preferredX, horizontalPadding), max(horizontalPadding, containerSize.width - horizontalPadding)),
            y: min(max(preferredY, verticalPadding), max(verticalPadding, containerSize.height - verticalPadding))
        )
    }

    private func draftPolishPanelAnchorPosition(in containerSize: CGSize, anchor: CGPoint?) -> CGPoint {
        let horizontalPadding: CGFloat = 180
        let verticalPadding: CGFloat = 28
        let preferredX = anchor?.x ?? (containerSize.width / 2)
        let preferredY = (anchor?.y ?? (containerSize.height / 2)) + 36

        return CGPoint(
            x: min(max(preferredX, horizontalPadding), max(horizontalPadding, containerSize.width - horizontalPadding)),
            y: min(max(preferredY, verticalPadding), max(verticalPadding, containerSize.height - verticalPadding))
        )
    }

    private func selectionPolishContext(in draft: String, selection: NSRange) -> (leading: String, trailing: String) {
        let nsDraft = draft as NSString
        let safeLocation = min(max(selection.location, 0), nsDraft.length)
        let safeLength = min(max(selection.length, 0), max(0, nsDraft.length - safeLocation))
        let safeSelection = NSRange(location: safeLocation, length: safeLength)

        let leadingStart = max(0, safeSelection.location - 220)
        let leadingRange = NSRange(location: leadingStart, length: safeSelection.location - leadingStart)
        let trailingStart = NSMaxRange(safeSelection)
        let trailingLength = min(220, max(0, nsDraft.length - trailingStart))
        let trailingRange = NSRange(location: trailingStart, length: trailingLength)

        return (
            leading: leadingRange.length > 0 ? nsDraft.substring(with: leadingRange) : "",
            trailing: trailingRange.length > 0 ? nsDraft.substring(with: trailingRange) : ""
        )
    }

    private func configurationActions(
        importAction: (() -> Void)? = nil,
        supplementalActions: [WritingDeskToolbarAction] = []
    ) -> [WritingDeskToolbarAction] {
        var actions = supplementalActions

        if let importAction {
            actions.append(
                WritingDeskToolbarAction(
                    symbolName: "square.and.arrow.down",
                    accessibilityLabel: "导入文本"
                ) {
                    importAction()
                }
            )
        }

        actions.append(
            WritingDeskToolbarAction(
                symbolName: areConfigurationCardsCollapsed ? "chevron.down" : "chevron.up",
                accessibilityLabel: areConfigurationCardsCollapsed ? "展开顶部卡片" : "收起顶部卡片"
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    pendingScrollAnchor = nil
                    areConfigurationCardsCollapsed.toggle()
                }
            }
        )

        return actions
    }

    private func handleReferenceImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else { return }

        do {
            let urls = try result.get()
            let documents = try ReferenceDocumentImporting.documents(from: urls)
            appState.importReferenceDocuments(documents, for: project.id)
            aiStatusMessage = "已导入 \(documents.count) 份参考文本，AI 写作会同时读取这些材料。"
        } catch {
            aiStatusMessage = "导入参考文本失败：\(error.localizedDescription)"
        }
    }

    private func handleOutlineImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else { return }

        do {
            guard let url = try result.get().first else { return }
            let outlineText = try ReferenceDocumentImporting.text(from: url)
            appState.updateOutlineText(outlineText, for: project.id)
            aiStatusMessage = "作品大纲已导入，可以继续补充章节目标和特殊要求。"
        } catch {
            aiStatusMessage = "导入作品大纲失败：\(error.localizedDescription)"
        }
    }

    private func handleRequirementsImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else { return }

        do {
            guard let url = try result.get().first else { return }
            let requirementsText = try ReferenceDocumentImporting.text(from: url)
            appState.updateSpecialRequirements(requirementsText, for: project.id)
            aiStatusMessage = "特殊要求已导入，你也可以继续手动补充字数设定。"
        } catch {
            aiStatusMessage = "导入特殊要求失败：\(error.localizedDescription)"
        }
    }

}
