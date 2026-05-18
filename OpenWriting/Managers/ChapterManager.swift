import Foundation
import Observation

/// 负责章节保存、加载、版本历史和导航的管理器
@MainActor
@Observable
final class ChapterManager {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Chapter Save/Load

    func saveCurrentChapterDraft(for projectID: NovelProject.ID) -> ChapterDraftSaveResult? {
        appState?.saveCurrentChapterDraft(for: projectID)
    }

    func loadChapterDraft(_ chapterDraftID: ChapterDraft.ID, for projectID: NovelProject.ID) {
        appState?.loadChapterDraft(chapterDraftID, for: projectID)
    }

    func ensureChapterDraftLoaded(_ chapterDraftID: ChapterDraft.ID, for projectID: NovelProject.ID) -> ChapterDraft? {
        appState?.ensureChapterDraftLoaded(chapterDraftID, for: projectID)
    }

    func ensureAllChapterDraftsLoaded(for projectID: NovelProject.ID) -> [ChapterDraft] {
        appState?.ensureAllChapterDraftsLoaded(for: projectID) ?? []
    }

    func updateSavedChapterDraft(
        _ chapterDraftID: ChapterDraft.ID,
        title: String,
        content: String,
        for projectID: NovelProject.ID
    ) -> ChapterDraft? {
        appState?.updateSavedChapterDraft(chapterDraftID, title: title, content: content, for: projectID)
    }

    func restoreChapterVersion(
        _ versionID: ChapterDraftVersion.ID,
        chapterDraftID: ChapterDraft.ID,
        for projectID: NovelProject.ID
    ) -> ChapterDraft? {
        appState?.restoreChapterVersion(versionID, chapterDraftID: chapterDraftID, for: projectID)
    }

    // MARK: - Chapter Navigation

    func beginNextChapter(after chapterDraft: ChapterDraft, for projectID: NovelProject.ID) {
        appState?.beginNextChapter(after: chapterDraft, for: projectID)
    }

    // MARK: - Draft Operations

    func appendDraftText(_ text: String, for projectID: NovelProject.ID) {
        appState?.appendDraftText(text, for: projectID)
    }

    func hydratedProjectForFullText(_ projectID: NovelProject.ID) -> NovelProject? {
        appState?.hydratedProjectForFullText(projectID)
    }

    func hydratedProjectsForPersistenceSnapshot(_ projects: [NovelProject]) -> [NovelProject] {
        appState?.hydratedProjectsForPersistenceSnapshot(projects) ?? []
    }

    // MARK: - Reference Documents

    func importReferenceDocuments(_ documents: [ReferenceDocument], for projectID: NovelProject.ID) {
        appState?.importReferenceDocuments(documents, for: projectID)
    }

    func removeReferenceDocument(_ documentID: ReferenceDocument.ID, for projectID: NovelProject.ID) {
        appState?.removeReferenceDocument(documentID, for: projectID)
    }

    func updateReferenceDocumentCategory(
        _ category: ReferenceMaterialCategory,
        documentID: ReferenceDocument.ID,
        for projectID: NovelProject.ID
    ) {
        appState?.updateReferenceDocumentCategory(category, documentID: documentID, for: projectID)
    }

    // MARK: - Memory

    func updateGlobalMemorySnapshot(_ snapshot: GlobalMemorySnapshot, for projectID: NovelProject.ID) {
        appState?.updateGlobalMemorySnapshot(snapshot, for: projectID)
    }

    func appendOutlineSummaryToContinuity(for projectID: NovelProject.ID) {
        appState?.appendOutlineSummaryToContinuity(for: projectID)
    }

    func extractAndStoreMemoryItems(
        from chapterContent: String,
        chapterNumber: Int,
        for projectID: NovelProject.ID
    ) {
        appState?.extractAndStoreMemoryItems(from: chapterContent, chapterNumber: chapterNumber, for: projectID)
    }

    func appendLocalAntiPatterns(
        from chapterContent: String,
        for projectID: NovelProject.ID
    ) {
        appState?.appendLocalAntiPatterns(from: chapterContent, for: projectID)
    }
}