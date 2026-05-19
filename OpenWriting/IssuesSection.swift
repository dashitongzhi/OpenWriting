import SwiftUI

// MARK: - Issues Section

struct IssuesSection: View {
    let blockingIssues: [ReviewIssue]
    let nonBlockingIssues: [ReviewIssue]
    let palette: DashboardPalette

    private var highIssues: [ReviewIssue] { nonBlockingIssues.filter { $0.severity == .high } }
    private var mediumIssues: [ReviewIssue] { nonBlockingIssues.filter { $0.severity == .medium } }
    private var lowIssues: [ReviewIssue] { nonBlockingIssues.filter { $0.severity == .low } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Blocking issues
            if !blockingIssues.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.shield.fill")
                            .foregroundStyle(Color.red)

                        Text("⛔ 阻断性问题（\(blockingIssues.count)）")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.red)
                    }

                    Text("以下问题会阻断下一章的创作，必须修复后才能继续。")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                    ForEach(blockingIssues) { issue in
                        BlockingIssueCard(issue: issue, palette: palette)
                    }
                }
            }

            // Non-blocking issues grouped by severity
            if !nonBlockingIssues.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundStyle(palette.coolAccent)

                        Text("📝 改进建议（\(nonBlockingIssues.count)）")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                    }

                    // High
                    if !highIssues.isEmpty {
                        severityGroup(
                            title: "高优先级",
                            icon: "exclamationmark.triangle.fill",
                            color: palette.warmAccent,
                            issues: highIssues
                        )
                    }

                    // Medium
                    if !mediumIssues.isEmpty {
                        severityGroup(
                            title: "中优先级",
                            icon: "info.circle.fill",
                            color: palette.coolAccent,
                            issues: mediumIssues
                        )
                    }

                    // Low
                    if !lowIssues.isEmpty {
                        severityGroup(
                            title: "低优先级",
                            icon: "lightbulb.fill",
                            color: palette.textSecondary,
                            issues: lowIssues
                        )
                    }
                }
            }

            // No issues at all
            if blockingIssues.isEmpty && nonBlockingIssues.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.successAccent)
                        .font(.title3)

                    Text("没有发现任何问题，质量优秀！")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.successAccent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.successAccent.opacity(palette.isDark ? 0.10 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.successAccent.opacity(0.25), lineWidth: 1)
                )
            }
        }
        .padding(20)
        .background(
            GlassPanelBackground(
                cornerRadius: 22,
                palette: palette,
                tint: LinearGradient(
                    colors: [
                        palette.warmAccent.opacity(palette.isDark ? 0.06 : 0.04),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func severityGroup(
        title: String,
        icon: String,
        color: Color,
        issues: [ReviewIssue]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)

                Text("\(title)（\(issues.count)）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }

            ForEach(issues) { issue in
                NonBlockingIssueRow(issue: issue, palette: palette)
            }
        }
    }
}