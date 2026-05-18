import Foundation
import Observation

/// 负责 Dashboard 统计和项目统计信息的管理器
@MainActor
@Observable
final class DashboardManager {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Dashboard Stats

    var dashboardStats: [DashboardStat] {
        appState?.dashboardStats ?? []
    }

    var totalDraftWordCount: Int {
        appState?.totalDraftWordCount ?? 0
    }

    var totalReferenceDocumentCount: Int {
        appState?.totalReferenceDocumentCount ?? 0
    }

    var totalWrittenChapters: Int {
        appState?.totalWrittenChapters ?? 0
    }

    var totalSavedChapterWordCount: Int {
        appState?.totalSavedChapterWordCount ?? 0
    }

    // MARK: - Project Access

    func project(for projectID: NovelProject.ID) -> NovelProject? {
        appState?.project(for: projectID)
    }
}