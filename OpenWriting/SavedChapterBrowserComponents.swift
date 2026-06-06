import SwiftUI

struct SavedChapterDirectoryStyle {
    let accentColor: Color
    let textPrimary: Color
    let textSecondary: Color
    let selectedNumberColor: Color
    let numberColor: Color
    let selectedNumberBackground: Color
    let numberBackground: Color
    let selectedRowBackground: Color
    let rowBackground: Color
    let selectedRowBorder: Color
    let rowBorder: Color
    let rowCornerRadius: CGFloat
    let showsPreviewText: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat?
}

struct SavedChapterPreviewStyle {
    let previewMinHeight: CGFloat
}

enum SavedChapterLoadButtonStyle {
    case bordered
    case prominent(tint: Color?)
}

func resolvedSavedChapter(
    in project: NovelProject,
    selectedChapterID: ChapterDraft.ID?
) -> ChapterDraft? {
    if let selectedChapterID {
        return project.sortedChapterDrafts.first(where: { $0.id == selectedChapterID })
    }

    return project.sortedChapterDrafts.first
}

func resolvedSavedChapterMetadata(
    in project: NovelProject,
    selectedChapterID: ChapterDraft.ID?
) -> ChapterDraftMetadata? {
    if let selectedChapterID,
       let metadata = project.sortedChapterCatalog.first(where: { $0.id == selectedChapterID }) {
        return metadata
    }

    return project.sortedChapterCatalog.first
}

struct SavedChapterDirectoryList: View {
    let title: String
    let countLabel: String
    let chapterDrafts: [ChapterDraftMetadata]
    let selectedChapterID: ChapterDraft.ID?
    let style: SavedChapterDirectoryStyle
    let onSelect: (ChapterDraftMetadata) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(style.textPrimary)

                Spacer()

                Text(countLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.textSecondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(chapterDrafts) { chapterDraft in
                        Button {
                            onSelect(chapterDraft)
                        } label: {
                            VStack(alignment: .leading, spacing: style.showsPreviewText ? 8 : 0) {
                                HStack(spacing: 12) {
                                    Text(String(format: "%02d", chapterDraft.chapterNumber))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(chapterDraft.id == selectedChapterID ? style.selectedNumberColor : style.numberColor)
                                        .frame(width: 34, height: 34)
                                        .background(
                                            Circle()
                                                .fill(
                                                    chapterDraft.id == selectedChapterID
                                                        ? style.selectedNumberBackground
                                                        : style.numberBackground
                                                )
                                        )

                                    Text(chapterDraft.chapterTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(style.textPrimary)
                                        .lineLimit(1)

                                    Spacer(minLength: 0)
                                }

                                if style.showsPreviewText {
                                    Text(chapterDraft.previewText)
                                        .font(.caption)
                                        .foregroundStyle(style.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: style.rowCornerRadius, style: .continuous)
                                    .fill(
                                        chapterDraft.id == selectedChapterID
                                            ? style.selectedRowBackground
                                            : style.rowBackground
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: style.rowCornerRadius, style: .continuous)
                                    .strokeBorder(
                                        chapterDraft.id == selectedChapterID
                                            ? style.selectedRowBorder
                                            : style.rowBorder,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看第 \(chapterDraft.chapterNumber) 章 \(chapterDraft.chapterTitle)")
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: style.minHeight, maxHeight: style.maxHeight, alignment: .topLeading)
        }
    }
}

struct SavedChapterPreviewPanel: View {
    let chapterDraft: ChapterDraft?
    let previewLabel: String
    let emptyStateText: String
    let loadButtonStyle: SavedChapterLoadButtonStyle
    let previewStyle: SavedChapterPreviewStyle
    let onLoadChapter: (ChapterDraft) -> Void
    let onRestoreVersion: ((ChapterDraft, ChapterDraftVersion) -> Void)?

    init(
        chapterDraft: ChapterDraft?,
        previewLabel: String,
        emptyStateText: String,
        loadButtonStyle: SavedChapterLoadButtonStyle,
        previewStyle: SavedChapterPreviewStyle,
        onLoadChapter: @escaping (ChapterDraft) -> Void,
        onRestoreVersion: ((ChapterDraft, ChapterDraftVersion) -> Void)? = nil
    ) {
        self.chapterDraft = chapterDraft
        self.previewLabel = previewLabel
        self.emptyStateText = emptyStateText
        self.loadButtonStyle = loadButtonStyle
        self.previewStyle = previewStyle
        self.onLoadChapter = onLoadChapter
        self.onRestoreVersion = onRestoreVersion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let chapterDraft {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        WorkspaceMetricBadge(label: previewLabel, value: chapterDraft.chapterSummary)
                        WorkspaceMetricBadge(label: "字数", value: "\(chapterDraft.wordCount)")
                        WorkspaceMetricBadge(label: "保存时间", value: chapterDraft.savedAt)
                        WorkspaceMetricBadge(label: "历史版本", value: "\(chapterDraft.versionCount)")

                        Spacer(minLength: 0)

                        loadButton(for: chapterDraft)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        WorkspaceMetricBadge(label: previewLabel, value: chapterDraft.chapterSummary)
                        HStack(spacing: 12) {
                            WorkspaceMetricBadge(label: "字数", value: "\(chapterDraft.wordCount)")
                            WorkspaceMetricBadge(label: "保存时间", value: chapterDraft.savedAt)
                            WorkspaceMetricBadge(label: "历史版本", value: "\(chapterDraft.versionCount)")
                        }

                        loadButton(for: chapterDraft)
                    }
                }

                SavedChapterPreviewSurface(
                    text: chapterDraft.content,
                    placeholder: "当前章节正文会显示在这里。"
                )
                .frame(minHeight: previewStyle.previewMinHeight)

                if !chapterDraft.versionHistory.isEmpty, let onRestoreVersion {
                    ChapterVersionHistoryPanel(
                        chapterDraft: chapterDraft,
                        onRestoreVersion: onRestoreVersion
                    )
                }
            } else {
                Text(emptyStateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func loadButton(for chapterDraft: ChapterDraft) -> some View {
        switch loadButtonStyle {
        case .bordered:
            Button("载入写作台继续编辑") {
                onLoadChapter(chapterDraft)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("把这一章载入写作台继续编辑")
        case let .prominent(tint):
            Button("载入写作台继续编辑") {
                onLoadChapter(chapterDraft)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .accessibilityHint("把这一章载入写作台继续编辑")
        }
    }
}

struct ChapterVersionHistoryPanel: View {
    let chapterDraft: ChapterDraft
    let onRestoreVersion: (ChapterDraft, ChapterDraftVersion) -> Void
    @State private var comparisonVersion: ChapterDraftVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("版本历史")
                .font(.headline)

            ForEach(chapterDraft.versionHistory.prefix(8)) { version in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(version.chapterTitle) · \(version.savedAt)")
                            .font(.subheadline.weight(.semibold))

                        Text("\(version.reason) · \(version.wordCount) 字")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button("对比") {
                            comparisonVersion = version
                        }
                        .buttonStyle(.bordered)

                        Button("回滚") {
                            onRestoreVersion(chapterDraft, version)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .sheet(item: $comparisonVersion) { version in
            ChapterVersionComparisonSheet(
                chapterDraft: chapterDraft,
                version: version
            )
        }
    }
}

struct ChapterVersionComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapterDraft: ChapterDraft
    let version: ChapterDraftVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("版本差异")
                        .font(.title2.weight(.bold))

                    Text("\(version.savedAt) 与当前版本对比")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "历史字数", value: "\(version.wordCount)")
                WorkspaceMetricBadge(label: "当前字数", value: "\(chapterDraft.wordCount)")
                WorkspaceMetricBadge(label: "字数变化", value: wordDeltaLabel)
                WorkspaceMetricBadge(label: "标题", value: titleChangeLabel)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    comparisonColumn(
                        title: "历史版本",
                        subtitle: version.chapterTitle,
                        text: version.content
                    )
                    comparisonColumn(
                        title: "当前版本",
                        subtitle: chapterDraft.chapterTitle,
                        text: chapterDraft.content
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    comparisonColumn(
                        title: "历史版本",
                        subtitle: version.chapterTitle,
                        text: version.content
                    )
                    comparisonColumn(
                        title: "当前版本",
                        subtitle: chapterDraft.chapterTitle,
                        text: chapterDraft.content
                    )
                }
            }
        }
        .padding(24)
        .frame(minWidth: 760, idealWidth: 980, minHeight: 560, idealHeight: 720)
    }

    private var wordDeltaLabel: String {
        let delta = chapterDraft.wordCount - version.wordCount
        guard delta != 0 else { return "无变化" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private var titleChangeLabel: String {
        chapterDraft.chapterTitle == version.chapterTitle ? "未变化" : "已变化"
    }

    private func comparisonColumn(title: String, subtitle: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            SavedChapterPreviewSurface(
                text: text,
                placeholder: "这个版本没有正文。"
            )
            .frame(minHeight: 360)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct LongformSearchResultsPanel: View {
    let results: [LongformSearchResult]
    let onSelectChapter: (ChapterDraft.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("全书检索")
                    .font(.headline)

                Spacer()

                Text("\(results.count) 条")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if results.isEmpty {
                Text("没有匹配结果。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(results) { result in
                            Button {
                                if let chapterID = result.chapterID {
                                    onSelectChapter(chapterID)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 8) {
                                        Text(result.kind.title)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)

                                        Text(result.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }

                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(result.excerpt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(result.chapterID == nil)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 260)
            }
        }
    }
}

struct SavedChapterPreviewSurface: View {
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
        DashboardPalette(colorScheme: colorScheme).editorBorder
    }
}
