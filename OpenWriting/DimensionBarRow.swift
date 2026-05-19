import SwiftUI

// MARK: - Dimension Bar Row

struct DimensionBarRow: View {
    let dimension: ReviewDimension
    let score: Int // 1–10 scale
    let palette: DashboardPalette

    private var barColor: Color {
        switch score {
        case 8...10: return palette.successAccent
        case 6...7:  return palette.coolAccent
        case 4...5:  return palette.warmAccent
        default:     return Color.red
        }
    }

    private var fraction: CGFloat { CGFloat(score) / 10.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dimension.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                Text("\(score)/10")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(barColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(palette.divider)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.7), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeInOut(duration: 0.8), value: score)
                }
            }
            .frame(height: 10)
        }
    }
}