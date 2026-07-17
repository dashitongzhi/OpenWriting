import Foundation

struct LegacyProjectSidecarMigrator {
    private let userDefaults: UserDefaults
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func migrate(
        _ projects: [NovelProject],
        persist: ([NovelProject]) -> Bool
    ) -> [NovelProject] {
        var migratedProjects = projects
        var keysToRemove: Set<String> = []

        for index in migratedProjects.indices {
            migrateProject(&migratedProjects[index], keysToRemove: &keysToRemove)
        }

        guard !keysToRemove.isEmpty else { return projects }
        guard persist(migratedProjects) else { return migratedProjects }

        keysToRemove.forEach(userDefaults.removeObject(forKey:))
        return migratedProjects
    }

    private func migrateProject(
        _ project: inout NovelProject,
        keysToRemove: inout Set<String>
    ) {
        let memoryBucketsKey = key("memoryBuckets", projectID: project.id)
        if let data = userDefaults.data(forKey: memoryBucketsKey) {
            if project.persistedMemoryBuckets != nil {
                keysToRemove.insert(memoryBucketsKey)
            } else if let value = try? decoder.decode(MemoryBuckets.self, from: data) {
                project.persistedMemoryBuckets = value
                keysToRemove.insert(memoryBucketsKey)
            }
        }

        let strandWeaveKey = key("strandWeave", projectID: project.id)
        if let data = userDefaults.data(forKey: strandWeaveKey) {
            if project.persistedStrandWeaveState != nil {
                keysToRemove.insert(strandWeaveKey)
            } else if let value = try? decoder.decode(StrandWeaveState.self, from: data) {
                project.persistedStrandWeaveState = value
                keysToRemove.insert(strandWeaveKey)
            }
        }

        let lastReviewKey = key("lastReview", projectID: project.id)
        if let data = userDefaults.data(forKey: lastReviewKey) {
            if project.persistedLastReviewResult != nil {
                keysToRemove.insert(lastReviewKey)
            } else if let value = try? decoder.decode(ChapterReviewResult.self, from: data) {
                project.persistedLastReviewResult = value
                keysToRemove.insert(lastReviewKey)
            }
        }

        let antiPatternsKey = key("antiPatterns", projectID: project.id)
        if let value = userDefaults.stringArray(forKey: antiPatternsKey) {
            if project.persistedAntiPatterns == nil {
                project.persistedAntiPatterns = value
            }
            keysToRemove.insert(antiPatternsKey)
        }

        let runtimeKey = key("longformRuntime", projectID: project.id)
        if let data = userDefaults.data(forKey: runtimeKey) {
            if project.persistedLongformRuntimeState != nil {
                keysToRemove.insert(runtimeKey)
            } else if let value = try? decoder.decode(LongformStoryRuntimeState.self, from: data) {
                project.persistedLongformRuntimeState = value
                keysToRemove.insert(runtimeKey)
            }
        }
    }

    private func key(_ prefix: String, projectID: NovelProject.ID) -> String {
        "\(prefix)_\(projectID)"
    }
}
