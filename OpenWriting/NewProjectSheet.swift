import SwiftUI

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var projectTitle = ""
    @State private var selectedLength: NovelLength = .long
    let onCreate: (String, NovelLength) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建项目")
                .font(.title2.weight(.semibold))

            Text("先输入项目名称，再选择短篇、中篇或长篇模式，系统会带上对应的结构模板和写作辅助。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                Text("项目名称")
                    .font(.subheadline.weight(.semibold))

                TextField("例如：雾港纪事", text: $projectTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .onSubmit(createProject)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("创作模式")
                    .font(.subheadline.weight(.semibold))

                Picker("创作模式", selection: $selectedLength) {
                    ForEach(NovelLength.allCases) { length in
                        Text(length.title).tag(length)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(selectedLength.title)
                            .font(.headline.weight(.bold))

                        Text(selectedLength.targetRangeSummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(selectedLength.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedLength.creationChecklist, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("创建", action: createProject)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 520, maxWidth: 620)
        .onAppear {
            DispatchQueue.main.async {
                isNameFieldFocused = true
            }
        }
    }

    private func createProject() {
        let trimmedTitle = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        onCreate(trimmedTitle, selectedLength)
        dismiss()
    }
}
