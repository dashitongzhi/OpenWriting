import Foundation

// MARK: - Unified Chapter Quality Review System
//
// Merges the best of:
//   • ChapterQualityReviewer (6 dimensions, JSON output, AI-flavor pre-check)
//   • QualityReviewService (legacy: highPoint, pacing, readerPull)
//   • webnovel-writer scoring methodology (100-base with severity penalties)
//   • Blocking/non-blocking classification (auto-reject on blocking issues)
//
// This is the single source of truth for quality review.

// MARK: - Review Dimensions (9 unified dimensions)

enum ReviewDimension: String, CaseIterable, Codable, Identifiable {
    // From ChapterQualityReviewer (original 6)
    case settingConsistency = "setting"      // 设定一致性
    case timelineConsistency = "timeline"    // 时间线
    case narrativeContinuity = "continuity"  // 叙事连贯
    case characterConsistency = "character"  // 角色一致性
    case logicIntegrity = "logic"            // 逻辑
    case aiFlavor = "ai_flavor"              // AI味

    // From QualityReviewService (merged 3)
    case highPointDensity = "high_point"     // 爽点密度
    case pacing = "pacing"                   // 节奏比例
    case readerPull = "reader_pull"          // 追读力

    var id: Self { self }

    var displayName: String {
        switch self {
        case .settingConsistency: return "🔒 设定一致性"
        case .timelineConsistency: return "⏰ 时间线"
        case .narrativeContinuity: return "🔗 叙事连贯"
        case .characterConsistency: return "🎭 角色一致性"
        case .logicIntegrity: return "📐 逻辑"
        case .aiFlavor: return "🤖 AI味"
        case .highPointDensity: return "🎯 爽点密度"
        case .pacing: return "📊 节奏比例"
        case .readerPull: return "🪝 追读力"
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
        case .highPointDensity:
            return "章节中是否有足够的吸引力元素让读者想继续读下去"
        case .pacing:
            return "主线推进、感情线、世界观扩展的比例是否合理"
        case .readerPull:
            return "章末钩子强度、期待管理、微兑现是否到位"
        }
    }

    /// Legacy 6 dimensions used by the original ChapterQualityReviewer and WritingDeskView.
    static var legacySixDimensions: [ReviewDimension] {
        [.settingConsistency, .timelineConsistency, .narrativeContinuity,
         .characterConsistency, .logicIntegrity, .aiFlavor]
    }

    /// All 9 unified dimensions.
    static var allUnifiedDimensions: [ReviewDimension] {
        Array(ReviewDimension.allCases)
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

    /// Whether this issue blocks chapter progression (critical severity).
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

// MARK: - Review Severity (webnovel-writer penalty model)

enum ReviewSeverity: String, Codable, CaseIterable {
    case critical    // blocking — auto-rejects chapter
    case high        // non-blocking, must address
    case medium      // non-blocking, should address
    case low         // non-blocking, suggestion

    /// Penalty points deducted from 100-base score (webnovel-writer methodology).
    var penalty: Int {
        switch self {
        case .critical: return 35
        case .high:     return 15
        case .medium:   return 6
        case .low:      return 2
        }
    }

    var displayName: String {
        switch self {
        case .critical: return "严重"
        case .high:     return "高"
        case .medium:   return "中"
        case .low:      return "低"
        }
    }
}

// MARK: - Unified Review Result

/// Primary output of the unified quality review system.
/// Uses 100-base scoring with severity penalties (webnovel-writer methodology).
struct ChapterReviewResult: Codable, Hashable {
    /// Computed score: 100 minus sum of issue penalties, clamped to 0...100.
    let overallScore: Int
    /// Per-dimension scores (1-10 scale from AI, or computed).
    let dimensionScores: [ReviewDimension: Int]
    /// All found issues, with severity and blocking classification.
    let issues: [ReviewIssue]
    /// Whether any critical/blocking issues exist (auto-reject flag).
    let hasBlockingIssues: Bool
    /// Accumulated AI-flavor anti-patterns for memory system.
    let antiPatterns: [String]
    /// Overall narrative summary from the reviewer.
    let overallSummary: String

    // MARK: Codable — backward-compatible (handles old data missing `overallSummary`)

    enum CodingKeys: String, CodingKey {
        case overallScore
        case dimensionScores
        case issues
        case hasBlockingIssues
        case antiPatterns
        case overallSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overallScore = try container.decode(Int.self, forKey: .overallScore)
        dimensionScores = try container.decode([ReviewDimension: Int].self, forKey: .dimensionScores)
        issues = try container.decode([ReviewIssue].self, forKey: .issues)
        hasBlockingIssues = try container.decode(Bool.self, forKey: .hasBlockingIssues)
        antiPatterns = try container.decodeIfPresent([String].self, forKey: .antiPatterns) ?? []
        overallSummary = try container.decodeIfPresent(String.self, forKey: .overallSummary) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overallScore, forKey: .overallScore)
        try container.encode(dimensionScores, forKey: .dimensionScores)
        try container.encode(issues, forKey: .issues)
        try container.encode(hasBlockingIssues, forKey: .hasBlockingIssues)
        try container.encode(antiPatterns, forKey: .antiPatterns)
        try container.encode(overallSummary, forKey: .overallSummary)
    }

    // MARK: Memberwise init

    init(
        overallScore: Int,
        dimensionScores: [ReviewDimension: Int],
        issues: [ReviewIssue],
        hasBlockingIssues: Bool,
        antiPatterns: [String],
        overallSummary: String = ""
    ) {
        self.overallScore = overallScore
        self.dimensionScores = dimensionScores
        self.issues = issues
        self.hasBlockingIssues = hasBlockingIssues
        self.antiPatterns = antiPatterns
        self.overallSummary = overallSummary
    }

    // MARK: Blocking / Non-blocking classification

    var blockingIssues: [ReviewIssue] {
        issues.filter { $0.isBlocking }
    }

    var nonBlockingIssues: [ReviewIssue] {
        issues.filter { !$0.isBlocking }
    }

    func passes(minimumScore: Int) -> Bool {
        !hasBlockingIssues && overallScore >= minimumScore
    }

    /// Whether the chapter passes review under the legacy default threshold.
    var isPassed: Bool {
        passes(minimumScore: 60)
    }

    // MARK: Grade (for UI display)

    var grade: ReviewGrade {
        switch overallScore {
        case 85...100: return .excellent
        case 70..<85:  return .good
        case 50..<70:  return .fair
        default:       return .poor
        }
    }

    // MARK: Summary (backward-compatible with WritingDeskView)

    var summary: String {
        var lines: [String] = ["综合评分: \(overallScore)/100 (\(grade.rawValue))"]

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

        if !overallSummary.isEmpty {
            lines.append("📋 \(overallSummary)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Convenience: issues grouped by dimension

    func issues(for dimension: ReviewDimension) -> [ReviewIssue] {
        issues.filter { $0.dimension == dimension }
    }

    func score(for dimension: ReviewDimension) -> Int {
        dimensionScores[dimension] ?? 80
    }
}

// MARK: - Review Grade (from QualityReviewService, kept for UI)

enum ReviewGrade: String, Codable {
    case excellent = "优秀"
    case good = "良好"
    case fair = "一般"
    case poor = "需改进"

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good:      return "blue"
        case .fair:      return "yellow"
        case .poor:      return "red"
        }
    }
}

// MARK: - Unified Quality Reviewer

enum UnifiedQualityReviewer {

    // MARK: - System Prompt (9 dimensions, blocking model, evidence required)

    static let reviewSystemPrompt = """
    你是一位中文长篇小说的质量审查员。你的任务是对候选正文进行九维质量审查。
    必须遵守：
    1. 严格按 9 个维度逐一检查，不跳过任何维度。
    2. 每个问题必须提供原文引用作为证据，不允许主观"感觉不好"。
    3. 问题严重性分为：critical（阻断）、high（高）、medium（中）、low（低）。
    4. 每个 issue 必须输出 blocking 布尔值；critical 必须 blocking=true，其他严重度若会破坏长篇连续性也应 blocking=true。
    5. 特别关注 AI 味问题：高频AI词汇、同构句式、情绪标签化、模板化对白。
    6. 必须以 JSON 格式输出审查结果，不要解释。
    """

    // MARK: - User Prompt Builder

    static func reviewUserPrompt(
        project: NovelProject,
        chapterDraft: String,
        memoryContext: String
    ) -> String {
        let draftContext = reviewDraftContext(project: project, chapterDraft: chapterDraft)
        return """
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

        后台长篇合同：
        \(excerpt(project.longformStorySystemContext, limit: 3000))

        \(draftContext)

        待审查正文：
        \(chapterDraft)

        审查要求：
        请对上述正文进行九维质量审查。
        如果提供了草稿箱当前正文，它只作为承接上下文和连续性参照；issues 只记录待审查正文自身的问题。
        必须判断待审查正文能否自然接在草稿箱最后状态之后，若明显断裂、倒退、重复或改写已有正文，标记为 critical。
        必须逐条核对后台长篇合同中的本章必须执行、禁区与风险、写后门禁和本章修订反馈。
        如果正文漏掉后台合同里的明确章节节点，标记为 critical。
        如果正文违背全局记忆、人物状态、世界规则、时间线或草稿箱最后状态，标记为 critical。
        如果正文绕开本章修订反馈继续推进下一章，标记为 critical。
        每个 issue 都必须输出 blocking；凡是会导致不能安全保存、不能进入下一章或会污染长期记忆的问题，blocking 必须为 true。
        如果长篇章节没有有效章末钩子、微兑现或下一章期待，追读力至少标记为 high 问题。

        审查维度：
        1. 设定一致性 — 战力/地点/道具/能力是否与已有设定矛盾
        2. 时间线 — 时间线是否连贯，是否有不合理跳跃
        3. 叙事连贯 — 场景切换、情绪弧线、上文承接是否通顺
        4. 角色一致性 — 对白风格、行为动机、信息获取是否符合人设
        5. 逻辑 — 因果关系、决策动机、战斗结果是否合理
        6. 爽点密度 — 是否有足够吸引力元素让读者想继续读
        7. 节奏比例 — 主线推进、感情线、世界观扩展的比例是否合理
        8. 追读力 — 章末钩子、期待管理、微兑现是否到位
        9. AI味 — 是否有AI高频词、同构句式、情绪标签化、模板化对白

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
            "high_point": 82,
            "pacing": 78,
            "reader_pull": 80,
            "ai_flavor": 75
          },
          "issues": [
            {
              "dimension": "ai_flavor",
              "severity": "high",
              "blocking": false,
              "description": "问题描述",
              "evidence": "原文引用",
              "fix_hint": "修复建议",
              "location": "第N段"
            }
          ],
          "anti_patterns": ["应避免的AI模式1", "应避免的AI模式2"],
          "overall_summary": "整体评价（一句话）"
        }

        如果没有问题，issues 数组为空，所有维度分数 95+。
        """
    }

    // MARK: - Review Entry Point (API-based, full 9 dimensions)

    static func reviewChapter(
        project: NovelProject,
        chapterDraft: String,
        memoryContext: String,
        configuration: AIConnectionConfiguration
    ) async throws -> ChapterReviewResult {
        // Quick local AI-flavor pre-check (no API call)
        let localPatterns = quickAIFlavorCheck(text: chapterDraft)

        // Full AI review
        let reviewResponse = try await AIWritingService.generateText(
            configuration: configuration,
            systemPrompt: reviewSystemPrompt,
            userPrompt: reviewUserPrompt(
                project: project,
                chapterDraft: chapterDraft,
                memoryContext: memoryContext
            ),
            temperature: 0.3,
            maxTokens: 3_000
        )

        let result = parseReviewResult(from: reviewResponse)

        return mergeLocalAntiPatterns(into: result, localPatterns: localPatterns)
    }

    private static func reviewDraftContext(project: NovelProject, chapterDraft: String) -> String {
        let currentDraft = project.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewedDraft = chapterDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentDraft.isEmpty, currentDraft != reviewedDraft else {
            return "草稿箱当前正文：\n暂无额外草稿箱上下文。"
        }

        return """
        草稿箱当前正文（只作承接上下文，不要把这里已有的问题计入待审查正文 issues）：
        \(excerpt(currentDraft, limit: 2400))
        """
    }

    // MARK: - Parse Review Result (JSON → ChapterReviewResult)

    /// Codable intermediate for the AI review JSON response.
    /// Uses snake_case keys matching the AI prompt output format.
    private struct AIReviewResponse: Decodable {
        let overall_score: Int
        let dimension_scores: [String: Int]
        let issues: [AIReviewIssue]
        let anti_patterns: [String]?
        let overall_summary: String?
    }

    private struct AIReviewIssue: Decodable {
        let dimension: String
        let severity: String
        let description: String
        let evidence: String?
        let fix_hint: String?
        let location: String?
        let blocking: Bool?
    }

    static func parseReviewResult(from jsonString: String) -> ChapterReviewResult {
        let cleaned = extractJSONPayload(from: jsonString)

        guard let data = cleaned.data(using: .utf8),
              let response = try? JSONDecoder().decode(AIReviewResponse.self, from: data) else {
            return fallbackParse(from: cleaned)
        }

        // Map dimension scores
        var dimensionScores: [ReviewDimension: Int] = [:]
        for dim in ReviewDimension.allCases {
            dimensionScores[dim] = response.dimension_scores[dim.rawValue] ?? 80
        }

        // Map issues
        let issues: [ReviewIssue] = response.issues.map { issue in
            let dimension = reviewDimension(from: issue.dimension)
            let severity = issue.blocking == true
                ? .critical
                : reviewSeverity(from: issue.severity)
            return ReviewIssue(
                dimension: dimension,
                severity: severity,
                description: issue.description,
                evidence: issue.evidence ?? "",
                fixHint: issue.fix_hint ?? "",
                location: issue.location ?? ""
            )
        }

        let antiPatterns = response.anti_patterns ?? []
        let overallSummary = response.overall_summary ?? ""

        // Compute overall score using webnovel-writer penalty methodology:
        // 100 - sum(penalties for all issues), clamped to 0...100.
        // If the AI provided an overall_score, use it as an upper-bound hint,
        // but the penalty-based calculation takes precedence for consistency.
        let penaltyScore = computePenaltyScore(issues: issues)
        let finalScore = min(response.overall_score, penaltyScore)

        let hasBlocking = issues.contains { $0.isBlocking }

        return ChapterReviewResult(
            overallScore: finalScore,
            dimensionScores: dimensionScores,
            issues: issues,
            hasBlockingIssues: hasBlocking,
            antiPatterns: antiPatterns,
            overallSummary: overallSummary
        )
    }

    private static func extractJSONPayload(from response: String) -> String {
        var cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start <= end {
            cleaned = String(cleaned[start...end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    private static func reviewDimension(from rawValue: String) -> ReviewDimension {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let dimension = ReviewDimension(rawValue: normalized) {
            return dimension
        }

        let compact = normalized
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        let aliases: [(ReviewDimension, [String])] = [
            (.settingConsistency, ["settingconsistency", "setting", "设定", "设定一致性", "世界观", "规则"]),
            (.timelineConsistency, ["timelineconsistency", "timeline", "时间线", "时间"]),
            (.narrativeContinuity, ["narrativecontinuity", "continuity", "叙事", "连贯", "承接"]),
            (.characterConsistency, ["characterconsistency", "character", "角色", "人物", "ooc"]),
            (.logicIntegrity, ["logicintegrity", "logic", "逻辑", "因果"]),
            (.aiFlavor, ["aiflavor", "ai", "ai味", "模型味", "机器味"]),
            (.highPointDensity, ["highpointdensity", "highpoint", "爽点", "吸引力"]),
            (.pacing, ["pacing", "节奏", "比例"]),
            (.readerPull, ["readerpull", "追读", "钩子", "期待"])
        ]

        for (dimension, values) in aliases where values.contains(where: { compact.contains($0) }) {
            return dimension
        }

        return .logicIntegrity
    }

    private static func reviewSeverity(from rawValue: String) -> ReviewSeverity {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let severity = ReviewSeverity(rawValue: normalized) {
            return severity
        }

        let compact = normalized
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        if ["critical", "blocker", "blocking", "fatal", "严重", "阻断", "致命"].contains(where: { compact.contains($0) }) {
            return .critical
        }
        if ["high", "major", "重要", "高"].contains(where: { compact.contains($0) }) {
            return .high
        }
        if ["medium", "middle", "moderate", "中", "一般"].contains(where: { compact.contains($0) }) {
            return .medium
        }
        if ["low", "minor", "轻微", "低"].contains(where: { compact.contains($0) }) {
            return .low
        }

        return .critical
    }

    // MARK: - Penalty-Based Score Calculation (webnovel-writer methodology)

    /// Computes overall score from 100 minus severity penalties.
    /// critical = -35, high = -15, medium = -6, low = -2.
    static func computePenaltyScore(issues: [ReviewIssue]) -> Int {
        let totalPenalty = issues.reduce(0) { $0 + $1.severity.penalty }
        return max(0, 100 - totalPenalty)
    }

    static func mergeLocalAntiPatterns(
        into result: ChapterReviewResult,
        localPatterns: [String]
    ) -> ChapterReviewResult {
        guard !localPatterns.isEmpty else { return result }

        let localIssues = localPatterns.map { pattern in
            ReviewIssue(
                dimension: .aiFlavor,
                severity: localPatternSeverity(pattern),
                description: pattern,
                evidence: pattern,
                fixHint: "改成更具体的动作、对白或场景细节，避免重复套话。",
                location: "本地启发式检查"
            )
        }
        let mergedIssues = result.issues + localIssues
        let mergedAntiPatterns = uniqueStrings(result.antiPatterns + localPatterns)
        let penaltyScore = computePenaltyScore(issues: mergedIssues)

        return ChapterReviewResult(
            overallScore: min(result.overallScore, penaltyScore),
            dimensionScores: result.dimensionScores,
            issues: mergedIssues,
            hasBlockingIssues: result.hasBlockingIssues || mergedIssues.contains { $0.isBlocking },
            antiPatterns: mergedAntiPatterns,
            overallSummary: result.overallSummary
        )
    }

    private static func localPatternSeverity(_ pattern: String) -> ReviewSeverity {
        if pattern.contains("连续") || pattern.contains("模板表达") || pattern.contains("情绪标签化") {
            return .high
        }
        return .medium
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedValue.isEmpty, !seen.contains(normalizedValue) else {
                return false
            }
            seen.insert(normalizedValue)
            return true
        }
    }

    // MARK: - Fallback Parse (text-based, when JSON parsing fails)

    private static func fallbackParse(from text: String) -> ChapterReviewResult {
        return ChapterReviewResult(
            overallScore: 0,
            dimensionScores: [:],
            issues: [ReviewIssue(
                dimension: .aiFlavor,
                severity: .critical,
                description: "审查结果解析失败，当前质量门禁不可用。",
                evidence: String(text.prefix(200)),
                fixHint: "请重新运行质量审查，确认模型返回可解析 JSON 后再保存或接受候选稿。",
                location: "质量审查响应"
            )],
            hasBlockingIssues: true,
            antiPatterns: [],
            overallSummary: "审查结果解析失败，请人工检查。"
        )
    }

    // MARK: - AI Flavor Pre-Check (Local, No API)

    /// Quick local check for obvious AI-flavor patterns before sending to API.
    /// Returns list of detected anti-pattern descriptions.
    static func quickAIFlavorCheck(text: String) -> [String] {
        var patterns: [String] = []

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

        // Check for consecutive identical sentence structures (basic heuristic)
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.count >= 3 {
            var consecutiveSameStart = 1
            for i in 1..<paragraphs.count {
                let prevFirst2 = String(paragraphs[i-1].prefix(2))
                let currFirst2 = String(paragraphs[i].prefix(2))
                if prevFirst2 == currFirst2 && !prevFirst2.isEmpty {
                    consecutiveSameStart += 1
                } else {
                    consecutiveSameStart = 1
                }
                if consecutiveSameStart >= 3 {
                    patterns.append("连续 \(consecutiveSameStart) 段以相同开头，建议变化段落起始方式")
                    break
                }
            }
        }

        return patterns
    }

    // MARK: - Helpers

    private static func excerpt(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed.isEmpty ? "暂无" : trimmed }
        return "…" + String(trimmed.suffix(limit))
    }

    private static func normalized(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

// MARK: - Backward-Compatible Alias

/// Alias so existing code referencing `ChapterQualityReviewer` continues to compile.
typealias ChapterQualityReviewer = UnifiedQualityReviewer
