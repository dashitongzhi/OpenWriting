import Observation
import SwiftUI

struct CurrentProjectSnapshotCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let project: NovelProject
    let action: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                coverView

                VStack(alignment: .leading, spacing: 10) {
                    Text("当前创作")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(palette.textPrimary)

                        HStack(spacing: 8) {
                            Text(project.genre)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(palette.coolAccent)

                            Text(project.storyLengthTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(palette.panelBase.opacity(palette.isDark ? 0.88 : 0.72))
                                )
                        }
                    }

                    Text(project.summary)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(3)
                        .lineSpacing(3)

                    HStack(spacing: 14) {
                        Label(project.updatedAt, systemImage: "clock")
                        Label("已创作 \(project.writtenChapters) 章", systemImage: "text.book.closed")
                        Label("\(project.manuscriptWordCount) 字", systemImage: "textformat.123")
                    }
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)

                    HStack(spacing: 10) {
                        ProjectChapterPill(
                            label: "当前创作",
                            value: project.currentChapterSummary
                        )

                        ProjectChapterPill(
                            label: "全书字数",
                            value: "\(project.manuscriptWordCount)"
                        )

                        ProjectChapterPill(
                            label: "完成度",
                            value: project.completionStatusLabel
                        )
                    }
                }
            }
            .padding(18)
            .background(
                GlassPanelBackground(
                    cornerRadius: 24,
                    palette: palette,
                    tint: LinearGradient(
                        colors: [
                            palette.warmAccent.opacity(palette.isDark ? 0.12 : 0.08),
                            palette.coolAccent.opacity(palette.isDark ? 0.10 : 0.06),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("打开当前项目并定位到项目空间")
    }

    private var coverView: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.coolAccent.opacity(0.95),
                            palette.warmAccent.opacity(0.88),
                            palette.successAccent.opacity(0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(palette.isDark ? 0.20 : 0.08),
                            .clear
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(project.title.prefix(2))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))

                Text(project.genre)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(width: 112, height: 148)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.coverStroke, lineWidth: 1)
        )
        .shadow(color: palette.shadow.opacity(0.45), radius: 14, y: 10)
    }
}

struct ModelConnectionSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: appState.connectionStatus.symbolName)
                    .foregroundStyle(statusColor)

                Text(appState.connectionStatus.label)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.coolAccent)
            }

            summaryRow(label: "模型选择", value: appState.selectedProvider.title)
            summaryRow(label: "Base URL", value: displayBaseURL)
            summaryRow(label: "模型 ID", value: displayModelName)

            if appState.selectedProvider == .custom {
                summaryRow(
                    label: "API Key",
                    value: appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : "已填写"
                )
            }

            Text(appState.validationMessage)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)

            Text("跟随 Apple 的原生偏好结构，供应商选择和凭证录入都放在设置窗口，不再占用首页编辑空间。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
        }
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .idle:
            return palette.textSecondary
        case .checking:
            return palette.activeAccent
        case .ready:
            return palette.readyAccent
        case .needsAttention:
            return palette.warningAccent
        }
    }

    private var displayBaseURL: String {
        let trimmedBaseURL = appState.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaseURL.isEmpty {
            return trimmedBaseURL
        }

        return appState.selectedProvider == .openAICompatible
            ? AppState.defaultBaseURL(for: .openAICompatible)
            : "未填写"
    }

    private var displayModelName: String {
        let trimmedModelName = appState.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModelName.isEmpty {
            return trimmedModelName
        }

        return appState.selectedProvider == .openAICompatible
            ? AppState.defaultModelName(for: .openAICompatible)
            : "未填写"
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }
}

struct DashboardPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let fixedHeight: CGFloat?
    let content: Content

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    init(
        title: String,
        subtitle: String,
        fixedHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.fixedHeight = fixedHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(palette.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
            }

            content

            if fixedHeight != nil {
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .topLeading)
        .background(
            GlassPanelBackground(
                cornerRadius: 28,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.coolAccent.opacity(palette.isDark ? 0.10 : 0.06),
                        palette.warmAccent.opacity(palette.isDark ? 0.08 : 0.05),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.15 : 0.72),
                            palette.coolAccent.opacity(palette.isDark ? 0.15 : 0.08),
                            Color.white.opacity(palette.isDark ? 0.08 : 0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: palette.shadow.opacity(palette.isDark ? 0.92 : 0.28), radius: palette.isDark ? 28 : 18, y: palette.isDark ? 18 : 10)
    }
}

struct QuickActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let symbolName: String
    let action: () -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.coolAccent.opacity(0.92),
                                palette.successAccent.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: symbolName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    )
                    .rotation3DEffect(.degrees(18), axis: (x: 1, y: -1, z: 0))
                    .shadow(color: palette.coolAccent.opacity(0.28), radius: 12, y: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                GlassPanelBackground(
                    cornerRadius: 22,
                    palette: palette,
                    tint: LinearGradient(
                        colors: [
                            palette.successAccent.opacity(palette.isDark ? 0.10 : 0.06),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PillTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(palette.panelBase.opacity(palette.isDark ? 0.9 : 0.74))
            )
            .overlay(
                Capsule()
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
    }
}

struct DashboardSplitSection<Primary: View, Secondary: View>: View {
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

struct ProjectChapterPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.panelBase.opacity(palette.isDark ? 0.82 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

struct WorkspaceMetricBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.panelBase.opacity(palette.isDark ? 0.82 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

struct WorkspaceChecklist: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let items: [String]
    let compact: Bool

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    init(title: String, items: [String], compact: Bool = false) {
        self.title = title
        self.items = items
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(palette.coolAccent)
                            .frame(width: compact ? 7 : 8, height: compact ? 7 : 8)
                            .padding(.top, compact ? 5 : 6)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.panelSecondary.opacity(palette.isDark ? 0.82 : 0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}
