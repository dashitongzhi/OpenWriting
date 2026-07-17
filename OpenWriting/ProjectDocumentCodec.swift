import Foundation

nonisolated enum ProjectDocumentCodecError: Error, Equatable {
    case invalidSchemaVersion(Int)
    case unsupportedFutureVersion(Int)
}

nonisolated struct DecodedProjectDocument {
    var project: NovelProject
    var sourceVersion: Int
    var didMigrate: Bool
}

nonisolated struct ProjectDocumentCodec {
    private struct SchemaEnvelope: Decodable {
        var schemaVersion: Int?
    }

    func decode(_ data: Data) throws -> DecodedProjectDocument {
        let envelope = try JSONDecoder().decode(SchemaEnvelope.self, from: data)
        let sourceVersion = envelope.schemaVersion ?? 1

        guard sourceVersion >= 1 else {
            throw ProjectDocumentCodecError.invalidSchemaVersion(sourceVersion)
        }
        guard sourceVersion <= NovelProject.currentSchemaVersion else {
            throw ProjectDocumentCodecError.unsupportedFutureVersion(sourceVersion)
        }

        var migratedData = data
        var migratedVersion = sourceVersion
        while migratedVersion < NovelProject.currentSchemaVersion {
            switch migratedVersion {
            case 1:
                migratedData = try migrateV1ToV2(migratedData)
                migratedVersion = 2
            default:
                throw ProjectDocumentCodecError.invalidSchemaVersion(migratedVersion)
            }
        }

        var project = try JSONDecoder().decode(NovelProject.self, from: migratedData)
        project.schemaVersion = NovelProject.currentSchemaVersion
        return DecodedProjectDocument(
            project: project,
            sourceVersion: sourceVersion,
            didMigrate: sourceVersion != NovelProject.currentSchemaVersion
        )
    }

    func encode(_ project: NovelProject) throws -> Data {
        var currentProject = project
        currentProject.schemaVersion = NovelProject.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(currentProject)
    }

    private func migrateV1ToV2(_ data: Data) throws -> Data {
        guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectDocumentCodecError.invalidSchemaVersion(1)
        }
        document["schemaVersion"] = 2
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }
}
