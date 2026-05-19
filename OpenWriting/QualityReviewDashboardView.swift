import SwiftUI

// MARK: - Quality Review Dashboard View
//
// Full-screen dashboard for displaying chapter quality review results.
// Uses glassmorphism style consistent with the app's DashboardPalette.

import SwiftUI

// MARK: - Main Dashboard View

struct QualityReviewDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let result: ChapterReviewResult
    let chapterTitle: String

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Score gauge + grade + pass status
                scoreHeroSection

                // Dimension scores (9 bars)
                DimensionScoresPanel(
                    dimensionScores: result.dimensionScores,
                    palette: palette
                )

                // Issues (blocking + non-blocking)
                IssuesSection(
                    blockingIssues: result.blockingIssues,
                    nonBlockingIssues: result.nonBlockingIssues,
                    palette: palette
                )

                // Anti-patterns
                if !result.antiPatterns.isEmpty {
                    AntiPatternsSection(
                        antiPatterns: result.antiPatterns,
                        palette: palette
                    )
                }

                // Summary
                ReviewSummarySection(
                    grade: result.grade,
                    overallSummary: result.overallSummary,
                    palette: palette
                )
            }
            .padding(28)
        }
        .background(PageBackground())
        .navigationTitle("质量审查")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("质量审查报告")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: 12) {
                if !chapterTitle.isEmpty {
                    Label(chapterTitle, systemImage: "doc.text")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.coolAccent)
                }

                Label(
                    "共 \(result.issues.count) 个问题",
                    systemImage: "exclamationmark.circle"
                )
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)

                if result.hasBlockingIssues {
                    Label(
                        "\(result.blockingIssues.count) 个阻断",
                        systemImage: "xmark.shield.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                }
            }
        }
    }

    // MARK: - Score Hero

    private var scoreHeroSection: some View {
        HStack(spacing: 32) {
            // Gauge ring
            ScoreGaugeRing(
                score: result.overallScore,
                grade: result.grade,
                palette: palette
            )

            VStack(alignment: .leading, spacing: 16) {
                // Pass status
                PassStatusBadge(isPassed: result.isPassed, palette: palette)

                // Grade
                HStack(spacing: 10) {
                    Text("等级")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)

                    Text(result.grade.rawValue)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(gradeColor)
                }

                // Quick stats
                VStack(alignment: .leading, spacing: 6) {
                    if result.hasBlockingIssues {
                        statRow(
                            icon: "xmark.octagon.fill",
                            color: .red,
                            text: "\(result.blockingIssues.count) 个阻断性问题"
                        )
                    }

                    statRow(
                        icon: "exclamationmark.triangle.fill",
                        color: palette.warmAccent,
                        text: "\(result.nonBlockingIssues.filter { $0.severity == .high }.count) 个高优先级"
                    )

                    statRow(
                        icon: "info.circle.fill",
                        color: palette.coolAccent,
                        text: "\(result.nonBlockingIssues.filter { $0.severity == .medium }.count) 个中优先级"
                    )

                    statRow(
                        icon: "lightbulb.fill",
                        color: palette.textSecondary,
                        text: "\(result.nonBlockingIssues.filter { $0.severity == .low }.count) 个低优先级"
                    )

                    if !result.antiPatterns.isEmpty {
                        statRow(
                            icon: "wand.and.stars",
                            color: palette.warmAccent,
                            text: "\(result.antiPatterns.count) 个 AI 味反模式"
                        )
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .background(
            GlassPanelBackground(
                cornerRadius: 24,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        gradeColor.opacity(palette.isDark ? 0.10 : 0.06),
                        palette.coolAccent.opacity(palette.isDark ? 0.06 : 0.03),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var gradeColor: Color {
        switch result.grade {
        case .excellent: return palette.successAccent
        case .good:      return palette.coolAccent
        case .fair:      return palette.warmAccent
        case .poor:      return Color.red
        }
    }

    @ViewBuilder
    private func statRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.textPrimary)
        }
    }
}

// MARK: - Preview

#Preview("Quality Review Dashboard — Passed") {
    QualityReviewDashboardView(
        result: ChapterReviewResult(
            overallScore: 82,
            dimensionScores: [
                .settingConsistency: 9,
                .timelineConsistency: 8,
                .narrativeContinuity: 8,
                .characterConsistency: 9,
                .logicIntegrity: 8,
                .aiFlavor: 7,
                .highPointDensity: 8,
                .pacing: 7,
                .readerPull: 8
            ],
            issues: [
                ReviewIssue(
                    dimension: .aiFlavor,
                    severity: .high,
                    description: "「缓缓」一词在500字内出现4次，建议替换部分为更具体的动作描写",
                    evidence: "他缓缓站起身来…她缓缓转过头…",
                    fixHint: "将部分「缓缓」替换为具体动作，如「他撑着膝盖站起来」",
                    location: "第3-5段"
                ),
                ReviewIssue(
                    dimension: .characterConsistency,
                    severity: .medium,
                    description: "主角的对白风格过于正式，与之前章节中口语化的人设不一致",
                    evidence: "\"此事需要从长计议。\"",
                    fixHint: "改为更口语化的表达，如「这事儿急不得，咱慢慢想。」",
                    location: "第12段"
                ),
                ReviewIssue(
                    dimension: .pacing,
                    severity: .medium,
                    description: "前半章节奏偏慢，铺垫过长",
                    evidence: "",
                    fixHint: "将前两段的环境描写压缩为一段",
                    location: "前半部分"
                ),
                ReviewIssue(
                    dimension: .highPointDensity,
                    severity: .low,
                    description: "章中缺少小型爽点，可以增加一个微兑现",
                    evidence: "",
                    fixHint: "在主角遭遇困境时加入一个小反转",
                    location: "第8段附近"
                ),
                ReviewIssue(
                    dimension: .readerPull,
                    severity: .low,
                    description: "章末钩子可以更强烈一些",
                    evidence: "",
                    fixHint: "在最后一句加入一个悬念或反转暗示",
                    location: "最后一段"
                )
            ],
            hasBlockingIssues: false,
            antiPatterns: [
                "「缓缓」+动词 出现频率过高，建议多样化动作描写",
                "连续3段以「他」开头，建议变化段落起始方式",
                "情绪标签化「感到不安」，建议改用行为/动作暗示情绪"
            ],
            overallSummary: "本章整体质量良好，叙事连贯，角色行为基本符合人设。主要问题集中在 AI 味痕迹和节奏把控上，建议重点修正高频 AI 用词，并适当加快前半段节奏。章末钩子力度可以再加强。"
        ),
        chapterTitle: "第十二章 · 暗夜追踪"
    )
    .frame(width: 780, height: 900)
}

#Preview("Quality Review Dashboard — Failed") {
    QualityReviewDashboardView(
        result: ChapterReviewResult(
            overallScore: 35,
            dimensionScores: [
                .settingConsistency: 4,
                .timelineConsistency: 3,
                .narrativeContinuity: 5,
                .characterConsistency: 3,
                .logicIntegrity: 2,
                .aiFlavor: 3,
                .highPointDensity: 4,
                .pacing: 5,
                .readerPull: 4
            ],
            issues: [
                ReviewIssue(
                    dimension: .logicIntegrity,
                    severity: .critical,
                    description: "主角在失去全部修为的情况下使用了高阶法术，与设定严重矛盾",
                    evidence: "李默运起全身真气，一掌拍出——「天罡灭世掌」",
                    fixHint: "需要先安排恢复修为的情节，或改为使用低阶手段脱困",
                    location: "第18段"
                ),
                ReviewIssue(
                    dimension: .settingConsistency,
                    severity: .critical,
                    description: "角色出现在两个相距千里的地点，存在瞬移问题",
                    evidence: "（上一段）李默在青州城…（下一段）李默踏入幽州密林…",
                    fixHint: "添加过渡段落交代赶路过程",
                    location: "第22-23段"
                ),
                ReviewIssue(
                    dimension: .timelineConsistency,
                    severity: .high,
                    description: "时间线矛盾：上一章说「三天后」，本章开头却写「第二天清晨」",
                    evidence: "",
                    fixHint: "统一时间表述",
                    location: "开头"
                ),
                ReviewIssue(
                    dimension: .aiFlavor,
                    severity: .high,
                    description: "全章存在大量模板化表达",
                    evidence: "",
                    fixHint: "参见反模式列表逐一修正",
                    location: "全文"
                )
            ],
            hasBlockingIssues: true,
            antiPatterns: [
                "「缓缓」「淡淡」「微微」出现超过10次",
                "「眸中闪过」等模板表达出现5次以上",
                "每段结尾都是总结性旁白",
                "情绪全部直接标注而非行为暗示"
            ],
            overallSummary: "本章存在严重逻辑矛盾和设定冲突，无法通过审核。需要先修复两个阻断性问题，然后处理高优先级的 AI 味和时间线问题。建议大幅重写相关段落。"
        ),
        chapterTitle: "第十五章 · 绝境求生"
    )
    .frame(width: 780, height: 1000)
}