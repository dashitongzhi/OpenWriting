import Foundation
import SwiftUI

struct WritingDeskChapterNavigator: View {
    @Environment(\.colorScheme) private var colorScheme
    let project: NovelProject
    @Binding var searchText: String
    let onSelectChapter: (ChapterDraftMetadata) -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var filteredChapters: [ChapterDraftMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return project.chapterCatalog.sorted(by: chapterAscending)
        }

        return project.chapterCatalog
            .filter {
                $0.chapterSummary.localizedStandardContains(query)
                    || $0.previewText.localizedStandardContains(query)
            }
            .sorted(by: chapterAscending)
    }

    private var volumeGroups: [(volumeNumber: Int, chapters: [ChapterDraftMetadata])] {
        Dictionary(grouping: filteredChapters, by: \.volumeNumber)
            .map { volumeNumber, chapters in
                (volumeNumber, chapters.sorted(by: chapterAscending))
            }
            .sorted { $0.volumeNumber < $1.volumeNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("章节导航", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                WorkspaceMetricBadge(label: "已保存", value: "\(project.savedChapterCount) 章")
                WorkspaceMetricBadge(label: "目录", value: project.chapterIntegrityStatusLabel)
            }

            TextField("按卷、章节标题或正文片段搜索", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredChapters.isEmpty {
                Text("没有匹配章节。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(volumeGroups, id: \.volumeNumber) { group in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(group.chapters) { chapter in
                                        chapterButton(chapter)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(volumeTitle(for: group.volumeNumber))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text("\(group.chapters.count) 章")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.editorBorder, lineWidth: 1)
        )
    }

    private func chapterButton(_ chapter: ChapterDraftMetadata) -> some View {
        let isCurrent = chapter.volumeNumber == project.currentVolumeNumber
            && chapter.chapterNumber == project.currentChapterNumber

        return Button {
            onSelectChapter(chapter)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(String(format: "%02d", chapter.chapterNumber))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? palette.coolAccent : palette.textSecondary)
                    .frame(width: 34, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isCurrent ? palette.coolAccent.opacity(0.14) : palette.panelBase.opacity(0.55))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.chapterTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(chapter.wordCount) 字 · \(chapter.savedAt)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.coolAccent)
                        .font(.caption)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? palette.selectedPanel : palette.panelBase.opacity(0.45))
            )
        }
        .buttonStyle(.plain)
        .help("载入 \(chapter.chapterSummary)")
    }

    private func volumeTitle(for volumeNumber: Int) -> String {
        "第 \(volumeNumber) 卷"
    }

    private func chapterAscending(_ lhs: ChapterDraftMetadata, _ rhs: ChapterDraftMetadata) -> Bool {
        if lhs.volumeNumber != rhs.volumeNumber {
            return lhs.volumeNumber < rhs.volumeNumber
        }
        if lhs.chapterNumber != rhs.chapterNumber {
            return lhs.chapterNumber < rhs.chapterNumber
        }
        return lhs.savedAtDate < rhs.savedAtDate
    }
}

struct ChapterLoadDiffSheet: View {
    let project: NovelProject
    let targetMetadata: ChapterDraftMetadata
    let onOverwrite: () -> Void
    let onSaveFirst: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("载入已保存章节")
                        .font(.title3.weight(.bold))
                    Text("载入《\(targetMetadata.chapterSummary)》会替换当前草稿箱正文。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(alignment: .top, spacing: 14) {
                ChapterLoadPreviewColumn(
                    title: "当前草稿",
                    subtitle: project.currentChapterSummary,
                    text: project.draftText
                )

                ChapterLoadPreviewColumn(
                    title: "目标章节",
                    subtitle: "\(targetMetadata.savedAt) · \(targetMetadata.wordCount) 字",
                    text: targetMetadata.previewText
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

struct ChapterLoadPreviewColumn: View {
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
