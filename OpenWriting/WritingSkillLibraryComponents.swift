import SwiftUI

enum WritingSkillLibraryMode: String, CaseIterable, Identifiable {
    case installed
    case marketplace

    var id: Self { self }

    var title: String {
        switch self {
        case .installed:
            return "本地 Skill"
        case .marketplace:
            return "Skill 市场"
        }
    }

    var symbolName: String {
        switch self {
        case .installed:
            return "tray.full"
        case .marketplace:
            return "sparkles"
        }
    }
}

struct WritingSkillRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let skill: WritingSkill
    let isSelected: Bool
    var trailingLabel: String?

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(skill.title, systemImage: skill.category.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(trailingLabel ?? (skill.isEnabled ? "启用" : "停用"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(skill.isEnabled || trailingLabel != nil ? palette.coolAccent : palette.textSecondary)
            }

            Text(skill.summary)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(skill.category.title)
                Text(skill.origin.title)
                Text(skill.importedAt)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(palette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? palette.selectedPanel : palette.panelBase.opacity(palette.isDark ? 0.82 : 0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? palette.coolAccent.opacity(0.36) : palette.stroke, lineWidth: 1)
        )
    }
}

struct WritingSkillTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let symbolName: String
    var isActive = false

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? .white : palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? palette.coolAccent : palette.panelBase.opacity(palette.isDark ? 0.82 : 0.68))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? palette.coolAccent : palette.stroke, lineWidth: 1)
            )
    }
}
