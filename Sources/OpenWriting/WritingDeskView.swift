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
    @State private var isImportingRequirements = false
    @State private var isOutlineGeneratorPresented = false
    @State private var aiSuggestion = ""
    @State private var draftBufferText = ""
    @State private var aiStatusMessage = "准备就绪，可先补大纲、参考文本和特殊要求，再开始当前章节写作。"
    @State private var saveMessage = "自动保存已开启，可按章节收录"
    @State private var isGenerating = false
    @State private var isSavingChapter = false
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
                    profile: outlineGenerationProfileBinding(for: activeProject.id),
                    isGenerating: isGenerating,
                    onGenerate: {
                        generateOutline(for: appState.project(for: activeProject.id) ?? activeProject)
                    }
                )
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

            Text("这些约束会和全局记忆一起送进 AI，写作和润色都会参考。")
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
                        isEnabled: !isGenerating && !isSavingChapter && project.draftWordCount > 0
                    ) {
                        polishDraft(for: project)
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
                    isEnabled: !isGenerating && !isSavingChapter && appState.aiConfiguration != nil,
                    isPrimary: true
                ) {
                    startWriting(for: project)
                },
                .init(
                    symbolName: "arrow.clockwise",
                    accessibilityLabel: "重写当前候选稿",
                    isEnabled: !isGenerating && !isSavingChapter && appState.aiConfiguration != nil && !aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    rewriteSuggestion(for: project)
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
                        Text("这里会显示 AI 按当前大纲与要求生成的候选稿。满意就接受进草稿箱，不满意就直接重写。")
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

                    if appState.showWritingDeskCachePanel {
                        Button("暂存到缓存区") {
                            moveAISuggestionToCache()
                        }
                        .buttonStyle(.bordered)
                        .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

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

                    if appState.showWritingDeskCachePanel {
                        Button("暂存到缓存区") {
                            moveAISuggestionToCache()
                        }
                        .buttonStyle(.bordered)
                        .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

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
        if isGenerating || isSavingChapter {
            return "生成中"
        }

        return appState.aiConfiguration == nil ? "待配置" : "就绪"
    }

    private var aiStatusColor: Color {
        if isGenerating || isSavingChapter {
            return .orange
        }

        return appState.aiConfiguration == nil
            ? Color(red: 0.83, green: 0.45, blue: 0.20)
            : Color(red: 0.18, green: 0.68, blue: 0.40)
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
                    .foregroundStyle(profile.hasMinimumRequirements ? .secondary : Color.orange)

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

        guard profile.hasMinimumRequirements else {
            aiStatusMessage = "生成大纲前还差：\(profile.missingRequiredFieldLabels.joined(separator: "、"))。"
            isOutlineGeneratorPresented = true
            return
        }

        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不完整，请先到设置里填写 API Key、Base URL 和模型名称。"
            return
        }

        isGenerating = true
        aiStatusMessage = "AI 正在根据总体流程、世界观、主角底色、预期字数和结局偏好生成大纲…"
        timingSnapshot = .queued

        Task {
            let startedAt = Date()

            do {
                let outline = try await AIWritingService.generateStoryOutline(
                    configuration: configuration,
                    project: latestProject,
                    profile: profile
                )

                let total = Date().timeIntervalSince(startedAt)

                await MainActor.run {
                    appState.updateOutlineText(outline, for: project.id)
                    isGenerating = false
                    timingSnapshot = AIWriterTimingSnapshot(
                        queue: 0.1,
                        generate: max(total * 0.82, 0.1),
                        finish: max(total * 0.18, 0.1),
                        complete: max(total, 0.2)
                    )
                    aiStatusMessage = "大纲已生成并回填到大纲设定，可以继续微调后直接开始写作。"
                    revealWritingDeskWindow(for: project.id)
                }
            } catch {
                await MainActor.run {
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
            aiStatusMessage = "当前模型配置不完整，请先到设置里填写 API Key、Base URL 和模型名称。"
            return
        }

        let latestProject = appState.project(for: project.id) ?? project
        isGenerating = true
        aiStatusMessage = rejectedSuggestion == nil
            ? "AI 正在根据大纲、参考文本、特殊要求和字数要求创作候选稿…"
            : "AI 正在重写这一版候选稿，会保留当前约束，但换一种写法重新生成…"
        timingSnapshot = .queued

        Task {
            let startedAt = Date()

            do {
                let suggestion = try await AIWritingService.continueChapter(
                    configuration: configuration,
                    project: latestProject,
                    mode: latestProject.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .advanceChapter : .continueScene,
                    additionalInstruction: generationInstruction(rejecting: rejectedSuggestion),
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
                    aiStatusMessage = "候选稿已生成。满意可接受进草稿箱，不满意可继续重写。"
                    revealWritingDeskWindow(for: project.id)
                    focusAIEditor()
                    requestAutoScroll(to: .ai)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    timingSnapshot = .idle
                    aiStatusMessage = error.localizedDescription
                    revealWritingDeskWindow(for: project.id)
                }
            }
        }
    }

    private func rewriteSuggestion(for project: NovelProject) {
        let rejectedSuggestion = aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        startWriting(for: project, rejectedSuggestion: rejectedSuggestion.isEmpty ? nil : rejectedSuggestion)
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
                    aiStatusMessage = "润色结果已生成。建议先在右侧检查，满意后再接受进草稿箱。"
                    revealWritingDeskWindow(for: project.id)
                    focusAIEditor()
                    requestAutoScroll(to: .ai)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    timingSnapshot = .idle
                    aiStatusMessage = error.localizedDescription
                    revealWritingDeskWindow(for: project.id)
                }
            }
        }
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

    private func moveAISuggestionToCache() {
        let trimmed = aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        draftBufferText = trimmed
        aiStatusMessage = "AI 候选稿已暂存到缓存区，确认后可采纳进草稿箱。"
        isCacheCollapsed = false
        requestAutoScroll(to: .cache)
    }

    private func acceptCacheIntoDraft(for project: NovelProject) {
        let trimmed = draftBufferText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appState.appendDraftText(trimmed, for: project.id)
        draftBufferText = ""
        saveMessage = "缓存内容已采纳进草稿箱"
        aiStatusMessage = "缓存内容已采纳到草稿箱，可继续编辑并按章节保存。"
        focusDraftEditor()
        requestAutoScroll(to: .draft)
    }

    private func saveCurrentChapterDraft(for project: NovelProject) {
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
                aiStatusMessage = "已按当前标题更新 \(result.chapterDraft.chapterSummary)。未配置模型，暂未刷新全局记忆。"
                isSavingChapter = false
                return
            }

            refreshGlobalMemoryAfterChapterSave(
                for: project,
                saveResult: result,
                configuration: configuration,
                statusPrefix: "已按当前标题更新"
            )
            return
        }

        guard let configuration = appState.aiConfiguration else {
            let fallbackTitle = fallbackChapterTitle(for: latestProject)
            appState.updateCurrentChapterTitle(fallbackTitle, for: project.id)
            if let result = completeChapterDraftSave(for: project, statusPrefix: "模型未配置，已按当前标题保存") {
                aiStatusMessage = "模型未配置，已按当前标题保存 \(result.chapterDraft.chapterSummary)。暂未刷新全局记忆。"
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
                        refreshGlobalMemoryAfterChapterSave(
                            for: project,
                            saveResult: result,
                            configuration: configuration,
                            statusPrefix: "AI 已拟好标题并保存"
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
                        refreshGlobalMemoryAfterChapterSave(
                            for: project,
                            saveResult: result,
                            configuration: configuration,
                            statusPrefix: "AI 拟标题失败，已按当前标题保存",
                            detailMessage: error.localizedDescription
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

    private func generationInstruction(rejecting rejectedSuggestion: String?) -> String {
        let baseInstruction = "请同时遵守项目中的特殊要求和字数设定，直接创作可进入草稿箱的正文候选稿。"
        let trimmedRejectedSuggestion = rejectedSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedRejectedSuggestion.isEmpty else {
            return baseInstruction
        }

        return """
        \(baseInstruction)
        用户对上一版候选稿不满意，这次请明显更换起笔、节奏和措辞，不要重复下面这版的句子结构或段落组织：
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

    private func refreshGlobalMemoryAfterChapterSave(
        for project: NovelProject,
        saveResult: ChapterDraftSaveResult,
        configuration: AIConnectionConfiguration,
        statusPrefix: String,
        detailMessage: String? = nil
    ) {
        let chapterDraft = saveResult.chapterDraft
        aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。正在更新全局记忆…"

        Task {
            do {
                let latestProject = appState.project(for: project.id) ?? project
                let globalMemory = try await AIWritingService.refreshGlobalMemory(
                    configuration: configuration,
                    project: latestProject,
                    chapterDraft: chapterDraft
                )

                await MainActor.run {
                    appState.updateContinuityNotes(
                        globalMemory,
                        updatedAt: timestampLabel(),
                        for: project.id
                    )
                    isSavingChapter = false
                    if let detailMessage {
                        aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。\(detailMessage) 全局记忆已同步更新。"
                    } else {
                        aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。全局记忆已同步更新。"
                    }
                    revealWritingDeskWindow(for: project.id)
                }
            } catch {
                await MainActor.run {
                    isSavingChapter = false
                    if let detailMessage {
                        aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。\(detailMessage) 全局记忆更新失败：\(error.localizedDescription)"
                    } else {
                        aiStatusMessage = "\(statusPrefix) \(chapterDraft.chapterSummary)。全局记忆更新失败：\(error.localizedDescription)"
                    }
                    revealWritingDeskWindow(for: project.id)
                }
            }
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

    private func revealWritingDeskWindow(for projectID: NovelProject.ID) {
        appState.openWritingDesk(for: projectID)
        AppRuntime.shared.windowCoordinator.showMainWindow()
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
        isSavingChapter = false
        isCacheCollapsed = false
        autoScrollLocked = false
        timingSnapshot = .idle
        saveMessage = "自动保存已开启，可按章节收录"
        aiStatusMessage = "准备就绪，可先补大纲、参考文本和特殊要求，再开始当前章节写作。"
        focusDraftEditor()
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

    private func handleRequirementsImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else { return }

        do {
            guard let url = try result.get().first else { return }
            let requirementsText = try loadText(from: url)
            appState.updateSpecialRequirements(requirementsText, for: project.id)
            aiStatusMessage = "特殊要求已导入，你也可以继续手动补充字数设定。"
        } catch {
            aiStatusMessage = "导入特殊要求失败：\(error.localizedDescription)"
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

        draftEditorHeight = max(132, draftPrimaryCardHeight - 340)
        cacheEditorHeight = max(72, (cacheCardHeight ?? 0) - 124)
        aiEditorHeight = max(148, aiCardHeight - (showTimeline ? 272 : 214))
    }
}

private struct WritingDeskInlineField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct WritingDeskOutlineGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let projectTitle: String
    @Binding var profile: OutlineGenerationProfile
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    minimumChecklist

                    WritingDeskOutlinePromptGroupCard(
                        title: "小说框架",
                        description: "先把故事怎么开头、怎么推进、最后想走到哪里写清楚。"
                    ) {
                        WritingDeskOutlineField(
                            title: "总体流程",
                            placeholder: "起始、大致经过、预期结果",
                            isRequired: true,
                            minHeight: 138,
                            text: $profile.storyFlow
                        )

                        WritingDeskOutlineField(
                            title: "主要卖点",
                            placeholder: "金手指、设定亮点、爽点",
                            minHeight: 96,
                            text: $profile.sellingPoints
                        )

                        WritingDeskOutlineField(
                            title: "关键事件",
                            placeholder: "激励事件、低谷、高潮等",
                            minHeight: 108,
                            text: $profile.keyEvents
                        )

                        WritingDeskOutlineField(
                            title: "故事节奏",
                            placeholder: "慢热、快节奏、持续高压等",
                            isCompact: true,
                            text: $profile.storyPacing
                        )

                        WritingDeskOutlineField(
                            title: "重要伏笔",
                            placeholder: "需要提前埋下、后续必须回收的点",
                            minHeight: 96,
                            text: $profile.foreshadowingNotes
                        )
                    }

                    WritingDeskOutlinePromptGroupCard(
                        title: "主要世界观",
                        description: "把背景、势力、规则和境界体系这类基础约束说明白。"
                    ) {
                        WritingDeskOutlineField(
                            title: "世界观描述",
                            placeholder: "背景、势力、规则、境界体系",
                            isRequired: true,
                            minHeight: 168,
                            text: $profile.worldDescription
                        )
                    }

                    WritingDeskOutlinePromptGroupCard(
                        title: "核心人物设定",
                        description: "这里决定主角底色、人物动力、关键关系和主要对抗。"
                    ) {
                        WritingDeskOutlineField(
                            title: "主角性格标签",
                            placeholder: "主角的核心性格和人物底色",
                            isRequired: true,
                            isCompact: true,
                            text: $profile.protagonistTraits
                        )

                        WritingDeskOutlineField(
                            title: "角色动机与欲望",
                            placeholder: "主角和重要人物各自想要什么、害怕什么",
                            minHeight: 96,
                            text: $profile.motivations
                        )

                        WritingDeskOutlineField(
                            title: "人物关系图谱",
                            placeholder: "盟友、师徒、家族、情感线、敌对链条",
                            minHeight: 96,
                            text: $profile.relationshipMap
                        )

                        WritingDeskOutlineField(
                            title: "反派的描绘",
                            placeholder: "反派目标、手段、威压感、与主角的矛盾",
                            minHeight: 96,
                            text: $profile.antagonistPortrait
                        )
                    }

                    WritingDeskOutlinePromptGroupCard(
                        title: "输出控制参数",
                        description: "决定这本书要写多长，以及最后收束到什么类型的结局。"
                    ) {
                        WritingDeskOutlineField(
                            title: "预期字数",
                            placeholder: "例如：50万 / 100万 / 200万",
                            isRequired: true,
                            isCompact: true,
                            text: $profile.expectedLength
                        )

                        WritingDeskOutlineField(
                            title: "结局偏好",
                            placeholder: "例如：好结局 / 坏结局 / 开放式",
                            isRequired: true,
                            isCompact: true,
                            text: $profile.endingPreference
                        )
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 860, minHeight: 820)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("生成大纲")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                Text(projectTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("最简可用版至少准备 5 项：故事怎么开头推进到哪里、世界规则、主角底色、想写多长、想要什么结局。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Text("必填 \(profile.completedRequiredFieldCount)/5")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 10) {
                    Button("关闭") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button(isGenerating ? "正在生成…" : "生成大纲") {
                        dismiss()
                        onGenerate()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || !profile.hasMinimumRequirements)
                }
            }
        }
    }

    private var minimumChecklist: some View {
        HStack(spacing: 10) {
            Text(profile.minimumRequirementSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(profile.hasMinimumRequirements ? .primary : Color.orange)

            Spacer()

            Text("扩展项 \(profile.filledOptionalFieldCount)/7")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.62))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WritingDeskOutlinePromptGroupCard<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WritingDeskOutlineField: View {
    let title: String
    let placeholder: String
    var isRequired = false
    var isCompact = false
    var minHeight: CGFloat = 96
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if isRequired {
                    Text("必填")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                }
            }

            if isCompact {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                WritingDeskTextSurface(
                    text: $text,
                    placeholder: placeholder,
                    minHeight: minHeight
                )
            }
        }
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
