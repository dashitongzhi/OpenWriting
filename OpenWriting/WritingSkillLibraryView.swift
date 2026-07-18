import SwiftUI
import UniformTypeIdentifiers

struct WritingSkillLibraryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState

    @State private var selectedMode: WritingSkillLibraryMode = .marketplace
    @State private var selectedSkillID: WritingSkill.ID?
    @State private var selectedMarketplaceSkillID: WritingSkill.ID = WritingSkillMarketplace.featured.first?.id ?? ""
    @State private var isImportingSkills = false
    @State private var isCreatorPresented = false
    @State private var statusMessage = "安装并启用的 Skill 会参与 AI 续写、修订、大纲生成与质量审查。"

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var selectedSkill: WritingSkill? {
        guard let selectedSkillID else { return appState.writingSkills.first }
        return appState.writingSkills.first { $0.id == selectedSkillID } ?? appState.writingSkills.first
    }

    private var selectedMarketplaceSkill: WritingSkill? {
        appState.marketplaceWritingSkills.first { $0.id == selectedMarketplaceSkillID }
            ?? appState.marketplaceWritingSkills.first
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
            title: "Skill 市场",
            subtitle: "发现、上传和发布写作能力。当前版本先提供本机市场目录，并为后续公开审核与同步保留接入接口。"
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
            WritingSkillPublisherSheet(
                defaultPublisherName: appState.activeAccount?.displayName ?? "本机创作者"
            ) { skill, publisherName, version in
                let published = appState.publishWritingSkills(
                    [skill],
                    publisherName: publisherName,
                    version: version
                )
                selectedMode = .marketplace
                selectedMarketplaceSkillID = published.first?.id ?? skill.id
                statusMessage = "已发布并启用「\(skill.title)」，它现在出现在本机 Skill 市场。"
            }
        }
        .onAppear {
            syncInstalledSelection()
            syncMarketplaceSelection()
        }
        .onChange(of: appState.writingSkills) { _, _ in
            syncInstalledSelection()
            syncMarketplaceSelection()
        }
    }

    private var skillOverviewRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WorkspaceMetricBadge(label: "已安装", value: "\(appState.writingSkills.count)")
                WorkspaceMetricBadge(label: "已启用", value: "\(appState.enabledWritingSkills.count)")
                WorkspaceMetricBadge(label: "市场目录", value: "\(appState.marketplaceWritingSkills.count)")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button {
                        isImportingSkills = true
                    } label: {
                        Label("上传 Skill", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.coolAccent)

                    Button {
                        isCreatorPresented = true
                    } label: {
                        Label("发布 Skill", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isImportingSkills = true
                    } label: {
                        Label("上传 Skill", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.coolAccent)

                    Button {
                        isCreatorPresented = true
                    } label: {
                        Label("发布 Skill", systemImage: "plus")
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
                    "从 Skill 市场安装一项写作能力",
                    "上传 Markdown、TXT 或 JSON 后发布为本机市场条目",
                    "启用后可随时停用，不会影响已保存正文"
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

                if let selectedMarketplaceSkill {
                    marketplaceDetail(selectedMarketplaceSkill)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            VStack(alignment: .leading, spacing: 24) {
                marketplaceList
                if let selectedMarketplaceSkill {
                    marketplaceDetail(selectedMarketplaceSkill)
                }
            }
        }
    }

    private var marketplaceList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("市场目录")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(appState.marketplaceWritingSkills) { skill in
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

            if let listing = skill.marketplaceListing {
                Label(
                    "\(listing.publisherName) · \(listing.source.title) · v\(listing.version) · \(listing.publishedAtLabel)",
                    systemImage: "person.crop.circle"
                )
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
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

    private func syncMarketplaceSelection() {
        if appState.marketplaceWritingSkills.contains(where: { $0.id == selectedMarketplaceSkillID }) {
            return
        }

        selectedMarketplaceSkillID = appState.marketplaceWritingSkills.first?.id ?? ""
    }

    private func handleSkillImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let skills = try WritingSkillImporting.skills(from: urls)
            let published = appState.publishWritingSkills(
                skills,
                publisherName: appState.activeAccount?.displayName ?? "本机创作者"
            )
            selectedMode = .marketplace
            selectedMarketplaceSkillID = published.first?.id ?? ""
            statusMessage = "已上传并发布 \(published.count) 个 Skill 到本机市场，同时完成安装和启用。"
        } catch {
            statusMessage = "导入 Skill 失败：\(error.localizedDescription)"
        }
    }
}
