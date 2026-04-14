import Observation
import SwiftUI

struct OutlineWorkspacePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState

    @State private var selectedSavedChapterID: ChapterDraft.ID?

    private var activeProject: NovelProject? {
        appState.activeProject
    }

    var body: some View {
        if let project = activeProject {
            VStack(alignment: .leading, spacing: 24) {
                chapterListPanel(for: project)
                globalMemoryPanel(for: project)
            }
            .id(project.id)
            .task(id: project.id) {
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

    private func chapterListPanel(for project: NovelProject) -> some View {
        let selectedChapter = selectedSavedChapter(for: project)

        return DashboardPanel(
            title: "章节目录",
            subtitle: "这里只显示当前已打开项目《\(project.title)》的已保存章节。目录只列章节编号和标题，点开即可预览正文。"
        ) {
            if project.sortedChapterDrafts.isEmpty {
                Text("当前还没有已保存章节。你在写作台点“AI 拟标题并保存”后，章节会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        chapterDirectoryList(for: project)
                            .frame(width: 320, alignment: .topLeading)

                        chapterPreviewPanel(for: selectedChapter, project: project)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        chapterDirectoryList(for: project)
                        chapterPreviewPanel(for: selectedChapter, project: project)
                    }
                }
            }
        }
    }

    private func chapterDirectoryList(for project: NovelProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(project.sortedChapterDrafts) { chapterDraft in
                    Button {
                        selectedSavedChapterID = chapterDraft.id
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", chapterDraft.chapterNumber))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(chapterDraft.id == selectedSavedChapterID ? Color.blue : chapterNumberColor)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(
                                            chapterDraft.id == selectedSavedChapterID
                                                ? Color.blue.opacity(0.14)
                                                : chapterNumberBackgroundColor
                                        )
                                )

                            Text(chapterDraft.chapterTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(chapterDraft.id == selectedSavedChapterID ? selectedRowBackgroundColor : rowBackgroundColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    chapterDraft.id == selectedSavedChapterID
                                        ? Color.blue.opacity(0.32)
                                        : rowBorderColor,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(minHeight: 260, maxHeight: 420, alignment: .topLeading)
    }

    private func chapterPreviewPanel(
        for chapterDraft: ChapterDraft?,
        project: NovelProject
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let chapterDraft {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        WorkspaceMetricBadge(label: "当前预览", value: chapterDraft.chapterSummary)
                        WorkspaceMetricBadge(label: "字数", value: "\(chapterDraft.wordCount)")
                        WorkspaceMetricBadge(label: "保存时间", value: chapterDraft.savedAt)
                        Spacer(minLength: 0)

                        Button("载入写作台继续编辑") {
                            appState.loadChapterDraft(chapterDraft.id, for: project.id)
                            appState.openWritingDesk(for: project.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        WorkspaceMetricBadge(label: "当前预览", value: chapterDraft.chapterSummary)
                        HStack(spacing: 12) {
                            WorkspaceMetricBadge(label: "字数", value: "\(chapterDraft.wordCount)")
                            WorkspaceMetricBadge(label: "保存时间", value: chapterDraft.savedAt)
                        }

                        Button("载入写作台继续编辑") {
                            appState.loadChapterDraft(chapterDraft.id, for: project.id)
                            appState.openWritingDesk(for: project.id)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SavedChapterPreviewSurface(
                    text: chapterDraft.content,
                    placeholder: "当前章节正文会显示在这里。"
                )
                .frame(minHeight: 260)
            } else {
                Text("点击左侧目录项后，这里会显示当前章节预览。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func globalMemoryPanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "全局记忆",
            subtitle: "每次保存章节后都会自动更新。这里记录前文发生过什么、人物和世界现在处于什么状态；前台看到的是一块文本，后端会同步保留结构化记忆版本。",
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    WorkspaceMetricBadge(label: "最近同步", value: project.globalMemoryStatusLabel)
                    WorkspaceMetricBadge(label: "结构化字段", value: "\(project.globalMemorySnapshot.populatedSectionCount)/9")
                    WorkspaceMetricBadge(label: "写作参与", value: "正文 / 润色 / 恢复 / 校正")
                }

                VStack(alignment: .leading, spacing: 10) {
                    WorkspaceMetricBadge(label: "最近同步", value: project.globalMemoryStatusLabel)
                    WorkspaceMetricBadge(label: "结构化字段", value: "\(project.globalMemorySnapshot.populatedSectionCount)/9")
                    WorkspaceMetricBadge(label: "写作参与", value: "正文 / 润色 / 恢复 / 校正")
                }
            }

            OutlineEditorSurface(
                text: globalMemoryBinding(for: project.id),
                placeholder: "这里会沉淀长期记忆：人物关系、身份变化、伤势、阵营、地点、道具、世界状态，以及尚未回收的伏笔。",
                minHeight: 320
            )

            WorkspaceChecklist(
                title: "建议重点维护",
                items: [
                    "人物关系、身份变化、伤势和阵营立场",
                    "关键地点、关键道具与世界状态",
                    "尚未回收的伏笔，以及最新章节带来的真实变化"
                ]
            )
        }
    }

    private func globalMemoryBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.continuityNotes ?? "" },
            set: { appState.updateContinuityNotes($0, updatedAt: timestampLabel(), for: projectID) }
        )
    }

    private func selectedSavedChapter(for project: NovelProject) -> ChapterDraft? {
        if let selectedSavedChapterID,
           let chapterDraft = project.sortedChapterDrafts.first(where: { $0.id == selectedSavedChapterID }) {
            return chapterDraft
        }

        return project.sortedChapterDrafts.first
    }

    private func timestampLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "今天 HH:mm"
        return formatter.string(from: Date())
    }

    private var chapterNumberColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : .secondary
    }

    private var chapterNumberBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.58)
    }

    private var rowBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.52)
    }

    private var selectedRowBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.82)
    }

    private var rowBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.16)
    }
}

private struct OutlineEditorSurface: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    .strokeBorder(borderColor, lineWidth: 1)
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

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.16)
    }
}

private struct SavedChapterPreviewSurface: View {
    @Environment(\.colorScheme) private var colorScheme
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
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.16)
    }
}
