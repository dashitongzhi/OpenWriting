import SwiftUI

// MARK: - Score Gauge Ring

struct ScoreGaugeRing: View {
    let score: Int // 0–100
    let grade: ReviewGrade
    let palette: DashboardPalette

    private var fraction: CGFloat { CGFloat(score) / 100.0 }
    private var gradeColor: Color {
        switch grade {
        case .excellent: return palette.successAccent
        case .good:      return palette.coolAccent
        case .fair:      return palette.warmAccent
        case .poor:      return Color.red
        }
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    palette.divider,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )

            // Progress arc
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            gradeColor.opacity(0.6),
                            gradeColor,
                            gradeColor.opacity(0.85)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * fraction)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.0), value: score)

            // Glow behind progress
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(gradeColor.opacity(0.25), style: StrokeStyle(lineWidth: 24, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)

            // Center label
            VStack(spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)

                Text("综合评分")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(width: 160, height: 160)
    }
}