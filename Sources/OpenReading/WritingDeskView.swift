import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct WritingDeskView: View {
    @Bindable var appState: AppState
    let openSettings: () -> Void

    @FocusState private var focusedArea: FocusArea?
    @State private var isImportingReferences = false
    @State private var isImportingOutline = false
    @State private var aiSuggestion = ""
    @State private var draftBufferText = ""
    @State private var aiStatusMessage = "准备就绪，可先补大纲、参考文本和特殊要求，再开始当前章节写作。"
    @State private var saveMessage = "自动保存已开启"
    @State private var isGenerating = false
    @State private var isCacheCollapsed = false
    @State private var autoScrollLocked = false
    @State private var areConfigurationCardsCollapsed = false
    @State private var pendingScrollAnchor: WritingDeskScrollAnchor?
    @State private var timingSnapshot = AIWriterTimingSnapshot.idle

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
                    .background(WritingDeskBounceLockView())
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
                ViewThatFits(in: .horizontal) {
                    horizontalLayout

                    VStack(alignment: .leading, spacing: workspaceSpacing) {
                        writingDeskDraftColumn(for: project)
                        writingDeskAIColumn(for: project)
                    }
                }
            }
        }
    }

    private func writingDeskOutlineCard(for project: NovelProject, isCollapsed: Bool = false) -> some View {
        WritingDeskSectionCard(
            title: "大纲设定",
            badgeText: isCollapsed ? (project.hasOutline ? "已导入" : "未导入") : nil,
            actions: configurationActions(importAction: {
                isImportingOutline = true
            }),
            isCollapsed: isCollapsed
        ) {
            HStack(alignment: .center, spacing: 10) {
                PillTag(text: project.title)
                PillTag(text: project.currentChapterSummary)
            }

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
            actions: configurationActions(),
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

            Text("这些约束会和连续性笔记一起送进 AI，写作和润色都会参考。")
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
                    .init(
                        symbolName: "wand.and.stars",
                        accessibilityLabel: "润色当前草稿",
                        isEnabled: !isGenerating && project.draftWordCount > 0
                    ) {
                        polishDraft(for: project)
                    },
                    .init(
                        symbolName: "square.and.arrow.down",
                        accessibilityLabel: "保存草稿"
                    ) {
                        saveDraft(for: project)
                    }
                ],
                fillContentHeight: layout != nil
            ) {
                HStack(alignment: .center, spacing: 10) {
                    PillTag(text: project.title)
                    PillTag(text: project.currentChapterSummary)
                    PillTag(text: "已创作 \(project.writtenChapters) 章")
                }

                Text("采纳后的内容会进入草稿箱，可继续键盘编辑；润色会把结果先送到右侧 AI 作家。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                TextEditor(text: draftBinding(for: project.id))
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(18)
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
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
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
                    .focused($focusedArea, equals: .draft)
                    .id(WritingDeskScrollAnchor.draft.rawValue)

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
                    badgeText: isCacheCollapsed ? "已收起" : "临时暂存",
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
                            text: $draftBufferText,
                            placeholder: "AI 结果送到缓存区后，会先停在这里，确认无误再采纳进草稿箱。",
                            minHeight: layout?.cacheEditorHeight ?? 152
                        )
                        .id(WritingDeskScrollAnchor.cache.rawValue)

                        HStack(spacing: 10) {
                            Button("采纳到草稿箱") {
                                acceptCacheIntoDraft(for: project)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(draftBufferText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("清空缓存") {
                                draftBufferText = ""
                                aiStatusMessage = "缓存区已清空。"
                            }
                            .buttonStyle(.bordered)
                            .disabled(draftBufferText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()

                            Text(draftBufferText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无缓存内容" : "可继续编辑后再采纳")
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
            actions: [
                .init(
                    symbolName: "play.fill",
                    accessibilityLabel: "开始写作",
                    isEnabled: !isGenerating && appState.aiConfiguration != nil,
                    isPrimary: true
                ) {
                    startWriting(for: project)
                },
                .init(
                    symbolName: autoScrollLocked ? "lock.fill" : "lock.open.fill",
                    accessibilityLabel: autoScrollLocked ? "解锁自动滑动" : "锁定自动滑动"
                ) {
                    autoScrollLocked.toggle()
                    aiStatusMessage = autoScrollLocked ? "已锁定自动滑动，生成后不会自动跳转模块。" : "已恢复自动滑动，生成后会自动定位到结果区域。"
                }
            ],
            fillContentHeight: layout != nil
        ) {
            if appState.showWritingDeskTimeline {
                WritingDeskTimelineRow(snapshot: timingSnapshot)
            }

            Text(aiStatusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            TextEditor(text: $aiSuggestion)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(18)
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
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("这里会显示 AI 生成或润色后的内容。你可以先改，再送到缓存区或直接插入草稿箱。")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focusedArea, equals: .ai)
                .id(WritingDeskScrollAnchor.ai.rawValue)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button(appState.showWritingDeskCachePanel ? "送入缓存区" : "插入草稿箱") {
                        routeAISuggestion(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("清空结果") {
                        aiSuggestion = ""
                        aiStatusMessage = "AI 结果区已清空。"
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Button("设置", action: openSettings)
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button(appState.showWritingDeskCachePanel ? "送入缓存区" : "插入草稿箱") {
                        routeAISuggestion(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("清空结果") {
                        aiSuggestion = ""
                        aiStatusMessage = "AI 结果区已清空。"
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("设置", action: openSettings)
                        .buttonStyle(.bordered)
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
        if isGenerating {
            return "生成中"
        }

        return appState.aiConfiguration == nil ? "待配置" : "就绪"
    }

    private var aiStatusColor: Color {
        if isGenerating {
            return .orange
        }

        return appState.aiConfiguration == nil
            ? Color(red: 0.83, green: 0.45, blue: 0.20)
            : Color(red: 0.18, green: 0.68, blue: 0.40)
    }

    private func outlineBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.outlineText ?? "" },
            set: { appState.updateOutlineText($0, for: projectID) }
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

    private func draftBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.draftText ?? "" },
            set: { appState.updateDraftText($0, for: projectID) }
        )
    }

    private func startWriting(for project: NovelProject) {
        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不完整，请先到设置里填写 API Key、Base URL 和模型名称。"
            return
        }

        let latestProject = appState.project(for: project.id) ?? project
        isGenerating = true
        aiStatusMessage = "AI 正在根据大纲、参考文本、特殊要求和当前章节状态生成正文…"
        timingSnapshot = .queued

        Task {
            let startedAt = Date()

            do {
                let suggestion = try await AIWritingService.continueChapter(
                    configuration: configuration,
                    project: latestProject,
                    mode: latestProject.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .advanceChapter : .continueScene,
                    additionalInstruction: "请同时遵守项目中的特殊要求和字数设定。",
                    length: preferredLength(for: latestProject.wordTargetText)
                )

                let total = Date().timeIntervalSince(startedAt)

                await MainActor.run {
                    aiSuggestion = suggestion
                    isGenerating = false
                    timingSnapshot = AIWriterTimingSnapshot(
                        queue: 0.1,
                        generate: max(total * 0.82, 0.1),
                        finish: max(total * 0.18, 0.1),
                        complete: max(total, 0.2)
                    )
                    aiStatusMessage = "AI 已生成当前章节草稿，你可以继续编辑后再送入缓存区或直接插入草稿箱。"
                    focusAIEditor()
                    requestAutoScroll(to: .ai)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    timingSnapshot = .idle
                    aiStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func polishDraft(for project: NovelProject) {
        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不完整，请先到设置里填写 API Key、Base URL 和模型名称。"
            return
        }

        let latestProject = appState.project(for: project.id) ?? project
        let passage = polishTargetText(for: latestProject)
        guard !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiStatusMessage = "草稿箱里还没有可润色的内容。"
            return
        }

        isGenerating = true
        aiStatusMessage = "AI 正在润色当前草稿尾段，尽量保持当前章节气质和叙述连续性…"
        timingSnapshot = .queued

        Task {
            let startedAt = Date()

            do {
                let polished = try await AIWritingService.polishPassage(
                    configuration: configuration,
                    project: latestProject,
                    passage: passage
                )

                let total = Date().timeIntervalSince(startedAt)

                await MainActor.run {
                    aiSuggestion = polished
                    isGenerating = false
                    timingSnapshot = AIWriterTimingSnapshot(
                        queue: 0.1,
                        generate: max(total * 0.76, 0.1),
                        finish: max(total * 0.24, 0.1),
                        complete: max(total, 0.2)
                    )
                    aiStatusMessage = "润色结果已生成。建议先在右侧检查，再决定送入缓存区或直接插入草稿箱。"
                    focusAIEditor()
                    requestAutoScroll(to: .ai)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    timingSnapshot = .idle
                    aiStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func routeAISuggestion(for project: NovelProject) {
        let trimmed = aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if appState.showWritingDeskCachePanel {
            draftBufferText = trimmed
            aiStatusMessage = "AI 结果已送入缓存区，确认后可采纳到草稿箱。"
            isCacheCollapsed = false
            requestAutoScroll(to: .cache)
        } else {
            appState.appendDraftText(trimmed, for: project.id)
            aiSuggestion = ""
            saveMessage = "AI 内容已直接插入草稿箱"
            aiStatusMessage = "AI 结果已直接插入草稿箱。"
            focusDraftEditor()
            requestAutoScroll(to: .draft)
        }
    }

    private func acceptCacheIntoDraft(for project: NovelProject) {
        let trimmed = draftBufferText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appState.appendDraftText(trimmed, for: project.id)
        draftBufferText = ""
        saveMessage = "缓存内容已采纳进草稿箱"
        aiStatusMessage = "缓存内容已采纳到草稿箱，可继续直接编辑正文。"
        focusDraftEditor()
        requestAutoScroll(to: .draft)
    }

    private func saveDraft(for project: NovelProject) {
        appState.touchProject(project.id)
        saveMessage = "已手动保存 · \(timestampLabel())"
        aiStatusMessage = "当前项目已保存，可以继续写作或切回项目空间。"
    }

    private func referenceImportSummary(for project: NovelProject) -> String {
        guard let latestDocument = project.referenceDocuments.first else {
            return "还没有导入参考文件，也可以直接在上面手动粘贴上下文。"
        }

        return "已导入 \(project.referenceDocuments.count) 份 · 最近：\(latestDocument.title) · 共 \(project.referenceDocuments.reduce(0) { $0 + $1.wordCount }) 字。"
    }

    private func preferredLength(for wordTargetText: String) -> AIWritingLength {
        let digits = wordTargetText.compactMap(\.wholeNumberValue)
        let number = digits.reduce(0) { ($0 * 10) + $1 }

        switch number {
        case 0 ..< 900:
            return .short
        case 1_800...:
            return .long
        default:
            return .medium
        }
    }

    private func polishTargetText(for project: NovelProject) -> String {
        let trimmed = project.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > 1_800 else { return trimmed }
        return String(trimmed.suffix(1_800))
    }

    private func requestAutoScroll(to anchor: WritingDeskScrollAnchor) {
        guard !autoScrollLocked, !areConfigurationCardsCollapsed else { return }
        pendingScrollAnchor = anchor
    }

    private func focusDraftEditor() {
        DispatchQueue.main.async {
            focusedArea = .draft
        }
    }

    private func focusAIEditor() {
        DispatchQueue.main.async {
            focusedArea = .ai
        }
    }

    private func resetSessionState() {
        aiSuggestion = ""
        draftBufferText = ""
        isGenerating = false
        isCacheCollapsed = false
        autoScrollLocked = false
        timingSnapshot = .idle
        saveMessage = "自动保存已开启"
        aiStatusMessage = "准备就绪，可先补大纲、参考文本和特殊要求，再开始当前章节写作。"
        focusDraftEditor()
    }

    private func configurationActions(importAction: (() -> Void)? = nil) -> [WritingDeskToolbarAction] {
        var actions: [WritingDeskToolbarAction] = []

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
            let documents = try urls.map(loadReferenceDocument)
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
            let outlineText = try loadText(from: url)
            appState.updateOutlineText(outlineText, for: project.id)
            aiStatusMessage = "作品大纲已导入，可以继续补充章节目标和特殊要求。"
        } catch {
            aiStatusMessage = "导入作品大纲失败：\(error.localizedDescription)"
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
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    private func timestampLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

private enum WritingDeskScrollAnchor: String {
    case draft
    case ai
    case cache
}

private struct AIWriterTimingSnapshot {
    var queue: Double
    var generate: Double
    var finish: Double
    var complete: Double

    static let idle = AIWriterTimingSnapshot(queue: 0, generate: 0, finish: 0, complete: 0)
    static let queued = AIWriterTimingSnapshot(queue: 0.1, generate: 0, finish: 0, complete: 0.1)
}

private struct WritingDeskToolbarAction: Identifiable {
    let id = UUID()
    let symbolName: String
    let accessibilityLabel: String
    var isEnabled = true
    var isPrimary = false
    let action: () -> Void
}

private struct WritingDeskSectionCard<Content: View>: View {
    let title: String
    let badgeText: String?
    let statusLabel: String?
    let statusColor: Color?
    let actions: [WritingDeskToolbarAction]
    let headerTapAction: (() -> Void)?
    let isCollapsed: Bool
    let fillContentHeight: Bool
    @ViewBuilder let content: Content

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
                                .fill(Color.white.opacity(0.52))
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
                            .foregroundStyle(action.isPrimary ? Color.blue : .primary)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.72))
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
                    .overlay(Color.white.opacity(0.16))

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
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 12)
    }
}

private struct WritingDeskCollapsedLayout {
    static let configurationCardHeight: CGFloat = 74

    let creationRowHeight: CGFloat
    let draftPrimaryCardHeight: CGFloat
    let cacheCardHeight: CGFloat?
    let draftEditorHeight: CGFloat
    let cacheEditorHeight: CGFloat
    let aiCardHeight: CGFloat
    let aiEditorHeight: CGFloat

    init(
        containerSize: CGSize,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        spacing: CGFloat,
        showCachePanel: Bool,
        showTimeline: Bool
    ) {
        let availableHeight = max(280, containerSize.height - topPadding - bottomPadding - Self.configurationCardHeight - spacing)
        creationRowHeight = availableHeight
        aiCardHeight = availableHeight

        if showCachePanel {
            let proposedCacheHeight = min(max(128, availableHeight * 0.22), 196)
            cacheCardHeight = proposedCacheHeight
            draftPrimaryCardHeight = max(200, availableHeight - spacing - proposedCacheHeight)
        } else {
            cacheCardHeight = nil
            draftPrimaryCardHeight = availableHeight
        }

        draftEditorHeight = max(132, draftPrimaryCardHeight - 230)
        cacheEditorHeight = max(72, (cacheCardHeight ?? 0) - 124)
        aiEditorHeight = max(148, aiCardHeight - (showTimeline ? 272 : 214))
    }
}

private struct WritingDeskTextSurface: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14, weight: .regular))
            .scrollContentBackground(.hidden)
            .padding(14)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct WritingDeskCacheSurface: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 15, weight: .regular, design: .serif))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .padding(14)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct WritingDeskTimelineRow: View {
    let snapshot: AIWriterTimingSnapshot

    var body: some View {
        HStack(spacing: 10) {
            WritingDeskTimelineNode(title: "排队", value: snapshot.queue)
            WritingDeskTimelineNode(title: "生成", value: snapshot.generate)
            WritingDeskTimelineNode(title: "收尾", value: snapshot.finish)
            WritingDeskTimelineNode(title: "完成", value: snapshot.complete)
        }
    }
}

private struct WritingDeskTimelineNode: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(format: "%.1fs", value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

#Preview {
    WritingDeskView(appState: AppState())
}

private struct WritingDeskBounceLockView: NSViewRepresentable {
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
