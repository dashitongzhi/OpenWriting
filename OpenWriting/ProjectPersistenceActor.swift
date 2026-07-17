import Foundation

actor ProjectPersistenceActor {
    private let store: ProjectFileStore
    private var generations: [String: UInt64] = [:]

    init(store: ProjectFileStore) {
        self.store = store
    }

    func saveAfterDelay(
        _ projects: [NovelProject],
        for scope: String?,
        delay: Duration = .milliseconds(250)
    ) async throws -> Bool {
        let key = scopeKey(scope)
        let generation = advanceGeneration(for: key)
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        guard generations[key] == generation else { return false }

        try store.saveProjects(projects, for: scope)
        return true
    }

    func saveNow(_ projects: [NovelProject], for scope: String?) throws {
        advanceGeneration(for: scopeKey(scope))
        try store.saveProjects(projects, for: scope)
    }

    func cancel(for scope: String?) {
        advanceGeneration(for: scopeKey(scope))
    }

    func cancelAndRemove(for scope: String?) throws {
        advanceGeneration(for: scopeKey(scope))
        try store.removeProjects(for: scope)
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

nonisolated final class ProjectPersistenceBlockingResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func store(_ result: Result<Void, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
