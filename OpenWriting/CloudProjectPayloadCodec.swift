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
            if let date = try? fractionalDateFormat.parse(rawValue) {
                return date
            }
            if let date = try? wholeSecondDateFormat.parse(rawValue) {
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
        fractionalDateFormat.format(date)
    }

    static func representsSamePersistedInstant(_ lhs: Date, _ rhs: Date) -> Bool {
        string(from: lhs) == string(from: rhs)
    }

    private static let fractionalDateFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
        timeZone: .gmt
    )
    private static let wholeSecondDateFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: false,
        timeZone: .gmt
    )
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
        "globalMemorySnapshot",
        "strandWeaveTracker",
        "foreshadowList",
        "plotThreadList",
        "genreTemplateId"
    ]
    private static let iOSExclusiveLegacyMarkers: Set<String> = [
        "referenceContextItems"
    ]
    private static let iOSLegacyFallbackMarkers: Set<String> = [
        "persistedLongformRuntimeState",
        "persistedLastReviewResult",
        "persistedAntiPatterns"
    ]
    private static let iOSOwnedFieldNames: Set<String> = [
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
        "draftWordCount",
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
        "referenceContextText",
        "referenceContextItems",
        "aiWritingMode",
        "aiWritingLength",
        "aiAdditionalInstruction",
        "chapterCatalog",
        "qualityReviewReports",
        "persistedMemoryBuckets",
        "persistedStrandWeaveState",
        "persistedAntiPatterns",
        "persistedLastReviewResult",
        "persistedLongformRuntimeState",
        "pendingAIWritingCandidate",
        "chapterDrafts",
        "referenceDocuments",
        "coverImageData"
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
        var preservedRootFields: [String: Any] = [:]
        let expectedProjectID = try requiredProjectID(
            in: platformObject,
            context: platform.rawValue
        )

        if let previousData {
            let previousObject = try jsonObject(from: previousData)
            if let envelope = try validatedEnvelope(previousObject) {
                let platforms = try platformObjects(in: envelope)
                let common = try requiredObject(envelope[commonKey], named: commonKey)
                try validateEnvelopeIdentity(
                    common: common,
                    platforms: platforms,
                    expectedProjectID: expectedProjectID
                )
                preservedRootFields = envelope.filter {
                    ![versionKey, commonKey, platformsKey].contains($0.key)
                }
                preservedPlatforms = platforms
                preservedCommon = common
                if let previousPlatformObject = platforms[platform.rawValue] as? [String: Any] {
                    platformObject = mergedPlatformObject(
                        previous: previousPlatformObject,
                        replacement: platformObject,
                        platform: platform
                    )
                }
            } else {
                let legacyProjectID = try requiredProjectID(
                    in: previousObject,
                    context: "legacy project payload"
                )
                guard legacyProjectID == expectedProjectID else {
                    throw CodecError.malformedEnvelope
                }
                preservedCommon = commonObject(from: previousObject)
                switch try legacyPlatform(for: previousObject) {
                case platform:
                    platformObject = mergedPlatformObject(
                        previous: previousObject,
                        replacement: platformObject,
                        platform: platform
                    )
                case let preservedPlatform?:
                    preservedPlatforms[preservedPlatform.rawValue] = previousObject
                case nil:
                    break
                }
            }
        }

        preservedPlatforms[platform.rawValue] = platformObject
        preservedCommon.merge(commonObject(from: platformObject)) { _, newValue in newValue }
        var envelope = preservedRootFields
        envelope[versionKey] = currentVersion
        envelope[commonKey] = preservedCommon
        envelope[platformsKey] = preservedPlatforms
        _ = try validatedEnvelope(envelope)
        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys]
        )
    }

    static func decodeMacProject(from data: Data) throws -> NovelProject {
        let root = try jsonObject(from: data)
        if let envelope = try validatedEnvelope(root) {
            let common = try requiredObject(envelope[commonKey], named: commonKey)
            let platforms = try platformObjects(in: envelope)
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
        guard let envelope = try validatedEnvelope(root) else { return nil }
        let platforms = try platformObjects(in: envelope)
        guard let payload = platforms[platform.rawValue] as? [String: Any] else {
            return nil
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func commonPayload(in data: Data) throws -> Data? {
        let root = try jsonObject(from: data)
        guard let envelope = try validatedEnvelope(root) else { return nil }
        let common = try requiredObject(envelope[commonKey], named: commonKey)
        return try JSONSerialization.data(withJSONObject: common, options: [.sortedKeys])
    }

    static func projectID(in data: Data) throws -> String {
        let root = try jsonObject(from: data)
        if let envelope = try validatedEnvelope(root) {
            let common = try requiredObject(envelope[commonKey], named: commonKey)
            return try requiredProjectID(in: common, context: commonKey)
        }

        return try requiredProjectID(in: root, context: "legacy project payload")
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

    private static func mergedPlatformObject(
        previous: [String: Any],
        replacement: [String: Any],
        platform: CloudProjectPayloadPlatform
    ) -> [String: Any] {
        let ownedFieldNames: Set<String>
        switch platform {
        case .macOS:
            ownedFieldNames = Set(NovelProject.CodingKeys.allCases.map(\.rawValue))
        case .iOS:
            ownedFieldNames = iOSOwnedFieldNames
        }

        var merged = previous.filter { !ownedFieldNames.contains($0.key) }
        merged.merge(replacement) { _, newValue in newValue }
        return merged
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return object
    }

    private static func validatedEnvelope(_ object: [String: Any]) throws -> [String: Any]? {
        guard object[versionKey] != nil else { return nil }
        let version = try envelopeVersion(in: object)
        guard version == currentVersion else {
            throw CodecError.unsupportedEnvelopeVersion(version)
        }
        let common = try requiredObject(object[commonKey], named: commonKey)
        let platforms = try platformObjects(in: object)
        let commonID = try requiredProjectID(in: common, context: commonKey)
        try validateEnvelopeIdentity(
            common: common,
            platforms: platforms,
            expectedProjectID: commonID
        )
        return object
    }

    private static func envelopeVersion(in object: [String: Any]) throws -> Int {
        guard let rawValue = object[versionKey] as? NSNumber else {
            throw CodecError.malformedEnvelope
        }
        let integerObjectiveCTypes: Set<String> = [
            "q", "Q", "i", "I", "s", "S", "l", "L"
        ]
        let objectiveCType = String(cString: rawValue.objCType)
        guard integerObjectiveCTypes.contains(objectiveCType),
              let version = Int(rawValue.stringValue) else {
            throw CodecError.malformedEnvelope
        }
        return version
    }

    private static func platformObjects(
        in object: [String: Any]
    ) throws -> [String: Any] {
        let rawPlatforms = try requiredObject(object[platformsKey], named: platformsKey)
        var platforms: [String: Any] = [:]
        for (platform, value) in rawPlatforms {
            platforms[platform] = try requiredObject(
                value,
                named: "\(platformsKey).\(platform)"
            )
        }
        return platforms
    }

    private static func requiredObject(
        _ value: Any?,
        named name: String
    ) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw CodecError.malformedEnvelope
        }
        return object
    }

    private static func validateEnvelopeIdentity(
        common: [String: Any],
        platforms: [String: Any],
        expectedProjectID: String
    ) throws {
        let commonProjectID = try requiredProjectID(in: common, context: commonKey)
        guard commonProjectID == expectedProjectID else {
            throw CodecError.malformedEnvelope
        }

        for (platform, value) in platforms {
            guard let payload = value as? [String: Any] else {
                throw CodecError.malformedEnvelope
            }
            let requiresProjectID =
                platform == CloudProjectPayloadPlatform.macOS.rawValue
                    || platform == CloudProjectPayloadPlatform.iOS.rawValue
            guard requiresProjectID || payload["id"] != nil else {
                continue
            }
            let platformProjectID = try requiredProjectID(
                in: payload,
                context: "\(platformsKey).\(platform)"
            )
            guard platformProjectID == expectedProjectID else {
                throw CodecError.malformedEnvelope
            }
        }
    }

    private static func requiredProjectID(
        in payload: [String: Any],
        context _: String
    ) throws -> String {
        guard let projectID = payload["id"] as? String,
              !projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodecError.malformedEnvelope
        }
        return projectID
    }

    private static func legacyPlatform(
        for object: [String: Any]
    ) throws -> CloudProjectPayloadPlatform? {
        let keys = Set(object.keys)
        let hasMacOSMarker = !keys.isDisjoint(with: macOSLegacyMarkers)
        let hasIOSExclusiveMarker = !keys.isDisjoint(
            with: iOSExclusiveLegacyMarkers
        )
        let hasIOSFallbackMarker = !keys.isDisjoint(
            with: iOSLegacyFallbackMarkers
        )

        guard !(hasMacOSMarker && hasIOSExclusiveMarker) else {
            throw CodecError.malformedEnvelope
        }
        if hasMacOSMarker {
            return .macOS
        }
        if hasIOSExclusiveMarker || hasIOSFallbackMarker {
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
