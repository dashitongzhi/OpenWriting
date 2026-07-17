import Foundation
import SwiftUI

struct WritingDeskToolbarAction: Identifiable {
    let id = UUID()
    let symbolName: String
    let accessibilityLabel: String
    var isEnabled = true
    var isPrimary = false
    var tintColor: Color? = nil
    let action: () -> Void
}

struct DraftPolishProgressBadge: View {
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

struct DraftSelectionPolishToolbar: View {
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

struct DraftSelectionPolishRequestPanel: View {
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
                        .strokeBorder(palette.editorBorder, lineWidth: 1)
                )

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button {
                    onSubmit()
                } label: {
                    Label("开始润色", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.activeAccent)
                .disabled(!isEnabled)
                .help(isEnabled ? "按当前要求润色选区" : "先配置模型后可润色选区")
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
}

struct DraftPolishResultPanel: View {
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
                    Text(review.blockingMessage == nil ? review.mode.reviewTitle : "润色结果未写入正文")
                        .font(.headline.weight(.semibold))

                    Text(review.changedCharacterCount == 0 ? "请确认如何处理这次润色。" : "字数变化约 \(review.changedCharacterCount) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let blockingMessage = review.blockingMessage {
                Label(blockingMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
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
                .disabled(review.blockingMessage != nil)
                .accessibilityHint("保留当前已写入草稿的润色结果")

                Button(action: onReplace) {
                    Label("替换", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(review.blockingMessage != nil)
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

struct DraftPolishSheet: View {
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

                    Text("输入你希望这次润色遵守的要求。留空会按“整体提纯表达、修顺节奏、保留剧情与设定”的默认方向处理。")
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
struct DraftSelectionPolishPopover: View {
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
