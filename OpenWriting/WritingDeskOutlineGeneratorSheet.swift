import SwiftUI

struct WritingDeskOutlineGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let projectTitle: String
    let storyLength: NovelLength
    @Binding var profile: OutlineGenerationProfile
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    minimumChecklist

                    WritingDeskOutlinePromptGroupCard(
                        title: "小说框架",
                        description: "先把故事怎么开头、怎么推进、最后想走到哪里写清楚。"
                    ) {
                        WritingDeskOutlineField(
                            title: "总体流程",
                            placeholder: "起始、大致经过、预期结果",
                            isRequired: true,
                            minHeight: 138,
                            text: $profile.storyFlow
                        )

                        WritingDeskOutlineField(
                            title: "主要卖点",
                            placeholder: "金手指、设定亮点、爽点",
                            minHeight: 96,
                            text: $profile.sellingPoints
                        )

                        WritingDeskOutlineField(
                            title: "关键事件",
                            placeholder: "激励事件、低谷、高潮等",
                            minHeight: 108,
                            text: $profile.keyEvents
                        )

                        WritingDeskOutlineField(
                            title: "故事节奏",
                            placeholder: "慢热、快节奏、持续高压等",
                            isCompact: true,
                            text: $profile.storyPacing
                        )

                        WritingDeskOutlineField(
                            title: "重要伏笔",
                            placeholder: "需要提前埋下、后续必须回收的点",
                            minHeight: 96,
                            text: $profile.foreshadowingNotes
                        )
                    }

                    WritingDeskOutlinePromptGroupCard(
                        title: "主要世界观",
                        description: "把背景、势力、规则和境界体系这类基础约束说明白。"
                    ) {
                        WritingDeskOutlineField(
                            title: "世界观描述",
                            placeholder: "背景、势力、规则、境界体系",
                            isRequired: true,
                            minHeight: 168,
                            text: $profile.worldDescription
                        )
                    }

                    WritingDeskOutlinePromptGroupCard(
                        title: "核心人物设定",
                        description: "这里决定主角底色、人物动力、关键关系和主要对抗。"
                    ) {
                        WritingDeskOutlineField(
                            title: "主角性格标签",
                            placeholder: "主角的核心性格和人物底色",
                            isRequired: true,
                            isCompact: true,
                            text: $profile.protagonistTraits
                        )

                        WritingDeskOutlineField(
                            title: "角色动机与欲望",
                            placeholder: "主角和重要人物各自想要什么、害怕什么",
                            minHeight: 96,
                            text: $profile.motivations
                        )

                        WritingDeskOutlineField(
                            title: "人物关系图谱",
                            placeholder: "盟友、师徒、家族、情感线、敌对链条",
                            minHeight: 96,
                            text: $profile.relationshipMap
                        )

                        WritingDeskOutlineField(
                            title: "反派的描绘",
                            placeholder: "反派目标、手段、威压感、与主角的矛盾",
                            minHeight: 96,
                            text: $profile.antagonistPortrait
                        )
                    }

                    WritingDeskOutlinePromptGroupCard(
                        title: "输出控制参数",
                        description: "决定这本书要写多长，以及最后收束到什么类型的结局。"
                    ) {
                        WritingDeskOutlineField(
                            title: "预期字数",
                            placeholder: "例如：50万 / 100万 / 200万",
                            isRequired: true,
                            isCompact: true,
                            text: $profile.expectedLength
                        )

                        WritingDeskOutlineField(
                            title: "结局偏好",
                            placeholder: "例如：好结局 / 坏结局 / 开放式",
                            isRequired: true,
                            isCompact: true,
                            text: $profile.endingPreference
                        )
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 860, minHeight: 820)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("生成大纲")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                Text(projectTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("当前模式：\(storyLength.title) · \(storyLength.summary)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("最简可用版至少准备 5 项：故事怎么开头推进到哪里、世界规则、主角底色、想写多长、想要什么结局。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Text("必填 \(profile.completedRequiredFieldCount)/5")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 10) {
                    Button("关闭") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button(isGenerating ? "正在生成…" : "生成大纲") {
                        dismiss()
                        onGenerate()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || !profile.hasMinimumRequirements)
                }
            }
        }
    }

    private var minimumChecklist: some View {
        HStack(spacing: 10) {
            Text(profile.minimumRequirementSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(profile.hasMinimumRequirements ? .primary : Color.orange)

            Spacer()

            Text("扩展项 \(profile.filledOptionalFieldCount)/7")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.62))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WritingDeskOutlinePromptGroupCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WritingDeskOutlineField: View {
    let title: String
    let placeholder: String
    var isRequired = false
    var isCompact = false
    var minHeight: CGFloat = 96
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if isRequired {
                    Text("必填")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                }
            }

            if isCompact {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                WritingDeskTextSurface(
                    text: $text,
                    placeholder: placeholder,
                    minHeight: minHeight
                )
            }
        }
    }
}
