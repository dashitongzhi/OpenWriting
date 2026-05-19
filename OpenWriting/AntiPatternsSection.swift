import SwiftUI

// MARK: - Anti-Patterns Section

struct AntiPatternsSection: View {
    let antiPatterns: [String]
    let palette: DashboardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(palette.warmAccent)

                Text("🤖 AI 味反模式（\(antiPatterns.count)）")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
            }

            Text("以下模式会让文字带有明显的 AI 生成痕迹，建议逐一修正。")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)

            ForEach(Array(antiPatterns.enumerated()), id: \.offset) { index, pattern in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(palette.warmAccent.opacity(0.75)))

                    Text(pattern)
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(4)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(
            GlassPanelBackground(
                cornerRadius: 22,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.warmAccent.opacity(palette.isDark ? 0.08 : 0.05),
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