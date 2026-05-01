import Foundation

// MARK: - AI Writing Service Extensions for Webnovel-Writer Integration

/// Adds pre-write validation, post-write review, memory management,
/// and strand weave tracking to the writing pipeline.

extension AIWritingService {

    // MARK: - Enhanced Continue Chapter (with validation + review)

    /// Enhanced version of continueChapter that adds:
    /// 1. Pre-write validation (anti-hallucination three laws)
    /// 2. Genre template injection
    /// 3. Structured memory context
    /// 4. Post-write quality review
    /// 5. Strand weave tracking
    static func continueChapterEnhanced(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        enableReview: Bool = true
    ) async throws -> EnhancedWritingResult {
        // Step 1: Pre-write validation
        let validation = PrewriteValidator.validate(project: project)
        guard validation.isReady else {
            return EnhancedWritingResult(
                text: "",
                validation: validation,
                review: nil,
                strandWarning: nil,
                memoryUpdate: nil
            )
        }

        // Step 2: Build enhanced support context
        let support = EnhancedWritingSupport(project: project)

        // Step 3: Write with enhanced context
        let plan = try await completeEnhancedText(
            configuration: configuration,
            systemPrompt: writingPlanSystemPrompt,
            userPrompt: enhancedWritingPlanPrompt(
                project: project,
                mode: mode,
                additionalInstruction: additionalInstruction,
                length: length,
                support: support
            ),
            temperature: 0.42,
            maxTokens: 760
        )

        let draft = try await completeEnhancedText(
            configuration: configuration,
            systemPrompt: enhancedSystemPrompt(project: project),
            userPrompt: enhancedUserPrompt(
                project: project,
                mode: mode,
                additionalInstruction: additionalInstruction,
                length: length,
                support: support,
                writingPlan: plan
            ),
            temperature: 0.82,
            maxTokens: length.maxTokens
        )

        let revisedDraft = try await completeEnhancedText(
            configuration: configuration,
            systemPrompt: writingRevisionSystemPrompt,
            userPrompt: writingRevisionUserPrompt(
                project: project,
                mode: mode,
                additionalInstruction: additionalInstruction,
                length: length,
                support: AIWritingService.WritingSupportContext(project: project),
                writingPlan: plan,
                draft: draft
            ),
            temperature: 0.34,
            maxTokens: length.maxTokens + 500
        )

        let finalText: String
        if revisedDraft.count >= length.minimumAcceptableCount {
            finalText = revisedDraft
        } else {
            let supplement = try await completeEnhancedText(
                configuration: configuration,
                systemPrompt: writingSupplementSystemPrompt,
                userPrompt: writingSupplementUserPrompt(
                    project: project,
                    length: length,
                    support: AIWritingService.WritingSupportContext(project: project),
                    writingPlan: plan,
                    draft: revisedDraft
                ),
                temperature: 0.72,
                maxTokens: max(700, length.maxTokens / 2)
            )
            let finalSegments: [String] = [revisedDraft, supplement]
            finalText = finalSegments
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        // Step 4: Post-write quality review (if enabled)
        var reviewResult: ChapterReviewResult? = nil
        if enableReview {
            // Quick local AI-flavor check first
            let localPatterns = ChapterQualityReviewer.quickAIFlavorCheck(text: finalText)

            // Full AI review
            let reviewPrompt = ChapterQualityReviewer.reviewUserPrompt(
                project: project,
                chapterDraft: finalText,
                memoryContext: support.enhancedMemoryContext
            )
            let reviewResponse = try await completeEnhancedText(
                configuration: configuration,
                systemPrompt: ChapterQualityReviewer.reviewSystemPrompt,
                userPrompt: reviewPrompt,
                temperature: 0.3,
                maxTokens: 2_000
            )
            reviewResult = ChapterQualityReviewer.parseReviewResult(from: reviewResponse)

            // Merge local anti-patterns
            if !localPatterns.isEmpty, var review = reviewResult {
                review = ChapterReviewResult(
                    overallScore: review.overallScore,
                    dimensionScores: review.dimensionScores,
                    issues: review.issues,
                    hasBlockingIssues: review.hasBlockingIssues,
                    antiPatterns: review.antiPatterns + localPatterns,
                    overallSummary: review.overallSummary
                )
                reviewResult = review
            }
        }

        // Step 5: Strand weave analysis
        let strandType = analyzeStrandType(text: finalText, project: project)
        var strandState = project.strandWeaveState
        let warnings = strandState.checkRedLines(currentChapter: project.currentChapterNumber)
        strandState.recordChapter(project.currentChapterNumber, dominant: strandType)

        return EnhancedWritingResult(
            text: finalText,
            validation: validation,
            review: reviewResult,
            strandWarning: warnings.first,
            memoryUpdate: MemoryUpdateContext(
                strandState: strandState,
                antiPatterns: reviewResult?.antiPatterns ?? []
            )
        )
    }

    // MARK: - Enhanced System Prompt

    private static func enhancedSystemPrompt(project: NovelProject) -> String {
        let genreTemplate = project.genreTemplate
        let antiPatterns = project.accumulatedAntiPatterns

        var prompt = """
        你是一位擅长中文长篇小说创作的原生写作助手。
        你的任务是续写当前章节，而不是重写设定。
        必须遵守：
        1. 保持人物语气、世界观规则和既有叙事视角一致。
        2. 优先承接上一已保存章节结尾与当前章节既定目标，保持节奏、句式和情绪连续。
        3. 只输出可直接接在正文后的小说内容，不要解释，不要列提纲，不要加标题。
        4. 如果参考文本与当前项目冲突，以当前项目摘要、大纲、全局记忆和已有正文为准。
        5. 根据项目规模控制叙事：短篇要集中闭环，中篇要稳住阶段推进，长篇要维护分卷延展、长期伏笔和人物长期状态。
        6. 保持连续性，避免突然跳到未来情节、提前透支长期真相或重复已写内容。

        \(AntiAIWritingGuide.formattedGuide)

        题材约束（\(genreTemplate.name)）：
        \(genreTemplate.formattedForPrompt)

        叙事阶段：
        \(project.narrativeStage.pacingDirective)
        \(project.narrativeStage.contextWeightHint)
        """

        if !antiPatterns.isEmpty {
            prompt += "\n\n已识别的反模式（务必避免）：\n"
            for pattern in antiPatterns.prefix(10) {
                prompt += "· \(pattern)\n"
            }
        }

        return prompt
    }

    // MARK: - Enhanced User Prompt

    private static func enhancedUserPrompt(
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        support: EnhancedWritingSupport,
        writingPlan: String
    ) -> String {
        let previousChapterSummary = normalized(
            project.previousChapterDraftForContinuation?.chapterSummary ?? "",
            fallback: "暂无上一已保存章节，请直接依据当前章节目标起笔。"
        )
        let previousChapterEnding = normalized(
            project.draftContinuationCache,
            fallback: "暂无上一章节结尾缓存，请依据当前章节目标稳妥起笔。"
        )
        let recentChapterSummaries = project.sortedChapterDrafts
            .filter { $0.chapterNumber < project.currentChapterNumber }
            .prefix(3)
            .map(\.chapterSummary)
            .joined(separator: "、")

        // Build rankable context sections
        var sections: [ContextSection] = []

        sections.append(ContextSection(
            label: "草稿箱当前正文",
            content: support.currentDraftExcerpt,
            category: .currentDraft
        ))
        sections.append(ContextSection(
            label: "增强记忆系统",
            content: support.enhancedMemoryContext,
            category: .enhancedMemory
        ))
        sections.append(ContextSection(
            label: "作品大纲",
            content: normalized(project.outlineText, fallback: "暂无大纲，请依据项目摘要和当前章节目标稳步推进。"),
            category: .outline
        ))
        sections.append(ContextSection(
            label: "分卷/阶段规划",
            content: normalized(project.volumePlanNotes, fallback: "暂无分卷规划。"),
            category: .volumePlan
        ))
        sections.append(ContextSection(
            label: "在途线索",
            content: normalized(project.activeThreadsNotes, fallback: "暂无在途线索。"),
            category: .activeThreads
        ))
        sections.append(ContextSection(
            label: "章节树关键约束",
            content: support.chapterTreeFocus,
            category: .chapterTree
        ))
        sections.append(ContextSection(
            label: "风格指纹",
            content: support.styleFingerprint,
            category: .styleFingerprint
        ))
        sections.append(ContextSection(
            label: "节奏监控",
            content: support.strandContext,
            category: .strandContext
        ))
        sections.append(ContextSection(
            label: "题材配置",
            content: support.genreTemplateContext,
            category: .genreTemplate
        ))
        sections.append(ContextSection(
            label: "手动参考文本",
            content: normalized(project.referenceContextText, fallback: "暂无手动补充的参考文本。"),
            category: .manualReference
        ))
        sections.append(ContextSection(
            label: "检索到的相关参考文本",
            content: support.relevantReferences,
            category: .retrievedReferences
        ))
        sections.append(ContextSection(
            label: "特殊要求",
            content: normalized(project.specialRequirements, fallback: "暂无额外特殊要求。"),
            category: .specialRequirements
        ))

        // Rank sections by relevance
        let rankedSections = ContextRanker.rank(sections, project: project)

        // Assemble fixed prefix
        var prompt = """
        项目名称：\(project.title)
        类型：\(project.genre)
        创作规模：\(project.storyLength.title)
        项目摘要：\(project.summary)
        当前进度：已创作 \(project.writtenChapters) 章

        规模要求：
        \(project.storyLength.promptDirective)

        当前章节：\(project.currentChapterSummary)
        本章目标：\(project.chapterFocus)
        当前正文概况：\(project.draftWordCount) 字，约 \(project.draftParagraphCount) 段

        本次写作模式：
        \(mode.title)；\(mode.instruction)

        本次续写拍点：
        \(normalized(writingPlan, fallback: "请先承接当前草稿，再推进一个明确的新情节拍点。"))
        """

        // Append ranked context sections
        for section in rankedSections {
            prompt += "\n\n\(section.label)：\n\(section.content)"
        }

        // Append fixed suffix (always at end)
        prompt += """

        叙事阶段：
        \(project.narrativeStage.pacingDirective)
        \(project.narrativeStage.contextWeightHint)

        字数设定：
        \(normalized(project.wordTargetText, fallback: "暂无专门字数设定，请按正常章节节奏展开。"))

        上一已保存章节：
        \(previousChapterSummary)

        缓存区（上一章节末尾 400 字）：
        \(previousChapterEnding)

        近三章标题：
        \(normalized(recentChapterSummaries, fallback: "暂无可参考的已保存章节标题。"))

        额外指令：
        \(normalized(additionalInstruction, fallback: "延续当前场景，不要跳章节。"))

        输出要求：
        \(length.instruction)
        必须保持与当前章节位置、角色口吻、时间线状态和伏笔进度一致。
        \(project.storyLength.continuityDirective)
        如果草稿箱已有正文，必须从草稿最后状态继续写，不要绕回上一章结尾重新起笔。
        如果提供了上一章节缓存，请优先承接缓存区里的最后一句、段落节奏和场景状态，但不要重复复述上一章已经写出的动作、对白、心理或信息。
        开场两段避免重复解释既有设定、人物关系和刚刚发生过的事件，默认读者记得上一章。
        每次续写至少推进一个新的情节拍点、关系变化或信息增量，不要用改写前文来充字数。
        若需承上启下，请用新的动作、冲突、观察或结果进入当前章节，而不是复述上一章摘要。
        请直接输出续写后的正文。
        """

        return prompt
    }

    // MARK: - Enhanced Writing Plan Prompt

    private static func enhancedWritingPlanPrompt(
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        support: EnhancedWritingSupport
    ) -> String {
        """
        项目名称：\(project.title)
        类型：\(project.genre)
        当前章节：\(project.currentChapterSummary)
        本章目标：\(project.chapterFocus)
        本次写作模式：\(mode.title)；\(mode.instruction)
        字数目标：\(length.instruction)

        当前草稿箱正文（必须承接用户已修改/新增的内容）：
        \(support.currentDraftExcerpt)

        上一章节末尾 400 字：
        \(normalized(project.draftContinuationCache, fallback: "暂无上一章节结尾缓存。"))

        增强记忆：
        \(support.enhancedMemoryContext)

        章节树关键约束：
        \(support.chapterTreeFocus)

        作品大纲：
        \(normalized(project.outlineText, fallback: "暂无完整大纲。"))

        风格指纹：
        \(support.styleFingerprint)

        节奏状态：
        \(support.strandContext)

        题材配置：
        \(support.genreTemplateContext)

        特殊要求与额外指令：
        \(normalized(project.specialRequirements, fallback: "暂无特殊要求。"))
        \(normalized(additionalInstruction, fallback: "延续当前场景，不要跳章节。"))

        输出要求：
        请给出本次续写的 3 到 5 个执行拍点。
        """
    }

    // MARK: - Strand Type Analysis

    /// Analyze the dominant strand type of the written text.
    private static func analyzeStrandType(text: String, project: NovelProject) -> StrandType {
        let textLower = text.lowercased()

        // Fire strand indicators
        let fireKeywords = ["心动", "喜欢", "爱", "拥抱", "亲吻", "脸红", "心跳",
                           "思念", "吃醋", "告白", "约会", "暧昧", "温柔", "甜蜜"]
        let fireCount = fireKeywords.filter { textLower.contains($0) }.count

        // Constellation strand indicators
        let constKeywords = ["势力", "家族", "宗门", "王国", "帝国", "联盟", "规则",
                            "体系", "境界", "历史", "传说", "地图", "大陆", "世界"]
        let constCount = constKeywords.filter { textLower.contains($0) }.count

        // Default to quest
        if fireCount >= 3 && fireCount > constCount {
            return .fire
        }
        if constCount >= 3 && constCount > fireCount {
            return .constellation
        }
        return .quest
    }

    private static func completeEnhancedText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let endpoint = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let payload = EnhancedChatCompletionsRequest(
            model: configuration.modelName,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: temperature,
            maxTokens: maxTokens
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWritingError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AIWritingError.serverError(message)
        }

        let decoded = try JSONDecoder().decode(EnhancedChatCompletionsResponse.self, from: data)
        guard
            let text = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            throw AIWritingError.emptyResult
        }

        return text
    }

}

private struct EnhancedChatCompletionsRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct EnhancedChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

// MARK: - Enhanced Writing Support Context

struct EnhancedWritingSupport {
    let currentDraftExcerpt: String
    let relevantReferences: String
    let chapterTreeFocus: String
    let styleFingerprint: String
    let enhancedMemoryContext: String
    let strandContext: String
    let genreTemplateContext: String

    init(project: NovelProject) {
        let baseSupport = AIWritingService.WritingSupportContext(project: project)
        currentDraftExcerpt = baseSupport.currentDraftExcerpt
        relevantReferences = baseSupport.relevantReferences
        chapterTreeFocus = baseSupport.chapterTreeFocus
        styleFingerprint = baseSupport.styleFingerprint
        enhancedMemoryContext = project.enhancedMemoryContext
        strandContext = project.strandContext
        genreTemplateContext = project.genreTemplateContext
    }
}

// MARK: - Enhanced Writing Result

struct EnhancedWritingResult {
    let text: String
    let validation: PrewriteValidationResult
    let review: ChapterReviewResult?
    let strandWarning: StrandWeaveState.PacingWarning?
    let memoryUpdate: MemoryUpdateContext?

    var isSuccessful: Bool {
        !text.isEmpty && validation.isReady && !(review?.hasBlockingIssues ?? false)
    }

    var summary: String {
        var lines: [String] = []

        lines.append(validation.readySummary)

        if !text.isEmpty {
            let wordCount = text.unicodeScalars.filter { !$0.properties.isWhitespace }.count
            lines.append("📝 生成 \(wordCount) 字")
        }

        if let review {
            lines.append(review.summary)
        }

        if let warning = strandWarning {
            lines.append("⚠️ 节奏告警: \(warning.message)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Memory Update Context

struct MemoryUpdateContext {
    let strandState: StrandWeaveState
    let antiPatterns: [String]
}
