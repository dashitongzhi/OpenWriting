import Foundation
import Observation

/// AppState 的管理器访问器
/// 提供对各专业化管理器的便捷访问
@MainActor
@Observable
final class AppStateManagers {
    let projectManager: ProjectManager
    let chapterManager: ChapterManager
    let searchManager: SearchManager
    let dashboardManager: DashboardManager
    let writersAICommandsManager: WritersAICommandsManager

    init(appState: AppState) {
        self.projectManager = ProjectManager(appState: appState)
        self.chapterManager = ChapterManager(appState: appState)
        self.searchManager = SearchManager(appState: appState)
        self.dashboardManager = DashboardManager(appState: appState)
        self.writersAICommandsManager = WritersAICommandsManager(appState: appState)
    }
}