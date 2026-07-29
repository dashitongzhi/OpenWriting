import XCTest
@testable import OpenWriting

@MainActor
final class NovelProjectTests: XCTestCase {

    // MARK: - NovelProject Basic Tests

    func testNovelProjectCreation() {
        let project = NovelProject(
            title: "测试小说",
            genre: "都市",
            summary: "这是一个测试故事"
        )

        XCTAssertEqual(project.title, "测试小说")
        XCTAssertEqual(project.genre, "都市")
        XCTAssertEqual(project.summary, "这是一个测试故事")
        XCTAssertEqual(project.storyLength, .medium) // Default
        XCTAssertEqual(project.writtenChapters, 0)
        XCTAssertEqual(project.currentChapterNumber, 1)
        XCTAssertEqual(project.currentVolumeNumber, 1)
    }

    func testNovelProjectDefaultValues() {
        let project = NovelProject(
            title: "Test",
            genre: "Test",
            summary: "Test"
        )

        XCTAssertEqual(project.draftText, "")
        XCTAssertEqual(project.outlineText, "")
        XCTAssertEqual(project.chapterCatalog, [])
        XCTAssertEqual(project.chapterDrafts, [])
    }

    // MARK: - Chapter Draft Tests

    func testChapterDraftCreation() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "这是第一章的内容。这是一个很长的测试内容。"
        )

        XCTAssertEqual(draft.volumeNumber, 1)
        XCTAssertEqual(draft.chapterNumber, 1)
        XCTAssertEqual(draft.chapterTitle, "第一章")
        XCTAssertFalse(draft.content.isEmpty)
    }

    func testChapterDraftWordCount() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "测试",
            content: "这是测试内容。包含中文和标点符号！"
        )

        // Word count counts non-whitespace unicode scalars
        let wordCount = draft.wordCount
        XCTAssertGreaterThan(wordCount, 0)
    }

    func testChapterDraftVersionSnapshot() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "测试章节",
            content: "原始内容"
        )

        let version = draft.versionSnapshot(reason: "手动保存", savedAt: "2026-06-06")
        XCTAssertEqual(version.chapterTitle, "测试章节")
        XCTAssertEqual(version.content, "原始内容")
        XCTAssertEqual(version.reason, "手动保存")
    }

    func testChapterDraftSorting() {
        let draft1 = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "内容1"
        )
        let draft2 = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "第二章",
            content: "内容2"
        )
        let draft3 = ChapterDraft(
            volumeNumber: 2,
            chapterNumber: 1,
            chapterTitle: "第三卷第一章",
            content: "内容3"
        )

        let sorted = [draft3, draft1, draft2].sorted(by: ChapterDraft.sortDescending)
        XCTAssertEqual(sorted[0].chapterNumber, 1)
        XCTAssertEqual(sorted[0].volumeNumber, 2) // Volume 2 comes first
        XCTAssertEqual(sorted[1].chapterNumber, 2)
        XCTAssertEqual(sorted[2].chapterNumber, 1)
    }

    // MARK: - Chapter Draft Metadata Tests

    func testChapterDraftMetadataFromDraft() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 5,
            chapterTitle: "测试章节",
            content: "这是测试章节的完整内容。"
        )

        let metadata = ChapterDraftMetadata(chapterDraft: draft)

        XCTAssertEqual(metadata.volumeNumber, 1)
        XCTAssertEqual(metadata.chapterNumber, 5)
        XCTAssertEqual(metadata.chapterTitle, "测试章节")
        XCTAssertGreaterThan(metadata.wordCount, 0)
        XCTAssertFalse(metadata.previewText.isEmpty)
    }

    func testChapterDraftMetadataSorting() {
        let meta1 = ChapterDraftMetadata(chapterDraft: ChapterDraft(
            id: "1",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "预览1",
            savedAt: "2024-01-01"
        ))
        let meta2 = ChapterDraftMetadata(chapterDraft: ChapterDraft(
            id: "2",
            volumeNumber: 1,
            chapterNumber: 2,
            chapterTitle: "第二章",
            content: "预览2",
            savedAt: "2024-01-02"
        ))

        let sorted = [meta2, meta1].sorted(by: ChapterDraftMetadata.sortDescending)
        XCTAssertEqual(sorted[0].chapterNumber, 2)
    }

    // MARK: - Volume Planning Tests

    func testNovelProjectVolumeNumberIsNormalized() {
        let project = NovelProject(
            id: "volume-normalization",
            title: "测试小说",
            genre: "都市",
            summary: "故事的开始",
            updatedAt: "2026-06-06",
            currentChapterTitle: "第一章",
            currentVolumeNumber: 0,
            currentChapterNumber: 1,
            writtenChapters: 0,
            chapterFocus: "推进开篇",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: []
        )

        XCTAssertEqual(project.currentVolumeNumber, 1)
    }

    func testLongLengthSupportsVolumePlanning() {
        XCTAssertTrue(NovelLength.long.supportsVolumePlanning)
        XCTAssertTrue(NovelLength.long.creationChecklist.contains { $0.contains("分卷") })
    }

    func testShortAndMediumDoNotRequireVolumePlanning() {
        XCTAssertFalse(NovelLength.short.supportsVolumePlanning)
        XCTAssertFalse(NovelLength.medium.supportsVolumePlanning)
    }

    // MARK: - Reference Document Tests

    func testReferenceDocumentCreation() {
        let doc = ReferenceDocument(
            title: "主角设定",
            content: "主角是一个年轻人..."
        )

        XCTAssertEqual(doc.title, "主角设定")
        XCTAssertFalse(doc.content.isEmpty)
    }

    func testReferenceDocumentCategoryInference() {
        let category = ReferenceMaterialCategory.infer(fromTitle: "主角人物设定", content: "姓名：小明\n年龄：20")
        XCTAssertEqual(category, .character)
    }

    func testReferenceDocumentWordCount() {
        let doc = ReferenceDocument(
            title: "测试",
            content: "这是测试内容。"
        )

        XCTAssertGreaterThan(doc.wordCount, 0)
    }

    // MARK: - Global Memory Snapshot Tests

    func testGlobalMemorySnapshotEmpty() {
        let memory = GlobalMemorySnapshot.empty

        XCTAssertEqual(memory.recentDevelopments, "")
        XCTAssertEqual(memory.characterRelations, "")
        XCTAssertEqual(memory.populatedSectionCount, 0)
        XCTAssertFalse(memory.hasStructuredContent)
    }

    func testGlobalMemorySnapshotSetValue() {
        var memory = GlobalMemorySnapshot.empty

        memory.setValue("主角受伤了", for: .injuries)
        memory.setValue("主角与反派的关系紧张", for: .characterRelations)

        XCTAssertEqual(memory.recentDevelopments, "")
        XCTAssertEqual(memory.injuries, "主角受伤了")
        XCTAssertEqual(memory.characterRelations, "主角与反派的关系紧张")
        XCTAssertEqual(memory.populatedSectionCount, 2)
        XCTAssertTrue(memory.hasStructuredContent)
    }

    func testGlobalMemorySnapshotParseFrom() {
        let text = """
        前情推进
        主角刚刚完成了第一个任务

        人物关系
        主角和配角A是好朋友

        关键地点
        城市中心广场
        """

        let memory = GlobalMemorySnapshot.parse(from: text)

        XCTAssertFalse(memory.recentDevelopments.isEmpty)
        XCTAssertFalse(memory.characterRelations.isEmpty)
        XCTAssertFalse(memory.locations.isEmpty)
    }

    func testGlobalMemorySnapshotFormattedText() {
        var memory = GlobalMemorySnapshot.empty
        memory.setValue("测试发展", for: .recentDevelopments)
        memory.setValue("测试关系", for: .characterRelations)

        let formatted = memory.formattedText

        XCTAssertTrue(formatted.contains("前情推进"))
        XCTAssertTrue(formatted.contains("测试发展"))
        XCTAssertTrue(formatted.contains("人物关系"))
        XCTAssertTrue(formatted.contains("测试关系"))
    }

    func testPrimaryWritingPromptsInjectStructuredLongTermMemory() {
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .storyFact,
            subject: "玄铁令",
            field: "归属",
            value: "仍在沈青袖手中",
            sourceChapter: 7
        ))
        let project = NovelProject(
            id: "prompt-memory-project",
            title: "长篇测试",
            genre: "玄幻",
            summary: "围绕玄铁令展开的长篇故事",
            storyLength: .long,
            updatedAt: "2026-06-06",
            currentChapterTitle: "夜探山门",
            currentChapterNumber: 8,
            writtenChapters: 7,
            chapterFocus: "沈青袖确认玄铁令的下一步用途",
            draftText: "山门外的风压低了灯火。",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: [],
            persistedMemoryBuckets: buckets
        )
        let support = AIWritingService.WritingSupportContext(project: project)

        let mainPrompt = AIWritingService.userPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: "",
            length: .short,
            support: support,
            writingPlan: "- 承接山门外的场景。"
        )
        let planPrompt = AIWritingService.writingPlanUserPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: "",
            length: .short,
            support: support
        )

        XCTAssertTrue(project.enhancedMemoryContext.contains("仍在沈青袖手中"))
        XCTAssertTrue(mainPrompt.contains("结构化长期记忆"))
        XCTAssertTrue(mainPrompt.contains("仍在沈青袖手中"))
        XCTAssertTrue(planPrompt.contains("结构化长期记忆"))
        XCTAssertTrue(planPrompt.contains("仍在沈青袖手中"))
    }

    func testEnhancedMemoryContextKeepsRelevantOpenLoopBeyondCoreBudget() {
        var buckets = MemoryBuckets.empty
        for index in 1...120 {
            buckets.upsert(MemoryItem(
                category: .worldRule,
                subject: "世界规则\(index)",
                field: "限制",
                value: String(repeating: "该规则必须持续生效", count: 6),
                sourceChapter: index
            ))
        }
        buckets.upsert(MemoryItem(
            category: .openLoop,
            subject: "银色纹路",
            field: "血脉真相",
            value: "月下伤口浮现银色纹路，仍需追查其真正来源",
            sourceChapter: 121
        ))

        var project = NovelProject(
            title: "超长篇记忆测试",
            genre: "玄幻",
            summary: "主角追查血脉真相",
            storyLength: .long
        )
        project.currentChapterNumber = 122
        project.chapterFocus = "调查银色纹路与血脉真相"
        project.draftText = "他再次看见伤口上的银色纹路。"
        project.persistedMemoryBuckets = buckets

        XCTAssertTrue(project.enhancedMemoryContext.contains("仍需追查其真正来源"))
        XCTAssertLessThanOrEqual(project.enhancedMemoryContext.count, NovelProject.enhancedMemoryContextCharacterLimit + 40)
    }

    func testEnhancedUserPromptUsesOneDeterministicTotalCharacterBudget() {
        let oversized = String(repeating: "超长上下文必须参与同一个总预算。", count: 900)
        let previousChapter = ChapterDraft(
            id: "prompt-budget-previous",
            volumeNumber: 1,
            chapterNumber: 7,
            chapterTitle: "HISTORY-SENTINEL",
            content: oversized + "HISTORY-ENDING-SENTINEL",
            savedAt: "2026-06-06"
        )
        let project = NovelProject(
            id: "prompt-budget-project",
            title: "总预算测试",
            genre: "玄幻",
            summary: "SUMMARY-SENTINEL " + oversized,
            storyLength: .long,
            updatedAt: "2026-06-06",
            currentChapterTitle: "山门夜变",
            currentChapterNumber: 8,
            writtenChapters: 7,
            chapterFocus: "CONTRACT-SENTINEL " + oversized,
            draftText: "DRAFT-SENTINEL " + oversized,
            outlineText: "OUTLINE-SENTINEL " + oversized,
            structureNotes: oversized,
            sceneProgressNotes: oversized,
            characterArcNotes: oversized,
            foreshadowNotes: oversized,
            volumePlanNotes: oversized,
            activeThreadsNotes: oversized,
            outlineSummary: oversized,
            referenceContextText: oversized,
            specialRequirements: oversized,
            wordTargetText: oversized,
            continuityNotes: oversized,
            referenceDocuments: [],
            chapterDrafts: [previousChapter]
        )
        let support = EnhancedWritingSupport(project: project)

        let first = AIWritingService.enhancedUserPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: "EXTRA-INSTRUCTION-SENTINEL " + oversized,
            length: .short,
            support: support,
            writingPlan: "PLAN-SENTINEL " + oversized
        )
        let second = AIWritingService.enhancedUserPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: "EXTRA-INSTRUCTION-SENTINEL " + oversized,
            length: .short,
            support: support,
            writingPlan: "PLAN-SENTINEL " + oversized
        )

        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(first.count, RankedContextBudget.maximumCharacters)
        XCTAssertTrue(first.contains("SUMMARY-SENTINEL"))
        XCTAssertTrue(first.contains("CONTRACT-SENTINEL"))
        XCTAssertTrue(first.contains("PLAN-SENTINEL"))
        XCTAssertTrue(first.contains("HISTORY-SENTINEL"))
        XCTAssertTrue(first.contains("EXTRA-INSTRUCTION-SENTINEL"))
        XCTAssertTrue(first.contains("请直接输出续写后的正文"))
        XCTAssertTrue(first.contains("[提示词内容因总预算已截断]"))
    }

    func testEveryEnhancedRequestPathUsesTheSameFinalPromptBudget() {
        let oversized = String(repeating: "所有动态内容必须共享最终提示词预算。", count: 1_500)
        let project = NovelProject(
            id: "all-enhanced-prompt-paths",
            title: "PROJECT-SENTINEL " + oversized,
            genre: "悬疑",
            summary: "SUMMARY-SENTINEL " + oversized,
            storyLength: .long,
            updatedAt: "2026-07-28",
            currentChapterTitle: "钟楼密信",
            currentChapterNumber: 9,
            writtenChapters: 8,
            chapterFocus: "GOAL-SENTINEL " + oversized,
            draftText: oversized + " CURRENT-DRAFT-SENTINEL",
            outlineText: "OUTLINE-SENTINEL " + oversized,
            structureNotes: "第9章：CONTRACT-CONTEXT-SENTINEL\n" + oversized,
            sceneProgressNotes: oversized,
            characterArcNotes: oversized,
            foreshadowNotes: oversized,
            volumePlanNotes: oversized,
            activeThreadsNotes: oversized,
            outlineSummary: oversized,
            referenceContextText: oversized,
            specialRequirements: "USER-REQUIREMENT-SENTINEL " + oversized,
            wordTargetText: oversized,
            continuityNotes: "MEMORY-SENTINEL " + oversized,
            referenceDocuments: []
        )
        let support = EnhancedWritingSupport(project: project)
        XCTAssertTrue(support.currentDraftExcerpt.contains("CURRENT-DRAFT-SENTINEL"))
        XCTAssertTrue(support.enhancedMemoryContext.contains("MEMORY-SENTINEL"))
        XCTAssertTrue(
            support.longformStorySystemContext.contains("CONTRACT-CONTEXT-SENTINEL")
        )
        let candidate = "CANDIDATE-SENTINEL " + oversized + " CANDIDATE-TAIL-SENTINEL"
        let plan = "PLAN-SENTINEL " + oversized
        let additionalInstruction = "ADDITIONAL-SENTINEL " + oversized
        let review = ChapterReviewResult(
            overallScore: 40,
            dimensionScores: [:],
            issues: [],
            hasBlockingIssues: true,
            antiPatterns: [],
            overallSummary: "REVIEW-FEEDBACK-SENTINEL " + oversized
        )

        let prompts: [(path: String, prompt: String, requiredInstruction: String)] = [
            (
                "planning",
                AIWritingService.enhancedWritingPlanPrompt(
                    project: project,
                    mode: .advanceChapter,
                    additionalInstruction: additionalInstruction,
                    length: .short,
                    support: support
                ),
                "请给出本次续写的 3 到 5 个执行拍点"
            ),
            (
                "revision",
                AIWritingService.enhancedWritingRevisionUserPrompt(
                    project: project,
                    mode: .advanceChapter,
                    additionalInstruction: additionalInstruction,
                    length: .short,
                    support: support,
                    writingPlan: plan,
                    draft: candidate
                ),
                "只输出修订后的完整候选正文"
            ),
            (
                "review repair",
                AIWritingService.enhancedWritingReviewRepairUserPrompt(
                    project: project,
                    mode: .advanceChapter,
                    additionalInstruction: additionalInstruction,
                    length: .short,
                    support: support,
                    writingPlan: plan,
                    draft: candidate,
                    review: review
                ),
                "只输出返修后的完整候选正文"
            ),
            (
                "supplement",
                AIWritingService.enhancedWritingSupplementUserPrompt(
                    project: project,
                    length: .short,
                    support: support,
                    writingPlan: plan,
                    draft: candidate
                ),
                "只输出补写部分，接在已有候选正文之后即可"
            ),
            (
                "quality review",
                AIWritingService.enhancedReviewUserPrompt(
                    project: project,
                    chapterDraft: candidate,
                    memoryContext: "REVIEW-MEMORY-SENTINEL " + oversized
                ),
                "输出格式（严格 JSON）"
            )
        ]

        for entry in prompts {
            XCTAssertLessThanOrEqual(
                entry.prompt.count,
                EnhancedPromptBudget.maximumCharacters,
                "\(entry.path) exceeded the final prompt budget"
            )
            XCTAssertTrue(
                entry.prompt.contains(entry.requiredInstruction),
                "\(entry.path) lost its critical task instruction"
            )
            XCTAssertTrue(
                entry.prompt.contains("[提示词内容因总预算已截断]"),
                "\(entry.path) did not report deterministic truncation"
            )
        }

        let contextSensitiveRequests: [
            (
                path: String,
                systemPrompt: String,
                userPrompt: String,
                requiredSignals: [String]
            )
        ] = [
            (
                "revision",
                AIWritingService.writingRevisionSystemPrompt,
                AIWritingService.enhancedWritingRevisionUserPrompt(
                    project: project,
                    mode: .advanceChapter,
                    additionalInstruction: additionalInstruction,
                    length: .short,
                    support: support,
                    writingPlan: plan,
                    draft: candidate
                ),
                [
                    "CURRENT-DRAFT-SENTINEL",
                    "PLAN-SENTINEL",
                    "ADDITIONAL-SENTINEL",
                    "MEMORY-SENTINEL",
                    "CONTRACT-CONTEXT-SENTINEL",
                    "CANDIDATE-TAIL-SENTINEL"
                ]
            ),
            (
                "review repair",
                AIWritingService.writingReviewRepairSystemPrompt,
                AIWritingService.enhancedWritingReviewRepairUserPrompt(
                    project: project,
                    mode: .advanceChapter,
                    additionalInstruction: additionalInstruction,
                    length: .short,
                    support: support,
                    writingPlan: plan,
                    draft: candidate,
                    review: review
                ),
                [
                    "CURRENT-DRAFT-SENTINEL",
                    "PLAN-SENTINEL",
                    "ADDITIONAL-SENTINEL",
                    "MEMORY-SENTINEL",
                    "CONTRACT-CONTEXT-SENTINEL",
                    "CANDIDATE-TAIL-SENTINEL"
                ]
            ),
            (
                "supplement",
                AIWritingService.writingSupplementSystemPrompt,
                AIWritingService.enhancedWritingSupplementUserPrompt(
                    project: project,
                    length: .short,
                    support: support,
                    writingPlan: plan,
                    draft: candidate
                ),
                [
                    "CURRENT-DRAFT-SENTINEL",
                    "PLAN-SENTINEL",
                    "MEMORY-SENTINEL",
                    "CONTRACT-CONTEXT-SENTINEL",
                    "CANDIDATE-TAIL-SENTINEL"
                ]
            )
        ]

        for entry in contextSensitiveRequests {
            let boundedRequest = EnhancedPromptBudget.boundedRequestPrompts(
                systemPrompt: entry.systemPrompt,
                userPrompt: entry.userPrompt
            )
            XCTAssertLessThanOrEqual(
                boundedRequest.systemPrompt.count + boundedRequest.userPrompt.count,
                EnhancedPromptBudget.maximumCharacters,
                "\(entry.path) exceeded the final system + user prompt budget"
            )
            for signal in entry.requiredSignals {
                XCTAssertTrue(
                    boundedRequest.userPrompt.contains(signal),
                    "\(entry.path) lost required context signal \(signal)"
                )
            }
        }
    }

    func testEnhancedRequestBudgetIncludesSystemAndUserPrompts() {
        let oversized = String(repeating: "系统与用户提示词必须共享总预算。", count: 2_000)
        let systemPrompt = "SYSTEM-PREFIX-SENTINEL " + oversized + " SYSTEM-TAIL-SENTINEL"
        let userPrompt = "USER-PREFIX-SENTINEL " + oversized + " CRITICAL-USER-TASK-TAIL"

        let first = EnhancedPromptBudget.boundedRequestPrompts(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
        let second = EnhancedPromptBudget.boundedRequestPrompts(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        XCTAssertEqual(first.systemPrompt, second.systemPrompt)
        XCTAssertEqual(first.userPrompt, second.userPrompt)
        XCTAssertLessThanOrEqual(
            first.systemPrompt.count + first.userPrompt.count,
            EnhancedPromptBudget.maximumCharacters
        )
        XCTAssertGreaterThanOrEqual(
            first.userPrompt.count,
            EnhancedPromptBudget.minimumReservedUserCharacters
        )
        XCTAssertTrue(first.systemPrompt.contains("SYSTEM-PREFIX-SENTINEL"))
        XCTAssertTrue(first.systemPrompt.contains("SYSTEM-TAIL-SENTINEL"))
        XCTAssertTrue(first.userPrompt.contains("USER-PREFIX-SENTINEL"))
        XCTAssertTrue(first.userPrompt.hasSuffix("CRITICAL-USER-TASK-TAIL"))
        XCTAssertTrue(first.systemPrompt.contains("[提示词内容因总预算已截断]"))
        XCTAssertTrue(first.userPrompt.contains("[提示词内容因总预算已截断]"))

        let unchanged = EnhancedPromptBudget.boundedRequestPrompts(
            systemPrompt: "短系统指令",
            userPrompt: "短用户任务"
        )
        XCTAssertEqual(unchanged.systemPrompt, "短系统指令")
        XCTAssertEqual(unchanged.userPrompt, "短用户任务")
    }

    func testLongformPromptContextPreservesStandalonePromptSemantics() {
        let project = NovelProject(
            id: "prompt-context-project",
            title: "长篇上下文复用测试",
            genre: "悬疑",
            summary: "调查员追查一封来自未来的信。",
            storyLength: .long,
            updatedAt: "2026-06-06",
            currentChapterTitle: "钟楼回声",
            currentChapterNumber: 3,
            writtenChapters: 0,
            chapterFocus: "确认钟楼内第二封信的来源",
            draftText: "雨水沿着铜钟的裂纹往下淌。",
            outlineText: "第3章：进入钟楼，发现第二封信，但暂不揭示寄信者。",
            structureNotes: "第3章必须确认信件时间戳异常。",
            sceneProgressNotes: "钟楼入口 -> 机械室 -> 铜钟背面。",
            characterArcNotes: "调查员开始怀疑自己的记忆。",
            foreshadowNotes: "旧表停在三点十七分，暂不回收。",
            volumePlanNotes: "第一卷目标：确认未来信件真实存在。",
            activeThreadsNotes: "主线：未来信；关系线：调查员与守钟人互不信任。",
            outlineSummary: "调查进入证据验证阶段。",
            referenceContextText: "钟楼建于一百年前。",
            specialRequirements: "保持有限视角。",
            wordTargetText: "本章约 2000 字。",
            continuityNotes: "调查员左手仍有旧伤。",
            referenceDocuments: []
        )

        let context = LongformStorySystem.buildPromptContext(for: project)
        let cachedPrompt = AIWritingService.writingExecutionContractPrompt(
            project: project,
            context: context
        )
        let standalonePrompt = AIWritingService.writingExecutionContractPrompt(
            project: project
        )
        let support = EnhancedWritingSupport(project: project)

        XCTAssertEqual(cachedPrompt, standalonePrompt)
        XCTAssertEqual(
            context.contract.writingBrief,
            LongformStorySystem.contextBlock(for: project)
        )
        XCTAssertEqual(
            context.nextChapterBrief.formattedForPrompt,
            project.longformNextChapterBrief.formattedForPrompt
        )
        XCTAssertEqual(
            context.qualityTrend.formattedForPrompt,
            project.longformQualityTrend.formattedForPrompt
        )
        XCTAssertEqual(context.health.summary, project.longformRuntimeHealth.summary)
        XCTAssertEqual(support.longformStorySystemContext, context.contract.writingBrief)
        XCTAssertEqual(support.writingExecutionContractContext, cachedPrompt)
        XCTAssertEqual(
            support.minimumAcceptedScore,
            context.contract.review.minimumAcceptedScore
        )
    }
}
