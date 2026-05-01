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
                chapterTreeWorkspacePanel(for: project)
                globalMemoryPanel(for: project)
                storyModePanel(for: project)
            }
            .id(project.id)
            .task(id: project.id) {
                selectedSavedChapterID = project.sortedChapterCatalog.first?.id
                if let selectedSavedChapterID {
                    appState.ensureChapterDraftLoaded(selectedSavedChapterID, for: project.id)
                }
            }
            .onChange(of: project.chapterCatalog) { _, chapterCatalog in
                let sortedDrafts = chapterCatalog.sorted(by: ChapterDraftMetadata.sortDescending)
                if let selectedSavedChapterID,
                   sortedDrafts.contains(where: { $0.id == selectedSavedChapterID }) {
                    return
                }

                self.selectedSavedChapterID = sortedDrafts.first?.id
                if let selectedSavedChapterID = self.selectedSavedChapterID {
                    appState.ensureChapterDraftLoaded(selectedSavedChapterID, for: project.id)
                }
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
        let selectedChapter = resolvedSavedChapter(in: project, selectedChapterID: selectedSavedChapterID)

        return DashboardPanel(
            title: "章节目录",
            subtitle: "这里只显示当前已打开项目《\(project.title)》的已保存章节。目录只列章节编号和标题，点开即可预览正文。"
        ) {
            if project.sortedChapterCatalog.isEmpty {
                Text("当前还没有已保存章节。你在写作台点“AI 拟标题并保存”后，章节会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        SavedChapterDirectoryList(
                            title: "章节目录",
                            countLabel: "\(project.savedChapterCount) 章",
                            chapterDrafts: project.sortedChapterCatalog,
                            selectedChapterID: selectedSavedChapterID,
                            style: outlineDirectoryStyle,
                            onSelect: { metadata in
                                selectedSavedChapterID = metadata.id
                                appState.ensureChapterDraftLoaded(metadata.id, for: project.id)
                            }
                        )
                            .frame(width: 320, alignment: .topLeading)

                        SavedChapterPreviewPanel(
                            chapterDraft: selectedChapter,
                            previewLabel: "当前预览",
                            emptyStateText: "点击左侧目录项后，这里会显示当前章节预览。",
                            loadButtonStyle: .bordered,
                            previewStyle: SavedChapterPreviewStyle(previewMinHeight: 260),
                            onLoadChapter: { chapterDraft in
                                appState.loadChapterDraft(chapterDraft.id, for: project.id)
                                appState.openWritingDesk(for: project.id)
                            }
                        )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        SavedChapterDirectoryList(
                            title: "章节目录",
                            countLabel: "\(project.savedChapterCount) 章",
                            chapterDrafts: project.sortedChapterCatalog,
                            selectedChapterID: selectedSavedChapterID,
                            style: outlineDirectoryStyle,
                            onSelect: { metadata in
                                selectedSavedChapterID = metadata.id
                                appState.ensureChapterDraftLoaded(metadata.id, for: project.id)
                            }
                        )
                        SavedChapterPreviewPanel(
                            chapterDraft: selectedChapter,
                            previewLabel: "当前预览",
                            emptyStateText: "点击左侧目录项后，这里会显示当前章节预览。",
                            loadButtonStyle: .bordered,
                            previewStyle: SavedChapterPreviewStyle(previewMinHeight: 260),
                            onLoadChapter: { chapterDraft in
                                appState.loadChapterDraft(chapterDraft.id, for: project.id)
                                appState.openWritingDesk(for: project.id)
                            }
                        )
                    }
                }
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
                    WorkspaceMetricBadge(label: "写作参与", value: "正文 / 恢复 / 校正 / 记忆")
                }

                VStack(alignment: .leading, spacing: 10) {
                    WorkspaceMetricBadge(label: "最近同步", value: project.globalMemoryStatusLabel)
                    WorkspaceMetricBadge(label: "结构化字段", value: "\(project.globalMemorySnapshot.populatedSectionCount)/9")
                    WorkspaceMetricBadge(label: "写作参与", value: "正文 / 恢复 / 校正 / 记忆")
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
            set: { appState.updateContinuityNotes($0, updatedAt: TimestampLabel.project(), for: projectID) }
        )
    }

    private func chapterTreeWorkspacePanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "章节树工作区",
            subtitle: "这里集中维护章节树本身的结构记录。保存章节后，AI 会自动刷新章节树总结；你也可以继续手动补齐结构、场景、角色弧线和伏笔。"
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    WorkspaceMetricBadge(label: "AI 总结", value: project.outlineSummaryStatusLabel)
                    WorkspaceMetricBadge(label: "结构节点", value: project.structureStatusLabel)
                    WorkspaceMetricBadge(label: "场景推进", value: project.sceneProgressStatusLabel)
                    WorkspaceMetricBadge(label: "角色弧线", value: project.characterArcStatusLabel)
                    WorkspaceMetricBadge(label: "伏笔回收", value: project.foreshadowStatusLabel)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        WorkspaceMetricBadge(label: "AI 总结", value: project.outlineSummaryStatusLabel)
                        WorkspaceMetricBadge(label: "结构节点", value: project.structureStatusLabel)
                    }

                    HStack(spacing: 12) {
                        WorkspaceMetricBadge(label: "场景推进", value: project.sceneProgressStatusLabel)
                        WorkspaceMetricBadge(label: "角色弧线", value: project.characterArcStatusLabel)
                        WorkspaceMetricBadge(label: "伏笔回收", value: project.foreshadowStatusLabel)
                    }
                }
            }

            Text("AI 章节树总结")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            OutlineEditorSurface(
                text: outlineSummaryBinding(for: project.id),
                placeholder: "保存章节后，AI 会在这里汇总当前章节树状态、推进判断和下一步建议。",
                minHeight: 220
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        chapterTreeEditorSection(
                            title: "章节骨架拆解",
                            placeholder: "记录卷章骨架、章节目标和前后承接关系。",
                            text: structureNotesBinding(for: project.id),
                            minHeight: 220
                        )

                        chapterTreeEditorSection(
                            title: "角色弧线记录",
                            placeholder: "记录人物欲望变化、关系扭转、立场摇摆和关键情绪节点。",
                            text: characterArcNotesBinding(for: project.id),
                            minHeight: 220
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 18) {
                        chapterTreeEditorSection(
                            title: "场景推进记录",
                            placeholder: "把当前章节拆成若干场景，写清每个场景推进了什么。",
                            text: sceneProgressNotesBinding(for: project.id),
                            minHeight: 220
                        )

                        chapterTreeEditorSection(
                            title: "伏笔与回收记录",
                            placeholder: "记录已埋下、已推进、待回收的伏笔和它们的最近状态。",
                            text: foreshadowNotesBinding(for: project.id),
                            minHeight: 220
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    chapterTreeEditorSection(
                        title: "章节骨架拆解",
                        placeholder: "记录卷章骨架、章节目标和前后承接关系。",
                        text: structureNotesBinding(for: project.id),
                        minHeight: 220
                    )

                    chapterTreeEditorSection(
                        title: "场景推进记录",
                        placeholder: "把当前章节拆成若干场景，写清每个场景推进了什么。",
                        text: sceneProgressNotesBinding(for: project.id),
                        minHeight: 220
                    )

                    chapterTreeEditorSection(
                        title: "角色弧线记录",
                        placeholder: "记录人物欲望变化、关系扭转、立场摇摆和关键情绪节点。",
                        text: characterArcNotesBinding(for: project.id),
                        minHeight: 220
                    )

                    chapterTreeEditorSection(
                        title: "伏笔与回收记录",
                        placeholder: "记录已埋下、已推进、待回收的伏笔和它们的最近状态。",
                        text: foreshadowNotesBinding(for: project.id),
                        minHeight: 220
                    )
                }
            }
        }
    }

    private func chapterTreeEditorSection(
        title: String,
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            OutlineEditorSurface(
                text: text,
                placeholder: placeholder,
                minHeight: minHeight
            )
        }
    }

    private func outlineSummaryBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.outlineSummary ?? "" },
            set: { appState.updateOutlineSummary($0, updatedAt: TimestampLabel.project(), for: projectID) }
        )
    }

    private func structureNotesBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.structureNotes ?? "" },
            set: { appState.updateStructureNotes($0, for: projectID) }
        )
    }

    private func sceneProgressNotesBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.sceneProgressNotes ?? "" },
            set: { appState.updateSceneProgressNotes($0, for: projectID) }
        )
    }

    private func characterArcNotesBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.characterArcNotes ?? "" },
            set: { appState.updateCharacterArcNotes($0, for: projectID) }
        )
    }

    private func foreshadowNotesBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.foreshadowNotes ?? "" },
            set: { appState.updateForeshadowNotes($0, for: projectID) }
        )
    }

    private func storyModePanel(for project: NovelProject) -> some View {
        DashboardPanel(
            title: "\(project.storyLengthTitle)创作支撑",
            subtitle: storyModeSubtitle(for: project)
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    WorkspaceMetricBadge(label: "创作模式", value: project.storyLengthTitle)
                    WorkspaceMetricBadge(label: "目标篇幅", value: project.storyLength.targetRangeSummary)
                    WorkspaceMetricBadge(
                        label: "连续性重点",
                        value: project.storyLength.supportsVolumePlanning ? "分卷 + 在途线索" : (project.storyLength.supportsThreadTracking ? "阶段线索" : "单篇闭环")
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    WorkspaceMetricBadge(label: "创作模式", value: project.storyLengthTitle)
                    HStack(spacing: 12) {
                        WorkspaceMetricBadge(label: "目标篇幅", value: project.storyLength.targetRangeSummary)
                        WorkspaceMetricBadge(
                            label: "连续性重点",
                            value: project.storyLength.supportsVolumePlanning ? "分卷 + 在途线索" : (project.storyLength.supportsThreadTracking ? "阶段线索" : "单篇闭环")
                        )
                    }
                }
            }

            if project.storyLength.supportsVolumePlanning {
                Text("分卷/阶段规划")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                OutlineEditorSurface(
                    text: volumePlanBinding(for: project.id),
                    placeholder: "为长篇记录每一卷的目标、卷末回收点、敌我升级和下一卷的接力方向。",
                    minHeight: 220
                )
            }

            if project.storyLength.supportsThreadTracking {
                Text(project.storyLength.supportsVolumePlanning ? "在途线索" : "阶段线索")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                OutlineEditorSurface(
                    text: activeThreadsBinding(for: project.id),
                    placeholder: project.storyLength.supportsVolumePlanning
                        ? "记录当前卷仍在推进的主线、支线、关系线、伏笔线和最近必须回收的旧埋点。"
                        : "记录当前阶段最重要的主线、关系线和最近必须推进的一条伏笔线。",
                    minHeight: project.storyLength.supportsVolumePlanning ? 220 : 180
                )
            }

            WorkspaceChecklist(
                title: "建议优先维护",
                items: project.storyLength.creationChecklist
            )
        }
    }

    private func volumePlanBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.volumePlanNotes ?? "" },
            set: { appState.updateVolumePlanNotes($0, for: projectID) }
        )
    }

    private func activeThreadsBinding(for projectID: NovelProject.ID) -> Binding<String> {
        Binding(
            get: { appState.project(for: projectID)?.activeThreadsNotes ?? "" },
            set: { appState.updateActiveThreadsNotes($0, for: projectID) }
        )
    }

    private func storyModeSubtitle(for project: NovelProject) -> String {
        switch project.storyLength {
        case .short:
            return "短篇更重视冲突集中和结尾闭环，这里主要给你一组节奏提醒，避免故事被拉散。"
        case .medium:
            return "中篇需要稳住阶段推进和主要关系线，这里可以维护当前阶段最重要的在途线索。"
        case .long:
            return "长篇除了全局记忆，还要持续维护分卷目标和在途线索，避免跨章、跨卷写着写着失联。"
        }
    }

    private var outlineDirectoryStyle: SavedChapterDirectoryStyle {
        let palette = DashboardPalette(colorScheme: colorScheme)

        return SavedChapterDirectoryStyle(
            accentColor: palette.activeAccent,
            textPrimary: palette.textPrimary,
            textSecondary: palette.textSecondary,
            selectedNumberColor: palette.activeAccent,
            numberColor: palette.textSecondary,
            selectedNumberBackground: palette.activeAccent.opacity(0.14),
            numberBackground: palette.mutedCapsuleFill,
            selectedRowBackground: palette.selectedPanel,
            rowBackground: palette.panelBase.opacity(palette.isDark ? 0.68 : 0.52),
            selectedRowBorder: palette.activeAccent.opacity(0.32),
            rowBorder: palette.editorBorder,
            rowCornerRadius: 18,
            showsPreviewText: false,
            minHeight: 260,
            maxHeight: 420
        )
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
        DashboardPalette(colorScheme: colorScheme).editorBorder
    }
}
