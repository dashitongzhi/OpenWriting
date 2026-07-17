import Foundation

struct ChapterCommitRequest {
    let project: NovelProject
    let chapterDraft: ChapterDraft
    let review: ChapterReviewResult?
    let reviewFailureReason: String?
    let contractOverride: LongformStoryContractBundle?
    let updatedAt: String
}

struct ChapterCommitOutcome {
    let project: NovelProject
    let commit: LongformChapterCommit
}

enum ChapterCommitUseCase {
    static func commit(_ request: ChapterCommitRequest) -> ChapterCommitOutcome {
        var project = request.project
        let contract = request.contractOverride ?? LongformStorySystem.buildRuntimeContract(for: project)
        let extractedMemoryItems = KeywordMemoryExtractor.extract(
            from: request.chapterDraft.content,
            volumeNumber: request.chapterDraft.volumeNumber,
            chapterNumber: request.chapterDraft.chapterNumber
        )
        let commit = LongformStorySystem.buildCommit(
            project: project,
            chapterDraft: request.chapterDraft,
            review: request.review,
            reviewFailureReason: request.reviewFailureReason,
            extractedMemoryItems: extractedMemoryItems,
            contract: contract
        )

        LongformStorySystem.apply(commit: commit, contract: contract, to: &project)
        project.appendAntiPatterns(
            from: ChapterQualityReviewer.quickAIFlavorCheck(text: request.chapterDraft.content)
        )
        project.updatedAt = request.updatedAt

        return ChapterCommitOutcome(
            project: project,
            commit: project.longformRuntimeState.latestCommit ?? commit
        )
    }
}
