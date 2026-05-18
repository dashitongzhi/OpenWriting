import Foundation
import Observation

/// 负责全文搜索功能的管理器
@MainActor
@Observable
final class SearchManager {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Search

    func searchLongformProject(_ query: String, in projectID: NovelProject.ID, limit: Int = 60) -> [LongformSearchResult] {
        appState?.searchLongformProject(query, in: projectID, limit: limit) ?? []
    }
}