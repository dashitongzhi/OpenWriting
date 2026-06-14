import SwiftUI

struct DashboardPalette {
    let isDark: Bool
    let backgroundTop: Color
    let backgroundBottom: Color
    let panelBase: Color
    let panelSecondary: Color
    let insetPanel: Color
    let selectedPanel: Color
    let textPrimary: Color
    let textSecondary: Color
    let warmAccent: Color
    let coolAccent: Color
    let successAccent: Color
    let badgeFill: Color
    let badgeFillSelected: Color
    let glassUnderlay: Color
    let glassHighlightStrong: Color
    let glassHighlightSoft: Color
    let stroke: Color
    let shadow: Color

    init(colorScheme: ColorScheme) {
        isDark = colorScheme == .dark

        if isDark {
            backgroundTop = Color(red: 0.04, green: 0.04, blue: 0.05)
            backgroundBottom = Color(red: 0.10, green: 0.10, blue: 0.12)
            panelBase = Color(red: 0.12, green: 0.12, blue: 0.14)
            panelSecondary = Color(red: 0.07, green: 0.07, blue: 0.09)
            insetPanel = Color(red: 0.09, green: 0.09, blue: 0.11).opacity(0.98)
            selectedPanel = Color(red: 0.17, green: 0.19, blue: 0.23).opacity(0.96)
            textPrimary = Color.white.opacity(0.96)
            textSecondary = Color.white.opacity(0.70)
            warmAccent = Color(red: 1.00, green: 0.53, blue: 0.33)
            coolAccent = Color(red: 0.26, green: 0.72, blue: 0.98)
            successAccent = Color(red: 0.43, green: 0.84, blue: 0.66)
            badgeFill = Color.white.opacity(0.10)
            badgeFillSelected = Color.white.opacity(0.16)
            glassUnderlay = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.96)
            glassHighlightStrong = Color.white.opacity(0.06)
            glassHighlightSoft = Color.white.opacity(0.015)
            stroke = Color.white.opacity(0.12)
            shadow = Color.black.opacity(0.52)
        } else {
            backgroundTop = Color(red: 0.98, green: 0.98, blue: 0.97)
            backgroundBottom = Color(red: 0.92, green: 0.96, blue: 0.98)
            panelBase = Color.white.opacity(0.78)
            panelSecondary = Color(red: 0.94, green: 0.96, blue: 0.99).opacity(0.74)
            insetPanel = Color.white.opacity(0.90)
            selectedPanel = Color.white.opacity(0.88)
            textPrimary = Color(red: 0.12, green: 0.13, blue: 0.20)
            textSecondary = Color(red: 0.30, green: 0.34, blue: 0.43)
            warmAccent = Color(red: 0.92, green: 0.55, blue: 0.30)
            coolAccent = Color(red: 0.27, green: 0.56, blue: 0.92)
            successAccent = Color(red: 0.26, green: 0.68, blue: 0.52)
            badgeFill = Color.white.opacity(0.18)
            badgeFillSelected = Color.white.opacity(0.32)
            glassUnderlay = Color.white.opacity(0.50)
            glassHighlightStrong = Color.white.opacity(0.38)
            glassHighlightSoft = Color.white.opacity(0.12)
            stroke = Color.white.opacity(0.58)
            shadow = Color.black.opacity(0.10)
        }
    }

    var activeAccent: Color {
        coolAccent
    }

    var readyAccent: Color {
        successAccent
    }

    var warningAccent: Color {
        warmAccent
    }

    var editorBorder: Color {
        isDark ? Color.white.opacity(0.12) : Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.10)
    }

    var panelBorder: Color {
        isDark ? Color.white.opacity(0.10) : Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.08)
    }

    var toolbarButtonFill: Color {
        isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.72)
    }

    var secondaryChipFill: Color {
        isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.52)
    }

    var divider: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.16)
    }

    var mutedCapsuleFill: Color {
        isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.62)
    }

    var coverStroke: Color {
        Color.white.opacity(isDark ? 0.18 : 0.42)
    }

    var orbStroke: Color {
        Color.white.opacity(isDark ? 0.24 : 0.58)
    }
}

struct PageBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.warmAccent.opacity(palette.isDark ? 0.24 : 0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: -260, y: -240)

            Circle()
                .fill(palette.coolAccent.opacity(palette.isDark ? 0.22 : 0.18))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 360, y: -120)

            Circle()
                .fill(palette.successAccent.opacity(palette.isDark ? 0.18 : 0.12))
                .frame(width: 460, height: 460)
                .blur(radius: 150)
                .offset(x: 320, y: 300)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.isDark ? 0.02 : 0.24),
                            palette.coolAccent.opacity(palette.isDark ? 0.06 : 0.10),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 760, height: 420)
                .rotationEffect(.degrees(-18))
                .rotation3DEffect(.degrees(28), axis: (x: 1, y: 0.2, z: 0))
                .offset(x: 220, y: -240)
                .blur(radius: 1)
        }
        .ignoresSafeArea()
    }
}

struct GlassPanelBackground: View {
    let cornerRadius: CGFloat
    let palette: DashboardPalette
    let tint: LinearGradient

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.glassUnderlay)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.panelBase.opacity(palette.isDark ? 0.94 : 0.76),
                            palette.panelSecondary.opacity(palette.isDark ? 0.86 : 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.glassHighlightStrong,
                            .clear,
                            palette.glassHighlightSoft
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

struct DashboardInsetPanelBackground: View {
    let cornerRadius: CGFloat
    let palette: DashboardPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.insetPanel)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.glassHighlightStrong.opacity(palette.isDark ? 0.55 : 0.80),
                            .clear,
                            palette.glassHighlightSoft.opacity(palette.isDark ? 0.65 : 0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}
