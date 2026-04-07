import Observation
import SwiftUI

struct OutlineWorkspacePanel: View {
    @Bindable var appState: AppState

    @State private var isSummarizing = false
    @State private var summaryStatusMessage = "AI 总结会只围绕当前选中的书籍生成，不会混入其他项目。"
    @State private var selectedSavedChapterID: ChapterDraft.ID?

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    var body: some View {
        if let project = activeProject {
            VStack(alignment: .leading, spacing: 24) {
                overviewPanel(for: project)
                savedChaptersPanel(for: project)
                structureEditorRows(for: project)
                summaryPanel(for: project)
            }
            .task(id: project.id) {
                summaryStatusMessage = project.hasOutlineSummary
                    ? "已为《\(project.title)》保留章节树总结，可继续手动整理后写回连续性笔记。"
                    : "先补结构节点，再调用 AI 做一次章节树总览。"
                selectedSavedChapterID = project.sortedChapterDrafts.first?.id
            }
            .onChange(of: project.chapterDrafts) { _, chapterDrafts in
                let sortedDrafts = chapterDrafts.sorted(by: ChapterDraft.sortDescending)
                if let selectedSavedChapterID,
                   sortedDrafts.contains(where: { $0.id == selectedSavedChapterID }) {
                    return
                }

                self.selectedSavedChapterID = sortedDrafts.first?.id
            }
        } else {
            DashboardPanel(
                title: "章节树",
                subtitle: "当前还没有选中的项目，先去项目空间选择一本书。"
            ) {
                Button("前往项目空间") {
                    appState.openProjectSpace()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func overviewPanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "章节结构工作台",
            subtitle: "当前只处理《\(project.title)》这一本书。这里的结构拆解、角色弧线、伏笔回收和 AI 总结都会跟着当前选中的项目走。"
        ) {
            HStack(spacing: 12) {
                ProjectChapterPill(label: "当前创作", value: project.currentChapterSummary)
                WorkspaceMetricBadge(label: "结构节点", value: "\(project.structureNodeCount)")
                WorkspaceMetricBadge(label: "角色弧线", value: project.characterArcStatusLabel)
                WorkspaceMetricBadge(label: "伏笔回收", value: project.foreshadowStatusLabel)
                WorkspaceMetricBadge(label: "已存章节", value: "\(project.savedChapterCount) 章")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button("调用 AI 总结") {
                        summarizeOutline(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSummarizing)

                    Button("写回连续性笔记") {
                        appState.appendOutlineSummaryToContinuity(for: project.id)
                        summaryStatusMessage = "已把章节树总结写回《\(project.title)》的连续性笔记。"
                    }
                    .buttonStyle(.bordered)
                    .disabled(project.outlineSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("进入写作台") {
                        appState.openWritingDesk(for: project.id)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button("调用 AI 总结") {
                        summarizeOutline(for: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSummarizing)

                    Button("写回连续性笔记") {
                        appState.appendOutlineSummaryToContinuity(for: project.id)
                        summaryStatusMessage = "已把章节树总结写回《\(project.title)》的连续性笔记。"
                    }
                    .buttonStyle(.bordered)
                    .disabled(project.outlineSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("进入写作台") {
                        appState.openWritingDesk(for: project.id)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Label(summaryStatusMessage, systemImage: isSummarizing ? "sparkles" : "text.magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func savedChaptersPanel(for project: NovelProject) -> some View {
        let selectedChapter = selectedSavedChapter(for: project)

        return DashboardPanel(
            title: "章节存档",
            subtitle: "写作台里保存过的章节统一放在这里查看。你可以在这里浏览已收录章节，也可以把某一章重新载入写作台继续改。"
        ) {
            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "已保存", value: project.savedChapterCount == 0 ? "暂无" : "\(project.savedChapterCount) 章")
                WorkspaceMetricBadge(
                    label: "最近保存",
                    value: project.sortedChapterDrafts.first?.savedAt ?? "暂无"
                )
            }

            if project.sortedChapterDrafts.isEmpty {
                Text("当前还没有已保存章节。你在写作台点“AI 拟标题并保存”后，章节会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(project.sortedChapterDrafts) { chapterDraft in
                            Button {
                                selectedSavedChapterID = chapterDraft.id
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(chapterDraft.chapterSummary)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(chapterDraft.previewText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    HStack {
                                        Text("\(chapterDraft.wordCount) 字")
                                        Spacer()
                                        Text(chapterDraft.savedAt)
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(width: 240, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.white.opacity(chapterDraft.id == selectedSavedChapterID ? 0.82 : 0.58))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(
                                            chapterDraft.id == selectedSavedChapterID
                                                ? Color.blue.opacity(0.35)
                                                : Color.white.opacity(0.16),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let selectedChapter {
                    HStack(alignment: .center, spacing: 12) {
                        WorkspaceMetricBadge(label: "当前查看", value: selectedChapter.chapterSummary)
                        WorkspaceMetricBadge(label: "字数", value: "\(selectedChapter.wordCount)")
                        Spacer()

                        Button("载入写作台继续编辑") {
                            appState.loadChapterDraft(selectedChapter.id, for: project.id)
                            appState.openWritingDesk(for: project.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    SavedChapterPreviewSurface(
                        text: selectedChapter.content,
                        placeholder: "当前章节正文会显示在这里。"
                    )
                    .frame(minHeight: 220)
                }
            }
        }
    }

    private func structureEditorRows(for project: NovelProject) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    outlineEditorCard(
                        title: "章节骨架拆解",
                        subtitle: "按卷、章或节点写下全书结构。AI 总结会优先读取这里。",
                        badge: project.structureStatusLabel,
                        text: structureNotesBinding(for: project.id),
                        placeholder: "示例：\n第一卷：钟楼与港口\n1. 退潮夜失踪案启动\n2. 顾临追到港务局旧档案\n3. 守夜人证词和钟楼记录开始并线",
                        fixedHeight: 330
                    )

                    outlineEditorCard(
                        title: "场景推进",
                        subtitle: "只围绕当前章节拆分场景目标、转折点和收束动作。",
                        badge: project.sceneProgressStatusLabel,
                        text: sceneProgressBinding(for: project.id),
                        placeholder: "示例：\n1. 开场先让主角确认潮位异常\n2. 中段发现新证词，但证词仍不完整\n3. 结尾把线索指向钟楼守夜人",
                        fixedHeight: 330
                    )
                }

                VStack(alignment: .leading, spacing: 24) {
                    outlineEditorCard(
                        title: "章节骨架拆解",
                        subtitle: "按卷、章或节点写下全书结构。AI 总结会优先读取这里。",
                        badge: project.structureStatusLabel,
                        text: structureNotesBinding(for: project.id),
                        placeholder: "示例：\n第一卷：钟楼与港口\n1. 退潮夜失踪案启动\n2. 顾临追到港务局旧档案\n3. 守夜人证词和钟楼记录开始并线",
                        fixedHeight: 330
                    )

                    outlineEditorCard(
                        title: "场景推进",
                        subtitle: "只围绕当前章节拆分场景目标、转折点和收束动作。",
                        badge: project.sceneProgressStatusLabel,
                        text: sceneProgressBinding(for: project.id),
                        placeholder: "示例：\n1. 开场先让主角确认潮位异常\n2. 中段发现新证词，但证词仍不完整\n3. 结尾把线索指向钟楼守夜人",
                        fixedHeight: 330
                    )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    outlineEditorCard(
                        title: "角色弧线",
                        subtitle: "记录当前书里主要角色的情绪变化、目标偏移和冲突状态。",
                        badge: project.characterArcStatusLabel,
                        text: characterArcBinding(for: project.id),
                        placeholder: "示例：\n顾临：从旁观判断转向主动试探港务局\n守夜人：表面冷静，实际开始回避钟楼记录",
                        fixedHeight: 280
                    )

                    outlineEditorCard(
                        title: "伏笔回收",
                        subtitle: "把已埋伏笔、触发条件和预期回收章节放在一起追踪。",
                        badge: project.foreshadowStatusLabel,
                        text: foreshadowBinding(for: project.id),
                        placeholder: "示例：\n铜纽扣：第 18 章出现，第 21 章回收到失踪名单\n钟楼缺页：第 16 章提及，第 19 章解释来源",
                        fixedHeight: 280
                    )
                }

                VStack(alignment: .leading, spacing: 24) {
                    outlineEditorCard(
                        title: "角色弧线",
                        subtitle: "记录当前书里主要角色的情绪变化、目标偏移和冲突状态。",
                        badge: project.characterArcStatusLabel,
                        text: characterArcBinding(for: project.id),
                        placeholder: "示例：\n顾临：从旁观判断转向主动试探港务局\n守夜人：表面冷静，实际开始回避钟楼记录",
                        fixedHeight: 280
                    )

                    outlineEditorCard(
                        title: "伏笔回收",
                        subtitle: "把已埋伏笔、触发条件和预期回收章节放在一起追踪。",
                        badge: project.foreshadowStatusLabel,
                        text: foreshadowBinding(for: project.id),
                        placeholder: "示例：\n铜纽扣：第 18 章出现，第 21 章回收到失踪名单\n钟楼缺页：第 16 章提及，第 19 章解释来源",
                        fixedHeight: 280
                    )
                }
            }
        }
    }

    private func summaryPanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "AI 结构总结",
            subtitle: "只围绕当前选中的《\(project.title)》生成。你可以先让 AI 总结一次，再手动改成真正可执行的章节树说明。"
        ) {
            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "当前章节", value: project.currentChapterLabel)
                WorkspaceMetricBadge(label: "AI 总结", value: project.outlineSummaryStatusLabel)
                WorkspaceMetricBadge(label: "参考资料", value: project.referenceStatusLabel)
            }

            OutlineEditorSurface(
                text: outlineSummaryBinding(for: project.id),
                placeholder: "点击“调用 AI 总结”后，这里会生成当前书的结构判断、本章推进建议、角色弧线提醒和伏笔回收建议。",
                minHeight: 260
            )

            WorkspaceChecklist(
                title: "建议使用顺序",
                items: [
                    "先补章节骨架和当前章场景推进",
                    "再让 AI 汇总结构风险和弧线变化",
                    "确认无误后写回连续性笔记，再回写作台继续正文"
                ]
            )
        }
    }

    private func outlineEditorCard(
        title: String,
        subtitle: String,
        badge: String,
        text: Binding<String>,
        placeholder: String,
        fixedHeight: CGFloat
    ) -> some View {
        DashboardPanel(
            title: title,
            subtitle: subtitle,
            fixedHeight: fixedHeight
        ) {
            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "当前状态", value: badge)
            }

            OutlineEditorSurface(
                text: text,
                placeholder: placeholder,
                minHeight: max(120, fixedHeight - 150)
            )
        }
    }

    private func structureNotesBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.structureNotes ?? "" },
            set: { appState.updateStructureNotes($0, for: projectID) }
        )
    }

    private func sceneProgressBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.sceneProgressNotes ?? "" },
            set: { appState.updateSceneProgressNotes($0, for: projectID) }
        )
    }

    private func characterArcBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.characterArcNotes ?? "" },
            set: { appState.updateCharacterArcNotes($0, for: projectID) }
        )
    }

    private func foreshadowBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.foreshadowNotes ?? "" },
            set: { appState.updateForeshadowNotes($0, for: projectID) }
        )
    }

    private func outlineSummaryBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.outlineSummary ?? "" },
            set: { appState.updateOutlineSummary($0, for: projectID) }
        )
    }

    private func selectedSavedChapter(for project: NovelProject) -> ChapterDraft? {
        if let selectedSavedChapterID,
           let chapterDraft = project.sortedChapterDrafts.first(where: { $0.id == selectedSavedChapterID }) {
            return chapterDraft
        }

        return project.sortedChapterDrafts.first
    }

    private func summarizeOutline(for project: NovelProject) {
        guard let configuration = appState.aiConfiguration else {
            summaryStatusMessage = "当前模型配置不完整，请先到设置里填写 API Key、Base URL 和模型名称。"
            return
        }

        isSummarizing = true
        summaryStatusMessage = "AI 正在为《\(project.title)》整理章节树结构，请稍候…"

        Task {
            do {
                let latestProject = appState.project(for: project.id) ?? project
                let summary = try await AIWritingService.summarizeStoryStructure(
                    configuration: configuration,
                    project: latestProject
                )

                await MainActor.run {
                    appState.updateOutlineSummary(summary, updatedAt: timestampLabel(), for: latestProject.id)
                    isSummarizing = false
                    summaryStatusMessage = "AI 总结已生成，可继续手动精简后写回连续性笔记。"
                }
            } catch {
                await MainActor.run {
                    isSummarizing = false
                    summaryStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func timestampLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "今天 HH:mm"
        return formatter.string(from: Date())
    }
}

private struct OutlineEditorSurface: View {
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

private struct SavedChapterPreviewSurface: View {
    let text: String
    let placeholder: String

    var body: some View {
        ScrollView {
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : text)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiary : .primary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(18)
        }
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
