import Foundation

actor ProjectPersistenceActor {
    private let store: ProjectFileStore
    private var generations: [String: UInt64] = [:]

    init(store: ProjectFileStore) {
        self.store = store
    }

    func saveAfterDelay(
        _ projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone] = [],
        for scope: String?,
        delay: Duration = .milliseconds(250)
    ) async throws -> Bool {
        let key = scopeKey(scope)
        let generation = advanceGeneration(for: key)
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        guard generations[key] == generation else { return false }

        try store.saveProjects(
            projects,
            deletedProjects: deletedProjects,
            for: scope
        )
        return true
    }

    func saveNow(
        _ projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone] = [],
        for scope: String?
    ) throws {
        advanceGeneration(for: scopeKey(scope))
        try store.saveProjects(
            projects,
            deletedProjects: deletedProjects,
            for: scope
        )
    }

    func cancel(for scope: String?) {
        advanceGeneration(for: scopeKey(scope))
    }

    func cancelAndRemove(for scope: String?) throws {
        advanceGeneration(for: scopeKey(scope))
        try store.removeProjects(for: scope)
    }

    func hydratedProjectsForPersistenceSnapshot(
        _ projects: [NovelProject],
        for scope: String?
    ) -> [NovelProject] {
        projects.map { project in
            var hydratedProject = project
            let storedDraftReport = store.loadChapterDraftReport(
                for: project.id,
                scope: scope
            )

            var draftByID = Dictionary(
                uniqueKeysWithValues: storedDraftReport.drafts.map { ($0.id, $0) }
            )
            for chapterDraft in project.chapterDrafts {
                draftByID[chapterDraft.id] = chapterDraft
            }

            if !project.chapterCatalog.isEmpty {
                let retainedChapterIDs = Set(project.chapterCatalog.map(\.id))
                    .union(project.chapterDrafts.map(\.id))
                draftByID = draftByID.filter { retainedChapterIDs.contains($0.key) }
            }

            hydratedProject.chapterDrafts = draftByID.values.sorted(
                by: ChapterDraft.sortDescending
            )
            let hydratedChapterIDs = Set(hydratedProject.chapterDrafts.map(\.id))
            let catalogChapterIDs = Set(project.chapterCatalog.map(\.id))
            if !hydratedProject.chapterDrafts.isEmpty,
               catalogChapterIDs.isSubset(of: hydratedChapterIDs) {
                hydratedProject.chapterCatalog = hydratedProject.chapterDrafts
                    .map(ChapterDraftMetadata.init)
                    .sorted(by: ChapterDraftMetadata.sortDescending)
            } else if !storedDraftReport.isComplete,
                      !project.chapterCatalog.isEmpty {
                hydratedProject.chapterCatalog = project.chapterCatalog
            }
            return hydratedProject
        }
    }

    @discardableResult
    func saveEmergencySnapshot(
        _ projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone],
        for scope: String?,
        failureReason: String
    ) throws -> URL {
        try store.writeEmergencySnapshot(
            projects: projects,
            deletedProjects: deletedProjects,
            for: scope,
            failureReason: failureReason
        )
    }

    @discardableResult
    private func advanceGeneration(for key: String) -> UInt64 {
        let generation = (generations[key] ?? 0) &+ 1
        generations[key] = generation
        return generation
    }

    private func scopeKey(_ scope: String?) -> String {
        guard let scope else { return "local" }
        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "local" : trimmed
    }
}

extension NovelProject {
    /// Break the remaining reference-type alias before a project crosses into
    /// the persistence actor. This keeps background encoding isolated from
    /// later MainActor mutations to the legacy StrandWeaveTracker object.
    nonisolated func detachedPersistenceSnapshot() -> NovelProject {
        var snapshot = self
        let trackerSnapshot = StrandWeaveTracker(
            idealRatio: strandWeaveTracker.idealRatio,
            redLineConfig: strandWeaveTracker.redLineConfig
        )
        trackerSnapshot.records = strandWeaveTracker.records
        snapshot.strandWeaveTracker = trackerSnapshot
        return snapshot
    }
}
