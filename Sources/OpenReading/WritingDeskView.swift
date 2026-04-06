import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct WritingDeskView: View {
    @Bindable var appState: AppState
    let openSettings: () -> Void

    @FocusState private var isEditorFocused: Bool
    @State private var isImportingReferences = false
    @State private var isImportingOutline = false
    @State private var additionalInstruction = ""
    @State private var selectedLength: AIWritingLength = .medium
    @State private var selectedMode: AIWritingMode = .continueScene
    @State private var aiSuggestion = ""
    @State private var aiStatusMessage = "准备就绪，可先导入参考文本或作品大纲，再让 AI 接续当前章节。"
    @State private var isGenerating = false

    private let contentTopPadding: CGFloat = 18
    private let contentHorizontalPadding: CGFloat = 32
    private let contentBottomPadding: CGFloat = 32
    private let headerPanelHeight: CGFloat = 560

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
                VStack(alignment: .leading, spacing: 22) {
                    if let activeProject {
                        writingDeskHeader(for: activeProject)
                        writingDeskWorkspace(for: activeProject)
                        referencesLibraryPanel(for: activeProject)
                    } else {
                        emptyState
                    }
                }
                .padding(.top, contentTopPadding)
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.bottom, contentBottomPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(WritingDeskBounceLockView())
        }
        .task(id: activeProject?.id) {
            focusEditor()
            aiSuggestion = ""
            additionalInstruction = ""
            selectedMode = .continueScene
            selectedLength = .medium
            aiStatusMessage = "准备就绪，可先导入参考文本或作品大纲，再让 AI 接续当前章节。"
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
    private func writingDeskHeader(for project: NovelProject) -> some View {
        WritingDeskSplitSection(alignment: .bottom) {
            writingDeskOverviewCard(for: project)
        } secondary: {
            writingDeskControlCard(for: project)
        }
    }

    private func writingDeskOverviewCard(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "写作台",
            subtitle: "把当前项目、当前章节和写作上下文钉在顶部，再在正文区持续推进当前章节。",
            fixedHeight: headerPanelHeight
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(project.title)
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(project.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    PillTag(text: project.genre)
                    PillTag(text: project.currentChapterLabel)
                    PillTag(text: "已创作 \(project.writtenChapters) 章")
                }

                WritingDeskFeatureCard(
                    eyebrow: "当前续写锚点",
                    title: project.currentChapterSummary,
                    subtitle: project.chapterFocus,
                    trailing: project.updatedAt
                )

                Text("正文 \(project.draftWordCount) 字 · 参考文本 \(project.referenceStatusLabel) · 大纲 \(project.outlineStatusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Button("进入项目空间") {
                            appState.openProjectSpace(for: project.id)
                        }
                        .buttonStyle(.bordered)

                        Button("聚焦正文") {
                            focusEditor()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("进入项目空间") {
                            appState.openProjectSpace(for: project.id)
                        }
                        .buttonStyle(.bordered)

                        Button("聚焦正文") {
                            focusEditor()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func writingDeskControlCard(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "连续性控制台",
            subtitle: "把大纲、设定和参考文本都放在同一条工作线上，AI 才能稳定接续长篇。",
            fixedHeight: headerPanelHeight
        ) {
            VStack(alignment: .leading, spacing: 14) {
                WritingDeskMetricGrid(
                    items: [
                        .init(label: "当前章节", value: project.currentChapterSummary, detail: project.updatedAt),
                        .init(label: "作品大纲", value: project.outlineStatusLabel, detail: "导入后可继续手动补写"),
                        .init(label: "连续性笔记", value: project.continuityStatusLabel, detail: "建议记录角色语气与时间线"),
                        .init(label: "参考文本", value: project.referenceStatusLabel, detail: "样文、设定、旧稿都可导入")
                    ]
                )

                WritingDeskChecklistCard(
                    title: "进入 AI 前建议先完成",
                    items: [
                        "确认本章目标和当前切入点",
                        project.hasOutline ? "作品大纲已就绪，可直接继续补细节" : "先导入或补写作品大纲",
                        project.referenceDocuments.isEmpty ? "导入 1 到 3 份参考文本帮助统一风格" : "参考文本已导入，可继续补充样文",
                        appState.aiConfiguration == nil ? "到设置里补完 API Key、Base URL 和模型名称" : "模型配置已就绪，可直接发起续写"
                    ]
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button("导入参考文本") {
                            isImportingReferences = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("导入作品大纲") {
                            isImportingOutline = true
                        }
                        .buttonStyle(.bordered)

                        Button("模型设置", action: openSettings)
                            .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("导入参考文本") {
                            isImportingReferences = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("导入作品大纲") {
                            isImportingOutline = true
                        }
                        .buttonStyle(.bordered)

                        Button("模型设置", action: openSettings)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func writingDeskWorkspace(for project: NovelProject) -> some View {
        WritingDeskSplitSection {
            writingEditorPanel(for: project)
        } secondary: {
            VStack(alignment: .leading, spacing: 22) {
                aiContinuationPanel(for: project)
                continuityPanel(for: project)
            }
        }
    }

    private func writingEditorPanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "正文创作",
            subtitle: "正文持续保存在当前项目；先写本章目标，再把段落推进和 AI 建议落进同一处正文。"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                WritingDeskFeatureCard(
                    eyebrow: "当前创作章节",
                    title: project.currentChapterSummary,
                    subtitle: project.draftPreview,
                    trailing: "最后更新 \(project.updatedAt)"
                )

                WritingDeskSectionEditor(
                    title: "本章目标",
                    text: chapterFocusBinding(for: project.id),
                    placeholder: "例如：让主角在本章发现新的线索，并推动冲突进入下一段。"
                )
                .frame(minHeight: 120)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("正文")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(project.draftWordCount) 字 · \(project.draftParagraphCount) 段")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextEditor(text: draftBinding(for: project.id))
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .padding(18)
                        .frame(minHeight: 640, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("从当前章节的第一句开始写，或先用右侧 AI 协作生成一个可接续的段落。")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 24)
                                    .allowsHitTesting(false)
                            }
                        }
                        .focused($isEditorFocused)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button("回到项目空间") {
                            appState.openProjectSpace(for: project.id)
                        }
                        .buttonStyle(.bordered)

                        Button("查看章节树") {
                            appState.openOutline()
                        }
                        .buttonStyle(.bordered)

                        Button("继续专注写作") {
                            focusEditor()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("回到项目空间") {
                            appState.openProjectSpace(for: project.id)
                        }
                        .buttonStyle(.bordered)

                        Button("查看章节树") {
                            appState.openOutline()
                        }
                        .buttonStyle(.bordered)

                        Button("继续专注写作") {
                            focusEditor()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func aiContinuationPanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "AI 协作续写",
            subtitle: "围绕当前章节工作，不跳章节、不改设定；建议先补全本章目标和连续性笔记。"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("写作方式", selection: $selectedMode) {
                    ForEach(AIWritingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("续写长度", selection: $selectedLength) {
                    ForEach(AIWritingLength.allCases) { length in
                        Text(length.title).tag(length)
                    }
                }
                .pickerStyle(.segmented)

                WritingDeskSectionEditor(
                    title: "额外指令",
                    text: $additionalInstruction,
                    placeholder: "例如：先把冲突顶起来，不要转场；保持港口潮湿冷白的质感。"
                )
                .frame(minHeight: 126)

                Text("本次将按“项目摘要 → 当前章节 → 本章目标 → 大纲 → 连续性笔记 → 参考文本 → 正文尾段”的顺序组织上下文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button(isGenerating ? "AI 正在续写..." : "开始续写") {
                            generateContinuation(for: project)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(isGenerating || appState.aiConfiguration == nil)

                        Button("打开模型设置", action: openSettings)
                            .buttonStyle(.bordered)

                        if !aiSuggestion.isEmpty {
                            Button("清空建议") {
                                aiSuggestion = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button(isGenerating ? "AI 正在续写..." : "开始续写") {
                            generateContinuation(for: project)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(isGenerating || appState.aiConfiguration == nil)

                        Button("打开模型设置", action: openSettings)
                            .buttonStyle(.bordered)

                        if !aiSuggestion.isEmpty {
                            Button("清空建议") {
                                aiSuggestion = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Text(aiStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                if !aiSuggestion.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI 续写建议")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        TextEditor(text: $aiSuggestion)
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .lineSpacing(4)
                            .scrollContentBackground(.hidden)
                            .padding(14)
                        .frame(minHeight: 180, maxHeight: 300)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        )

                        Button("插入正文末尾") {
                            appState.appendDraftText(aiSuggestion, for: project.id)
                            aiStatusMessage = "AI 续写内容已插入正文末尾。"
                            aiSuggestion = ""
                            focusEditor()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(aiSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func continuityPanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "大纲与连续性",
            subtitle: "这里是长篇创作的硬约束区。角色语气、时间线、伏笔和不能违背的规则，都应写在这里。"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                WritingDeskFeatureCard(
                    eyebrow: "当前约束状态",
                    title: project.hasContinuityNotes ? "连续性已建立" : "连续性待补充",
                    subtitle: project.hasContinuityNotes
                        ? "AI 会优先读取这里的约束，避免角色说话方式和世界观规则突然跑偏。"
                        : "建议先写下角色语气、当前时间线、已揭示伏笔和不能违背的规则。",
                    trailing: project.referenceStatusLabel
                )

                WritingDeskSectionEditor(
                    title: "作品大纲",
                    text: outlineBinding(for: project.id),
                    placeholder: "把卷章结构、章节安排、关键转折和回收节点写在这里，或直接导入现成大纲。"
                )
                .frame(minHeight: 180)

                WritingDeskSectionEditor(
                    title: "连续性笔记",
                    text: continuityBinding(for: project.id),
                    placeholder: "记录角色口吻、关系变化、时间线、已出现线索、不能违背的设定与后续待回收伏笔。"
                )
                .frame(minHeight: 180)
            }
        }
    }

    private func referencesLibraryPanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "参考文本库",
            subtitle: "导入样文、旧稿、设定说明、人物小传或语气参考，AI 续写时会优先抽取相关片段。"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        WritingDeskInfoBadge(label: "参考文本", value: project.referenceStatusLabel)
                        WritingDeskInfoBadge(label: "总字数", value: "\(project.referenceDocuments.reduce(0) { $0 + $1.wordCount })")
                        WritingDeskInfoBadge(label: "大纲", value: project.outlineStatusLabel)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        WritingDeskInfoBadge(label: "参考文本", value: project.referenceStatusLabel)
                        WritingDeskInfoBadge(label: "总字数", value: "\(project.referenceDocuments.reduce(0) { $0 + $1.wordCount })")
                        WritingDeskInfoBadge(label: "大纲", value: project.outlineStatusLabel)
                    }
                }

                Button("继续导入参考文本") {
                    isImportingReferences = true
                }
                .buttonStyle(.borderedProminent)

                if project.referenceDocuments.isEmpty {
                    WritingDeskChecklistCard(
                        title: "建议优先导入的参考材料",
                        items: [
                            "当前作品的旧稿或前几章正文",
                            "人物卡、世界观设定或组织规则",
                            "你希望 AI 靠近的语气样文"
                        ]
                    )
                } else {
                    ForEach(project.referenceDocuments) { document in
                        ReferenceDocumentRow(document: document) {
                            appState.removeReferenceDocument(document.id, for: project.id)
                            aiStatusMessage = "已移除《\(document.title)》。"
                        }
                    }
                }
            }
        }
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

    private func draftBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.draftText ?? "" },
            set: { appState.updateDraftText($0, for: projectID) }
        )
    }

    private func chapterFocusBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.chapterFocus ?? "" },
            set: { appState.updateChapterFocus($0, for: projectID) }
        )
    }

    private func outlineBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.outlineText ?? "" },
            set: { appState.updateOutlineText($0, for: projectID) }
        )
    }

    private func continuityBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.continuityNotes ?? "" },
            set: { appState.updateContinuityNotes($0, for: projectID) }
        )
    }

    private func focusEditor() {
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }

    private func handleReferenceImport(_ result: Result<[URL], Error>) {
        guard let project = activeProject else { return }

        do {
            let urls = try result.get()
            let documents = try urls.map(loadReferenceDocument)
            appState.importReferenceDocuments(documents, for: project.id)
            aiStatusMessage = "已导入 \(documents.count) 份参考文本，AI 续写会纳入这些内容。"
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
            aiStatusMessage = "作品大纲已导入，AI 续写会优先参考当前大纲。"
        } catch {
            aiStatusMessage = "导入作品大纲失败：\(error.localizedDescription)"
        }
    }

    private func generateContinuation(for project: NovelProject) {
        guard let configuration = appState.aiConfiguration else {
            aiStatusMessage = "当前模型配置不完整，请先到设置里填写 Base URL、API Key 和模型名称。"
            return
        }

        isGenerating = true
        aiStatusMessage = "AI 正在读取大纲、连续性笔记、参考文本和正文尾段，准备续写当前章节..."

        Task {
            do {
                let suggestion = try await AIWritingService.continueChapter(
                    configuration: configuration,
                    project: project,
                    mode: selectedMode,
                    additionalInstruction: additionalInstruction,
                    length: selectedLength
                )

                await MainActor.run {
                    aiSuggestion = suggestion
                    isGenerating = false
                    aiStatusMessage = "AI 已生成续写建议。确认后可以插入正文末尾。"
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    aiStatusMessage = error.localizedDescription
                }
            }
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
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}

private struct WritingDeskSplitSection<Primary: View, Secondary: View>: View {
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

private struct WritingDeskSignalStrip: View {
    let project: NovelProject

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                WritingDeskInfoBadge(label: "当前章节", value: project.currentChapterSummary)
                WritingDeskInfoBadge(label: "正文长度", value: "\(project.draftWordCount) 字")
                WritingDeskInfoBadge(label: "参考文本", value: project.referenceStatusLabel)
            }

            VStack(alignment: .leading, spacing: 10) {
                WritingDeskInfoBadge(label: "当前章节", value: project.currentChapterSummary)
                WritingDeskInfoBadge(label: "正文长度", value: "\(project.draftWordCount) 字")
                WritingDeskInfoBadge(label: "参考文本", value: project.referenceStatusLabel)
            }
        }
    }
}

private struct WritingDeskInfoBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct WritingDeskFeatureCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct WritingDeskChecklistCard: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct WritingDeskSectionEditor: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            TextEditor(text: $text)
                .font(.system(size: 14, weight: .regular))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
}

private struct WritingDeskMetricGrid: View {
    let items: [WritingDeskMetricItem]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(items) { item in
                WritingDeskMetricCard(label: item.label, value: item.value, detail: item.detail)
            }
        }
    }
}

private struct WritingDeskMetricItem: Identifiable {
    let label: String
    let value: String
    let detail: String

    var id: String { label }
}

private struct WritingDeskMetricCard: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ReferenceDocumentRow: View {
    let document: ReferenceDocument
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(document.importedAt) · \(document.wordCount) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("移除", action: removeAction)
                    .buttonStyle(.bordered)
            }

            Text(document.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .lineSpacing(3)
        }
        .padding(16)
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
