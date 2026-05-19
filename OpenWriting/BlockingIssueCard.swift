import SwiftUI

// MARK: - Blocking Issue Card

struct BlockingIssueCard: View {
    let issue: ReviewIssue
    let palette: DashboardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(Color.red)

                Text(issue.dimension.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                Text(issue.severity.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }

            Text(issue.description)
                .font(.subheadline)
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(4)

            if !issue.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("原文证据")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)

                    Text(issue.evidence)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.insetPanel)
                        )
                }
            }

            if !issue.fixHint.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(palette.warmAccent)
                        .font(.caption)

                    Text(issue.fixHint)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                }
            }

            if !issue.location.isEmpty {
                Label(issue.location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.isDark
                    ? Color.red.opacity(0.08)
                    : Color.red.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.red.opacity(palette.isDark ? 0.30 : 0.20), lineWidth: 1)
        )
    }
}