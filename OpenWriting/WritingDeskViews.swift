import SwiftUI

// MARK: - Draft Polish Views

// MARK: - Draft Polish Progress Badge

private struct DraftPolishProgressBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let mode: DraftPolishMode

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(mode.progressTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(palette.activeAccent.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.22 : 0.10), radius: 12, y: 5)
        .allowsHitTesting(false)
    }
}

// MARK: - Draft Selection Polish Toolbar

private struct DraftSelectionPolishToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    let isEnabled: Bool
    let action: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))

                Text("润色")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(palette.panelBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(palette.isDark ? 0.30 : 0.16), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(isEnabled ? "润色当前选区" : "先配置模型后可润色选区")
    }
}

// MARK: - Draft Selection Polish Request Panel

private struct DraftSelectionPolishRequestPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedText: String
    @Binding var instruction: String
    let isEnabled: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.activeAccent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(palette.toolbarButtonFill))

                VStack(alignment: .leading, spacing: 2) {
                    Text("润色选区")
                        .font(.headline.weight(.semibold))

                    Text("可以补充风格、语气或改写方向")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("取消")
            }

            Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.insetPanel.opacity(palette.isDark ? 0.62 : 0.54))
                )

            TextEditor(text: $instruction)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.insetPanel.opacity(palette.isDark ? 0.72 : 0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            HStack {
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("开始润色") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.panelBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.36 : 0.18), radius: 22, y: 10)
    }

    private var isProcessing: Bool { false }

    private var borderColor: Color {
        palette.editorBorder
    }
}

// MARK: - Draft Polish Result Panel

private struct DraftPolishResultPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let review: DraftPolishReview
    let onKeep: () -> Void
    let onReplace: () -> Void
    let onDiscard: () -> Void
    let onCopy: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.activeAccent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(palette.toolbarButtonFill))

                VStack(alignment: .leading, spacing: 2) {
                    Text(review.mode.reviewTitle)
                        .font(.headline.weight(.semibold))

                    Text(review.changedCharacterCount == 0 ? "请确认如何处理这次润色。" : "字数变化约 \(review.changedCharacterCount) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ScrollView {
                Text(review.polishedText)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.insetPanel.opacity(palette.isDark ? 0.70 : 0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.editorBorder, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button(action: onKeep) {
                    Label("保留", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.activeAccent)
                .accessibilityHint("保留当前已写入草稿的润色结果")

                Button(action: onReplace) {
                    Label("替换", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("重新将正文替换为这次润色结果")

                Button(action: onDiscard) {
                    Label("舍弃", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("恢复润色前的草稿内容")

                Spacer()

                Button(action: onCopy) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("复制润色结果")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.panelBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.38 : 0.20), radius: 24, y: 12)
    }
}

// MARK: - Draft Polish Sheet

private struct DraftPolishSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let projectTitle: String
    @Binding var instruction: String
    let isProcessing: Bool
    let onSubmit: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("润色整篇草稿")
                        .font(.title2.weight(.semibold))

                    Text("当前项目：\(projectTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("输入你希望这次润色遵守的要求。留空会按"整体提纯表达、修顺节奏、保留剧情与设定"的默认方向处理。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    TextEditor(text: $instruction)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .frame(minHeight: 240)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 1)
                        )
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("关闭整篇润色面板")

                Spacer()

                Button("开始润色") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                .accessibilityHint("根据当前要求润色整篇草稿")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: 760,
            minHeight: 420,
            idealHeight: 520,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var borderColor: Color {
        palette.editorBorder
    }
}

// MARK: - Draft Selection Polish Popover

private struct DraftSelectionPolishPopover: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let selectedText: String
    @Binding var instruction: String
    let isProcessing: Bool
    let onSubmit: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("润色当前选区")
                .font(.headline)

            Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前没有选中文本。" : "可输入这次润色要遵守的要求，结果会直接替换当前选区。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("当前选中内容")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(selectedText.count) 字")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                ScrollView {
                    Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前没有可润色的选区。" : selectedText)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(minHeight: 108)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
            }

            TextEditor(text: $instruction)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("关闭选区润色面板")

                Spacer()

                Button("开始润色") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("按当前要求替换选中的正文")
            }
        }
        .padding(18)
        .frame(minWidth: 320, idealWidth: 356, maxWidth: 420, alignment: .topLeading)
    }

    private var borderColor: Color {
        palette.editorBorder
    }
}

// MARK: - Strand Ratio Bar

private struct StrandRatioBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.78))
                        .frame(width: max(4, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 7)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }
}

// MARK: - Chapter Quality Review Panel

private struct ChapterQualityReviewPanel: View {
    let review: ChapterReviewResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("质量审查", systemImage: review.hasBlockingIssues ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(review.overallScore)/100")
                    .font(.headline.monospacedDigit())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(ReviewDimension.allCases) { dimension in
                    HStack {
                        Text(dimension.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text("\(review.dimensionScores[dimension] ?? 0)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }

            if !review.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(review.issues.prefix(3)) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("[\(issue.severity.displayName)] \(issue.description)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(issue.isBlocking ? .red : .primary)
                                .lineLimit(2)

                            if !issue.fixHint.isEmpty {
                                Text(issue.fixHint)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                Text("未发现阻断问题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }
}

// MARK: - Writing Desk Section Card

private struct WritingDeskSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let badgeText: String?
    let statusLabel: String?
    let statusColor: Color?
    let actions: [WritingDeskToolbarAction]
    let headerTapAction: (() -> Void)?
    let isCollapsed: Bool
    let fillContentHeight: Bool
    @ViewBuilder let content: Content

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
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
                                .fill(chipBackgroundColor)
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help(action.accessibilityLabel)
                }
            }

            if !isCollapsed {
                content
            }
        }
    }

    private var chipBackgroundColor: Color {
        palette.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

// MARK: - Writing Desk Text Surface

private struct WritingDeskTextSurface: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                Group {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }
            )
    }
}