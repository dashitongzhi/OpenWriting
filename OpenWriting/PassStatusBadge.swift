import SwiftUI

// MARK: - Pass Status Badge

struct PassStatusBadge: View {
    let isPassed: Bool
    let palette: DashboardPalette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isPassed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(isPassed ? palette.successAccent : Color.red)

            Text(isPassed ? "审核通过" : "审核未通过")
                .font(.headline.weight(.bold))
                .foregroundStyle(isPassed ? palette.successAccent : Color.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill((isPassed ? palette.successAccent : Color.red).opacity(palette.isDark ? 0.15 : 0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    (isPassed ? palette.successAccent : Color.red).opacity(palette.isDark ? 0.40 : 0.30),
                    lineWidth: 1
                )
        )
    }
}