import SwiftUI

struct DimensionalSceneView: View {
    enum SceneStyle {
        case hero
        case workspace
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var animateScene = false
    let style: SceneStyle

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style == .hero ? 34 : 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.04 : 0.32),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.coolAccent.opacity(palette.isDark ? 0.34 : 0.28),
                            palette.successAccent.opacity(palette.isDark ? 0.22 : 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: style == .hero ? 180 : 150, height: style == .hero ? 140 : 122)
                .rotation3DEffect(.degrees(animateScene ? 40 : 24), axis: (x: 1, y: -1, z: 0))
                .offset(x: animateScene ? 42 : 26, y: animateScene ? -46 : -28)
                .shadow(color: palette.coolAccent.opacity(0.36), radius: 26, y: 16)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.panelBase.opacity(0.96),
                            palette.panelSecondary.opacity(0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: style == .hero ? 220 : 180, height: style == .hero ? 160 : 136)
                .rotation3DEffect(.degrees(animateScene ? -18 : -10), axis: (x: 1, y: 0.3, z: 0))
                .offset(x: animateScene ? -24 : -10, y: animateScene ? 18 : 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(palette.coverStroke, lineWidth: 1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.82 : 0.95),
                            palette.warmAccent.opacity(0.82),
                            palette.coolAccent.opacity(0.08)
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 120
                    )
                )
                .frame(width: style == .hero ? 132 : 110, height: style == .hero ? 132 : 110)
                .overlay(
                    Circle()
                        .strokeBorder(palette.orbStroke, lineWidth: 1)
                )
                .offset(x: animateScene ? -88 : -68, y: animateScene ? -70 : -48)
                .shadow(color: palette.warmAccent.opacity(0.36), radius: 22, y: 16)

            VStack(spacing: 12) {
                SceneSlab(width: style == .hero ? 148 : 130, height: 18, palette: palette)
                    .offset(x: style == .hero ? 84 : 56)

                SceneSlab(width: style == .hero ? 188 : 164, height: 18, palette: palette)
                    .offset(x: style == .hero ? 18 : 12)

                SceneSlab(width: style == .hero ? 124 : 110, height: 18, palette: palette)
                    .offset(x: style == .hero ? 62 : 46)
            }
            .offset(y: style == .hero ? 76 : 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            guard !animateScene else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                animateScene = true
            }
        }
    }
}

private struct SceneSlab: View {
    let width: CGFloat
    let height: CGFloat
    let palette: DashboardPalette

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(palette.isDark ? 0.14 : 0.74),
                        palette.panelBase.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
    }
}
