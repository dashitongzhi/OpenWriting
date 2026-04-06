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
                .init(
                    role: "user",
                    content: userPrompt(
                        project: project,
                        mode: mode,
                        additionalInstruction: additionalInstruction,
                        length: length
                    )
                )
            ],
            temperature: 0.85,
            maxTokens: length.maxTokens
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

        参考文本：
        \(normalized(references, fallback: "暂无导入参考文本。"))

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

    private static func excerpt(from text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.suffix(limit))
    }

    private static func normalized(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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
