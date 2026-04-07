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
            return "600 字"
        case .medium:
            return "1200 字"
        case .long:
            return "2000 字"
        }
    }

    var maxTokens: Int {
        switch self {
        case .short:
            return 900
        case .medium:
            return 1500
        case .long:
            return 2400
        }
    }

    var instruction: String {
        switch self {
        case .short:
            return "续写约 600 字，保持推进迅速。"
        case .medium:
            return "续写约 1200 字，兼顾推进与氛围。"
        case .long:
            return "续写约 2000 字，允许完整展开一个场景。"
        }
    }
}

enum AIWritingService {
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

    static func summarizeStoryStructure(
        configuration: AIConnectionConfiguration,
        project: NovelProject
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: outlineSummarySystemPrompt,
            userPrompt: outlineSummaryUserPrompt(project: project),
            temperature: 0.45,
            maxTokens: 1800
        )
    }

    static func polishPassage(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        passage: String
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: polishSystemPrompt,
            userPrompt: polishUserPrompt(project: project, passage: passage),
            temperature: 0.65,
            maxTokens: 1400
        )
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
    2. 优先延续已有正文最后一段的节奏、句式和情绪。
    3. 只输出可直接接在正文后的小说内容，不要解释，不要列提纲，不要加标题。
    4. 如果参考文本与当前项目冲突，以当前项目摘要、大纲、连续性笔记和已有正文为准。
    5. 保持长篇创作连续性，避免突然跳到未来情节或重复已写内容。
    """

    private static let polishSystemPrompt = """
    你是一位擅长中文小说润色的写作助手。
    你的任务是润色用户给出的现有正文片段，而不是续写新剧情。
    必须遵守：
    1. 不改变事件顺序、叙事视角、角色关系和核心信息。
    2. 优先优化句式、节奏、氛围、动作细节和对白张力。
    3. 保持人物口吻、世界观规则和长篇整体气质一致。
    4. 只输出润色后的正文内容，不要解释，不要对比，不要附加说明。
    """

    private static let outlineSummarySystemPrompt = """
    你是一位擅长中文长篇小说结构规划的章节编辑。
    你的任务是总结当前项目的章节树状态，只围绕用户给出的这一本书工作。
    必须遵守：
    1. 不添加原文中没有出现的新人物、新设定或新剧情。
    2. 优先根据作品大纲、场景推进、角色弧线、伏笔记录和正文摘要做结构判断。
    3. 输出应服务于长篇连续创作，帮助用户继续完善章节树。
    4. 直接给出中文总结，不要解释你的推理过程。
    5. 用清晰分段输出以下 5 个小节：当前结构判断、本章推进建议、角色弧线提醒、伏笔与回收、下一步整理动作。
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

        return """
        项目名称：\(project.title)
        类型：\(project.genre)
        项目摘要：\(project.summary)
        当前进度：已创作 \(project.writtenChapters) 章

        当前章节：\(project.currentChapterSummary)
        本章目标：\(project.chapterFocus)
        当前正文概况：\(project.draftWordCount) 字，约 \(project.draftParagraphCount) 段

        本次写作模式：
        \(mode.title)；\(mode.instruction)

        长篇连续性笔记：
        \(normalized(project.continuityNotes, fallback: "暂无，请优先保持当前正文语气、叙事视角和冲突方向。"))

        作品大纲：
        \(normalized(project.outlineText, fallback: "暂无大纲，请依据项目摘要和当前章节目标稳步推进。"))

        手动参考文本：
        \(normalized(project.referenceContextText, fallback: "暂无手动补充的参考文本。"))

        参考文本：
        \(normalized(references, fallback: "暂无导入参考文本。"))

        特殊要求：
        \(normalized(project.specialRequirements, fallback: "暂无额外特殊要求。"))

        字数设定：
        \(normalized(project.wordTargetText, fallback: "暂无专门字数设定，请按正常章节节奏展开。"))

        当前正文结尾：
        \(excerpt(from: project.draftText, limit: 4200))

        额外指令：
        \(normalized(additionalInstruction, fallback: "延续当前场景，不要跳章节。"))

        输出要求：
        \(length.instruction)
        必须保持与当前章节位置、角色口吻、时间线状态和伏笔进度一致。
        请直接输出续写后的正文。
        """
    }

    private static func polishUserPrompt(project: NovelProject, passage: String) -> String {
        let references = project.referenceDocuments
            .prefix(3)
            .map { document in
                "参考《\(document.title)》：\n\(excerpt(from: document.content, limit: 900))"
            }
            .joined(separator: "\n\n")

        return """
        项目名称：\(project.title)
        类型：\(project.genre)
        当前章节：\(project.currentChapterSummary)
        本章目标：\(project.chapterFocus)

        作品大纲：
        \(normalized(project.outlineText, fallback: "暂无大纲。"))

        连续性笔记：
        \(normalized(project.continuityNotes, fallback: "暂无连续性笔记，请保持原文气质与视角。"))

        手动参考文本：
        \(normalized(project.referenceContextText, fallback: "暂无手动参考文本。"))

        导入参考文本：
        \(normalized(references, fallback: "暂无导入参考文本。"))

        特殊要求：
        \(normalized(project.specialRequirements, fallback: "以统一语气、增强流畅度为主。"))

        字数设定：
        \(normalized(project.wordTargetText, fallback: "润色时保持段落体量稳定，不额外扩写。"))

        待润色正文：
        \(normalized(passage, fallback: "暂无可润色文本。"))

        输出要求：
        在不改剧情走向和核心信息的前提下，让文字更顺、更稳、更贴近当前项目风格。
        请直接输出润色后的正文。
        """
    }

    private static func outlineSummaryUserPrompt(project: NovelProject) -> String {
        let references = project.referenceDocuments
            .prefix(3)
            .map { document in
                "参考《\(document.title)》：\n\(excerpt(from: document.content, limit: 900))"
            }
            .joined(separator: "\n\n")

        return """
        项目名称：\(project.title)
        类型：\(project.genre)
        项目摘要：\(project.summary)
        当前进度：已创作 \(project.writtenChapters) 章
        当前章节：\(project.currentChapterSummary)
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

        连续性笔记：
        \(normalized(project.continuityNotes, fallback: "暂无连续性笔记。"))

        正文摘要：
        \(normalized(excerpt(from: project.draftText, limit: 2200), fallback: "正文还较短，请重点根据大纲和本章目标判断结构。"))

        导入参考文本：
        \(normalized(references, fallback: "暂无导入参考文本。"))

        输出要求：
        请针对这一部小说，给出适合继续完善章节树的总结。
        每个小节 2 到 4 句，尽量具体，不要空泛。
        """
    }

    private static func chapterTitleUserPrompt(project: NovelProject, draft: String) -> String {
        """
        项目名称：\(project.title)
        类型：\(project.genre)
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
