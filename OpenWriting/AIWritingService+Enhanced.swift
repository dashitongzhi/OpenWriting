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
                minimumAcceptedScore: LongformStorySystem.minimumAcceptedScore(for: project.storyLength),
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
            userPrompt: enhancedWritingRevisionUserPrompt(
                project: project,
                mode: mode,
                additionalInstruction: additionalInstruction,
                length: length,
                support: support,
                writingPlan: plan,
                draft: draft
            ),
            temperature: 0.34,
            maxTokens: length.maxTokens + 500
        )

        var finalText: String
        if revisedDraft.count >= length.minimumAcceptableCount {
            finalText = revisedDraft
        } else {
            let supplement = try await completeEnhancedText(
                configuration: configuration,
                systemPrompt: writingSupplementSystemPrompt,
                userPrompt: enhancedWritingSupplementUserPrompt(
                    project: project,
                    length: length,
                    support: support,
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
            do {
                let initialReview = try await reviewCandidate(
                    finalText,
                    project: project,
                    support: support,
                    configuration: configuration
                )
                reviewResult = initialReview

                if shouldRepairCandidate(
                    review: initialReview,
                    minimumAcceptedScore: support.minimumAcceptedScore
                ) {
                    do {
                        let repairedDraft = try await completeEnhancedText(
                            configuration: configuration,
                            systemPrompt: writingReviewRepairSystemPrompt,
                            userPrompt: enhancedWritingReviewRepairUserPrompt(
                                project: project,
                                mode: mode,
                                additionalInstruction: additionalInstruction,
                                length: length,
                                support: support,
                                writingPlan: plan,
                                draft: finalText,
                                review: initialReview
                            ),
                            temperature: 0.32,
                            maxTokens: length.maxTokens + 700
                        )
                        let normalizedRepair = repairedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !normalizedRepair.isEmpty {
                            if normalizedRepair.count >= length.minimumAcceptableCount {
                                finalText = normalizedRepair
                            } else {
                                let supplement = try await completeEnhancedText(
                                    configuration: configuration,
                                    systemPrompt: writingSupplementSystemPrompt,
                                    userPrompt: enhancedWritingSupplementUserPrompt(
                                        project: project,
                                        length: length,
                                        support: support,
                                        writingPlan: plan,
                                        draft: normalizedRepair
                                    ),
                                    temperature: 0.72,
                                    maxTokens: max(700, length.maxTokens / 2)
                                )
                                finalText = [normalizedRepair, supplement]
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                    .joined(separator: "\n\n")
                            }

                            if let repairedReview = try? await reviewCandidate(
                                finalText,
                                project: project,
                                support: support,
                                configuration: configuration
                            ) {
                                reviewResult = repairedReview
                            }
                        }
                    } catch {
                        reviewResult = initialReview
                    }
                }
            } catch {
                reviewResult = nil
            }
        }

        // Step 5: Strand weave analysis
        let strandType = analyzeStrandType(text: finalText, project: project)
        var strandState = project.strandWeaveState
        let warnings = strandState.checkRedLines(currentChapter: project.currentChapterNumber)
        strandState.recordChapter(
            project.currentChapterNumber,
            volumeNumber: project.currentVolumeNumber,
            dominant: strandType
        )

        return EnhancedWritingResult(
            text: finalText,
            validation: validation,
            review: reviewResult,
            minimumAcceptedScore: support.minimumAcceptedScore,
            strandWarning: warnings.first,
            memoryUpdate: MemoryUpdateContext(
                strandState: strandState,
                antiPatterns: reviewResult?.antiPatterns ?? []
            )
        )
    }

    static func enhancedWritingRevisionUserPrompt(
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        support: EnhancedWritingSupport,
        writingPlan: String,
        draft: String
    ) -> String {
        let prefix = """
        当前章节：\(EnhancedPromptBudget.boundedContent(
            project.currentChapterSummary,
            fallback: project.currentChapterLabel,
            limit: 300
        ))
        本章目标：\(EnhancedPromptBudget.boundedContent(
            project.chapterFocus,
            fallback: "承接当前草稿并推进一个明确的新情节拍点。",
            limit: 700
        ))
        写作模式：\(mode.title)
        字数目标：\(length.instruction)

        本章执行验收：
        \(EnhancedPromptBudget.boundedContent(
            support.writingExecutionContractContext,
            fallback: "依据本章目标、草稿箱最后状态和章节树约束推进。",
            limit: 4_200
        ))
        """

        let suffix = """

        修订要求：
        1. 如果开头在复述上一章或解释既有设定，请改成直接承接草稿最后状态的新动作、新对白或新观察。
        2. 如果没有推进本章目标，请补足一个明确的信息增量、关系变化或冲突进展。
        3. 如果和草稿箱内容衔接不顺，请修顺第一段。
        4. 必须按增强记忆、后台长篇合同、节奏状态和本章执行验收修订，不能只做表层润色。
        5. 只输出修订后的完整候选正文。
        """

        let sections = [
            ContextSection(
                label: "待检查候选正文",
                content: normalized(draft, fallback: "暂无候选正文，请按本章目标生成可修订正文。"),
                category: .currentDraft
            )
        ] + enhancedSharedContextSections(
            project: project,
            support: support,
            currentDraftLabel: "草稿箱当前正文（候选正文应接在它后面）",
            writingPlan: writingPlan,
            writingPlanFallback: "暂无拍点，请至少推进一个新的情节增量。",
            additionalInstruction: additionalInstruction,
            includePreviousEnding: true
        )

        return EnhancedPromptBudget.render(
            prefix: prefix,
            rankedSections: ContextRanker.rank(sections, project: project),
            suffix: suffix
        )
    }

    static func enhancedWritingReviewRepairUserPrompt(
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        support: EnhancedWritingSupport,
        writingPlan: String,
        draft: String,
        review: ChapterReviewResult
    ) -> String {
        let prefix = """
        当前章节：\(EnhancedPromptBudget.boundedContent(
            project.currentChapterSummary,
            fallback: project.currentChapterLabel,
            limit: 300
        ))
        本章目标：\(EnhancedPromptBudget.boundedContent(
            project.chapterFocus,
            fallback: "承接当前草稿并修复审查发现的问题。",
            limit: 700
        ))
        写作模式：\(mode.title)
        字数目标：\(length.instruction)

        本章执行验收：
        \(EnhancedPromptBudget.boundedContent(
            support.writingExecutionContractContext,
            fallback: "依据本章目标、草稿箱最后状态和章节树约束返修。",
            limit: 4_000
        ))

        质量审查反馈（必须逐条修复 critical/high 问题）：
        \(EnhancedPromptBudget.boundedContent(
            review.summary,
            fallback: "暂无结构化审查摘要，请至少修复连续性与推进不足。",
            limit: 2_600
        ))
        """

        let suffix = """

        返修要求：
        1. 修掉审查反馈里的阻断和高优先级问题，不要只改几个词。
        2. 保持候选正文整体篇幅和章节推进，必要时补写关键动作、对白、证据链或章末钩子。
        3. 返修后仍必须自然接在草稿箱最后状态之后。
        4. 必须维护增强记忆、后台长篇合同和节奏状态中的连续性约束。
        5. 只输出返修后的完整候选正文。
        """

        let sections = [
            ContextSection(
                label: "待返修候选正文",
                content: normalized(draft, fallback: "暂无候选正文，请依据审查反馈生成返修正文。"),
                category: .currentDraft
            )
        ] + enhancedSharedContextSections(
            project: project,
            support: support,
            currentDraftLabel: "草稿箱当前正文（返修后的候选正文仍应接在它后面）",
            writingPlan: writingPlan,
            additionalInstruction: additionalInstruction
        )

        return EnhancedPromptBudget.render(
            prefix: prefix,
            rankedSections: ContextRanker.rank(sections, project: project),
            suffix: suffix
        )
    }

    static func enhancedWritingSupplementUserPrompt(
        project: NovelProject,
        length: AIWritingLength,
        support: EnhancedWritingSupport,
        writingPlan: String,
        draft: String
    ) -> String {
        let prefix = """
        当前章节：\(EnhancedPromptBudget.boundedContent(
            project.currentChapterSummary,
            fallback: project.currentChapterLabel,
            limit: 300
        ))
        本章目标：\(EnhancedPromptBudget.boundedContent(
            project.chapterFocus,
            fallback: "继续推进当前场景。",
            limit: 700
        ))
        目标长度：\(length.instruction)
        当前候选正文约 \(draft.count) 字，低于目标下限，请补足同一场景。

        本章执行验收：
        \(EnhancedPromptBudget.boundedContent(
            support.writingExecutionContractContext,
            fallback: "依据本章目标、草稿箱最后状态和章节树约束补写。",
            limit: 4_200
        ))
        """

        let suffix = """

        输出要求：
        只输出补写部分，接在已有候选正文之后即可。
        """

        let sections = [
            ContextSection(
                label: "已有候选正文（不要重复）",
                content: normalized(draft, fallback: "暂无候选正文，请从草稿箱最后状态继续补写。"),
                category: .currentDraft
            )
        ] + enhancedSharedContextSections(
            project: project,
            support: support,
            writingPlan: writingPlan,
            writingPlanFallback: "请继续推进当前场景。"
        )

        return EnhancedPromptBudget.render(
            prefix: prefix,
            rankedSections: ContextRanker.rank(sections, project: project),
            suffix: suffix
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

        \(CBNStructureGuide.formattedGuide)

        \(NarrativeStageGuide.formattedGuide)

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

    static func enhancedUserPrompt(
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        support: EnhancedWritingSupport,
        writingPlan: String
    ) -> String {
        let previousChapterSummary = EnhancedPromptBudget.boundedContent(
            project.previousChapterDraftForContinuation?.chapterSummary ?? "",
            fallback: "暂无上一已保存章节，请直接依据当前章节目标起笔。",
            limit: 500
        )
        let previousChapterEnding = EnhancedPromptBudget.boundedContent(
            project.draftContinuationCache,
            fallback: "暂无上一章节结尾缓存，请依据当前章节目标稳妥起笔。",
            limit: 500
        )
        let recentChapterSummaries = project.previousChapterDraftsForContinuation
            .prefix(3)
            .map(\.chapterSummary)
            .joined(separator: "、")
        let boundedRecentChapterSummaries = EnhancedPromptBudget.boundedContent(
            recentChapterSummaries,
            fallback: "暂无可参考的已保存章节标题。",
            limit: 400
        )
        let boundedProjectTitle = EnhancedPromptBudget.boundedContent(
            project.title,
            fallback: "未命名项目",
            limit: 160
        )
        let boundedGenre = EnhancedPromptBudget.boundedContent(
            project.genre,
            fallback: "未指定题材",
            limit: 120
        )
        let boundedSummary = EnhancedPromptBudget.boundedContent(
            project.summary,
            fallback: "暂无项目摘要。",
            limit: 700
        )
        let boundedStoryDirective = EnhancedPromptBudget.boundedContent(
            project.storyLength.promptDirective,
            fallback: "按当前项目规模稳步推进。",
            limit: 800
        )
        let boundedChapterSummary = EnhancedPromptBudget.boundedContent(
            project.currentChapterSummary,
            fallback: project.currentChapterLabel,
            limit: 300
        )
        let boundedChapterFocus = EnhancedPromptBudget.boundedContent(
            project.chapterFocus,
            fallback: "承接当前草稿并推进一个明确的新情节拍点。",
            limit: 700
        )
        let boundedWritingPlan = EnhancedPromptBudget.boundedContent(
            writingPlan,
            fallback: "请先承接当前草稿，再推进一个明确的新情节拍点。",
            limit: 1_200
        )
        let boundedExecutionContract = EnhancedPromptBudget.boundedContent(
            support.writingExecutionContractContext,
            fallback: "暂无后台长篇合同，请至少依据本章目标、草稿箱最后状态和章节树约束推进。",
            limit: 4_200
        )
        let boundedNarrativeStage = EnhancedPromptBudget.boundedContent(
            [
                project.narrativeStage.pacingDirective,
                project.narrativeStage.contextWeightHint
            ].joined(separator: "\n"),
            fallback: "按当前章节位置保持自然节奏。",
            limit: 800
        )
        let boundedWordTarget = EnhancedPromptBudget.boundedContent(
            project.wordTargetText,
            fallback: "暂无专门字数设定，请按正常章节节奏展开。",
            limit: 300
        )
        let boundedAdditionalInstruction = EnhancedPromptBudget.boundedContent(
            additionalInstruction,
            fallback: "延续当前场景，不要跳章节。",
            limit: 900
        )

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
            label: "后台长篇合同",
            content: support.longformStorySystemContext,
            category: .chapterTree
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

        // Prefix and suffix are bounded before rankable context is added so
        // the 16,000-character limit applies to the complete user prompt.
        let prefix = """
        项目名称：\(boundedProjectTitle)
        类型：\(boundedGenre)
        创作规模：\(project.storyLength.title)
        项目摘要：\(boundedSummary)
        当前进度：已创作 \(project.writtenChapters) 章

        规模要求：
        \(boundedStoryDirective)

        当前章节：\(boundedChapterSummary)
        本章目标：\(boundedChapterFocus)
        当前正文概况：\(project.draftWordCount) 字，约 \(project.draftParagraphCount) 段

        本次写作模式：
        \(mode.title)；\(mode.instruction)

        本次续写拍点：
        \(boundedWritingPlan)

        长篇后台执行合同（固定高优先级，必须先于普通参考文本执行）：
        \(boundedExecutionContract)
        """

        let suffix = """

        叙事阶段：
        \(boundedNarrativeStage)

        字数设定：
        \(boundedWordTarget)

        上一已保存章节：
        \(previousChapterSummary)

        缓存区（上一章节末尾 400 字）：
        \(previousChapterEnding)

        近三章标题：
        \(boundedRecentChapterSummaries)

        额外指令：
        \(boundedAdditionalInstruction)

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

        return EnhancedPromptBudget.render(
            prefix: prefix,
            rankedSections: rankedSections,
            suffix: suffix
        )
    }

    // MARK: - Enhanced Writing Plan Prompt

    static func enhancedWritingPlanPrompt(
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        support: EnhancedWritingSupport
    ) -> String {
        let prefix = """
        项目名称：\(EnhancedPromptBudget.boundedContent(
            project.title,
            fallback: "未命名项目",
            limit: 160
        ))
        类型：\(EnhancedPromptBudget.boundedContent(
            project.genre,
            fallback: "未指定题材",
            limit: 120
        ))
        当前章节：\(EnhancedPromptBudget.boundedContent(
            project.currentChapterSummary,
            fallback: project.currentChapterLabel,
            limit: 300
        ))
        本章目标：\(EnhancedPromptBudget.boundedContent(
            project.chapterFocus,
            fallback: "承接当前草稿并推进一个明确的新情节拍点。",
            limit: 700
        ))
        本次写作模式：\(mode.title)；\(mode.instruction)
        字数目标：\(length.instruction)

        本章执行验收：
        \(EnhancedPromptBudget.boundedContent(
            support.writingExecutionContractContext,
            fallback: "依据本章目标、草稿箱最后状态和章节树约束规划。",
            limit: 4_200
        ))
        """

        let suffix = """

        输出要求：
        请给出本次续写的 3 到 5 个执行拍点。
        """

        let sections = enhancedSharedContextSections(
            project: project,
            support: support,
            currentDraftLabel: "当前草稿箱正文（必须承接用户已修改/新增的内容）",
            additionalInstruction: additionalInstruction,
            additionalInstructionFallback: "延续当前场景，不要跳章节。",
            includePreviousEnding: true,
            includeOutline: true
        )

        return EnhancedPromptBudget.render(
            prefix: prefix,
            rankedSections: ContextRanker.rank(sections, project: project),
            suffix: suffix
        )
    }

    private static func enhancedSharedContextSections(
        project: NovelProject,
        support: EnhancedWritingSupport,
        currentDraftLabel: String = "草稿箱当前正文",
        writingPlan: String? = nil,
        writingPlanFallback: String = "请至少推进一个新的情节增量。",
        additionalInstruction: String? = nil,
        additionalInstructionFallback: String = "暂无额外指令。",
        includePreviousEnding: Bool = false,
        includeOutline: Bool = false
    ) -> [ContextSection] {
        var sections = [
            ContextSection(
                label: currentDraftLabel,
                content: support.currentDraftExcerpt,
                category: .currentDraft
            ),
            ContextSection(
                label: "增强记忆",
                content: support.enhancedMemoryContext,
                category: .enhancedMemory
            ),
            ContextSection(
                label: "后台长篇合同",
                content: support.longformStorySystemContext,
                category: .chapterTree
            ),
            ContextSection(
                label: "章节树关键约束",
                content: support.chapterTreeFocus,
                category: .chapterTree
            ),
            ContextSection(
                label: "风格指纹",
                content: support.styleFingerprint,
                category: .styleFingerprint
            ),
            ContextSection(
                label: "节奏状态",
                content: support.strandContext,
                category: .strandContext
            ),
            ContextSection(
                label: "题材配置",
                content: support.genreTemplateContext,
                category: .genreTemplate
            ),
            ContextSection(
                label: "特殊要求与启用写作 Skill",
                content: normalized(project.specialRequirements, fallback: "暂无特殊要求或启用 Skill。"),
                category: .specialRequirements
            )
        ]

        if let writingPlan {
            sections.append(ContextSection(
                label: "本次续写拍点",
                content: normalized(writingPlan, fallback: writingPlanFallback),
                category: .activeThreads
            ))
        }
        if let additionalInstruction {
            sections.append(ContextSection(
                label: "额外指令",
                content: normalized(additionalInstruction, fallback: additionalInstructionFallback),
                category: .specialRequirements
            ))
        }
        if includePreviousEnding {
            sections.append(ContextSection(
                label: "上一章节末尾 400 字（只能用于承接，不要复述）",
                content: normalized(project.draftContinuationCache, fallback: "暂无上一章节结尾缓存。"),
                category: .activeThreads
            ))
        }
        if includeOutline {
            sections.append(ContextSection(
                label: "作品大纲",
                content: normalized(project.outlineText, fallback: "暂无完整大纲。"),
                category: .outline
            ))
        }
        return sections
    }

    // MARK: - Strand Type Analysis

    /// Analyze the dominant strand type of the written text.
    private static func analyzeStrandType(text: String, project: NovelProject) -> StrandType {
        StrandKeywordClassifier.dominantStrand(in: text)
    }

    private static func reviewCandidate(
        _ text: String,
        project: NovelProject,
        support: EnhancedWritingSupport,
        configuration: AIConnectionConfiguration
    ) async throws -> ChapterReviewResult {
        let localPatterns = ChapterQualityReviewer.quickAIFlavorCheck(text: text)
        let localIssues = ChapterQualityReviewer.localHeuristicIssues(text: text, project: project)
        let reviewPrompt = enhancedReviewUserPrompt(
            project: project,
            chapterDraft: text,
            memoryContext: support.enhancedMemoryContext
        )
        let reviewResponse = try await completeEnhancedText(
            configuration: configuration,
            systemPrompt: ChapterQualityReviewer.reviewSystemPrompt,
            userPrompt: reviewPrompt,
            temperature: 0.3,
            maxTokens: 2_000
        )
        let review = ChapterQualityReviewer.parseReviewResult(from: reviewResponse)
        return ChapterQualityReviewer.mergeLocalHeuristicIssues(
            into: ChapterQualityReviewer.mergeLocalAntiPatterns(
                into: review,
                localPatterns: localPatterns
            ),
            localIssues: localIssues
        )
    }

    static func enhancedReviewUserPrompt(
        project: NovelProject,
        chapterDraft: String,
        memoryContext: String
    ) -> String {
        EnhancedPromptBudget.boundedPrompt(
            ChapterQualityReviewer.reviewUserPrompt(
                project: project,
                chapterDraft: chapterDraft,
                memoryContext: memoryContext
            )
        )
    }

    private static func shouldRepairCandidate(
        review: ChapterReviewResult,
        minimumAcceptedScore: Int
    ) -> Bool {
        return review.hasBlockingIssues
            || review.overallScore < minimumAcceptedScore
            || review.nonBlockingIssues.contains { $0.severity == .high }
    }

    private static func completeEnhancedText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let prompts = EnhancedPromptBudget.boundedRequestPrompts(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
        return try await AIWritingService.generateText(
            configuration: configuration,
            systemPrompt: prompts.systemPrompt,
            userPrompt: prompts.userPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

}

// MARK: - Enhanced Prompt Total Budget

nonisolated enum EnhancedPromptBudget {
    static let maximumCharacters = RankedContextBudget.maximumCharacters
    static let truncationMarker = "\n[提示词内容因总预算已截断]\n"
    static let minimumReservedUserCharacters = maximumCharacters / 2
    static let preferredUserTaskTailCharacters = 4_000

    static func boundedContent(
        _ text: String,
        fallback: String,
        limit: Int
    ) -> String {
        guard limit > 0 else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? fallback : trimmed
        guard resolved.count > limit else { return resolved }

        guard limit > truncationMarker.count else {
            return String(truncationMarker.prefix(limit))
        }

        let contentBudget = limit - truncationMarker.count
        let prefixBudget = (contentBudget * 2) / 3
        let suffixBudget = contentBudget - prefixBudget
        return String(resolved.prefix(prefixBudget))
            + truncationMarker
            + String(resolved.suffix(suffixBudget))
    }

    static func boundedPrompt(
        _ prompt: String,
        maximumCharacters: Int = maximumCharacters,
        preferredSuffixCharacters: Int? = nil
    ) -> String {
        guard maximumCharacters > 0 else { return "" }
        guard prompt.count > maximumCharacters else { return prompt }
        guard maximumCharacters > truncationMarker.count else {
            return String(truncationMarker.prefix(maximumCharacters))
        }

        let contentBudget = maximumCharacters - truncationMarker.count
        let suffixBudget: Int
        if let preferredSuffixCharacters {
            suffixBudget = min(
                contentBudget,
                max(0, preferredSuffixCharacters)
            )
        } else {
            suffixBudget = contentBudget / 3
        }
        let prefixBudget = contentBudget - suffixBudget
        return String(prompt.prefix(prefixBudget))
            + truncationMarker
            + String(prompt.suffix(suffixBudget))
    }

    static func boundedRequestPrompts(
        systemPrompt: String,
        userPrompt: String,
        maximumCharacters: Int = maximumCharacters
    ) -> (systemPrompt: String, userPrompt: String) {
        guard maximumCharacters > 0 else { return ("", "") }
        guard systemPrompt.count + userPrompt.count > maximumCharacters else {
            return (systemPrompt, userPrompt)
        }

        // When both prompts are oversized, reserve half of the current total
        // budget for the user prompt so its task/output tail cannot be crowded
        // out by a growing system guide. A shorter system prompt automatically
        // releases its unused capacity back to the user prompt.
        let userReservation = min(
            userPrompt.count,
            min(minimumReservedUserCharacters, maximumCharacters / 2)
        )
        let boundedSystemPrompt = boundedPrompt(
            systemPrompt,
            maximumCharacters: maximumCharacters - userReservation
        )
        let userBudget = max(
            0,
            maximumCharacters - boundedSystemPrompt.count
        )
        let boundedUserPrompt = boundedPrompt(
            userPrompt,
            maximumCharacters: userBudget,
            preferredSuffixCharacters: min(
                preferredUserTaskTailCharacters,
                userBudget / 2
            )
        )
        return (boundedSystemPrompt, boundedUserPrompt)
    }

    static func render(
        prefix: String,
        rankedSections: [ContextSection],
        suffix: String,
        maximumCharacters: Int = maximumCharacters
    ) -> String {
        guard maximumCharacters > 0 else { return "" }

        let fixedCharacterCount = prefix.count + suffix.count
        if fixedCharacterCount <= maximumCharacters {
            let rankedBudget = maximumCharacters - fixedCharacterCount
            return prefix
                + RankedContextBudget.render(
                    rankedSections,
                    maximumCharacters: rankedBudget
                )
                + suffix
        }

        // Future fixed-copy growth must still fail bounded while preserving
        // both the high-priority contract prefix and final output rules.
        guard maximumCharacters > truncationMarker.count else {
            return String(truncationMarker.prefix(maximumCharacters))
        }
        let contentBudget = maximumCharacters - truncationMarker.count
        let desiredSuffixBudget = min(suffix.count, contentBudget / 3)
        var prefixBudget = min(prefix.count, contentBudget - desiredSuffixBudget)
        var suffixBudget = min(suffix.count, contentBudget - prefixBudget)
        let unusedBudget = contentBudget - prefixBudget - suffixBudget
        if unusedBudget > 0 {
            let extraPrefix = min(unusedBudget, prefix.count - prefixBudget)
            prefixBudget += extraPrefix
            suffixBudget += min(
                unusedBudget - extraPrefix,
                suffix.count - suffixBudget
            )
        }

        return String(prefix.prefix(prefixBudget))
            + truncationMarker
            + String(suffix.suffix(suffixBudget))
    }
}

// MARK: - Enhanced Writing Support Context

struct EnhancedWritingSupport {
    let currentDraftExcerpt: String
    let relevantReferences: String
    let chapterTreeFocus: String
    let styleFingerprint: String
    let enhancedMemoryContext: String
    let longformStorySystemContext: String
    let writingExecutionContractContext: String
    let minimumAcceptedScore: Int
    let strandContext: String
    let genreTemplateContext: String

    init(project: NovelProject) {
        let baseSupport = AIWritingService.WritingSupportContext(project: project)
        let longformPromptContext = LongformStorySystem.buildPromptContext(for: project)
        currentDraftExcerpt = baseSupport.currentDraftExcerpt
        relevantReferences = baseSupport.relevantReferences
        chapterTreeFocus = baseSupport.chapterTreeFocus
        styleFingerprint = baseSupport.styleFingerprint
        enhancedMemoryContext = project.enhancedMemoryContext
        longformStorySystemContext = longformPromptContext.contract.writingBrief
        writingExecutionContractContext = AIWritingService.writingExecutionContractPrompt(
            project: project,
            context: longformPromptContext
        )
        minimumAcceptedScore = longformPromptContext.contract.review.minimumAcceptedScore
        strandContext = project.strandContext
        genreTemplateContext = project.genreTemplateContext
    }
}

// MARK: - Enhanced Writing Result

struct EnhancedWritingResult {
    let text: String
    let validation: PrewriteValidationResult
    let review: ChapterReviewResult?
    let minimumAcceptedScore: Int
    let strandWarning: StrandWeaveState.PacingWarning?
    let memoryUpdate: MemoryUpdateContext?

    var isSuccessful: Bool {
        !text.isEmpty && validation.isReady && (review?.passes(minimumScore: minimumAcceptedScore) ?? true)
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
            if review.passes(minimumScore: minimumAcceptedScore) {
                lines.append("✅ 已达到当前规模最低审查线 \(minimumAcceptedScore)/100")
            } else if review.hasBlockingIssues {
                lines.append("⛔ 存在阻断问题，当前候选稿不能直接进入长篇正文链。")
            } else {
                lines.append("⛔ 审查分数低于当前规模最低线 \(minimumAcceptedScore)/100，请先重写或修订。")
            }
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
