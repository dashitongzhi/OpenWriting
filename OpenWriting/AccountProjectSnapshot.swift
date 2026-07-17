import Foundation

/// Versioned local/cloud interchange contract for one account-scoped project set.
/// Keep migration concerns here instead of growing the CloudKit transport actor.
struct AccountProjectSnapshot: Codable {
    nonisolated static let currentSchemaVersion = 1

    var schemaVersion: Int
    var activeProjectID: NovelProject.ID?
    var recentProjects: [NovelProject]
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case activeProjectID
        case recentProjects
        case updatedAt
    }

    nonisolated init(
        schemaVersion: Int = AccountProjectSnapshot.currentSchemaVersion,
        activeProjectID: NovelProject.ID?,
        recentProjects: [NovelProject],
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.activeProjectID = activeProjectID
        self.recentProjects = recentProjects
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard sourceVersion >= 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "AccountProjectSnapshot schema version must be positive."
            )
        }
        guard sourceVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "AccountProjectSnapshot schema version \(sourceVersion) is newer than supported version \(Self.currentSchemaVersion)."
            )
        }

        schemaVersion = Self.currentSchemaVersion
        activeProjectID = try container.decodeIfPresent(NovelProject.ID.self, forKey: .activeProjectID)
        recentProjects = try container.decode([NovelProject].self, forKey: .recentProjects)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(activeProjectID, forKey: .activeProjectID)
        try container.encode(recentProjects, forKey: .recentProjects)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
