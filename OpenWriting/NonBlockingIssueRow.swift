import SwiftUI

// MARK: - Non-Blocking Issue Row

struct NonBlockingIssueRow: View {
    let issue: ReviewIssue
    let palette: DashboardPalette

    private var severityColor: Color {
        switch issue.severity {
        case .high:   return palette.warmAccent
        case .medium: return palette.coolAccent
        case .low:    return palette.textSecondary
        default:      return palette.textSecondary
        }
    }

    private var severityIcon: String {
        switch issue.severity {
        case .high:   return "exclamationmark.triangle.fill"
        case .medium: return "info.circle.fill"
        case .low:    return "lightbulb.fill"
        default:      return "circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: severityIcon)
                    .font(.caption)
                    .foregroundStyle(severityColor)

                Text(issue.dimension.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                Spacer()

                Text(issue.severity.displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(severityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(severityColor.opacity(palette.isDark ? 0.18 : 0.12)))

                if !issue.location.isEmpty {
                    Text(issue.location)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            Text(issue.description)
                .font(.subheadline)
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(4)

            if !issue.evidence.isEmpty {
                Text(issue.evidence)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.insetPanel.opacity(0.6))
                    )
            }

            if !issue.fixHint.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(palette.successAccent)

                    Text(issue.fixHint)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.panelBase.opacity(palette.isDark ? 0.50 : 0.40))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 0.5)
        )
    }
}