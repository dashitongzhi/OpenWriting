import Foundation

nonisolated protocol AIWritingServicing: Sendable {
    func validateConnection(configuration: AIConnectionConfiguration) async throws -> String
    func generateStoryOutline(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        profile: OutlineGenerationProfile
    ) async throws -> String
    func continueChapterEnhanced(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        enableReview: Bool
    ) async throws -> EnhancedWritingResult
    func polishFullDraft(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        draft: String,
        instruction: String
    ) async throws -> String
    func polishSelection(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        selectedText: String,
        instruction: String,
        fullDraft: String,
        precedingContext: String,
        followingContext: String
    ) async throws -> String
    func suggestChapterTitle(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        chapterContent: String
    ) async throws -> String
    func refreshGlobalMemory(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        savedChapter: ChapterDraft
    ) async throws -> String
    func refreshChapterTree(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        savedChapter: ChapterDraft
    ) async throws -> ChapterTreeRefresh
    func generateText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String
}

nonisolated struct DefaultAIWritingService: AIWritingServicing {
    func validateConnection(configuration: AIConnectionConfiguration) async throws -> String {
        try await AIWritingService.validateConnection(configuration: configuration)
    }

    func generateStoryOutline(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        profile: OutlineGenerationProfile
    ) async throws -> String {
        try await AIWritingService.generateStoryOutline(
            configuration: configuration,
            project: project,
            profile: profile
        )
    }

    func continueChapterEnhanced(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        enableReview: Bool = true
    ) async throws -> EnhancedWritingResult {
        try await AIWritingService.continueChapterEnhanced(
            configuration: configuration,
            project: project,
            mode: mode,
            additionalInstruction: additionalInstruction,
            length: length,
            enableReview: enableReview
        )
    }

    func polishFullDraft(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        draft: String,
        instruction: String
    ) async throws -> String {
        try await AIWritingService.polishFullDraft(
            configuration: configuration,
            project: project,
            draft: draft,
            instruction: instruction
        )
    }

    func polishSelection(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        selectedText: String,
        instruction: String,
        fullDraft: String,
        precedingContext: String,
        followingContext: String
    ) async throws -> String {
        try await AIWritingService.polishSelection(
            configuration: configuration,
            project: project,
            selectedText: selectedText,
            instruction: instruction,
            fullDraft: fullDraft,
            precedingContext: precedingContext,
            followingContext: followingContext
        )
    }

    func suggestChapterTitle(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        chapterContent: String
    ) async throws -> String {
        try await AIWritingService.suggestChapterTitle(
            configuration: configuration,
            project: project,
            draft: chapterContent
        )
    }

    func refreshGlobalMemory(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        savedChapter: ChapterDraft
    ) async throws -> String {
        try await AIWritingService.refreshGlobalMemory(
            configuration: configuration,
            project: project,
            chapterDraft: savedChapter
        )
    }

    func refreshChapterTree(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        savedChapter: ChapterDraft
    ) async throws -> ChapterTreeRefresh {
        try await AIWritingService.refreshChapterTree(
            configuration: configuration,
            project: project,
            chapterDraft: savedChapter
        )
    }

    func generateText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        try await AIWritingService.generateText(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}
