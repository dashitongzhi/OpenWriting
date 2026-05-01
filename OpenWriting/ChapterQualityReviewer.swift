import Foundation

// MARK: - Chapter Quality Review (Six-Dimensional Quality Check)

/// Post-chapter quality review system inspired by webnovel-writer's reviewer agent.
/// Checks chapters across 6 dimensions and produces structured feedback.

struct ChapterReviewResult: Codable, Hashable {
    let overallScore: Int
    let dimensionScores: [ReviewDimension: Int]
    let issues: [ReviewIssue]
    let hasBlockingIssues: Bool
    let antiPatterns: [String]

    var blockingIssues: [ReviewIssue] {
        issues.filter { $0.isBlocking }
    }

    var nonBlockingIssues: [ReviewIssue] {
        issues.filter { !$0.isBlocking }
    }

    var summary: String {
        var lines: [String] = ["综合评分: \(overallScore)/100"]

        if hasBlockingIssues {
            lines.append("⛔ 有 \(blockingIssues.count) 个阻断性问题需要修复：")
            for issue in blockingIssues {
                lines.append("  · [\(issue.dimension.displayName)] \(issue.description)")
            }
        } else {
            lines.append("✅ 无阻断性问题")
        }

        if !nonBlockingIssues.isEmpty {
            lines.append("📝 \(nonBlockingIssues.count) 条改进建议")
        }

        if !antiPatterns.isEmpty {
            lines.append("⚠️ 检测到 \(antiPatterns.count) 个 AI 味反模式")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Review Dimensions (6 dimensions)

enum ReviewDimension: String, CaseIterable, Codable, Identifiable {
    case settingConsistency = "setting"      // 设定一致性
    case timelineConsistency = "timeline"    // 时间线
    case narrativeContinuity = "continuity"  // 叙事连贯
    case characterConsistency = "character"  // 角色一致性
    case logicIntegrity = "logic"            // 逻辑
    case aiFlavor = "ai_flavor"              // AI味

    var id: Self { self }

    var displayName: String {
        switch self {
        case .settingConsistency: return "🔒 设定一致性"
        case .timelineConsistency: return "⏰ 时间线"
        case .narrativeContinuity: return "🔗 叙事连贯"
        case .characterConsistency: return "🎭 角色一致性"
        case .logicIntegrity: return "📐 逻辑"
        case .aiFlavor: return "🤖 AI味"
        }
    }

    var checkDescription: String {
        switch self {
        case .settingConsistency:
            return "战力等级、地点位置、道具状态、能力范围是否与已有设定矛盾"
        case .timelineConsistency:
            return "时间线是否跳跃、倒计时是否正确推进、角色是否瞬移"
        case .narrativeContinuity:
            return "上一章钩子是否被回应、场景切换是否有桥梁、情绪弧线是否连续"
        case .characterConsistency:
            return "对白风格是否符合性格、行为是否符合动机、是否拥有不该有的信息"
        case .logicIntegrity:
            return "因果关系是否成立、决策是否有动机、战斗结果是否匹配战力"
        case .aiFlavor:
            return "AI 高频词、同构句式、情绪标签化、模板化对白、解释性旁白"
        }
    }
}

// MARK: - Review Issue

struct ReviewIssue: Identifiable, Codable, Hashable {
    let id: String
    let dimension: ReviewDimension
    let severity: ReviewSeverity
    let description: String
    let evidence: String
    let fixHint: String
    let location: String
    var isBlocking: Bool { severity == .critical }

    init(
        id: String = UUID().uuidString,
        dimension: ReviewDimension,
        severity: ReviewSeverity,
        description: String,
        evidence: String = "",
        fixHint: String = "",
        location: String = ""
    ) {
        self.id = id
        self.dimension = dimension
        self.severity = severity
        self.description = description
        self.evidence = evidence
        self.fixHint = fixHint
        self.location = location
    }
}

enum ReviewSeverity: String, Codable, CaseIterable {
    case critical
    case high
    case medium
    case low

    var penalty: Int {
        switch self {
        case .critical: return 35
        case .high: return 15
        case .medium: return 6
        case .low: return 2
        }
    }

    var displayName: String {
        switch self {
        case .critical: return "严重"
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }
}

// MARK: - Quality Reviewer

enum ChapterQualityReviewer {

    // MARK: - System Prompt for AI Review

    static let reviewSystemPrompt = """
    你是一位中文长篇小说的质量审查员。你的任务是对候选正文进行六维质量审查。
    必须遵守：
    1. 严格按 6 个维度逐一检查，不跳过任何维度。
    2. 每个问题必须提供原文引用作为证据，不允许主观"感觉不好"。
    3. 问题严重性分为：critical（阻断）、high（高）、medium（中）、low（低）。
    4. critical 级别问题会阻断下一章的创作，必须修复。
    5. 特别关注 AI 味问题：高频AI词汇、同构句式、情绪标签化、模板化对白。
    6. 必须以 JSON 格式输出审查结果，不要解释。
    """

    // MARK: - User Prompt Builder

    static func reviewUserPrompt(
        project: NovelProject,
        chapterDraft: String,
        memoryContext: String
    ) -> String {
        """
        项目名称：\(project.title)
        类型：\(project.genre)
        创作规模：\(project.storyLength.title)
        当前章节：\(project.currentChapterSummary)
        本章目标：\(project.chapterFocus)

        作品大纲（节选）：
        \(excerpt(project.outlineText, limit: 1500))

        全局记忆：
        \(normalized(memoryContext, fallback: "暂无全局记忆。"))

        章节树关键约束：
        \(normalized(project.outlineSummary, fallback: "暂无章节树约束。"))

        角色弧线记录：
        \(normalized(project.characterArcNotes, fallback: "暂无角色弧线记录。"))

        伏笔与回收记录：
        \(normalized(project.foreshadowNotes, fallback: "暂无伏笔回收记录。"))

        待审查正文：
        \(chapterDraft)

        审查要求：
        请对上述正文进行六维质量审查。

        审查维度：
        1. 设定一致性 — 战力/地点/道具/能力是否与已有设定矛盾
        2. 时间线 — 时间线是否连贯，是否有不合理跳跃
        3. 叙事连贯 — 场景切换、情绪弧线、上文承接是否通顺
        4. 角色一致性 — 对白风格、行为动机、信息获取是否符合人设
        5. 逻辑 — 因果关系、决策动机、战斗结果是否合理
        6. AI味 — 是否有AI高频词、同构句式、情绪标签化、模板化对白

        AI味具体检查项：
        - 词汇："缓缓""淡淡""微微"+动词 500字内出现3次以上 → critical
        - 模板表达："眸中闪过""瞳孔微缩""嘴角微微上扬" → high
        - 句式：连续3段以上相同句式结构 → high
        - 叙事：每段结尾都是总结句 → medium
        - 情绪：直接写"他感到愤怒"而非行为暗示 → high
        - 对白：只有信息传递功能、没有个人特色的对白 → medium
        - 解释性旁白："他不知道的是..." → medium

        输出格式（严格 JSON）：
        {
          "overall_score": 85,
          "dimension_scores": {
            "setting": 90,
            "timeline": 85,
            "continuity": 80,
            "character": 88,
            "logic": 85,
            "ai_flavor": 75
          },
          "issues": [
            {
              "dimension": "ai_flavor",
              "severity": "high",
              "description": "问题描述",
              "evidence": "原文引用",
              "fix_hint": "修复建议",
              "location": "第N段"
            }
          ],
          "anti_patterns": ["应避免的AI模式1", "应避免的AI模式2"]
        }

        如果没有问题，issues 数组为空，所有维度分数 95+。
        """
    }

    // MARK: - Parse Review Result

    static func parseReviewResult(from jsonString: String) -> ChapterReviewResult {
        let cleaned = jsonString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallbackParse(from: cleaned)
        }

        let overallScore = json["overall_score"] as? Int ?? 80

        // Parse dimension scores
        var dimensionScores: [ReviewDimension: Int] = [:]
        if let scores = json["dimension_scores"] as? [String: Int] {
            for dim in ReviewDimension.allCases {
                dimensionScores[dim] = scores[dim.rawValue] ?? 80
            }
        }

        // Parse issues
        var issues: [ReviewIssue] = []
        if let issueList = json["issues"] as? [[String: Any]] {
            for issueDict in issueList {
                guard let dimStr = issueDict["dimension"] as? String,
                      let dimension = ReviewDimension(rawValue: dimStr),
                      let sevStr = issueDict["severity"] as? String,
                      let severity = ReviewSeverity(rawValue: sevStr),
                      let description = issueDict["description"] as? String else {
                    continue
                }
                issues.append(ReviewIssue(
                    dimension: dimension,
                    severity: severity,
                    description: description,
                    evidence: issueDict["evidence"] as? String ?? "",
                    fixHint: issueDict["fix_hint"] as? String ?? "",
                    location: issueDict["location"] as? String ?? ""
                ))
            }
        }

        // Parse anti-patterns
        let antiPatterns = json["anti_patterns"] as? [String] ?? []

        let hasBlocking = issues.contains { $0.isBlocking }

        return ChapterReviewResult(
            overallScore: overallScore,
            dimensionScores: dimensionScores,
            issues: issues,
            hasBlockingIssues: hasBlocking,
            antiPatterns: antiPatterns
        )
    }

    // MARK: - Fallback Parse (text-based)

    private static func fallbackParse(from text: String) -> ChapterReviewResult {
        // If JSON parsing fails, return a permissive result with a warning
        return ChapterReviewResult(
            overallScore: 75,
            dimensionScores: [:],
            issues: [ReviewIssue(
                dimension: .aiFlavor,
                severity: .low,
                description: "审查结果解析失败，请人工检查正文质量。",
                evidence: String(text.prefix(200))
            )],
            hasBlockingIssues: false,
            antiPatterns: []
        )
    }

    // MARK: - AI Flavor Pre-Check (Local, No API)

    /// Quick local check for obvious AI-flavor patterns before sending to API.
    static func quickAIFlavorCheck(text: String) -> [String] {
        var patterns: [String] = []
        let chars = Array(text)

        // Check for "缓缓/淡淡/微微+verb" density
        let slowAdverbs = ["缓缓", "淡淡", "微微", "轻轻", "默默", "静静"]
        for adverb in slowAdverbs {
            var count = 0
            var searchStart = text.startIndex
            while let range = text.range(of: adverb, range: searchStart..<text.endIndex) {
                count += 1
                searchStart = range.upperBound
            }
            if count >= 3 {
                patterns.append("「\(adverb)」出现 \(count) 次，建议替换部分为更具体的动作描写")
            }
        }

        // Check for template expressions
        let templates = ["眸中闪过", "瞳孔微缩", "嘴角微微上扬", "眼中闪过一丝", "不由得", "竟然"]
        for template in templates {
            var count = 0
            var searchStart = text.startIndex
            while let range = text.range(of: template, range: searchStart..<text.endIndex) {
                count += 1
                searchStart = range.upperBound
            }
            if count >= 2 {
                patterns.append("模板表达「\(template)」出现 \(count) 次，建议多样化描写")
            }
        }

        // Check for "他不知道的是" pattern
        let narratorMarkers = ["他不知道的是", "她不知道的是", "殊不知", "然而事实上"]
        for marker in narratorMarkers {
            if text.contains(marker) {
                patterns.append("解释性旁白「\(marker)」出现，考虑用场景展示替代")
            }
        }

        // Check for emotion labeling
        let emotionLabels = ["感到愤怒", "感到悲伤", "感到恐惧", "感到惊讶", "感到开心", "感到不安"]
        for label in emotionLabels {
            if text.contains(label) {
                patterns.append("情绪标签化「\(label)」，建议改用行为/动作暗示情绪")
            }
        }

        return patterns
    }

    // MARK: - Helpers

    private static func excerpt(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed.isEmpty ? "暂无" : trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    private static func normalized(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
