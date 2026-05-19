import SwiftUI

// MARK: - Dimension Scores Panel

struct DimensionScoresPanel: View {
    let dimensionScores: [ReviewDimension: Int]
    let palette: DashboardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(palette.coolAccent)

                Text("📊 九维评分")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
            }

            VStack(spacing: 10) {
                ForEach(ReviewDimension.allCases) { dimension in
                    let score = dimensionScores[dimension] ?? 8
                    DimensionBarRow(
                        dimension: dimension,
                        score: score,
                        palette: palette
                    )
                }
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