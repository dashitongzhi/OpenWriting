import Foundation
import Observation

/// 负责项目创建、选择、删除和元数据更新的管理器
@MainActor
@Observable
final class ProjectManager {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Project CRUD

    func createProject(named title: String, length: NovelLength) {
        appState?.createProject(named: title, length: length)
    }

    func selectProject(_ projectID: NovelProject.ID) {
        appState?.selectProject(projectID)
    }

    func deleteProject(_ projectID: NovelProject.ID) {
        appState?.deleteProject(projectID)
    }

    var activeProject: NovelProject? {
        appState?.activeProject
    }

    var recentProjects: [NovelProject] {
        appState?.recentProjects ?? []
    }

    // MARK: - Project Metadata Updates

    func updateDraftText(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateDraftText(text, for: projectID)
    }

    func updateCurrentChapterTitle(_ title: String, for projectID: NovelProject.ID) {
        appState?.updateCurrentChapterTitle(title, for: projectID)
    }

    func updateCurrentChapterNumber(_ number: Int, for projectID: NovelProject.ID) {
        appState?.updateCurrentChapterNumber(number, for: projectID)
    }

    func updateCurrentVolumeNumber(_ number: Int, for projectID: NovelProject.ID) {
        appState?.updateCurrentVolumeNumber(number, for: projectID)
    }

    func updateChapterFocus(_ focus: String, for projectID: NovelProject.ID) {
        appState?.updateChapterFocus(focus, for: projectID)
    }

    func updateOutlineText(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateOutlineText(text, for: projectID)
    }

    func updateStructureNotes(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateStructureNotes(text, for: projectID)
    }

    func updateSceneProgressNotes(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateSceneProgressNotes(text, for: projectID)
    }

    func updateCharacterArcNotes(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateCharacterArcNotes(text, for: projectID)
    }

    func updateForeshadowNotes(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateForeshadowNotes(text, for: projectID)
    }

    func updateVolumePlanNotes(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateVolumePlanNotes(text, for: projectID)
    }

    func updateActiveThreadsNotes(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateActiveThreadsNotes(text, for: projectID)
    }

    func updateOutlineSummary(_ text: String, updatedAt: String? = nil, for projectID: NovelProject.ID) {
        appState?.updateOutlineSummary(text, updatedAt: updatedAt, for: projectID)
    }

    func updateReferenceContextText(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateReferenceContextText(text, for: projectID)
    }

    func updateSpecialRequirements(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateSpecialRequirements(text, for: projectID)
    }

    func updateWordTargetText(_ text: String, for projectID: NovelProject.ID) {
        appState?.updateWordTargetText(text, for: projectID)
    }

    func updateContinuityNotes(_ text: String, updatedAt: String? = nil, for projectID: NovelProject.ID) {
        appState?.updateContinuityNotes(text, updatedAt: updatedAt, for: projectID)
    }

    // MARK: - Navigation

    func openProjectSpace(for projectID: NovelProject.ID? = nil, scrollToProject: Bool = false) {
        appState?.openProjectSpace(for: projectID, scrollToProject: scrollToProject)
    }

    func openWritingDesk(for projectID: NovelProject.ID? = nil) {
        appState?.openWritingDesk(for: projectID)
    }

    func openOutline() {
        appState?.openOutline()
    }

    func openLibrary() {
        appState?.openLibrary()
    }

    func navigate(to item: SidebarItem) {
        appState?.navigate(to: item)
    }

    func clearProjectSpaceScrollTarget() {
        appState?.clearProjectSpaceScrollTarget()
    }
}