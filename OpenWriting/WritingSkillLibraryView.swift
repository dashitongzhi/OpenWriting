import SwiftUI
import UniformTypeIdentifiers

struct WritingSkillLibraryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState

    @State private var selectedMode: WritingSkillLibraryMode = .installed
    @State private var selectedSkillID: WritingSkill.ID?
    @State private var selectedMarketplaceSkillID: WritingSkill.ID = WritingSkillMarketplace.featured.first?.id ?? ""
    @State private var isImportingSkills = false
    @State private var isCreatorPresented = false
    @State private var statusMessage = "导入或启用的 Skill 会作为写作策略参与后续 AI 续写、修订和大纲生成。"

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var selectedSkill: WritingSkill? {
        guard let selectedSkillID else { return appState.writingSkills.first }
        return appState.writingSkills.first { $0.id == selectedSkillID } ?? appState.writingSkills.first
    }

    private var selectedMarketplaceSkill: WritingSkill {
        WritingSkillMarketplace.featured.first { $0.id == selectedMarketplaceSkillID }
            ?? WritingSkillMarketplace.featured[0]
    }

    private var supportedSkillImportTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText, .text, .sourceCode, .json]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }

    var body: some View {
        DashboardPanel(
            title: "Skill 广场",
            subtitle: "导入写作 Skill、自建策略卡，或从广场安装一组可启用的创作能力。"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                skillOverviewRow

                Picker("Skill 视图", selection: $selectedMode) {
                    ForEach(WritingSkillLibraryMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedMode {
                case .installed:
                    installedSkillsSection
                case .marketplace:
                    marketplaceSection
                }

                Label(statusMessage, systemImage: "wand.and.stars")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .fileImporter(
            isPresented: $isImportingSkills,
            allowedContentTypes: supportedSkillImportTypes,
            allowsMultipleSelection: true,
            onCompletion: handleSkillImport
        )
        .sheet(isPresented: $isCreatorPresented) {
            WritingSkillCreatorSheet { skill in
                appState.importWritingSkills([skill])
                selectedMode = .installed
                selectedSkillID = skill.id
                statusMessage = "已创建并启用「\(skill.title)」。"
            }
        }
        .onAppear {
            syncInstalledSelection()
        }
        .onChange(of: appState.writingSkills) { _, _ in
            syncInstalledSelection()
        }
    }

    private var skillOverviewRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "已安装", value: "\(appState.writingSkills.count)")
                WorkspaceMetricBadge(label: "已启用", value: "\(appState.enabledWritingSkills.count)")
                WorkspaceMetricBadge(label: "广场 Skill", value: "\(WritingSkillMarketplace.featured.count)")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button {
                        isImportingSkills = true
                    } label: {
                        Label("导入 Skill", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.coolAccent)

                    Button {
                        isCreatorPresented = true
                    } label: {
                        Label("自建 Skill", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isImportingSkills = true
                    } label: {
                        Label("导入 Skill", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.coolAccent)

                    Button {
                        isCreatorPresented = true
                    } label: {
                        Label("自建 Skill", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var installedSkillsSection: some View {
        if appState.writingSkills.isEmpty {
            WorkspaceChecklist(
                title: "开始使用 Skill",
                items: [
                    "导入 Markdown、TXT 或 JSON 格式的写作 Skill",
                    "用自建 Skill 写下你自己的文风、节奏或题材规则",
                    "从 Skill 广场安装内置策略后，可随时启用或停用"
                ]
            )
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    installedSkillList
                        .frame(width: 360)

                    installedSkillDetail(selectedSkill)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 24) {
                    installedSkillList
                    installedSkillDetail(selectedSkill)
                }
            }
        }
    }

    private var installedSkillList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本地 Skill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.writingSkills) { skill in
                        Button {
                            selectedSkillID = skill.id
                        } label: {
                            WritingSkillRow(skill: skill, isSelected: selectedSkill?.id == skill.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 260)
        }
    }

    private func installedSkillDetail(_ skill: WritingSkill?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let skill {
                skillHeader(skill)

                HStack(spacing: 10) {
                    Button {
                        appState.toggleWritingSkill(skill.id)
                        statusMessage = skill.isEnabled ? "已停用「\(skill.title)」。" : "已启用「\(skill.title)」。"
                    } label: {
                        Label(skill.isEnabled ? "停用" : "启用", systemImage: skill.isEnabled ? "pause.circle" : "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(skill.isEnabled ? palette.warmAccent : palette.coolAccent)

                    Button(role: .destructive) {
                        appState.deleteWritingSkill(skill.id)
                        statusMessage = "已删除「\(skill.title)」。"
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                skillInstructions(skill)
            } else {
                WorkspaceChecklist(
                    title: "查看 Skill 详情",
                    items: [
                        "从左侧选择一个 Skill 查看完整规则",
                        "启用后，它会自动进入 AI 写作提示词",
                        "停用不会删除 Skill，只是不再参与生成"
                    ]
                )
            }
        }
    }

    private var marketplaceSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                marketplaceList
                    .frame(width: 360)

                marketplaceDetail(selectedMarketplaceSkill)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 24) {
                marketplaceList
                marketplaceDetail(selectedMarketplaceSkill)
            }
        }
    }

    private var marketplaceList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("精选广场")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(WritingSkillMarketplace.featured) { skill in
                    Button {
                        selectedMarketplaceSkillID = skill.id
                    } label: {
                        WritingSkillRow(
                            skill: skill,
                            isSelected: selectedMarketplaceSkillID == skill.id,
                            trailingLabel: appState.installedWritingSkillIDs.contains(skill.id) ? "已安装" : "可安装"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func marketplaceDetail(_ skill: WritingSkill) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            skillHeader(skill)

            Button {
                appState.installMarketplaceSkill(skill)
                selectedMode = .installed
                selectedSkillID = skill.id
                statusMessage = "已安装并启用「\(skill.title)」。"
            } label: {
                Label(appState.installedWritingSkillIDs.contains(skill.id) ? "重新启用" : "安装到本地", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.coolAccent)

            skillInstructions(skill)
        }
    }

    private func skillHeader(_ skill: WritingSkill) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [palette.coolAccent, palette.successAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: skill.category.symbolName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.textPrimary)

                    Text(skill.summary)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                WritingSkillTag(title: skill.category.title, symbolName: skill.category.symbolName)
                WritingSkillTag(title: skill.origin.title, symbolName: "shippingbox")
                WritingSkillTag(title: "\(skill.wordCount) 字", symbolName: "textformat.123")
                if skill.isEnabled {
                    WritingSkillTag(title: "已启用", symbolName: "checkmark.circle.fill", isActive: true)
                }
            }
        }
    }

    private func skillInstructions(_ skill: WritingSkill) -> some View {
        ScrollView {
            Text(skill.instructions)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(18)
        }
        .frame(minHeight: 320)
        .background(DashboardInsetPanelBackground(cornerRadius: 22, palette: palette))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    private func syncInstalledSelection() {
        if let selectedSkillID,
           appState.writingSkills.contains(where: { $0.id == selectedSkillID }) {
            return
        }

        selectedSkillID = appState.writingSkills.first?.id
    }

    private func handleSkillImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let skills = try WritingSkillImporting.skills(from: urls)
            appState.importWritingSkills(skills)
            selectedMode = .installed
            selectedSkillID = skills.first?.id
            statusMessage = "已导入并启用 \(skills.count) 个写作 Skill。"
        } catch {
            statusMessage = "导入 Skill 失败：\(error.localizedDescription)"
        }
    }
}

private enum WritingSkillLibraryMode: String, CaseIterable, Identifiable {
    case installed
    case marketplace

    var id: Self { self }

    var title: String {
        switch self {
        case .installed:
            return "本地 Skill"
        case .marketplace:
            return "Skill 广场"
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

private struct WritingSkillRow: View {
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

private struct WritingSkillTag: View {
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

private struct WritingSkillCreatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var title = ""
    @State private var summary = ""
    @State private var instructions = ""
    @State private var category: WritingSkillCategory = .custom

    let onCreate: (WritingSkill) -> Void

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("自建 Skill")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(palette.textPrimary)

                Text("把你自己的写作规则整理成一个可启用的 Skill。")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }

            TextField("Skill 名称", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("一句话说明", text: $summary)
                .textFieldStyle(.roundedBorder)

            Picker("分类", selection: $category) {
                ForEach(WritingSkillCategory.allCases) { category in
                    Label(category.title, systemImage: category.symbolName).tag(category)
                }
            }
            .pickerStyle(.menu)

            TextEditor(text: $instructions)
                .font(.system(size: 14, design: .serif))
                .frame(minHeight: 260)
                .scrollContentBackground(.hidden)
                .background(DashboardInsetPanelBackground(cornerRadius: 18, palette: palette))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(palette.stroke, lineWidth: 1)
                )

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("创建") {
                    let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCreate(
                        WritingSkill(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            summary: resolvedSummary.isEmpty ? String(trimmedInstructions.prefix(90)) : resolvedSummary,
                            instructions: trimmedInstructions,
                            category: category,
                            origin: .custom,
                            sourceName: "自建 Skill"
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.coolAccent)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560)
    }
}
