import Foundation

struct ProjectFileStore {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let writeCache = ProjectFileWriteCache()

    private struct ProjectIndex: Codable {
        var version: Int
        var projectIDs: [NovelProject.ID]
    }

    private struct ChapterIndex: Codable {
        var version: Int
        var chapterIDs: [ChapterDraft.ID]
    }

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        baseDirectoryName: String = "OpenWriting"
    ) {
        self.fileManager = fileManager

        let baseURL = baseDirectoryURL ?? (
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
        )

        self.baseDirectoryURL = baseURL
            .appendingPathComponent(baseDirectoryName, isDirectory: true)
            .appendingPathComponent("ProjectStore", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func loadProjects(for scope: String?) -> [NovelProject]? {
        if let projects = loadShardedProjects(for: scope) {
            return projects
        }

        let fileURL = projectsFileURL(for: scope)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? decoder.decode([NovelProject].self, from: data)
    }

    func saveProjects(_ projects: [NovelProject], for scope: String?) throws {
        if projects.isEmpty {
            try removeProjects(for: scope)
            return
        }

        try saveShardedProjects(projects, for: scope)
    }

    func hasProjects(for scope: String?) -> Bool {
        fileManager.fileExists(atPath: projectIndexURL(for: scope).path)
            || fileManager.fileExists(atPath: projectsFileURL(for: scope).path)
    }

    func removeProjects(for scope: String?) throws {
        let scopeURL = scopeDirectoryURL(for: scope)
        if fileManager.fileExists(atPath: scopeURL.path) {
            try fileManager.removeItem(at: scopeURL)
            writeCache.removeAll()
        }
    }

    private func loadShardedProjects(for scope: String?) -> [NovelProject]? {
        let indexURL = projectIndexURL(for: scope)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ProjectIndex.self, from: indexData)
        else { return nil }

        let projects = index.projectIDs.compactMap { projectID -> NovelProject? in
            let projectURL = projectMetadataURL(for: projectID, scope: scope)
            guard let projectData = try? Data(contentsOf: projectURL),
                  var project = try? decoder.decode(NovelProject.self, from: projectData)
            else { return nil }

            project.chapterDrafts = loadChapterDrafts(for: projectID, scope: scope)
            return project
        }

        return projects.isEmpty ? nil : projects
    }

    private func loadChapterDrafts(for projectID: NovelProject.ID, scope: String?) -> [ChapterDraft] {
        let indexURL = chapterIndexURL(for: projectID, scope: scope)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ChapterIndex.self, from: indexData)
        else { return [] }

        return index.chapterIDs.compactMap { chapterID in
            let chapterURL = chapterURL(for: chapterID, projectID: projectID, scope: scope)
            guard let data = try? Data(contentsOf: chapterURL) else { return nil }
            return try? decoder.decode(ChapterDraft.self, from: data)
        }
    }

    private func saveShardedProjects(_ projects: [NovelProject], for scope: String?) throws {
        let scopeURL = scopeDirectoryURL(for: scope)
        let projectsDirectory = scopeURL.appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)

        let index = ProjectIndex(version: 2, projectIDs: projects.map(\.id))
        try writeIfChanged(try encoder.encode(index), to: projectIndexURL(for: scope))

        for project in projects {
            try saveProject(project, scope: scope)
        }

        try removeDeletedProjectDirectories(keeping: Set(projects.map(\.id)), scope: scope)
        let legacyURL = projectsFileURL(for: scope)
        if fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
    }

    private func saveProject(_ project: NovelProject, scope: String?) throws {
        let chaptersDirectory = chapterDirectoryURL(for: project.id, scope: scope)
        try fileManager.createDirectory(at: chaptersDirectory, withIntermediateDirectories: true)

        var metadata = project
        metadata.chapterDrafts = []
        try writeIfChanged(try encoder.encode(metadata), to: projectMetadataURL(for: project.id, scope: scope))

        let chapterIndex = ChapterIndex(version: 2, chapterIDs: project.chapterDrafts.map(\.id))
        try writeIfChanged(try encoder.encode(chapterIndex), to: chapterIndexURL(for: project.id, scope: scope))

        for chapterDraft in project.chapterDrafts {
            let chapterData = try encoder.encode(chapterDraft)
            try writeIfChanged(
                chapterData,
                to: chapterURL(for: chapterDraft.id, projectID: project.id, scope: scope)
            )
        }

        try removeDeletedChapterFiles(
            in: chaptersDirectory,
            keeping: Set(project.chapterDrafts.map(\.id))
        )
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        let fingerprint = ProjectFileFingerprint(size: data.count, hash: data.hashValue)
        if writeCache.fingerprint(for: url) == fingerprint {
            return
        }

        if let existingData = try? Data(contentsOf: url), existingData == data {
            writeCache.set(fingerprint, for: url)
            return
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        writeCache.set(fingerprint, for: url)
    }

    private func removeDeletedProjectDirectories(keeping projectIDs: Set<NovelProject.ID>, scope: String?) throws {
        let projectsDirectory = scopeDirectoryURL(for: scope).appendingPathComponent("projects", isDirectory: true)
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let expectedDirectoryNames = Set(projectIDs.map(sanitizedStorageComponent))
        for url in directoryContents where !expectedDirectoryNames.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
            writeCache.removeItems(under: url)
        }
    }

    private func removeDeletedChapterFiles(in chaptersDirectory: URL, keeping chapterIDs: Set<ChapterDraft.ID>) throws {
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: chaptersDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let expectedFileNames = Set(chapterIDs.map { "\(sanitizedStorageComponent($0)).json" })
        for url in directoryContents where url.lastPathComponent != "index.json" && !expectedFileNames.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
            writeCache.remove(url)
        }
    }

    private func prepareProjectsFileURL(for scope: String?) throws -> URL {
        let directoryURL = scopeDirectoryURL(for: scope)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("projects.json", isDirectory: false)
    }

    private func projectsFileURL(for scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects.json", isDirectory: false)
    }

    private func projectIndexURL(for scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent("index.json", isDirectory: false)
    }

    private func projectDirectoryURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        scopeDirectoryURL(for: scope)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(sanitizedStorageComponent(projectID), isDirectory: true)
    }

    private func projectMetadataURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        projectDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent("project.json", isDirectory: false)
    }

    private func chapterDirectoryURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        projectDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent("chapters", isDirectory: true)
    }

    private func chapterIndexURL(for projectID: NovelProject.ID, scope: String?) -> URL {
        chapterDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent("index.json", isDirectory: false)
    }

    private func chapterURL(for chapterID: ChapterDraft.ID, projectID: NovelProject.ID, scope: String?) -> URL {
        chapterDirectoryURL(for: projectID, scope: scope)
            .appendingPathComponent(sanitizedStorageComponent(chapterID), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func scopeDirectoryURL(for scope: String?) -> URL {
        baseDirectoryURL.appendingPathComponent(scopeDirectoryName(for: scope), isDirectory: true)
    }

    private func scopeDirectoryName(for scope: String?) -> String {
        guard let normalizedScope = normalizedScope(scope) else {
            return "local"
        }

        return "account-\(sanitizedStorageComponent(normalizedScope))"
    }

    private func normalizedScope(_ scope: String?) -> String? {
        guard let scope else {
            return nil
        }

        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func sanitizedStorageComponent(_ value: String) -> String {
        value.map { character in
            if character.isLetter || character.isNumber {
                return String(character)
            }

            if character == "." || character == "_" || character == "-" {
                return String(character)
            }

            return "_"
        }
        .joined()
    }
}

private struct ProjectFileFingerprint: Equatable {
    let size: Int
    let hash: Int
}

private final class ProjectFileWriteCache {
    private var fingerprints: [String: ProjectFileFingerprint] = [:]

    func fingerprint(for url: URL) -> ProjectFileFingerprint? {
        fingerprints[url.path]
    }

    func set(_ fingerprint: ProjectFileFingerprint, for url: URL) {
        fingerprints[url.path] = fingerprint
    }

    func remove(_ url: URL) {
        fingerprints.removeValue(forKey: url.path)
    }

    func removeItems(under url: URL) {
        let prefix = url.path + "/"
        fingerprints = fingerprints.filter { key, _ in
            key != url.path && !key.hasPrefix(prefix)
        }
    }

    func removeAll() {
        fingerprints.removeAll()
    }
}
