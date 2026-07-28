import CryptoKit
import Foundation

nonisolated enum CloudProjectPayloadPlatform: String {
    case macOS
    case iOS
}

/// Shared JSON date contract for CloudKit assets on macOS and iOS.
///
/// New payloads always use UTC ISO-8601 with fractional seconds. The decoder
/// remains compatible with the two historical forms (whole-second ISO-8601
/// and Unix epoch numbers) so older snapshots can still migrate forward.
nonisolated enum CloudProjectJSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            let rawValue = try container.decode(String.self)
            if let seconds = Double(rawValue) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let date = formatter(withFractionalSeconds: true).date(from: rawValue)
                ?? formatter(withFractionalSeconds: false).date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a Unix epoch or ISO-8601 timestamp."
            )
        }
        return decoder
    }

    static func string(from date: Date) -> String {
        formatter(withFractionalSeconds: true).string(from: date)
    }

    static func representsSamePersistedInstant(_ lhs: Date, _ rhs: Date) -> Bool {
        string(from: lhs) == string(from: rhs)
    }

    private static func formatter(
        withFractionalSeconds: Bool
    ) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

nonisolated enum CloudProjectPayloadCodec {
    static let currentVersion = 1

    enum CodecError: LocalizedError {
        case unsupportedEnvelopeVersion(Int)
        case malformedEnvelope

        var errorDescription: String? {
            switch self {
            case let .unsupportedEnvelopeVersion(version):
                return "不支持 CloudKit 项目封套版本 \(version)。"
            case .malformedEnvelope:
                return "CloudKit 项目封套结构不完整。"
            }
        }
    }

    private static let versionKey = "_cloudProjectPayloadVersion"
    private static let commonKey = "_common"
    private static let platformsKey = "_platforms"
    private static let commonFieldNames: Set<String> = [
        "id",
        "title",
        "genre",
        "summary",
        "storyLength",
        "updatedAt",
        "currentChapterTitle",
        "currentVolumeNumber",
        "currentChapterNumber",
        "writtenChapters",
        "chapterFocus",
        "draftText",
        "outlineText",
        "structureNotes",
        "sceneProgressNotes",
        "characterArcNotes",
        "foreshadowNotes",
        "continuityNotes",
        "specialRequirements",
        "wordTargetText",
        "volumePlanNotes",
        "activeThreadsNotes",
        "outlineSummary",
        "referenceContextText"
    ]
    private static let crossPlatformIncompatibleFieldNames: Set<String> = [
        "persistedMemoryBuckets",
        "persistedStrandWeaveState",
        "strandWeaveTracker"
    ]
    private static let macOSLegacyMarkers: Set<String> = [
        "schemaVersion",
        "globalMemorySnapshot",
        "strandWeaveTracker",
        "foreshadowList",
        "plotThreadList",
        "genreTemplateId"
    ]
    private static let iOSLegacyMarkers: Set<String> = [
        "referenceContextItems",
        "persistedLongformRuntimeState",
        "persistedLastReviewResult",
        "persistedAntiPatterns"
    ]

    static func encodeMacProject(_ project: NovelProject, preserving previousData: Data?) throws -> Data {
        let encoder = makeEncoder()
        return try encodeEnvelope(
            platformPayload: encoder.encode(project),
            platform: .macOS,
            preserving: previousData
        )
    }

    static func encodeEnvelope(
        platformPayload: Data,
        platform: CloudProjectPayloadPlatform,
        preserving previousData: Data?
    ) throws -> Data {
        var platformObject = try jsonObject(from: platformPayload)
        var preservedPlatforms: [String: Any] = [:]
        var preservedCommon: [String: Any] = [:]

        if let previousData {
            let previousObject = try jsonObject(from: previousData)
            if let envelope = try validatedEnvelope(previousObject) {
                let platforms = envelope[platformsKey] as? [String: Any] ?? [:]
                preservedPlatforms = platforms
                preservedCommon = envelope[commonKey] as? [String: Any] ?? [:]
            } else {
                preservedCommon = commonObject(from: previousObject)
                switch legacyPlatform(for: previousObject) {
                case platform:
                    platformObject = previousObject.merging(platformObject) { _, newValue in newValue }
                case let preservedPlatform?:
                    preservedPlatforms[preservedPlatform.rawValue] = previousObject
                case nil:
                    break
                }
            }
        }

        preservedPlatforms[platform.rawValue] = platformObject
        preservedCommon.merge(commonObject(from: platformObject)) { _, newValue in newValue }
        let envelope: [String: Any] = [
            versionKey: currentVersion,
            commonKey: preservedCommon,
            platformsKey: preservedPlatforms
        ]
        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys]
        )
    }

    static func decodeMacProject(from data: Data) throws -> NovelProject {
        let root = try jsonObject(from: data)
        if let envelope = try validatedEnvelope(root) {
            let common = envelope[commonKey] as? [String: Any] ?? [:]
            let platforms = envelope[platformsKey] as? [String: Any] ?? [:]
            var resolved = platforms[CloudProjectPayloadPlatform.macOS.rawValue] as? [String: Any]
                ?? common
            resolved.merge(common) { _, commonValue in commonValue }
            return try decodeProject(from: resolved)
        }

        return try decodeProject(from: root)
    }

    static func platformPayload(
        named platform: CloudProjectPayloadPlatform,
        in data: Data
    ) throws -> Data? {
        let root = try jsonObject(from: data)
        guard let envelope = try validatedEnvelope(root),
              let platforms = envelope[platformsKey] as? [String: Any],
              let payload = platforms[platform.rawValue] as? [String: Any]
        else {
            return nil
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func commonPayload(in data: Data) throws -> Data? {
        let root = try jsonObject(from: data)
        guard let envelope = try validatedEnvelope(root),
              let common = envelope[commonKey] as? [String: Any]
        else {
            return nil
        }
        return try JSONSerialization.data(withJSONObject: common, options: [.sortedKeys])
    }

    static func payloadHash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func revisionIdentifier(
        projectPayloads: [(id: String, data: Data)],
        chapterPayloads: [(projectID: String, chapterID: String, data: Data)]
    ) -> String {
        var material = Data()
        for payload in projectPayloads.sorted(by: { $0.id < $1.id }) {
            material.append(Data("project:\(payload.id):\(payloadHash(for: payload.data))\n".utf8))
        }
        for payload in chapterPayloads.sorted(by: {
            ($0.projectID, $0.chapterID) < ($1.projectID, $1.chapterID)
        }) {
            material.append(
                Data("chapter:\(payload.projectID):\(payload.chapterID):\(payloadHash(for: payload.data))\n".utf8)
            )
        }
        return "sha256-\(payloadHash(for: material).prefix(32))"
    }

    static func contentRevision(components: [String]) -> String {
        let material = components.joined(separator: "\n")
        return "sha256-\(payloadHash(for: Data(material.utf8)).prefix(32))"
    }

    static func chapterRevision(payloadHash: String) -> String {
        contentRevision(components: [payloadHash])
    }

    static func projectRevision(
        payloadHash: String,
        chapterReferences: [(chapterID: String, recordName: String)]
    ) -> String {
        contentRevision(
            components: [payloadHash] + chapterReferences.sorted {
                if $0.chapterID == $1.chapterID {
                    return $0.recordName < $1.recordName
                }
                return $0.chapterID < $1.chapterID
            }.map {
                "\($0.chapterID):\($0.recordName)"
            }
        )
    }

    static func manifestRevision(
        projectReferences: [(projectID: String, recordName: String)],
        deletedProjects: [ProjectDeletionTombstone] = []
    ) -> String {
        contentRevision(
            components: projectReferences.sorted {
                if $0.projectID == $1.projectID {
                    return $0.recordName < $1.recordName
                }
                return $0.projectID < $1.projectID
            }.map {
                "\($0.projectID):\($0.recordName)"
            } + ProjectDeletionTombstone.normalized(deletedProjects).map {
                deletionTombstoneRevisionComponent($0)
            }
        )
    }

    static func deletionTombstoneRevisionComponent(
        _ tombstone: ProjectDeletionTombstone
    ) -> String {
        let timestamp = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            tombstone.deletedAt.timeIntervalSince1970
        )
        return "deleted:\(tombstone.projectID):\(timestamp)"
    }

    static func payloadNeedsUpload(
        _ data: Data,
        existingHash: String?,
        existingData: Data?
    ) -> Bool {
        let desiredHash = payloadHash(for: data)
        if existingHash == desiredHash {
            return false
        }
        if let existingData, existingData == data {
            return false
        }
        return true
    }

    private static func decodeProject(from object: [String: Any]) throws -> NovelProject {
        let decoder = makeDecoder()
        let originalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let project = try? decoder.decode(NovelProject.self, from: originalData) {
            return project
        }

        var compatibleObject = object
        for fieldName in crossPlatformIncompatibleFieldNames {
            compatibleObject.removeValue(forKey: fieldName)
        }
        let compatibleData = try JSONSerialization.data(
            withJSONObject: compatibleObject,
            options: [.sortedKeys]
        )
        return try decoder.decode(NovelProject.self, from: compatibleData)
    }

    private static func commonObject(from platformObject: [String: Any]) -> [String: Any] {
        platformObject.filter { commonFieldNames.contains($0.key) }
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return object
    }

    private static func validatedEnvelope(_ object: [String: Any]) throws -> [String: Any]? {
        guard let version = object[versionKey] as? NSNumber else { return nil }
        guard version.intValue == currentVersion else {
            throw CodecError.unsupportedEnvelopeVersion(version.intValue)
        }
        guard let common = object[commonKey] as? [String: Any],
              let platforms = object[platformsKey] as? [String: Any],
              let commonID = common["id"] as? String,
              !commonID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodecError.malformedEnvelope
        }
        for payload in platforms.values {
            guard let platformPayload = payload as? [String: Any] else {
                throw CodecError.malformedEnvelope
            }
            if let platformID = platformPayload["id"] as? String,
               platformID != commonID {
                throw CodecError.malformedEnvelope
            }
        }
        return object
    }

    private static func legacyPlatform(
        for object: [String: Any]
    ) -> CloudProjectPayloadPlatform? {
        let keys = Set(object.keys)
        if !keys.isDisjoint(with: macOSLegacyMarkers) {
            return .macOS
        }
        if !keys.isDisjoint(with: iOSLegacyMarkers) {
            return .iOS
        }
        return nil
    }

    private static func makeEncoder() -> JSONEncoder {
        CloudProjectJSONCoding.makeEncoder()
    }

    private static func makeDecoder() -> JSONDecoder {
        CloudProjectJSONCoding.makeDecoder()
    }
}
