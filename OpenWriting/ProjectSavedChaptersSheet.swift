import SwiftUI

struct ProjectSavedChaptersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    let projectID: NovelProject.ID

    @State private var selectedChapterID: ChapterDraft.ID?
    @State private var searchText = ""
    @State private var pendingChapterLoad: ChapterDraft?
    @State private var pendingRestore: (chapter: ChapterDraft, version: ChapterDraftVersion)?

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var project: NovelProject? {
        appState.project(for: projectID)
    }

    private var selectedChapter: ChapterDraft? {
        guard let project else { return nil }
        return resolvedSavedChapter(in: project, selectedChapterID: selectedChapterID)
    }

    private var selectedChapterMetadata: ChapterDraftMetadata? {
        guard let project else { return nil }
        return resolvedSavedChapterMetadata(in: project, selectedChapterID: selectedChapterID)
    }

    private var searchResults: [LongformSearchResult] {
        appState.searchLongformProject(searchText, in: projectID)
    }

    private var directoryStyle: SavedChapterDirectoryStyle {
        SavedChapterDirectoryStyle(
            accentColor: palette.coolAccent,
            textPrimary: palette.textPrimary,
            textSecondary: palette.textSecondary,
            selectedNumberColor: palette.coolAccent,
            numberColor: palette.textSecondary,
            selectedNumberBackground: palette.coolAccent.opacity(palette.isDark ? 0.18 : 0.12),
            numberBackground: palette.panelBase.opacity(palette.isDark ? 0.70 : 0.52),
            selectedRowBackground: palette.selectedPanel,
            rowBackground: palette.panelBase.opacity(palette.isDark ? 0.82 : 0.68),
            selectedRowBorder: palette.coolAccent.opacity(0.36),
            rowBorder: palette.stroke,
            rowCornerRadius: 20,
            showsPreviewText: true,
            minHeight: 0,
            maxHeight: nil
        )
    }

    var body: some View {
        ZStack {
            PageBackground()

            if let project {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("已创作章节")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(palette.textPrimary)

                            Text("《\(project.title)》已保存 \(project.savedChapterCount) 章。左侧选章节，右侧直接预览正文。")
                                .font(.subheadline)
                                .foregroundStyle(palette.textSecondary)
                                .lineSpacing(3)
                        }

                        Spacer()

                        Button("关闭") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("关闭已保存章节窗口")
                    }

                    TextField("搜索章节、正文、素材、大纲、伏笔或全局记忆", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 18) {
                                SavedChapterDirectoryList(
                                    title: "章节目录",
                                    countLabel: "\(project.savedChapterCount) 章",
                                    chapterDrafts: project.sortedChapterCatalog,
                                    selectedChapterID: selectedChapterMetadata?.id,
                                    style: directoryStyle,
                                    onSelect: { metadata in
                                        selectedChapterID = metadata.id
                                        appState.ensureChapterDraftLoaded(metadata.id, for: project.id)
                                    }
                                )

                                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    LongformSearchResultsPanel(
                                        results: searchResults,
                                        onSelectChapter: { chapterID in
                                            selectedChapterID = chapterID
                                            appState.ensureChapterDraftLoaded(chapterID, for: project.id)
                                        }
                                    )
                                }
                            }
                            .frame(width: 320, alignment: .topLeading)

                            SavedChapterPreviewPanel(
                                chapterDraft: selectedChapter,
                                previewLabel: "当前章节",
                                emptyStateText: "点击左侧目录项后，这里会显示当前章节预览。",
                                loadButtonStyle: .prominent(tint: palette.coolAccent),
                                previewStyle: SavedChapterPreviewStyle(previewMinHeight: 0),
                                onLoadChapter: { chapterDraft in
                                    requestChapterLoad(chapterDraft, project: project)
                                },
                                onRestoreVersion: { chapterDraft, version in
                                    pendingRestore = (chapterDraft, version)
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            SavedChapterDirectoryList(
                                    title: "章节目录",
                                    countLabel: "\(project.savedChapterCount) 章",
                                    chapterDrafts: project.sortedChapterCatalog,
                                    selectedChapterID: selectedChapterMetadata?.id,
                                    style: directoryStyle,
                                    onSelect: { metadata in
                                        selectedChapterID = metadata.id
                                        appState.ensureChapterDraftLoaded(metadata.id, for: project.id)
                                    }
                                )

                            SavedChapterPreviewPanel(
                                chapterDraft: selectedChapter,
                                previewLabel: "当前章节",
                                emptyStateText: "点击左侧目录项后，这里会显示当前章节预览。",
                                loadButtonStyle: .prominent(tint: palette.coolAccent),
                                previewStyle: SavedChapterPreviewStyle(previewMinHeight: 0),
                                onLoadChapter: { chapterDraft in
                                    requestChapterLoad(chapterDraft, project: project)
                                },
                                onRestoreVersion: { chapterDraft, version in
                                    pendingRestore = (chapterDraft, version)
                                }
                            )

                            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LongformSearchResultsPanel(
                                    results: searchResults,
                                    onSelectChapter: { chapterID in
                                        selectedChapterID = chapterID
                                        appState.ensureChapterDraftLoaded(chapterID, for: project.id)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(24)
                .frame(
                    minWidth: 720,
                    idealWidth: 920,
                    maxWidth: 1120,
                    minHeight: 540,
                    idealHeight: 720,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .task(id: project.id) {
                    selectedChapterID = project.sortedChapterCatalog.first?.id
                    if let selectedChapterID {
                        appState.ensureChapterDraftLoaded(selectedChapterID, for: project.id)
                    }
                }
                .onChange(of: project.chapterCatalog) { _, chapterCatalog in
                    let sortedDrafts = chapterCatalog.sorted(by: ChapterDraftMetadata.sortDescending)
                    if let selectedChapterID,
                       sortedDrafts.contains(where: { $0.id == selectedChapterID }) {
                        return
                    }

                    self.selectedChapterID = sortedDrafts.first?.id
                    if let selectedChapterID = self.selectedChapterID {
                        appState.ensureChapterDraftLoaded(selectedChapterID, for: project.id)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("项目已经不可用")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("这个项目可能已被删除或切换了账号范围，所以当前无法读取已保存章节。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Button("关闭") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("关闭已保存章节窗口")
                }
                .padding(24)
                .frame(
                    minWidth: 420,
                    idealWidth: 560,
                    maxWidth: 680,
                    minHeight: 240,
                    alignment: .topLeading
                )
            }
        }
        .frame(minWidth: 720, minHeight: 540, alignment: .topLeading)
        .sheet(item: $pendingChapterLoad) { chapterDraft in
            if let project {
                ProjectSavedChapterLoadDiffSheet(
                    project: project,
                    targetChapter: chapterDraft,
                    onOverwrite: {
                        performChapterLoad(chapterDraft, projectID: project.id)
                    },
                    onSaveFirst: {
                        pendingChapterLoad = nil
                        _ = appState.saveCurrentChapterDraft(for: project.id)
                    },
                    onCancel: {
                        pendingChapterLoad = nil
                    }
                )
            }
        }
        .confirmationDialog(
            "回滚章节版本",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRestore = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRestore {
                Button("回滚到 \(pendingRestore.version.savedAt)", role: .destructive) {
                    appState.restoreChapterVersion(
                        pendingRestore.version.id,
                        chapterDraftID: pendingRestore.chapter.id,
                        for: projectID
                    )
                    selectedChapterID = pendingRestore.chapter.id
                    self.pendingRestore = nil
                }
            }

            Button("取消", role: .cancel) {
                pendingRestore = nil
            }
        } message: {
            if let pendingRestore {
                Text("将《\(pendingRestore.chapter.chapterSummary)》恢复为历史版本《\(pendingRestore.version.chapterTitle)》。当前版本会先自动保存到历史中。")
            }
        }
    }

    private func requestChapterLoad(_ chapterDraft: ChapterDraft, project: NovelProject) {
        if shouldConfirmChapterLoad(chapterDraft, in: project) {
            pendingChapterLoad = chapterDraft
            return
        }

        performChapterLoad(chapterDraft, projectID: project.id)
    }

    private func performChapterLoad(_ chapterDraft: ChapterDraft, projectID: NovelProject.ID) {
        appState.loadChapterDraft(chapterDraft.id, for: projectID)
        appState.openWritingDesk(for: projectID)
        pendingChapterLoad = nil
        dismiss()
    }

    private func shouldConfirmChapterLoad(_ chapterDraft: ChapterDraft, in project: NovelProject) -> Bool {
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

        return true
    }
}

private struct ProjectSavedChapterLoadDiffSheet: View {
    let project: NovelProject
    let targetChapter: ChapterDraft
    let onOverwrite: () -> Void
    let onSaveFirst: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("载入已保存章节")
                    .font(.title3.weight(.bold))
                Text("载入《\(targetChapter.chapterSummary)》会替换当前草稿箱正文。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 14) {
                SavedChapterLoadPreviewColumn(
                    title: "当前草稿",
                    subtitle: project.currentChapterSummary,
                    text: project.draftText
                )

                SavedChapterLoadPreviewColumn(
                    title: "目标章节",
                    subtitle: "\(targetChapter.savedAt) · \(targetChapter.wordCount) 字",
                    text: targetChapter.content
                )
            }

            HStack {
                Button("取消", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("先保存当前草稿") {
                    onSaveFirst()
                }
                .buttonStyle(.bordered)

                Button("载入并覆盖当前草稿", role: .destructive) {
                    onOverwrite()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 460)
    }
}

private struct SavedChapterLoadPreviewColumn: View {
    let title: String
    let subtitle: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            ScrollView {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无正文。" : text)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
