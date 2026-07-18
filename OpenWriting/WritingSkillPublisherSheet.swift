import SwiftUI

struct WritingSkillPublisherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var title = ""
    @State private var summary = ""
    @State private var instructions = ""
    @State private var category: WritingSkillCategory = .custom
    @State private var publisherName: String
    @State private var version = "1.0.0"

    let onPublish: (WritingSkill, String, String) -> Void

    init(
        defaultPublisherName: String,
        onPublish: @escaping (WritingSkill, String, String) -> Void
    ) {
        _publisherName = State(initialValue: defaultPublisherName)
        self.onPublish = onPublish
    }

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publisherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("发布 Skill")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(palette.textPrimary)

                Text("把写作规则发布到本机 Skill 市场。公开社区将在接入账号同步与审核服务后开放。")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack(spacing: 12) {
                TextField("发布者", text: $publisherName)
                    .textFieldStyle(.roundedBorder)

                TextField("版本，例如 1.0.0", text: $version)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
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

                Button("发布并启用") {
                    let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    onPublish(
                        WritingSkill(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            summary: resolvedSummary.isEmpty ? String(trimmedInstructions.prefix(90)) : resolvedSummary,
                            instructions: trimmedInstructions,
                            category: category,
                            origin: .custom,
                            sourceName: "自建 Skill"
                        ),
                        publisherName.trimmingCharacters(in: .whitespacesAndNewlines),
                        version.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.coolAccent)
                .disabled(!canPublish)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 620)
    }
}
