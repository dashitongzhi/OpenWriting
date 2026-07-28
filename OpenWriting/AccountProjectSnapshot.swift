import Foundation

nonisolated struct ProjectDeletionTombstone: Codable, Hashable, Sendable {
    var projectID: NovelProject.ID
    var deletedAt: Date

    nonisolated init(projectID: NovelProject.ID, deletedAt: Date) {
        self.projectID = projectID
        self.deletedAt = deletedAt
    }

    /// Cloud JSON and the cross-platform revision contract use millisecond
    /// precision. Round upward so truncation can never put the tombstone
    /// before the project update being deleted.
    nonisolated static func deletionDate(
        now: Date,
        projectUpdatedAt: Date
    ) -> Date {
        let latestSeconds = max(
            now.timeIntervalSince1970,
            projectUpdatedAt.timeIntervalSince1970
        )
        return Date(
            timeIntervalSince1970: ceil(latestSeconds * 1_000) / 1_000
        )
    }

    nonisolated static func normalized(
        _ tombstones: [ProjectDeletionTombstone]
    ) -> [ProjectDeletionTombstone] {
        var newestByProjectID: [NovelProject.ID: ProjectDeletionTombstone] = [:]
        for tombstone in tombstones {
            let projectID = tombstone.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectID.isEmpty else { continue }
            let normalized = ProjectDeletionTombstone(
                projectID: projectID,
                deletedAt: tombstone.deletedAt
            )
            if let existing = newestByProjectID[projectID],
               existing.deletedAt >= normalized.deletedAt {
                continue
            }
            newestByProjectID[projectID] = normalized
        }
        return newestByProjectID.values.sorted {
            if $0.projectID == $1.projectID {
                return $0.deletedAt < $1.deletedAt
            }
            return $0.projectID < $1.projectID
        }
    }
}

/// Versioned local/cloud interchange contract for one account-scoped project set.
/// Keep migration concerns here instead of growing the CloudKit transport actor.
struct AccountProjectSnapshot: Codable, @unchecked Sendable {
    nonisolated static let currentSchemaVersion = 2

    var schemaVersion: Int
    var activeProjectID: NovelProject.ID?
    var recentProjects: [NovelProject]
    var deletedProjects: [ProjectDeletionTombstone]
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case activeProjectID
        case recentProjects
        case deletedProjects
        case updatedAt
    }

    nonisolated init(
        schemaVersion: Int = AccountProjectSnapshot.currentSchemaVersion,
        activeProjectID: NovelProject.ID?,
        recentProjects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone] = [],
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.activeProjectID = activeProjectID
        self.recentProjects = recentProjects
        self.deletedProjects = ProjectDeletionTombstone.normalized(deletedProjects)
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
        deletedProjects = ProjectDeletionTombstone.normalized(
            try container.decodeIfPresent(
                [ProjectDeletionTombstone].self,
                forKey: .deletedProjects
            ) ?? []
        )
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(activeProjectID, forKey: .activeProjectID)
        try container.encode(recentProjects, forKey: .recentProjects)
        try container.encode(
            ProjectDeletionTombstone.normalized(deletedProjects),
            forKey: .deletedProjects
        )
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
