import Foundation

struct AIConnectionConfiguration {
    let baseURL: URL
    let apiKey: String
    let modelName: String
}

enum AIWritingMode: String, CaseIterable, Identifiable {
    case continueScene
    case advanceChapter
    case deepenTexture

    var id: Self { self }

    var title: String {
        switch self {
        case .continueScene:
            return "续写场景"
        case .advanceChapter:
            return "推进章节"
        case .deepenTexture:
            return "强化氛围"
        }
    }

    var instruction: String {
        switch self {
        case .continueScene:
            return "延续当前场景，不跳时空、不跳章节，优先承接正文最后一段。"
        case .advanceChapter:
            return "让本章目标产生实质进展，但不要破坏既有节奏和角色状态。"
        case .deepenTexture:
            return "保持情节方向不变，优先补强氛围、动作细节、对白张力与人物感受。"
        }
    }
}

enum AIWritingLength: String, CaseIterable, Identifiable {
    case short
    case medium
    case long

    var id: Self { self }

    var title: String {
        switch self {
        case .short:
            return "700 字"
        case .medium:
            return "1400 字"
        case .long:
            return "2200 字"
        }
    }

    var maxTokens: Int {
        switch self {
        case .short:
            return 1_050
        case .medium:
            return 1_850
        case .long:
            return 3_000
        }
    }

    var instruction: String {
        switch self {
        case .short:
            return "续写约 700 到 900 字，保持推进迅速。"
        case .medium:
            return "续写约 1400 到 1700 字，兼顾推进与氛围。"
        case .long:
            return "续写约 2200 到 2600 字，允许完整展开一个场景。"
        }
    }
}

enum AIWritingService {
    static func validateConnection(configuration: AIConnectionConfiguration) async throws -> String {
        let rawResponse = try await completeText(
            configuration: configuration,
            systemPrompt: "You are a concise assistant.",
            userPrompt: "Reply with exactly OK.",
            temperature: 0.1,
            maxTokens: 16
        )

        guard rawResponse == "OK" else {
            throw AIWritingError.serverError("模型返回异常内容：\(rawResponse)")
        }

        return configuration.modelName
    }

    static func continueChapter(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt(
                project: project,
                mode: mode,
                additionalInstruction: additionalInstruction,
                length: length
            ),
            temperature: 0.85,
            maxTokens: length.maxTokens
        )
    }

    static func polishFullDraft(
        configuration: AIConnectionConfiguration,
        draft: String,
        instruction: String
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: draftPolishSystemPrompt,
            userPrompt: fullDraftPolishUserPrompt(draft: draft, instruction: instruction),
            temperature: 0.45,
            maxTokens: max(1_600, min(6_000, draft.count + 800))
        )
    }

    static func polishSelection(
        configuration: AIConnectionConfiguration,
        selectedText: String,
        instruction: String,
        fullDraft: String,
        precedingContext: String,
        followingContext: String
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: selectionPolishSystemPrompt,
            userPrompt: selectionPolishUserPrompt(
                selectedText: selectedText,
                instruction: instruction,
                fullDraft: fullDraft,
                precedingContext: precedingContext,
                followingContext: followingContext
            ),
            temperature: 0.42,
            maxTokens: max(320, min(1_800, selectedText.count + 400))
        )
    }

    static func refreshChapterTree(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        chapterDraft: ChapterDraft
    ) async throws -> ChapterTreeRefresh {
        let rawResponse = try await completeText(
            configuration: configuration,
            systemPrompt: chapterTreeRefreshSystemPrompt,
            userPrompt: chapterTreeRefreshUserPrompt(project: project, chapterDraft: chapterDraft),
            temperature: 0.45,
            maxTokens: 2_200
        )

        let refresh = ChapterTreeRefresh.parse(from: rawResponse)
        guard refresh.hasStructuredContent else {
            throw AIWritingError.emptyResult
        }

        return refresh
    }

    static func suggestChapterTitle(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        draft: String
    ) async throws -> String {
        let rawTitle = try await completeText(
            configuration: configuration,
            systemPrompt: chapterTitleSystemPrompt,
            userPrompt: chapterTitleUserPrompt(project: project, draft: draft),
            temperature: 0.7,
            maxTokens: 80
        )

        let normalizedTitle = normalizeChapterTitle(rawTitle)
        guard !normalizedTitle.isEmpty else {
            throw AIWritingError.emptyResult
        }

        return normalizedTitle
    }

    static func generateStoryOutline(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        profile: OutlineGenerationProfile
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: outlineGenerationSystemPrompt,
            userPrompt: outlineGenerationUserPrompt(project: project, profile: profile),
            temperature: 0.72,
            maxTokens: 2_600
        )
    }

    static func refreshGlobalMemory(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        chapterDraft: ChapterDraft
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: globalMemorySystemPrompt,
            userPrompt: globalMemoryUserPrompt(project: project, chapterDraft: chapterDraft),
            temperature: 0.35,
            maxTokens: 1_800
        )
    }

    private static func completeText(
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

        let payload = ChatCompletionsRequest(
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

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard
            let text = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            throw AIWritingError.emptyResult
        }

        return text
    }

    private static let systemPrompt = """
    你是一位擅长中文长篇小说创作的原生写作助手。
    你的任务是续写当前章节，而不是重写设定。
    必须遵守：
    1. 保持人物语气、世界观规则和既有叙事视角一致。
    2. 优先承接上一已保存章节结尾与当前章节既定目标，保持节奏、句式和情绪连续。
    3. 只输出可直接接在正文后的小说内容，不要解释，不要列提纲，不要加标题。
    4. 如果参考文本与当前项目冲突，以当前项目摘要、大纲、全局记忆和已有正文为准。
    5. 根据项目规模控制叙事：短篇要集中闭环，中篇要稳住阶段推进，长篇要维护分卷延展、长期伏笔和人物长期状态。
    6. 保持连续性，避免突然跳到未来情节、提前透支长期真相或重复已写内容。
    """

    private static let chapterTreeRefreshSystemPrompt = """
    你是一位擅长中文长篇小说结构维护的章节树编辑。
    你的任务是根据最新保存章节，刷新当前项目的章节树工作区。
    必须遵守：
    1. 只根据用户提供的内容更新，不擅自添加没有依据的新人物、新设定或新剧情。
    2. 优先做“更新”而不是“重写”，保留仍然有效的既有记录，修正已经过时的判断。
    3. 输出必须严格使用以下 5 个标题，顺序不能变：
    章节树总结：
    章节骨架拆解：
    场景推进记录：
    角色弧线记录：
    伏笔与回收记录：
    4. 每个小节写 2 到 6 条以“- ”开头的短句，尽量具体，不写空泛议论。
    5. 结论要服务于连续创作：短篇强调闭环，中篇强调阶段推进，长篇强调分卷延展、长期伏笔和人物长期状态。
    6. 只输出这 5 个小节，不要解释，不要补充额外标题。
    """

    private static let globalMemorySystemPrompt = """
    你是一位擅长长篇小说连续性管理的全局记忆编辑。
    你的任务是根据最新保存章节，更新后续创作要用的长期记忆。
    必须遵守：
    1. 只根据用户提供的内容更新，不虚构没有依据的新设定。
    2. 优先记录“现在的真实状态”，过期信息要被替换或修正，避免简单重复堆叠。
    3. 输出必须严格使用以下 9 个标题，且顺序不能变：
    前情推进：
    人物关系：
    身份变化：
    伤势状态：
    阵营立场：
    关键地点：
    关键道具：
    世界状态：
    未回收伏笔：
    4. 每个小节使用 1 到 4 条以“- ”开头的短句；如果没有明确变化，就写“- 暂无明确变化”或“- 暂无新增”。
    5. 输出内容要能直接拿去做正文生成、断点恢复和一致性修正。
    6. 只输出全局记忆，不要解释。
    """

    private static let chapterTitleSystemPrompt = """
    你是一位擅长中文小说命名的章节编辑。
    你的任务是根据当前章节正文，为它拟一个适合长篇连载的章节标题。
    必须遵守：
    1. 只输出一个中文标题，不要解释，不要加引号，不要加“第X章”。
    2. 标题要贴合正文内容、氛围和推进重点，但避免剧透最终答案。
    3. 控制在 4 到 14 个汉字以内，尽量凝练、好记、有画面感。
    4. 如果用户已有章节标题，只把它当参考，不要机械重复。
    """

    private static let outlineGenerationSystemPrompt = """
    你是一位擅长中文长篇网文策划的大纲编辑。
    你的任务是根据用户给出的创作条件，产出一份可直接开写的小说大纲。
    必须遵守：
    1. 优先服从用户已经明确写出的总体流程、世界观、主角底色、预期字数和结局偏好。
    2. 若信息不足，只做最小必要补全，不要擅自改变题材方向、人物底色或结局倾向。
    3. 输出要服务于当前创作规模：短篇强调闭环，中篇强调阶段推进，长篇强调分卷、长期冲突和多层伏笔回收。
    4. 不要解释提示词结构，不要写“根据你的要求”，直接输出中文大纲正文。
    5. 请按以下结构输出：作品定位、总纲主线、阶段/分卷推进、核心人物与关系、关键事件与伏笔、结局落点。
    6. 请根据预期字数控制规模，字数越长，阶段规划和伏笔层级应越完整。
    """

    private static let draftPolishSystemPrompt = """
    你是一位擅长中文小说润色的编辑。
    你的任务是根据用户要求，直接改写整篇草稿。
    必须遵守：
    1. 保留原文的人称、时态、剧情事实、设定和人物关系，不擅自改剧情走向。
    2. 重点优化表达、节奏、动作细节、对白自然度、氛围与段落衔接。
    3. 如果用户给了具体要求，优先满足这些要求；如果没有要求，就做克制润色，不要过度重写。
    4. 只输出润色后的完整正文，不要解释，不要分点，不要加标题。
    """

    private static let selectionPolishSystemPrompt = """
    你是一位擅长中文小说局部润色的编辑。
    你的任务是只改写用户选中的那一段文本。
    必须遵守：
    1. 只输出润色后的选区文本，不要解释，不要加引号，不要重复上下文。
    2. 保留原意、人物状态与叙事事实，不擅自改剧情。
    3. 用词、节奏与语气要能和原稿前后文自然衔接。
    4. 如果用户给了润色要求，优先满足；如果没有，就做克制优化。
    """

    private static func userPrompt(
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength
    ) -> String {
        let references = project.referenceDocuments
            .prefix(4)
            .map { document in
                "参考《\(document.title)》：\n\(excerpt(from: document.content, limit: 1400))"
            }
            .joined(separator: "\n\n")

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
        let volumePlan = normalized(
            project.volumePlanNotes,
            fallback: project.storyLength.supportsVolumePlanning
                ? "当前还没有明确分卷规划，请至少先写清本卷目标、卷末回收点和下一卷的升级方向。"
                : "当前项目不以分卷规划为主。"
        )
        let activeThreads = normalized(
            project.activeThreadsNotes,
            fallback: project.storyLength.supportsThreadTracking
                ? "当前还没有整理在途线索，请至少明确主线、关系线和最近必须推进的伏笔线。"
                : "当前项目以单次闭环为主，不强调多线并行。"
        )

        return """
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

        全局记忆：
        \(normalized(project.continuityNotes, fallback: "暂无，请优先保持当前正文语气、叙事视角和冲突方向。"))

        作品大纲：
        \(normalized(project.outlineText, fallback: "暂无大纲，请依据项目摘要和当前章节目标稳步推进。"))

        分卷/阶段规划：
        \(volumePlan)

        在途线索：
        \(activeThreads)

        手动参考文本：
        \(normalized(project.referenceContextText, fallback: "暂无手动补充的参考文本。"))

        参考文本：
        \(normalized(references, fallback: "暂无导入参考文本。"))

        特殊要求：
        \(normalized(project.specialRequirements, fallback: "暂无额外特殊要求。"))

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
        如果提供了上一章节缓存，请优先承接缓存区里的最后一句、段落节奏和场景状态，但不要重复复述上一章已经写出的动作、对白、心理或信息。
        开场两段避免重复解释既有设定、人物关系和刚刚发生过的事件，默认读者记得上一章。
        每次续写至少推进一个新的情节拍点、关系变化或信息增量，不要用改写前文来充字数。
        若需承上启下，请用新的动作、冲突、观察或结果进入当前章节，而不是复述上一章摘要。
        请直接输出续写后的正文。
        """
    }

    private static func fullDraftPolishUserPrompt(
        draft: String,
        instruction: String
    ) -> String {
        let normalizedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedInstruction = normalizedInstruction.isEmpty
            ? "未额外指定要求，请做克制润色，重点提升表达、节奏和句子顺滑度。"
            : normalizedInstruction

        return """
        润色要求：
        \(resolvedInstruction)

        待润色全文：
        \(draft)
        """
    }

    private static func selectionPolishUserPrompt(
        selectedText: String,
        instruction: String,
        fullDraft: String,
        precedingContext: String,
        followingContext: String
    ) -> String {
        let normalizedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedInstruction = normalizedInstruction.isEmpty
            ? "未额外指定要求，请做克制润色，重点提升自然度、顺滑度和节奏。"
            : normalizedInstruction

        return """
        润色要求：
        \(resolvedInstruction)

        原稿全文（用于对齐语气与上下文，不要整段重写全文）：
        \(excerpt(from: fullDraft, limit: 3_200))

        选区前文（紧邻选区）：
        \(normalized(precedingContext, fallback: "选区前面没有更多正文。"))

        需要润色的选区：
        \(selectedText)

        选区后文（紧邻选区）：
        \(normalized(followingContext, fallback: "选区后面没有更多正文。"))
        """
    }

    private static func chapterTreeRefreshUserPrompt(
        project: NovelProject,
        chapterDraft: ChapterDraft
    ) -> String {
        let references = project.referenceDocuments
            .prefix(3)
            .map { document in
                "参考《\(document.title)》：\n\(excerpt(from: document.content, limit: 900))"
            }
            .joined(separator: "\n\n")

        return """
        项目名称：\(project.title)
        类型：\(project.genre)
        创作规模：\(project.storyLength.title)
        项目摘要：\(project.summary)
        当前进度：已创作 \(project.writtenChapters) 章
        最新保存章节：\(chapterDraft.chapterSummary)
        本章目标：\(project.chapterFocus)

        作品大纲：
        \(normalized(project.outlineText, fallback: "暂无完整大纲。"))

        章节骨架拆解：
        \(normalized(project.structureNotes, fallback: "暂无单独拆解，请先参考作品大纲。"))

        场景推进记录：
        \(normalized(project.sceneProgressNotes, fallback: "暂无场景推进记录。"))

        角色弧线记录：
        \(normalized(project.characterArcNotes, fallback: "暂无角色弧线记录。"))

        伏笔与回收记录：
        \(normalized(project.foreshadowNotes, fallback: "暂无伏笔回收记录。"))

        分卷/阶段规划：
        \(normalized(project.volumePlanNotes, fallback: project.storyLength.supportsVolumePlanning ? "暂无分卷规划。" : "当前项目不以分卷规划为主。"))

        在途线索：
        \(normalized(project.activeThreadsNotes, fallback: project.storyLength.supportsThreadTracking ? "暂无在途线索整理。" : "当前项目以单次闭环为主。"))

        全局记忆：
        \(normalized(project.continuityNotes, fallback: "暂无全局记忆。"))

        最新保存章节正文：
        \(normalized(excerpt(from: chapterDraft.content, limit: 3_600), fallback: "正文还较短，请重点根据大纲和本章目标判断结构。"))

        导入参考文本：
        \(normalized(references, fallback: "暂无导入参考文本。"))

        输出要求：
        请根据这次章节保存后最新形成的状态，刷新章节树工作区。
        章节树总结要概括当前结构位置、推进成效与下一步整理方向。
        章节骨架拆解要写清卷章承接、当前章节功能和上下文接力关系。
        场景推进记录要按场景拍点概括“发生了什么、推进了什么”。
        角色弧线记录要突出人物欲望变化、关系变化、立场变化或心理转折。
        伏笔与回收记录要区分“新增”“推进”“待回收”。
        结论要符合当前创作规模：\(project.storyLength.outlineDirective)
        """
    }

    private static func chapterTitleUserPrompt(project: NovelProject, draft: String) -> String {
        """
        项目名称：\(project.title)
        类型：\(project.genre)
        创作规模：\(project.storyLength.title)
        当前章节编号：\(project.currentChapterLabel)
        当前章节标题参考：\(normalized(project.currentChapterTitle, fallback: "暂无"))
        本章目标：\(project.chapterFocus)

        作品大纲：
        \(normalized(project.outlineText, fallback: "暂无完整大纲。"))

        手动参考文本：
        \(normalized(project.referenceContextText, fallback: "暂无手动参考文本。"))

        特殊要求：
        \(normalized(project.specialRequirements, fallback: "暂无额外特殊要求。"))

        当前章节正文：
        \(excerpt(from: draft, limit: 3_000))

        输出要求：
        请只返回一个可直接用于章节保存的标题。
        """
    }

    private static func outlineGenerationUserPrompt(
        project: NovelProject,
        profile: OutlineGenerationProfile
    ) -> String {
        """
        项目名称：\(project.title)
        类型：\(project.genre)
        创作规模：\(project.storyLength.title)
        项目摘要：\(normalized(project.summary, fallback: "暂无项目摘要。"))
        现有大纲参考：
        \(normalized(project.outlineText, fallback: "暂无现成大纲，请从零开始生成。"))

        规模要求：
        \(project.storyLength.outlineDirective)

        分卷/阶段规划：
        \(normalized(project.volumePlanNotes, fallback: project.storyLength.supportsVolumePlanning ? "暂无分卷规划，请按当前规模补足。" : "当前项目不以分卷规划为主。"))

        请将以下信息按 4 组理解并据此生成小说大纲：

        小说框架：
        - 总体流程：\(normalized(profile.storyFlow, fallback: "未填写，请以项目摘要为主补全。"))
        - 主要卖点：\(normalized(profile.sellingPoints, fallback: "未额外指定，请根据题材做最小必要补足。"))
        - 关键事件：\(normalized(profile.keyEvents, fallback: "未额外指定，请围绕总体流程补足关键转折。"))
        - 故事节奏：\(normalized(profile.storyPacing, fallback: "未额外指定，请按长篇连载的正常节奏安排。"))
        - 重要伏笔：\(normalized(profile.foreshadowingNotes, fallback: "未额外指定，请只补充必要伏笔。"))

        主要世界观：
        - 世界观描述：\(normalized(profile.worldDescription, fallback: "未填写，请只做最小必要补足。"))

        核心人物设定：
        - 主角性格标签：\(normalized(profile.protagonistTraits, fallback: "未填写，请根据项目摘要保守补足。"))
        - 角色动机与欲望：\(normalized(profile.motivations, fallback: "未额外指定，请从主线目标自然推导。"))
        - 人物关系图谱：\(normalized(profile.relationshipMap, fallback: "未额外指定，请只补充主线必要关系。"))
        - 反派的描绘：\(normalized(profile.antagonistPortrait, fallback: "未额外指定，请补足主线对抗面。"))

        输出控制参数：
        - 预期字数：\(normalized(profile.expectedLength, fallback: "未填写，请按中长篇规模生成。"))
        - 结局偏好：\(normalized(profile.endingPreference, fallback: "未填写，请默认做收束明确的结局。"))

        输出要求：
        1. 开篇要明确“故事怎么开头”，中段要写清“怎么推进”，结尾要点出“最终会走到哪里”。
        2. 世界观部分要把背景、势力、规则、境界体系或核心约束说清楚。
        3. 角色部分重点突出主角底色、欲望驱动、关键关系和反派压力。
        4. 如果用户填了卖点、关键事件、伏笔，请务必在大纲里落地，而不是只复述原话。
        5. 直接输出可用大纲，不要附加解释。
        """
    }

    private static func globalMemoryUserPrompt(
        project: NovelProject,
        chapterDraft: ChapterDraft
    ) -> String {
        """
        项目名称：\(project.title)
        类型：\(project.genre)
        创作规模：\(project.storyLength.title)
        项目摘要：\(normalized(project.summary, fallback: "暂无项目摘要。"))
        当前保存章节：\(chapterDraft.chapterSummary)
        当前创作进度：已创作 \(project.writtenChapters) 章

        现有全局记忆：
        \(normalized(project.continuityNotes, fallback: "暂无现成全局记忆，请根据本次保存章节建立第一版。"))

        作品大纲：
        \(normalized(project.outlineText, fallback: "暂无完整大纲。"))

        章节骨架拆解：
        \(normalized(project.structureNotes, fallback: "暂无章节骨架拆解。"))

        场景推进记录：
        \(normalized(project.sceneProgressNotes, fallback: "暂无场景推进记录。"))

        角色弧线记录：
        \(normalized(project.characterArcNotes, fallback: "暂无角色弧线记录。"))

        伏笔与回收记录：
        \(normalized(project.foreshadowNotes, fallback: "暂无伏笔回收记录。"))

        分卷/阶段规划：
        \(normalized(project.volumePlanNotes, fallback: project.storyLength.supportsVolumePlanning ? "暂无分卷规划。" : "当前项目不以分卷规划为主。"))

        在途线索：
        \(normalized(project.activeThreadsNotes, fallback: project.storyLength.supportsThreadTracking ? "暂无在途线索整理。" : "当前项目以单次闭环为主。"))

        章节树总结：
        \(normalized(project.outlineSummary, fallback: "暂无章节树总结。"))

        最新保存章节正文：
        \(excerpt(from: chapterDraft.content, limit: 4_200))

        输出要求：
        请把这次章节保存后，后续创作真正需要记住的长期信息整理出来。
        \(project.storyLength.continuityDirective)
        重点覆盖：前文发生过什么、人物关系、身份变化、伤势、阵营、地点、道具、世界状态、尚未回收的伏笔。
        """
    }

    private static func excerpt(from text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.suffix(limit))
    }

    private static func normalized(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func normalizeChapterTitle(_ text: String) -> String {
        let firstLine = text
            .components(separatedBy: CharacterSet.newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let strippedPrefix = firstLine.replacingOccurrences(
            of: #"^第?\s*\d+\s*章[：:·\-\s]*"#,
            with: "",
            options: .regularExpression
        )

        let stripped = strippedPrefix
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:·-—_ "))

        return stripped
    }
}

enum AIWritingError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AI 服务返回了无效响应。"
        case let .serverError(message):
            return "AI 服务调用失败：\(message)"
        case .emptyResult:
            return "AI 没有返回可插入的正文内容。"
        }
    }
}

private struct ChatCompletionsRequest: Encodable {
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

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
