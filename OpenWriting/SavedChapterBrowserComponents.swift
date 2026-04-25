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
    if let selectedChapterID,
       let chapterDraft = project.sortedChapterDrafts.first(where: { $0.id == selectedChapterID }) {
        return chapterDraft
    }

    return project.sortedChapterDrafts.first
}

struct SavedChapterDirectoryList: View {
    let title: String
    let countLabel: String
    let chapterDrafts: [ChapterDraft]
    let selectedChapterID: ChapterDraft.ID?
    let style: SavedChapterDirectoryStyle
    let onSelect: (ChapterDraft) -> Void

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let chapterDraft {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        WorkspaceMetricBadge(label: previewLabel, value: chapterDraft.chapterSummary)
                        WorkspaceMetricBadge(label: "字数", value: "\(chapterDraft.wordCount)")
                        WorkspaceMetricBadge(label: "保存时间", value: chapterDraft.savedAt)

                        Spacer(minLength: 0)

                        loadButton(for: chapterDraft)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        WorkspaceMetricBadge(label: previewLabel, value: chapterDraft.chapterSummary)
                        HStack(spacing: 12) {
                            WorkspaceMetricBadge(label: "字数", value: "\(chapterDraft.wordCount)")
                            WorkspaceMetricBadge(label: "保存时间", value: chapterDraft.savedAt)
                        }

                        loadButton(for: chapterDraft)
                    }
                }

                SavedChapterPreviewSurface(
                    text: chapterDraft.content,
                    placeholder: "当前章节正文会显示在这里。"
                )
                .frame(minHeight: previewStyle.previewMinHeight)
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
