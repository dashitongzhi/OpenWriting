import SwiftUI

// MARK: - Dimension Bar Row

struct DimensionBarRow: View {
    let dimension: ReviewDimension
    let score: Int // 0–100 scale (unified reviewer output)
    let palette: DashboardPalette

    private var normalizedScore: Int {
        // Accept 1-10 (legacy) and 0-100 (unified) inputs by mapping to 0-100.
        score > 10 ? min(max(score, 0), 100) : min(max(score, 0), 10) * 10
    }

    private var barColor: Color {
        switch normalizedScore {
        case 80...100: return palette.successAccent
        case 60..<80:  return palette.coolAccent
        case 40..<60:  return palette.warmAccent
        default:       return Color.red
        }
    }

    private var fraction: CGFloat { CGFloat(normalizedScore) / 100.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dimension.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                Text("\(normalizedScore)/100")
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
                        .animation(.easeInOut(duration: 0.8), value: normalizedScore)
                }
            }
            .frame(height: 10)
        }
    }
}