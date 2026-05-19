import SwiftUI

// MARK: - Review Summary Section

struct ReviewSummarySection: View {
    let grade: ReviewGrade
    let overallSummary: String
    let palette: DashboardPalette

    private var gradeColor: Color {
        switch grade {
        case .excellent: return palette.successAccent
        case .good:      return palette.coolAccent
        case .fair:      return palette.warmAccent
        case .poor:      return Color.red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .foregroundStyle(palette.coolAccent)

                Text("📋 审查总结")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                Text(grade.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(gradeColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(gradeColor.opacity(palette.isDark ? 0.18 : 0.12)))
                    .overlay(
                        Capsule()
                            .strokeBorder(gradeColor.opacity(0.30), lineWidth: 1)
                    )
            }

            if !overallSummary.isEmpty {
                Text(overallSummary)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("暂无审查总结。")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .italic()
            }
        }
        .padding(18)
        .background(
            GlassPanelBackground(
                cornerRadius: 22,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.coolAccent.opacity(palette.isDark ? 0.08 : 0.05),
                        palette.successAccent.opacity(palette.isDark ? 0.05 : 0.03),
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
}