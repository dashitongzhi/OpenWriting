import Foundation
import Observation

/// 负责 AI 写作相关命令的管理器
@MainActor
@Observable
final class WritersAICommandsManager {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - AI Configuration

    var aiConfiguration: AIConnectionConfiguration? {
        appState?.aiConfiguration
    }

    var isConfigurationReady: Bool {
        appState?.isConfigurationReady ?? false
    }

    var connectionStatus: ConnectionStatus {
        appState?.connectionStatus ?? .idle
    }

    var validationMessage: String {
        appState?.validationMessage ?? ""
    }

    // MARK: - AI Operations

    func validateConfiguration() {
        appState?.validateConfiguration()
    }

    func continueWriting() {
        appState?.continueWriting()
    }

    func applyEnhancedWritingUpdate(
        _ context: MemoryUpdateContext?,
        review: ChapterReviewResult?,
        reviewedChapter: ChapterReviewTarget? = nil,
        for projectID: NovelProject.ID
    ) {
        appState?.applyEnhancedWritingUpdate(
            context,
            review: review,
            reviewedChapter: reviewedChapter,
            for: projectID
        )
    }

    func applyChapterTreeRefresh(
        _ refresh: ChapterTreeRefresh,
        baseline: ChapterTreeRefreshBaseline? = nil,
        updatedAt: String? = nil,
        for projectID: NovelProject.ID
    ) -> ChapterTreeRefreshApplyOutcome {
        appState?.applyChapterTreeRefresh(refresh, baseline: baseline, updatedAt: updatedAt, for: projectID) ?? ChapterTreeRefreshApplyOutcome()
    }

    // MARK: - Project Updates

    func updateOutlineGenerationProfile(_ profile: OutlineGenerationProfile, for projectID: NovelProject.ID) {
        appState?.updateOutlineGenerationProfile(profile, for: projectID)
    }

    func updateGenreTemplate(_ templateID: GenreTemplate.ID, for projectID: NovelProject.ID) {
        appState?.updateGenreTemplate(templateID, for: projectID)
    }
}
