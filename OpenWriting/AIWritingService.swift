import Foundation

enum ModelAPIFormat: String, Codable {
    case openAIChatCompletions
    case anthropicMessages
}

struct AIConnectionConfiguration: Sendable {
    let baseURL: URL
    let apiKey: String
    let modelName: String
    let apiFormat: ModelAPIFormat
    let additionalHeaders: [String: String]

    init(
        baseURL: URL,
        apiKey: String,
        modelName: String,
        apiFormat: ModelAPIFormat = .openAIChatCompletions,
        additionalHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.apiFormat = apiFormat
        self.additionalHeaders = additionalHeaders
    }
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
            return 1_300
        case .medium:
            return 2_300
        case .long:
            return 3_600
        }
    }

    var targetRange: ClosedRange<Int> {
        switch self {
        case .short:
            return 700 ... 900
        case .medium:
            return 1_400 ... 1_700
        case .long:
            return 2_200 ... 2_600
        }
    }

    var minimumAcceptableCount: Int {
        Int(Double(targetRange.lowerBound) * 0.80)
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
        let support = WritingSupportContext(project: project)
        let plan = try await completeText(
            configuration: configuration,
            systemPrompt: writingPlanSystemPrompt,
            userPrompt: writingPlanUserPrompt(
                project: project,
                mode: mode,
                additionalInstruction: additionalInstruction,
                length: length,
                support: support
            ),
            temperature: 0.42,
            maxTokens: 760
        )

        let draft = try await completeText(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt(
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

        let revisedDraft = try await completeText(
            configuration: configuration,
            systemPrompt: writingRevisionSystemPrompt,
            userPrompt: writingRevisionUserPrompt(
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

        guard revisedDraft.count < length.minimumAcceptableCount else {
            return revisedDraft
        }

        let supplement = try await completeText(
            configuration: configuration,
            systemPrompt: writingSupplementSystemPrompt,
            userPrompt: writingSupplementUserPrompt(
                project: project,
                length: length,
                support: support,
                writingPlan: plan,
                draft: revisedDraft
            ),
            temperature: 0.72,
            maxTokens: max(700, length.maxTokens / 2)
        )

        return [revisedDraft, supplement]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func polishFullDraft(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        draft: String,
        instruction: String
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: draftPolishSystemPrompt,
            userPrompt: fullDraftPolishUserPrompt(
                project: project,
                draft: draft,
                instruction: instruction
            ),
            temperature: 0.45,
            maxTokens: max(1_600, min(6_000, draft.count + 800))
        )
    }

    static func polishSelection(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
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
                project: project,
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

    static func generateText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        try await completeText(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    private static func completeText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                switch configuration.apiFormat {
                case .openAIChatCompletions:
                    return try await completeOpenAIText(
                        configuration: configuration,
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )
                case .anthropicMessages:
                    return try await completeAnthropicText(
                        configuration: configuration,
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                lastError = error
                guard attempt < maxAttempts, shouldRetryCompletion(after: error) else {
                    throw error
                }
                try await Task.sleep(for: .milliseconds(retryDelayMilliseconds(forAttempt: attempt)))
            }
        }

        throw lastError ?? AIWritingError.emptyResult
    }

    private static func completeOpenAIText(
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
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        applyAdditionalHeaders(from: configuration, to: &request)
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
            throw serverError(statusCode: httpResponse.statusCode, data: data)
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

    private static func completeAnthropicText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let endpoint = configuration.baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        applyAdditionalHeaders(from: configuration, to: &request)
        request.timeoutInterval = 120

        let payload = AnthropicMessagesRequest(
            model: configuration.modelName,
            system: systemPrompt,
            messages: [
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
            throw serverError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        let text = decoded.content
            .compactMap { block -> String? in
                guard block.type == "text" else { return nil }
                return block.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw AIWritingError.emptyResult
        }

        return text
    }

    private static func applyAdditionalHeaders(
        from configuration: AIConnectionConfiguration,
        to request: inout URLRequest
    ) {
        guard !configuration.additionalHeaders.isEmpty else { return }

        for (field, value) in configuration.additionalHeaders.sorted(by: { $0.key < $1.key }) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-OpenWriting-Request-ID")
    }

    private static func shouldRetryCompletion(after error: Error) -> Bool {
        if let aiError = error as? AIWritingError {
            switch aiError {
            case .rateLimited, .transientServerError:
                return true
            case .invalidResponse, .serverError, .emptyResult:
                return false
            }
        }

        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private static func retryDelayMilliseconds(forAttempt attempt: Int) -> Int {
        min(4_000, 500 * (1 << max(0, attempt - 1)))
    }

    private static func serverError(statusCode: Int, data: Data) -> AIWritingError {
        let message = sanitizedServerErrorMessage(from: data)
        if statusCode == 429 {
            return .rateLimited(message)
        }
        if statusCode == 408 || (500...599).contains(statusCode) {
            return .transientServerError(statusCode: statusCode, message: message)
        }
        return .serverError("HTTP \(statusCode)：\(message)")
    }

    private static func sanitizedServerErrorMessage(from data: Data) -> String {
        let rawMessage = String(data: data, encoding: .utf8) ?? "未知错误"
        let redactedMessage = rawMessage
            .replacingOccurrences(
                of: #"(?i)(bearer\s+)[a-z0-9._\-]+"#,
                with: "$1[redacted]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(api[_-]?key["'\s:=]+)[^"',\s}]+"#,
                with: "$1[redacted]",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !redactedMessage.isEmpty else { return "未知错误" }
        if redactedMessage.count <= 600 {
            return redactedMessage
        }
        return "\(redactedMessage.prefix(600))…"
    }

    // MARK: - BM25 Scorer

    /// Okapi BM25 scorer for reference retrieval.
    /// Supports Chinese text via character-level n-gram tokenization.
    private struct BM25Scorer {
        private static let k1: Double = 1.2
        private static let b: Double = 0.75

        private let corpusSize: Int
        private let avgDocLength: Double
        private let docLengths: [Int]
        private let docTermFreqs: [[String: Int]]
        private let docFreqs: [String: Int]

        /// Build scorer from a corpus of tokenized documents.
        init(documents: [[String]]) {
            corpusSize = documents.count
            var lengths = [Int]()
            var allTermFreqs = [[String: Int]]()
            var freqs = [String: Int]()

            for doc in documents {
                lengths.append(doc.count)
                var tf = [String: Int]()
                for term in doc {
                    tf[term, default: 0] += 1
                }
                allTermFreqs.append(tf)
                for term in tf.keys {
                    freqs[term, default: 0] += 1
                }
            }

            docLengths = lengths
            avgDocLength = lengths.isEmpty ? 1 : Double(lengths.reduce(0, +)) / Double(lengths.count)
            docTermFreqs = allTermFreqs
            docFreqs = freqs
        }

        /// BM25 score for a single document against the given query terms.
        func score(documentIndex: Int, queryTerms: [String]) -> Double {
            guard corpusSize > 0, documentIndex < corpusSize else { return 0 }
            let tf = docTermFreqs[documentIndex]
            let dl = Double(docLengths[documentIndex])
            var total: Double = 0

            for term in Set(queryTerms) {
                guard let f = tf[term], f > 0 else { continue }
                let n = Double(docFreqs[term] ?? 0)
                let idf = log((Double(corpusSize) - n + 0.5) / (n + 0.5) + 1.0)
                let numerator = Double(f) * (Self.k1 + 1)
                let denominator = Double(f) + Self.k1 * (1 - Self.b + Self.b * dl / avgDocLength)
                total += idf * numerator / denominator
            }
            return total
        }

        // MARK: - Tokenization

        /// Tokenize text for BM25 scoring. Handles both CJK and Latin scripts.
        /// CJK characters are split into unigrams, bigrams, and trigrams.
        /// Latin words are kept whole, lowercased.
        static func tokenize(_ text: String) -> [String] {
            var tokens = [String]()
            var cjkBuffer = [Unicode.Scalar]()
            var latinBuffer = [Unicode.Scalar]()

            for scalar in text.unicodeScalars {
                if isCJK(scalar) {
                    if !latinBuffer.isEmpty {
                        flushLatin(&latinBuffer, into: &tokens)
                    }
                    cjkBuffer.append(scalar)
                } else if isTokenSeparator(scalar) {
                    if !cjkBuffer.isEmpty {
                        flushCJK(&cjkBuffer, into: &tokens)
                    }
                    if !latinBuffer.isEmpty {
                        flushLatin(&latinBuffer, into: &tokens)
                    }
                } else {
                    if !cjkBuffer.isEmpty {
                        flushCJK(&cjkBuffer, into: &tokens)
                    }
                    latinBuffer.append(scalar)
                }
            }
            if !cjkBuffer.isEmpty {
                flushCJK(&cjkBuffer, into: &tokens)
            }
            if !latinBuffer.isEmpty {
                flushLatin(&latinBuffer, into: &tokens)
            }
            return tokens
        }

        private static func flushLatin(_ buffer: inout [Unicode.Scalar], into tokens: inout [String]) {
            let word = buffer.map(String.init).joined().lowercased()
            if !word.isEmpty { tokens.append(word) }
            buffer.removeAll()
        }

        private static func flushCJK(_ buffer: inout [Unicode.Scalar], into tokens: inout [String]) {
            tokens.append(contentsOf: cjkNGrams(buffer))
            buffer.removeAll()
        }

        private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
            let v = scalar.value
            return (v >= 0x4E00 && v <= 0x9FFF)       // CJK Unified Ideographs
                || (v >= 0x3400 && v <= 0x4DBF)       // CJK Extension A
                || (v >= 0xF900 && v <= 0xFAFF)       // CJK Compatibility
                || (v >= 0x20000 && v <= 0x2A6DF)     // CJK Extension B
                || (v >= 0x2A700 && v <= 0x2CEAF)     // CJK Extensions C–F
        }

        private static func isTokenSeparator(_ scalar: Unicode.Scalar) -> Bool {
            if scalar.properties.isWhitespace { return true }

            switch scalar.properties.generalCategory {
            case .connectorPunctuation,
                .dashPunctuation,
                .openPunctuation,
                .closePunctuation,
                .initialPunctuation,
                .finalPunctuation,
                .otherPunctuation,
                .mathSymbol,
                .currencySymbol,
                .modifierSymbol,
                .otherSymbol:
                return true
            default:
                return false
            }
        }

        /// Extract unigrams, bigrams, and trigrams from a run of CJK characters.
        private static func cjkNGrams(_ chars: [Unicode.Scalar]) -> [String] {
            let count = chars.count
            guard count > 0 else { return [] }
            var tokens = [String]()
            // Unigrams
            for i in 0..<count {
                tokens.append(String(chars[i]))
            }
            // Bigrams
            if count >= 2 {
                for i in 0..<(count - 1) {
                    tokens.append(String(chars[i]) + String(chars[i + 1]))
                }
            }
            // Trigrams
            if count >= 3 {
                for i in 0..<(count - 2) {
                    tokens.append(String(chars[i]) + String(chars[i + 1]) + String(chars[i + 2]))
                }
            }
            return tokens
        }
    }

    // MARK: - Writing Support Context

    struct WritingSupportContext {
        let currentDraftExcerpt: String
        let relevantReferences: String
        let chapterTreeFocus: String
        let styleFingerprint: String

        init(project: NovelProject) {
            currentDraftExcerpt = Self.currentDraftExcerpt(from: project.draftText)
            relevantReferences = Self.relevantReferenceExcerpts(for: project)
            chapterTreeFocus = Self.chapterTreeFocus(for: project)
            styleFingerprint = Self.styleFingerprint(for: project)
        }

        private static func currentDraftExcerpt(from draft: String) -> String {
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "当前草稿箱为空，请按本章目标起笔。"
            }

            return excerpt(from: trimmed, limit: 2_600)
        }

        private static func relevantReferenceExcerpts(for project: NovelProject) -> String {
            let query = [
                project.title,
                project.genre,
                project.summary,
                project.chapterFocus,
                project.draftText,
                project.specialRequirements,
                project.referenceContextText,
                project.outlineSummary,
                project.sceneProgressNotes,
                project.characterArcNotes,
                project.foreshadowNotes
            ]
            .joined(separator: "\n")

            let queryTerms = BM25Scorer.tokenize(query)
            let keywords = keywordCandidates(from: query)

            // BM25-rank reference documents
            let docTexts = project.referenceDocuments.map { "\($0.title)\n\($0.content)" }
            let docTokens = docTexts.map { BM25Scorer.tokenize($0) }
            let docScorer = BM25Scorer(documents: docTokens)
            let rankedDocuments = project.referenceDocuments.enumerated()
                .map { offset, document in
                    (document, docScorer.score(documentIndex: offset, queryTerms: queryTerms))
                }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        return lhs.0.wordCount > rhs.0.wordCount
                    }
                    return lhs.1 > rhs.1
                }
                .prefix(4)

            let chapterExcerpts = relevantChapterExcerpts(for: project, queryTerms: queryTerms, keywords: keywords)
            let documentExcerpts = rankedDocuments.map { document, _ in
                "参考《\(document.title)》：\n\(bestReferenceWindow(in: document.content, keywords: keywords, limit: 1_400))"
            }

            let excerpts = chapterExcerpts + documentExcerpts
            return excerpts.isEmpty ? "暂无相关章节或导入参考文本。" : excerpts.joined(separator: "\n\n")
        }

        private static func relevantChapterExcerpts(for project: NovelProject, queryTerms: [String], keywords: [String]) -> [String] {
            let filteredChapters = project.chapterDrafts
                .filter {
                    $0.volumeNumber != project.currentVolumeNumber
                        || $0.chapterNumber != project.currentChapterNumber
                }
            guard !filteredChapters.isEmpty else { return [] }

            let chapterTexts = filteredChapters.map { $0.content + "\n" + $0.chapterSummary }
            let chapterTokens = chapterTexts.map { BM25Scorer.tokenize($0) }
            let chapterScorer = BM25Scorer(documents: chapterTokens)

            return filteredChapters.enumerated()
                .map { offset, chapter in
                    (chapter, chapterScorer.score(documentIndex: offset, queryTerms: queryTerms))
                }
                .filter { _, score in score > 0 }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        if lhs.0.volumeNumber != rhs.0.volumeNumber {
                            return lhs.0.volumeNumber > rhs.0.volumeNumber
                        }
                        return lhs.0.chapterNumber > rhs.0.chapterNumber
                    }
                    return lhs.1 > rhs.1
                }
                .prefix(4)
                .map { chapter, _ in
                    "相关已保存章节《\(chapter.chapterSummary)》：\n\(bestReferenceWindow(in: chapter.content, keywords: keywords, limit: 1_200))"
                }
        }

        private static func bestReferenceWindow(in text: String, keywords: [String], limit: Int) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > limit else { return trimmed }

            let windows = stride(from: 0, to: trimmed.count, by: max(260, limit / 2)).map { offset -> String in
                let start = trimmed.index(trimmed.startIndex, offsetBy: offset)
                let endOffset = min(trimmed.count, offset + limit)
                let end = trimmed.index(trimmed.startIndex, offsetBy: endOffset)
                return String(trimmed[start..<end])
            }

            return windows.max { lhs, rhs in
                referenceWindowScore(lhs, keywords: keywords) < referenceWindowScore(rhs, keywords: keywords)
            } ?? excerpt(from: trimmed, limit: limit)
        }

        private static func referenceWindowScore(_ text: String, keywords: [String]) -> Int {
            keywords.reduce(0) { score, keyword in
                text.localizedStandardContains(keyword) ? score + keyword.count : score
            }
        }

        private static func keywordCandidates(from text: String) -> [String] {
            var seen = Set<String>()
            return BM25Scorer.tokenize(text)
                .filter { token in
                    guard token.count >= 2, !seen.contains(token) else { return false }
                    seen.insert(token)
                    return true
                }
                .prefix(200)
                .map { String($0) }
        }

        private static func chapterTreeFocus(for project: NovelProject) -> String {
            let sections = [
                ("章节树总结", project.outlineSummary),
                ("场景推进记录", project.sceneProgressNotes),
                ("角色弧线记录", project.characterArcNotes),
                ("伏笔与回收记录", project.foreshadowNotes),
                ("分卷/阶段规划", project.volumePlanNotes),
                ("在途线索", project.activeThreadsNotes)
            ]

            let content = sections
                .map { title, body in
                    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return "" }
                    return "\(title)：\n\(excerpt(from: trimmed, limit: 900))"
                }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            guard !content.isEmpty else {
                return "暂无章节树约束，请以项目大纲、全局记忆和本章目标为准。"
            }

            return content
        }

        private static func styleFingerprint(for project: NovelProject) -> String {
            let source = [
                project.draftText,
                project.previousChapterDraftForContinuation?.content ?? "",
                project.sortedChapterDrafts.first?.content ?? ""
            ]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !source.isEmpty else {
                return "暂无可提取风格样本，请默认使用中文长篇小说正文语感，避免说明腔。"
            }

            let paragraphs = source
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let sample = paragraphs.suffix(8).joined(separator: "\n")
            let dialogueCount = sample.filter { $0 == "“" || $0 == "\"" }.count
            let sentenceMarks = sample.filter { "。！？!?；;".contains($0) }.count
            let averageSentenceLength = sentenceMarks == 0 ? sample.count : max(1, sample.count / sentenceMarks)
            let dialogueStyle = dialogueCount >= 4 ? "对白占比较高" : "叙述占比较高"
            let rhythm = averageSentenceLength <= 24 ? "句子偏短，节奏较快" : "句子偏长，描写较充分"

            return "\(dialogueStyle)；\(rhythm)；延续样本文本的叙事视角、段落密度、对白自然度和心理描写比例。"
        }
    }

    // MARK: - Quality Review

    /// 对章节进行六维质量审查
    static func reviewChapter(
        project: NovelProject,
        configuration: AIConnectionConfiguration
    ) async throws -> QualityReviewReport {
        guard !project.draftText.isEmpty else {
            throw AIWritingError.emptyResult
        }
        return try await QualityReviewService.reviewChapter(
            chapterTitle: project.currentChapterTitle.isEmpty ? "第\(project.currentChapterNumber)章" : project.currentChapterTitle,
            chapterContent: project.draftText,
            chapterNumber: project.currentChapterNumber,
            project: project,
            configuration: configuration
        )
    }

}

// MARK: - Prompts moved to AIWritingService+Prompts.swift

enum AIWritingError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case rateLimited(String)
    case transientServerError(statusCode: Int, message: String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AI 服务返回了无效响应。"
        case let .serverError(message):
            return "AI 服务调用失败：\(message)"
        case let .rateLimited(message):
            return "AI 服务请求过于频繁，请稍后重试：\(message)"
        case let .transientServerError(statusCode, message):
            return "AI 服务暂时不可用（HTTP \(statusCode)）：\(message)"
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

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let system: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}
