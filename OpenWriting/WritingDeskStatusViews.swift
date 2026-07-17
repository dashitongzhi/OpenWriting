import Foundation
import SwiftUI

struct StrandRatioBar: View {
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

struct WritingDeskStatusPill: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

struct WritingDeskBriefRows: View {
    let rows: [(String, [String])]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let values = row.1
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.0)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)

                    Text(values.isEmpty ? "暂无" : values.prefix(2).joined(separator: "；"))
                        .font(.caption)
                        .foregroundStyle(values.isEmpty ? .tertiary : .secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct ChapterQualityReviewPanel: View {
    let review: ChapterReviewResult
    let minimumAcceptedScore: Int
    let onOpenFullReport: () -> Void

    private var isAccepted: Bool {
        review.passes(minimumScore: minimumAcceptedScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("质量审查", systemImage: isAccepted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button("完整报告", action: onOpenFullReport)
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(review.overallScore)/100")
                        .font(.headline.monospacedDigit())
                    Text("最低 \(minimumAcceptedScore)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isAccepted ? Color.secondary : Color.red)
                }
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

struct QualityReviewDashboardPresentation: Identifiable {
    let id = UUID()
    let review: ChapterReviewResult
    let chapterTitle: String
    let minimumAcceptedScore: Int
}

struct WritingDeskSectionCard<Content: View>: View {
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

    init(
        title: String,
        badgeText: String? = nil,
        statusLabel: String? = nil,
        statusColor: Color? = nil,
        actions: [WritingDeskToolbarAction] = [],
        headerTapAction: (() -> Void)? = nil,
        isCollapsed: Bool = false,
        fillContentHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.badgeText = badgeText
        self.statusLabel = statusLabel
        self.statusColor = statusColor
        self.actions = actions
        self.headerTapAction = headerTapAction
        self.isCollapsed = isCollapsed
        self.fillContentHeight = fillContentHeight
        self.content = content()
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(action.tintColor ?? (action.isPrimary ? palette.activeAccent : .primary))
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(toolbarButtonBackgroundColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
                    .help(action.accessibilityLabel)
                    .accessibilityLabel(action.accessibilityLabel)
                    .opacity(action.isEnabled ? 1 : 0.45)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, isCollapsed ? 16 : 18)
            .padding(.bottom, isCollapsed ? 16 : 16)

            if !isCollapsed {
                Divider()
                    .overlay(dividerColor)

                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(maxHeight: fillContentHeight ? .infinity : nil, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: fillContentHeight ? .infinity : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 12)
    }

    private var chipBackgroundColor: Color {
        palette.secondaryChipFill
    }

    private var toolbarButtonBackgroundColor: Color {
        palette.toolbarButtonFill
    }

    private var dividerColor: Color {
        palette.divider
    }

    private var borderColor: Color {
        palette.panelBorder
    }
}
