import Foundation

struct ProjectFileStore {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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

        let fileURL = try prepareProjectsFileURL(for: scope)
        let data = try encoder.encode(projects)
        try data.write(to: fileURL, options: .atomic)
    }

    func hasProjects(for scope: String?) -> Bool {
        fileManager.fileExists(atPath: projectsFileURL(for: scope).path)
    }

    func removeProjects(for scope: String?) throws {
        let fileURL = projectsFileURL(for: scope)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
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
