import Foundation

// MARK: - Quality Review System
// Six-dimension chapter quality review, inspired by webnovel-writer's Reviewer Agent

/// 审查维度
enum ReviewDimension: String, Codable, CaseIterable, Identifiable {
    case highPoint = "爽点密度"
    case consistency = "设定一致性"
    case characterOOC = "角色OOC"
    case pacing = "节奏比例"
    case continuity = "叙事连贯"
    case readerPull = "追读力"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .highPoint: return "🎯"
        case .consistency: return "🔒"
        case .characterOOC: return "🎭"
        case .pacing: return "📐"
        case .continuity: return "🔗"
        case .readerPull: return "🪝"
        }
    }
    
    var description: String {
        switch self {
        case .highPoint: return "检查章节中爽点的密度与质量，是否能持续吸引读者"
        case .consistency: return "检查战力、地点、时间线等设定是否前后矛盾"
        case .characterOOC: return "检查人物行为是否偏离既定人设（Out of Character）"
        case .pacing: return "检查主线、感情线、世界观扩展的比例是否合理"
        case .continuity: return "检查场景切换与叙事逻辑是否通顺"
        case .readerPull: return "检查钩子强度、期待管理、微兑现是否到位"
        }
    }
}

/// 单个维度的审查结果
struct ReviewDimensionResult: Codable, Identifiable {
    let dimension: ReviewDimension
    let score: Int // 1-10
    let issues: [ReviewIssue]
    let summary: String
    
    var id: String { dimension.rawValue }
    
    var grade: ReviewGrade {
        switch score {
        case 8...10: return .excellent
        case 6...7: return .good
        case 4...5: return .fair
        default: return .poor
        }
    }
}

/// 审查等级
enum ReviewGrade: String, Codable {
    case excellent = "优秀"
    case good = "良好"
    case fair = "一般"
    case poor = "需改进"
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "yellow"
        case .poor: return "red"
        }
    }
}

/// 审查问题
struct ReviewIssue: Codable, Identifiable {
    let id: UUID
    let severity: IssueSeverity
    let description: String
    let suggestion: String
    
    init(severity: IssueSeverity, description: String, suggestion: String) {
        self.id = UUID()
        self.severity = severity
        self.description = description
        self.suggestion = suggestion
    }
}

/// 问题严重程度
enum IssueSeverity: String, Codable {
    case critical = "严重"
    case major = "重要"
    case minor = "轻微"
}

/// 完整审查报告
struct QualityReviewReport: Codable, Identifiable {
    let id: UUID
    let chapterNumber: Int
    let chapterTitle: String
    let reviewedAt: Date
    let dimensionResults: [ReviewDimensionResult]
    let overallScore: Int // 平均分
    let overallSummary: String
    
    init(chapterNumber: Int, chapterTitle: String, dimensionResults: [ReviewDimensionResult], overallSummary: String) {
        self.id = UUID()
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.reviewedAt = Date()
        self.dimensionResults = dimensionResults
        let scores = dimensionResults.map { $0.score }
        self.overallScore = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        self.overallSummary = overallSummary
    }
    
    /// 是否通过审查（无严重问题，平均分 >= 6）
    var isPassed: Bool {
        let hasCritical = dimensionResults.contains { result in
            result.issues.contains { $0.severity == .critical }
        }
        return !hasCritical && overallScore >= 6
    }
    
    /// 按严重程度排序的所有问题
    var allIssues: [ReviewIssue] {
        dimensionResults.flatMap { $0.issues }
            .sorted { a, b in
                let order: [IssueSeverity] = [.critical, .major, .minor]
                return (order.firstIndex(of: a.severity) ?? 99) < (order.firstIndex(of: b.severity) ?? 99)
            }
    }
}

/// 六维质量审查服务
enum QualityReviewService {
    
    /// 对章节进行六维审查
    static func reviewChapter(
        chapterTitle: String,
        chapterContent: String,
        chapterNumber: Int,
        project: NovelProject,
        configuration: AIConnectionConfiguration
    ) async throws -> QualityReviewReport {
        
        let systemPrompt = buildReviewSystemPrompt(project: project)
        let userPrompt = buildReviewUserPrompt(
            chapterTitle: chapterTitle,
            chapterContent: chapterContent,
            chapterNumber: chapterNumber
        )
        
        let response = try await AIWritingService.completeText(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.3,
            maxTokens: 4000
        )
        
        return parseReviewResponse(
            response: response,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle
        )
    }
    
    // MARK: - Prompt Building
    
    private static func buildReviewSystemPrompt(project: NovelProject) -> String {
        var prompt = """
        你是一位专业的长篇小说质量审查专家。你需要从六个维度对给定章节进行严格审查。
        
        ## 审查维度
        
        1. **爽点密度** (1-10分)：章节中是否有足够的吸引力元素让读者想继续读下去
        2. **设定一致性** (1-10分)：战力、地点、时间线、世界观设定是否前后一致
        3. **角色OOC** (1-10分)：人物行为是否符合其既定性格和人设
        4. **节奏比例** (1-10分)：主线推进、感情线、世界观扩展的比例是否合理
        5. **叙事连贯** (1-10分)：场景切换、叙事逻辑是否通顺
        6. **追读力** (1-10分)：章末钩子、期待管理、微兑现是否到位
        
        ## 输出格式
        
        请严格按以下 JSON 格式输出，不要添加任何其他内容：
        
        ```json
        {
          "dimensions": [
            {
              "dimension": "爽点密度",
              "score": 8,
              "summary": "简要评价",
              "issues": [
                {
                  "severity": "minor",
                  "description": "问题描述",
                  "suggestion": "修改建议"
                }
              ]
            }
          ],
          "overallSummary": "整体评价"
        }
        ```
        
        severity 只能是: "critical", "major", "minor"
        """
        
        // 加入项目上下文
        if !project.outlineText.isEmpty {
            prompt += "\n\n## 大纲\n\(project.outlineText)"
        }
        if !project.globalMemorySnapshot.formattedText.isEmpty {
            prompt += "\n\n## 全局记忆\n\(project.globalMemorySnapshot.formattedText)"
        }
        if !project.characterArcNotes.isEmpty {
            prompt += "\n\n## 角色弧线\n\(project.characterArcNotes)"
        }
        if !project.foreshadowNotes.isEmpty {
            prompt += "\n\n## 伏笔追踪\n\(project.foreshadowNotes)"
        }
        
        return prompt
    }
    
    private static func buildReviewUserPrompt(chapterTitle: String, chapterContent: String, chapterNumber: Int) -> String {
        """
        请对第 \(chapterNumber) 章「\(chapterTitle)」进行六维质量审查。
        
        ## 章节正文
        
        \(chapterContent)
        """
    }
    
    // MARK: - Response Parsing
    
    private static func parseReviewResponse(response: String, chapterNumber: Int, chapterTitle: String) -> QualityReviewReport {
        // Extract JSON from response
        let jsonString = extractJSON(from: response)
        
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dimensions = parsed["dimensions"] as? [[String: Any]] else {
            // Fallback: return a default report
            return QualityReviewReport(
                chapterNumber: chapterNumber,
                chapterTitle: chapterTitle,
                dimensionResults: ReviewDimension.allCases.map { dim in
                    ReviewDimensionResult(
                        dimension: dim,
                        score: 5,
                        issues: [ReviewIssue(severity: .minor, description: "无法解析审查结果", suggestion: "请重新审查")],
                        summary: "审查结果解析失败"
                    )
                },
                overallSummary: "审查结果解析失败，请重试"
            )
        }
        
        let overallSummary = parsed["overallSummary"] as? String ?? "无整体评价"
        
        let results: [ReviewDimensionResult] = ReviewDimension.allCases.compactMap { dim in
            guard let dimData = dimensions.first(where: { ($0["dimension"] as? String) == dim.rawValue }) else {
                return ReviewDimensionResult(
                    dimension: dim,
                    score: 5,
                    issues: [],
                    summary: "未找到该维度的审查结果"
                )
            }
            
            let score = dimData["score"] as? Int ?? 5
            let summary = dimData["summary"] as? String ?? ""
            let issuesData = dimData["issues"] as? [[String: Any]] ?? []
            
            let issues = issuesData.map { issueData -> ReviewIssue in
                let severityStr = issueData["severity"] as? String ?? "minor"
                let severity = IssueSeverity(rawValue: severityStr) ?? .minor
                let description = issueData["description"] as? String ?? ""
                let suggestion = issueData["suggestion"] as? String ?? ""
                return ReviewIssue(severity: severity, description: description, suggestion: suggestion)
            }
            
            return ReviewDimensionResult(dimension: dim, score: score, issues: issues, summary: summary)
        }
        
        return QualityReviewReport(
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            dimensionResults: results,
            overallSummary: overallSummary
        )
    }
    
    private static func extractJSON(from text: String) -> String {
        // Try to find JSON block in markdown code fence
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", range: startRange.upperBound..<text.endRange) {
            return String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Try to find raw JSON
        if let startRange = text.range(of: "{"),
           let endRange = text.range(of: "}", options: .backwards, range: startRange.upperBound..<text.endRange) {
            return String(text[startRange.lowerBound...endRange.upperBound])
        }
        return text
    }
}
