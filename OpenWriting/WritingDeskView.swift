import Observation
import AppKit
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
        .task(id: activeProject?.id) {
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
    }

    @ViewBuilder
    private func writingDeskViewport(in size: CGSize) -> some View {
        if let activeProject {
            if areConfigurationCardsCollapsed {
                collapsedWritingDeskWorkspace(for: activeProject, containerSize: size)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: workspaceSpacing) {
                            writingDeskConfigurationRow(for: activeProject)
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
                        symbolName: "sparkles",
                        accessibilityLabel: "润色整篇草稿",
                        isEnabled: !isGenerating && !isSavingChapter && appState.aiConfiguration != nil && !project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                }

                Text("根据大纲、参考文本、特殊要求和字数设定生成的候选稿，确认后会进入这里。首次保存会同步让 AI 拟一个章节标题，之后你也可以手动改名再更新；已保存章节请到章节树里查看。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                writingDeskChapterControls(for: project)

                ZStack(alignment: .topLeading) {
                    WritingDeskDraftEditor(
                        text: draftBinding(for: project.id),
                        selection: $draftSelection,
                        selectionActionPoint: $draftSelectionActionPoint,
                        focusToken: draftEditorFocusToken
                    )
                    .frame(
                        minHeight: layout?.draftEditorHeight ?? 720,
                        maxHeight: layout?.draftEditorHeight,
                        alignment: .topLeading
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(draftEditorBorderColor, lineWidth: activeDraftPolishMode == nil ? 1 : 1.5)
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
                                isEnabled: !isGenerating && !isSavingChapter && appState.aiConfiguration != nil,
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
                                isEnabled: appState.aiConfiguration != nil,
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button("接受放入草稿箱") {
                        acceptAISuggestionIntoDraft(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("重写这一版") {
                        rewriteSuggestion(for: project)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating || isSavingChapter || appState.aiConfiguration == nil)

                    Button("清空结果") {
                        aiSuggestion = ""
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
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("重写这一版") {
                        rewriteSuggestion(for: project)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating || isSavingChapter || appState.aiConfiguration == nil)

                    Button("清空结果") {
                        aiSuggestion = ""
                        aiStatusMessage = "AI 结果区已清空。"
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(height: layout?.aiCardHeight, alignment: .top)
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

        return appState.aiConfiguration == nil
            ? palette.warningAccent
            : palette.readyAccent
    }

    private var draftEditorBorderColor: Color {
        activeDraftPolishMode == nil
            ? palette.editorBorder
            : palette.activeAccent.opacity(palette.isDark ? 0.72 : 0.58)
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

        let hasConfiguration = appState.aiConfiguration != nil
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

    private func draftBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.draftText ?? "" },
            set: { appState.updateDraftText($0, for: projectID) }
        )
    }

    private func generateOutline(for project: NovelProject) {
        let latestProject = appState.project(for: project.id) ?? project
        let profile = latestProject.outlineGenerationProfile
        let requestContext = outlineGenerationContext(for: latestProject, profile: profile)

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
                let outline = try await AIWritingService.generateStoryOutline(
                    configuration: configuration,
                    project: latestProject,
                    profile: profile
                )

                let total = Date().timeIntervalSince(startedAt)

                await MainActor.run {
                    guard outlineGenerationToken == requestToken else {
                        return
                    }

                    let currentContext = appState.project(for: project.id).map {
                        outlineGenerationContext(for: $0, profile: $0.outlineGenerationProfile)
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
                    aiStatusMessage = error.localizedDescription
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

        if let activeToken = writingGenerationToken {
            let task = writingGenerationTask
            clearWritingGenerationRequest(token: activeToken)
            task?.cancel()
        }

        let latestProject = appState.project(for: project.id) ?? project
        let requestContext = draftGenerationContext(for: latestProject, rejectedSuggestion: rejectedSuggestion)
        writingStopTask?.cancel()
        writingStopTask = nil
        isGenerating = true
        writingRunState = .requesting
        thinkingMode = rejectedSuggestion == nil ? .writing : .rewriting
        thinkingStepIndex = 0
        aiSuggestion = ""
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
                let suggestion = try await AIWritingService.continueChapter(
                    configuration: configuration,
                    project: latestProject,
                    mode: latestProject.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .advanceChapter : .continueScene,
                    additionalInstruction: generationInstruction(rejecting: rejectedSuggestion),
                    length: preferredLength(for: latestProject)
                )

                let total = Date().timeIntervalSince(startedAt)

                await MainActor.run {
                    guard writingGenerationToken == requestToken else {
                        return
                    }

                    let currentContext = appState.project(for: project.id).map {
                        draftGenerationContext(for: $0, rejectedSuggestion: rejectedSuggestion)
                    }
                    guard currentContext == requestContext else {
                        clearWritingGenerationRequest(token: requestToken)
                        isGenerating = false
                        timingSnapshot = .idle
                        aiStatusMessage = "生成期间写作上下文已经变化，旧候选稿已丢弃，请按当前内容重新生成。"
                        revealWritingDeskWindow(for: project.id)
                        return
                    }

                    aiSuggestion = suggestion
                    clearWritingGenerationRequest(token: requestToken)
                    isGenerating = false
                    writingRunState = .idle
                    stopWritingProgressMonitor()
                    timingSnapshot = AIWriterTimingSnapshot.completed(total: total)
                    aiStatusMessage = "候选稿已生成。满意可接受进草稿箱，不满意可继续重写。"
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
                    aiStatusMessage = error.localizedDescription
                    revealWritingDeskWindow(for: project.id)
                }
            }
        }
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

        appState.appendDraftText(trimmed, for: project.id)
        aiSuggestion = ""
        saveMessage = "已接受 AI 候选稿到草稿箱"
        aiStatusMessage = "候选稿已放入草稿箱，可继续编辑或保存当前章。"
        focusDraftEditor()
        requestAutoScroll(to: .draft)
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
        isGenerating = true
        activeDraftPolishMode = .full
        pendingDraftPolishReview = nil
        aiStatusMessage = instruction.isEmpty ? "AI 正在润色整篇草稿…" : "AI 正在按你的要求润色整篇草稿…"
        isDraftPolishSheetPresented = false

        Task {
            do {
                let polishedDraft = try await AIWritingService.polishFullDraft(
                    configuration: configuration,
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
                    appState.updateDraftText(normalizedDraft, for: project.id)
                    pendingDraftPolishReview = DraftPolishReview(
                        projectID: project.id,
                        mode: .full,
                        originalDraft: latestProject.draftText,
                        polishedDraft: normalizedDraft,
                        polishedText: normalizedDraft,
                        restoredSelection: originalSelection
                    )
                    pendingDraftPolishReviewAnchorPoint = nil
                    saveMessage = "润色结果待确认"
                    aiStatusMessage = "整篇草稿已完成润色并写回正文。可选择保留或舍弃。"
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
                    aiStatusMessage = "草稿润色失败：\(error.localizedDescription)"
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
                let polishedSelection = try await AIWritingService.polishSelection(
                    configuration: configuration,
                    selectedText: currentSelection.text,
                    instruction: instruction,
                    fullDraft: latestProject.draftText,
                    precedingContext: selectionContext.leading,
                    followingContext: selectionContext.trailing
                )

                await MainActor.run {
                    let normalizedSelection = normalizedSelectionPolishResult(polishedSelection)
                    if let updatedDraft = applyPolishedSelection(
                        normalizedSelection,
                        selection: currentSelection,
                        for: project.id
                    ) {
                        pendingDraftPolishReview = DraftPolishReview(
                            projectID: project.id,
                            mode: .selection,
                            originalDraft: latestProject.draftText,
                            polishedDraft: updatedDraft,
                            polishedText: normalizedSelection,
                            restoredSelection: currentSelection
                        )
                        pendingDraftPolishReviewAnchorPoint = reviewAnchorPoint
                    }
                    saveMessage = "润色结果待确认"
                    aiStatusMessage = "当前选区已润色并写回正文。可选择保留或舍弃。"
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
                    aiStatusMessage = "选区润色失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func saveCurrentChapterDraft(for project: NovelProject, advanceToNextChapter: Bool = false) {
        let latestProject = appState.project(for: project.id) ?? project
        let trimmedDraft = latestProject.draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDraft.isEmpty else {
            aiStatusMessage = "草稿箱里还没有可保存的正文。"
            return
        }

        isSavingChapter = true

        if latestProject.hasSavedCurrentChapter {
            guard let result = completeChapterDraftSave(for: project, statusPrefix: "已按当前标题更新") else {
                isSavingChapter = false
                return
            }

            guard let configuration = appState.aiConfiguration else {
                if advanceToNextChapter {
                    appState.beginNextChapter(after: result.chapterDraft, for: project.id)
                    aiStatusMessage = "已按当前标题更新 \(result.chapterDraft.chapterSummary)，并进入下一章。未配置模型，暂未刷新全局记忆和章节树。"
                } else {
                    aiStatusMessage = "已按当前标题更新 \(result.chapterDraft.chapterSummary)。未配置模型，暂未刷新全局记忆和章节树。"
                }
                isSavingChapter = false
                return
            }

            refreshProjectContextAfterChapterSave(
                for: project,
                saveResult: result,
                configuration: configuration,
                statusPrefix: "已按当前标题更新",
                advanceToNextChapter: advanceToNextChapter
            )
            return
        }

        guard let configuration = appState.aiConfiguration else {
            let fallbackTitle = fallbackChapterTitle(for: latestProject)
            appState.updateCurrentChapterTitle(fallbackTitle, for: project.id)
            if let result = completeChapterDraftSave(for: project, statusPrefix: "模型未配置，已按当前标题保存") {
                if advanceToNextChapter {
                    appState.beginNextChapter(after: result.chapterDraft, for: project.id)
                    aiStatusMessage = "模型未配置，已按当前标题保存 \(result.chapterDraft.chapterSummary)，并进入下一章。暂未刷新全局记忆和章节树。"
                } else {
                    aiStatusMessage = "模型未配置，已按当前标题保存 \(result.chapterDraft.chapterSummary)。暂未刷新全局记忆和章节树。"
                }
            }
            isSavingChapter = false
            return
        }

        aiStatusMessage = "AI 正在根据草稿箱内容拟一个章节标题，并同步保存当前章…"

        Task {
            do {
                let title = try await AIWritingService.suggestChapterTitle(
                    configuration: configuration,
                    project: latestProject,
                    draft: trimmedDraft
                )

                await MainActor.run {
                    appState.updateCurrentChapterTitle(title, for: project.id)
                    if let result = completeChapterDraftSave(for: project, statusPrefix: "AI 已拟好标题并保存") {
                        refreshProjectContextAfterChapterSave(
                            for: project,
                            saveResult: result,
                            configuration: configuration,
                            statusPrefix: "AI 已拟好标题并保存",
                            advanceToNextChapter: advanceToNextChapter
                        )
                    } else {
                        isSavingChapter = false
                        revealWritingDeskWindow(for: project.id)
                    }
                }
            } catch {
                await MainActor.run {
                    let fallbackTitle = fallbackChapterTitle(for: latestProject)
                    appState.updateCurrentChapterTitle(fallbackTitle, for: project.id)
                    if let result = completeChapterDraftSave(
                        for: project,
                        statusPrefix: "AI 拟标题失败，已按当前标题保存",
                        detailMessage: error.localizedDescription
                    ) {
                        refreshProjectContextAfterChapterSave(
                            for: project,
                            saveResult: result,
                            configuration: configuration,
                            statusPrefix: "AI 拟标题失败，已按当前标题保存",
                            detailMessage: error.localizedDescription,
                            advanceToNextChapter: advanceToNextChapter
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

    private func preferredLength(for project: NovelProject) -> AIWritingLength {
        let number = inferredTargetWordCount(from: project.wordTargetText)

        if number == 0 {
            switch project.storyLength {
            case .short:
                return .short
            case .medium:
                return .medium
            case .long:
                return .long
            }
        }

        switch number {
        case 0 ..< 850:
            return .short
        case 1_700...:
            return .long
        default:
            return .medium
        }
    }

    private func inferredTargetWordCount(from text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let rangePattern = #"(\d+(?:\.\d+)?)\s*(万|千)?\s*[-~—–至到]\s*(\d+(?:\.\d+)?)\s*(万|千)?\s*字?"#
        let singlePattern = #"(\d+(?:\.\d+)?)\s*(万|千)?\s*字"#
        let chapterKeywords = ["本章", "本次", "当前章节", "单章", "章节", "章均", "每章"]
        let projectKeywords = ["全书", "全文", "总字数", "总计", "预计", "完本", "全稿"]
        let adjustmentKeywords = ["上浮", "下浮", "浮动", "%", "百分"]

        struct Candidate {
            let value: Int
            let score: Int
        }

        func normalizedValue(_ numberText: String, unit: String?) -> Int? {
            guard let base = Double(numberText) else { return nil }
            let multiplier: Double

            switch unit {
            case "万":
                multiplier = 10_000
            case "千":
                multiplier = 1_000
            default:
                multiplier = 1
            }

            return Int(base * multiplier)
        }

        func context(for range: NSRange) -> String {
            let lowerBound = max(0, range.location - 12)
            let upperBound = min(nsText.length, range.location + range.length + 12)
            return nsText.substring(with: NSRange(location: lowerBound, length: upperBound - lowerBound))
        }

        func score(for context: String, value: Int, prefersRange: Bool) -> Int {
            var score = prefersRange ? 8 : 4

            if chapterKeywords.contains(where: context.contains) {
                score += 8
            }

            if projectKeywords.contains(where: context.contains) {
                score -= 8
            }

            if adjustmentKeywords.contains(where: context.contains) {
                score -= 5
            }

            if value > 10_000 {
                score -= 10
            } else if value >= 800, value <= 4_500 {
                score += 5
            }

            return score
        }

        var candidates: [Candidate] = []

        if let rangeExpression = try? NSRegularExpression(pattern: rangePattern) {
            for match in rangeExpression.matches(in: trimmed, range: fullRange) {
                guard match.numberOfRanges >= 5 else { continue }
                let lowerText = nsText.substring(with: match.range(at: 1))
                let lowerUnit = match.range(at: 2).location == NSNotFound ? nil : nsText.substring(with: match.range(at: 2))
                let upperText = nsText.substring(with: match.range(at: 3))
                let upperUnit = match.range(at: 4).location == NSNotFound ? lowerUnit : nsText.substring(with: match.range(at: 4))
                guard
                    let lower = normalizedValue(lowerText, unit: lowerUnit),
                    let upper = normalizedValue(upperText, unit: upperUnit)
                else { continue }

                let midpoint = (lower + upper) / 2
                let candidateContext = context(for: match.range)
                candidates.append(.init(value: midpoint, score: score(for: candidateContext, value: midpoint, prefersRange: true)))
            }
        }

        if let singleExpression = try? NSRegularExpression(pattern: singlePattern) {
            for match in singleExpression.matches(in: trimmed, range: fullRange) {
                guard match.numberOfRanges >= 3 else { continue }
                let numberText = nsText.substring(with: match.range(at: 1))
                let unit = match.range(at: 2).location == NSNotFound ? nil : nsText.substring(with: match.range(at: 2))
                guard let value = normalizedValue(numberText, unit: unit) else { continue }
                let candidateContext = context(for: match.range)
                candidates.append(.init(value: value, score: score(for: candidateContext, value: value, prefersRange: false)))
            }
        }

        if let bestCandidate = candidates.max(by: {
            if $0.score == $1.score {
                return abs($0.value - 2_000) > abs($1.value - 2_000)
            }
            return $0.score < $1.score
        }) {
            return bestCandidate.value
        }

        let fallbackNumbers = trimmed
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { (500 ... 5_000).contains($0) }

        if let fallback = fallbackNumbers.min(by: { abs($0 - 2_000) < abs($1 - 2_000) }) {
            return fallback
        }

        return 0
    }

    private func generationInstruction(rejecting rejectedSuggestion: String?) -> String {
        let baseInstruction = "请同时遵守项目中的特殊要求和字数设定，直接创作可进入草稿箱的正文候选稿。"
        let trimmedRejectedSuggestion = rejectedSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedRejectedSuggestion.isEmpty else {
            return baseInstruction
        }

        return """
        \(baseInstruction)
        用户对上一版候选稿不满意，这次重写方向是：\(rewriteDirection.title)。\(rewriteDirection.instruction)
        不要重复下面这版的句子结构或段落组织：
        \(excerpt(from: trimmedRejectedSuggestion, limit: 1_200))
        """
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

    private func refreshProjectContextAfterChapterSave(
        for project: NovelProject,
        saveResult: ChapterDraftSaveResult,
        configuration: AIConnectionConfiguration,
        statusPrefix: String,
        detailMessage: String? = nil,
        advanceToNextChapter: Bool = false
    ) {
        let chapterDraft = saveResult.chapterDraft
        aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。正在更新全局记忆和章节树…"
        let baselineProject = appState.project(for: project.id) ?? project
        let baseline = ChapterTreeRefreshBaseline(project: baselineProject)
        let refreshToken = UUID()
        projectContextRefreshTokens[project.id] = refreshToken

        Task {
            let latestProject = appState.project(for: project.id) ?? baselineProject

            async let globalMemoryTask: Result<String, Error> = {
                do {
                    return .success(try await AIWritingService.refreshGlobalMemory(
                        configuration: configuration,
                        project: latestProject,
                        chapterDraft: chapterDraft
                    ))
                } catch {
                    return .failure(error)
                }
            }()

            async let chapterTreeTask: Result<ChapterTreeRefresh, Error> = {
                do {
                    return .success(try await AIWritingService.refreshChapterTree(
                        configuration: configuration,
                        project: latestProject,
                        chapterDraft: chapterDraft
                    ))
                } catch {
                    return .failure(error)
                }
            }()

            let globalMemoryResult = await globalMemoryTask
            let chapterTreeResult = await chapterTreeTask

            await MainActor.run {
                guard projectContextRefreshTokens[project.id] == refreshToken else {
                    return
                }

                let updatedAt = TimestampLabel.project()
                let currentProject = appState.project(for: project.id)
                let normalizedContinuity = currentProject?.continuityNotes
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let shouldApplyGlobalMemory = normalizedContinuity == baseline.continuityNotes
                let preservedLocalGlobalMemory = !shouldApplyGlobalMemory
                    && (currentProject?.hasGlobalMemory ?? false)

                var chapterTreeApplyOutcome = ChapterTreeRefreshApplyOutcome()

                if case let .success(globalMemory) = globalMemoryResult, shouldApplyGlobalMemory {
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

                if advanceToNextChapter {
                    appState.beginNextChapter(after: chapterDraft, for: project.id)
                }

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
                    advancedToNextChapter: advanceToNextChapter
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
            if chapterTreeApplyOutcome.preservedLocalChanges {
                refreshNotes.append("章节树已刷新，并保留了你刚修改过的 \(chapterTreeApplyOutcome.protectedSections) 个区块")
            } else {
                refreshNotes.append("章节树已同步更新")
            }
        case let .failure(error):
            refreshNotes.append("章节树更新失败：\(error.localizedDescription)")
        }

        if advancedToNextChapter {
            refreshNotes.append("已进入下一章")
        }

        return "\(statusPrefix) \(chapterSummary)。\(detailPrefix)\(refreshNotes.joined(separator: "；"))。"
    }

    private func requestAutoScroll(to anchor: WritingDeskScrollAnchor) {
        guard !autoScrollLocked, !areConfigurationCardsCollapsed else { return }
        pendingScrollAnchor = anchor
    }

    private func revealWritingDeskWindow(for projectID: NovelProject.ID) {
        appState.openWritingDesk(for: projectID)
        AppRuntime.shared.windowCoordinator.showMainWindow()
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
        isSelectionPolishPopoverPresented = false
        saveMessage = "自动保存已开启，可按章节收录"
        aiStatusMessage = "准备就绪，可先补大纲、参考文本和特殊要求，再开始当前章节写作。"
        focusDraftEditor()
    }

    private func outlineGenerationContext(
        for project: NovelProject,
        profile: OutlineGenerationProfile
    ) -> OutlineGenerationRequestContext {
        OutlineGenerationRequestContext(
            projectID: project.id,
            storyLength: project.storyLength,
            outlineText: project.outlineText,
            profile: profile
        )
    }

    private func draftGenerationContext(
        for project: NovelProject,
        rejectedSuggestion: String?
    ) -> DraftGenerationRequestContext {
        DraftGenerationRequestContext(
            projectID: project.id,
            storyLength: project.storyLength,
            currentChapterTitle: project.currentChapterTitle,
            currentChapterNumber: project.currentChapterNumber,
            chapterFocus: project.chapterFocus,
            draftText: project.draftText,
            outlineText: project.outlineText,
            referenceContextText: project.referenceContextText,
            specialRequirements: project.specialRequirements,
            wordTargetText: project.wordTargetText,
            continuityNotes: project.continuityNotes,
            referenceDocuments: project.referenceDocuments,
            chapterDrafts: project.chapterDrafts,
            mode: project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .advanceChapter : .continueScene,
            length: preferredLength(for: project),
            rewriteDirection: rewriteDirection,
            rejectedSuggestion: rejectedSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
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

        pendingDraftPolishReview = nil
        pendingDraftPolishReviewAnchorPoint = nil
        saveMessage = review.mode == .full ? "已保留整篇润色结果" : "已保留选区润色结果"
        aiStatusMessage = "润色结果已保留，可继续编辑或保存当前章。"
        focusDraftEditor()
    }

    private func replaceDraftPolishReview(_ review: DraftPolishReview) {
        guard pendingDraftPolishReview?.id == review.id else { return }

        appState.updateDraftText(review.polishedDraft, for: review.projectID)
        pendingDraftPolishReview = nil
        pendingDraftPolishReviewAnchorPoint = nil
        saveMessage = review.mode == .full ? "已替换为整篇润色结果" : "已替换为选区润色结果"
        aiStatusMessage = "已将草稿内容替换为这次润色结果。"
        focusDraftEditor()
    }

    private func discardDraftPolishReview(_ review: DraftPolishReview) {
        guard pendingDraftPolishReview?.id == review.id else { return }

        appState.updateDraftText(review.originalDraft, for: review.projectID)
        pendingDraftPolishReview = nil
        pendingDraftPolishReviewAnchorPoint = nil
        draftSelection = review.restoredSelection
        saveMessage = "已舍弃本次润色"
        aiStatusMessage = "已恢复到润色前的草稿。"
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

private enum WritingDeskScrollAnchor: String {
    case draft
    case ai
    case cache
}

private struct OutlineGenerationRequestContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
    let outlineText: String
    let profile: OutlineGenerationProfile
}

private struct DraftGenerationRequestContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
    let currentChapterTitle: String
    let currentChapterNumber: Int
    let chapterFocus: String
    let draftText: String
    let outlineText: String
    let referenceContextText: String
    let specialRequirements: String
    let wordTargetText: String
    let continuityNotes: String
    let referenceDocuments: [ReferenceDocument]
    let chapterDrafts: [ChapterDraft]
    let mode: AIWritingMode
    let length: AIWritingLength
    let rewriteDirection: AIRewriteDirection
    let rejectedSuggestion: String
}

private enum WritingRunState {
    case idle
    case requesting
    case stopping
}

private enum AIRewriteDirection: String, CaseIterable, Identifiable {
    case freshTake
    case fasterPace
    case richerTexture
    case sharperTension
    case moreNaturalDialogue

    var id: Self { self }

    var title: String {
        switch self {
        case .freshTake:
            return "换一种写法"
        case .fasterPace:
            return "推进更快"
        case .richerTexture:
            return "细节更足"
        case .sharperTension:
            return "张力更强"
        case .moreNaturalDialogue:
            return "对白更自然"
        }
    }

    var instruction: String {
        switch self {
        case .freshTake:
            return "明显更换起笔、节奏和措辞，避免重复上一版的句子结构或段落组织。"
        case .fasterPace:
            return "减少铺垫和解释，优先推进动作、选择、冲突结果和信息增量。"
        case .richerTexture:
            return "保留推进方向，同时补强动作细节、场景感、心理层次和段落质感。"
        case .sharperTension:
            return "提高冲突压迫感和人物选择压力，让场景更紧、更有悬念。"
        case .moreNaturalDialogue:
            return "优化对白的口语节奏、潜台词和人物差异，减少说明式台词。"
        }
    }
}

private enum DraftPolishMode {
    case full
    case selection

    var progressTitle: String {
        switch self {
        case .full:
            return "正在润色整篇草稿"
        case .selection:
            return "正在润色选区"
        }
    }

    var reviewTitle: String {
        switch self {
        case .full:
            return "整篇润色结果已写入正文"
        case .selection:
            return "选区润色结果已写入正文"
        }
    }
}

private struct DraftPolishReview: Identifiable {
    let id = UUID()
    let projectID: NovelProject.ID
    let mode: DraftPolishMode
    let originalDraft: String
    let polishedDraft: String
    let polishedText: String
    let restoredSelection: WritingDeskDraftSelection

    var changedCharacterCount: Int {
        abs(polishedDraft.count - originalDraft.count)
    }
}

private enum AIWriterThinkingMode {
    case writing
    case rewriting

    var title: String {
        switch self {
        case .writing:
            return "AI 作家正在组织这一章"
        case .rewriting:
            return "AI 作家正在重写这一版"
        }
    }

    var subtitle: String {
        switch self {
        case .writing:
            return "会先梳理当前目标、人物状态和场景推进，再落到正文。"
        case .rewriting:
            return "会保留当前约束，但重新组织起笔、节奏和措辞。"
        }
    }

    var messages: [String] {
        switch self {
        case .writing:
            return [
                "回看当前章节目标、上一章缓存与正在进行的冲突。",
                "对齐大纲、参考文本、特殊要求和字数约束。",
                "先定这一段的切入点、情绪坡度和信息释放顺序。",
                "把人物动作、对白张力与场景质感压进可直接续写的正文。"
            ]
        case .rewriting:
            return [
                "回收上一版里不满意的句式和段落组织，避免重复。",
                "保留章节目标与既有约束，但重排起笔和推进节奏。",
                "换一组更贴合当前情绪的动作细节、对白与叙述重心。",
                "整理成另一种可直接进入草稿箱的候选稿。"
            ]
        }
    }
}

struct AIWriterTimingSnapshot {
    var queue: Double
    var generate: Double
    var finish: Double
    var complete: Double
    var activeStage: AIWriterTimelineStage?
    var isStopping: Bool

    static let idle = AIWriterTimingSnapshot(
        queue: 0,
        generate: 0,
        finish: 0,
        complete: 0,
        activeStage: nil,
        isStopping: false
    )

    static let queued = AIWriterTimingSnapshot(
        queue: 0.1,
        generate: 0,
        finish: 0,
        complete: 0.1,
        activeStage: .queue,
        isStopping: false
    )

    static func live(elapsed: TimeInterval) -> AIWriterTimingSnapshot {
        let queueDuration = min(elapsed, 0.6)
        let generateDuration = elapsed > 0.6 ? min(elapsed - 0.6, 2.4) : 0
        let finishDuration = elapsed > 3.0 ? elapsed - 3.0 : 0
        let activeStage: AIWriterTimelineStage =
            elapsed < 0.6 ? .queue :
            elapsed < 3.0 ? .generate :
            .finish

        return AIWriterTimingSnapshot(
            queue: queueDuration,
            generate: generateDuration,
            finish: finishDuration,
            complete: elapsed,
            activeStage: activeStage,
            isStopping: false
        )
    }

    static func completed(total: TimeInterval) -> AIWriterTimingSnapshot {
        AIWriterTimingSnapshot(
            queue: max(min(total * 0.12, 0.8), 0.1),
            generate: max(total * 0.70, 0.1),
            finish: max(total * 0.18, 0.1),
            complete: max(total, 0.2),
            activeStage: .complete,
            isStopping: false
        )
    }

    func stopping() -> AIWriterTimingSnapshot {
        AIWriterTimingSnapshot(
            queue: queue,
            generate: generate,
            finish: finish,
            complete: complete,
            activeStage: activeStage,
            isStopping: true
        )
    }
}

private struct WritingDeskToolbarAction: Identifiable {
    let id = UUID()
    let symbolName: String
    let accessibilityLabel: String
    var isEnabled = true
    var isPrimary = false
    var tintColor: Color? = nil
    let action: () -> Void
}

private struct DraftPolishProgressBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let mode: DraftPolishMode

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(mode.progressTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(palette.activeAccent.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.22 : 0.10), radius: 12, y: 5)
        .allowsHitTesting(false)
    }
}

private struct DraftSelectionPolishToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    let isEnabled: Bool
    let action: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))

                Text("润色")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(palette.panelBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(palette.isDark ? 0.30 : 0.16), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(isEnabled ? "润色当前选区" : "先配置模型后可润色选区")
    }
}

private struct DraftSelectionPolishRequestPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedText: String
    @Binding var instruction: String
    let isEnabled: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.activeAccent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(palette.toolbarButtonFill))

                VStack(alignment: .leading, spacing: 2) {
                    Text("润色选区")
                        .font(.headline.weight(.semibold))

                    Text("可以补充风格、语气或改写方向")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("取消")
            }

            Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.insetPanel.opacity(palette.isDark ? 0.62 : 0.54))
                )

            TextEditor(text: $instruction)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.insetPanel.opacity(palette.isDark ? 0.72 : 0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.editorBorder, lineWidth: 1)
                )

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button {
                    onSubmit()
                } label: {
                    Label("开始润色", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.activeAccent)
                .disabled(!isEnabled)
                .help(isEnabled ? "按当前要求润色选区" : "先配置模型后可润色选区")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.panelBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.36 : 0.18), radius: 22, y: 10)
    }
}

private struct DraftPolishResultPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let review: DraftPolishReview
    let onKeep: () -> Void
    let onReplace: () -> Void
    let onDiscard: () -> Void
    let onCopy: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.activeAccent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(palette.toolbarButtonFill))

                VStack(alignment: .leading, spacing: 2) {
                    Text(review.mode.reviewTitle)
                        .font(.headline.weight(.semibold))

                    Text(review.changedCharacterCount == 0 ? "请确认如何处理这次润色。" : "字数变化约 \(review.changedCharacterCount) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ScrollView {
                Text(review.polishedText)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.insetPanel.opacity(palette.isDark ? 0.70 : 0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.editorBorder, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button(action: onKeep) {
                    Label("保留", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.activeAccent)
                .accessibilityHint("保留当前已写入草稿的润色结果")

                Button(action: onReplace) {
                    Label("替换", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("重新将正文替换为这次润色结果")

                Button(action: onDiscard) {
                    Label("舍弃", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("恢复润色前的草稿内容")

                Spacer()

                Button(action: onCopy) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("复制润色结果")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.panelBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.38 : 0.20), radius: 24, y: 12)
    }
}

private struct DraftPolishSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let projectTitle: String
    @Binding var instruction: String
    let isProcessing: Bool
    let onSubmit: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("润色整篇草稿")
                        .font(.title2.weight(.semibold))

                    Text("当前项目：\(projectTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("输入你希望这次润色遵守的要求。留空会按“整体提纯表达、修顺节奏、保留剧情与设定”的默认方向处理。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    TextEditor(text: $instruction)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .frame(minHeight: 240)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 1)
                        )
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("关闭整篇润色面板")

                Spacer()

                Button("开始润色") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                .accessibilityHint("根据当前要求润色整篇草稿")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: 760,
            minHeight: 420,
            idealHeight: 520,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var borderColor: Color {
        palette.editorBorder
    }
}

private struct DraftSelectionPolishPopover: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let selectedText: String
    @Binding var instruction: String
    let isProcessing: Bool
    let onSubmit: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("润色当前选区")
                .font(.headline)

            Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前没有选中文本。" : "可输入这次润色要遵守的要求，结果会直接替换当前选区。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("当前选中内容")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(selectedText.count) 字")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                ScrollView {
                    Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前没有可润色的选区。" : selectedText)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(minHeight: 108)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
            }

            TextEditor(text: $instruction)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("关闭选区润色面板")

                Spacer()

                Button("开始润色") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("按当前要求替换选中的正文")
            }
        }
        .padding(18)
        .frame(minWidth: 320, idealWidth: 356, maxWidth: 420, alignment: .topLeading)
    }

    private var borderColor: Color {
        palette.editorBorder
    }
}

private struct WritingDeskSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let badgeText: String?
    let statusLabel: String?
    let statusColor: Color?
    let actions: [WritingDeskToolbarAction]
    let headerTapAction: (() -> Void)?
    let isCollapsed: Bool
    let fillContentHeight: Bool
    @ViewBuilder let content: Content

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    init(
        title: String,
        badgeText: String? = nil,
        statusLabel: String? = nil,
        statusColor: Color? = nil,
        actions: [WritingDeskToolbarAction] = [],
        headerTapAction: (() -> Void)? = nil,
        isCollapsed: Bool = false,
        fillContentHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.badgeText = badgeText
        self.statusLabel = statusLabel
        self.statusColor = statusColor
        self.actions = actions
        self.headerTapAction = headerTapAction
        self.isCollapsed = isCollapsed
        self.fillContentHeight = fillContentHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let headerTapAction {
                    Button(action: headerTapAction) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }

                if let badgeText {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(chipBackgroundColor)
                        )
                }

                if let statusLabel, let statusColor {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)

                        Text(statusLabel)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                ForEach(actions) { action in
                    Button(action: action.action) {
                        Image(systemName: action.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(action.tintColor ?? (action.isPrimary ? palette.activeAccent : .primary))
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(toolbarButtonBackgroundColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
                    .help(action.accessibilityLabel)
                    .opacity(action.isEnabled ? 1 : 0.45)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, isCollapsed ? 16 : 18)
            .padding(.bottom, isCollapsed ? 16 : 16)

            if !isCollapsed {
                Divider()
                    .overlay(dividerColor)

                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(maxHeight: fillContentHeight ? .infinity : nil, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: fillContentHeight ? .infinity : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 12)
    }

    private var chipBackgroundColor: Color {
        palette.secondaryChipFill
    }

    private var toolbarButtonBackgroundColor: Color {
        palette.toolbarButtonFill
    }

    private var dividerColor: Color {
        palette.divider
    }

    private var borderColor: Color {
        palette.panelBorder
    }
}
