import AuthenticationServices
import CloudKit
import Foundation
import OSLog
import Security

nonisolated protocol AppleCredentialStateProviding {
    func credentialState(
        for userID: String
    ) async throws -> ASAuthorizationAppleIDProvider.CredentialState
}

nonisolated struct SystemAppleCredentialStateProvider: AppleCredentialStateProviding {
    func credentialState(
        for userID: String
    ) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }
}

struct AppleAccountProfile: Codable, Hashable {
    var userID: String
    var email: String
    var fullName: String

    var displayName: String {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }

        return "Apple ID"
    }

    var secondaryLabel: String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? "已连接 Apple ID" : trimmedEmail
    }

    static func from(
        credential: ASAuthorizationAppleIDCredential,
        fallback: AppleAccountProfile?
    ) -> AppleAccountProfile {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default

        let resolvedName = (credential.fullName
            .map { formatter.string(from: $0) } ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AppleAccountProfile(
            userID: credential.user,
            email: credential.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback?.email ?? "",
            fullName: resolvedName.isEmpty ? (fallback?.fullName ?? "") : resolvedName
        )
    }
}

struct ICloudSnapshotRecordPlan: Equatable {
    var snapshotRecordName: String
    var projectRecordNames: [String]
    var chapterRecordNames: [String]
    var deletedRecordNames: [String]
}

nonisolated struct ContentAddressedPayloadTarget {
    let recordID: CKRecord.ID
    let payloadHash: String
    let recordType: String?
    let scope: String?
    let projectID: String?
    let chapterID: String?
    let updatedAt: Date?
    let chapterIDs: [String]?
    let chapterRecordNames: [String]?

    init(
        recordID: CKRecord.ID,
        payloadHash: String,
        recordType: String? = nil,
        scope: String? = nil,
        projectID: String? = nil,
        chapterID: String? = nil,
        updatedAt: Date? = nil,
        chapterIDs: [String]? = nil,
        chapterRecordNames: [String]? = nil
    ) {
        self.recordID = recordID
        self.payloadHash = payloadHash
        self.recordType = recordType
        self.scope = scope
        self.projectID = projectID
        self.chapterID = chapterID
        self.updatedAt = updatedAt
        self.chapterIDs = chapterIDs
        self.chapterRecordNames = chapterRecordNames
    }

    func matchesMetadata(in record: CKRecord) -> Bool {
        if let recordType, record.recordType != recordType { return false }
        if let scope, stringValue(record["scope"]) != scope { return false }
        if let projectID, stringValue(record["projectID"]) != projectID { return false }
        if let chapterID, stringValue(record["chapterID"]) != chapterID { return false }
        if let updatedAt {
            guard let storedUpdatedAt = dateValue(record["updatedAt"]),
                  CloudProjectJSONCoding.representsSamePersistedInstant(
                    storedUpdatedAt,
                    updatedAt
                  ) else {
                return false
            }
        }
        switch (chapterIDs, chapterRecordNames) {
        case (nil, nil):
            break
        case let (chapterIDs?, chapterRecordNames?):
            guard let expectedManifest = canonicalChapterManifest(
                chapterIDs: chapterIDs,
                recordNames: chapterRecordNames
            ),
            let storedChapterIDs = stringArray(record["chapterIDs"]),
            let storedChapterRecordNames = stringArray(record["chapterRecordNames"]),
            let storedManifest = canonicalChapterManifest(
                chapterIDs: storedChapterIDs,
                recordNames: storedChapterRecordNames
            ),
            storedManifest == expectedManifest else {
                return false
            }
        case (.some, nil), (nil, .some):
            return false
        }
        return true
    }

    private struct ChapterManifestEntry: Equatable {
        var chapterID: String
        var recordName: String
    }

    private func canonicalChapterManifest(
        chapterIDs: [String],
        recordNames: [String]
    ) -> [ChapterManifestEntry]? {
        guard chapterIDs.count == recordNames.count,
              chapterIDs.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              recordNames.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              Set(chapterIDs).count == chapterIDs.count,
              Set(recordNames).count == recordNames.count else {
            return nil
        }
        return zip(chapterIDs, recordNames)
            .map {
                ChapterManifestEntry(chapterID: $0.0, recordName: $0.1)
            }
            .sorted {
                if $0.chapterID != $1.chapterID {
                    return $0.chapterID < $1.chapterID
                }
                return $0.recordName < $1.recordName
            }
    }

    private func stringValue(_ value: CKRecordValue?) -> String? {
        if let value = value as? String { return value }
        return (value as? NSString).map(String.init)
    }

    private func stringArray(_ value: CKRecordValue?) -> [String]? {
        if let value = value as? [String] { return value }
        if let value = value as? [NSString] { return value.map(String.init) }
        if let value = value as? NSArray {
            let strings = value.compactMap { $0 as? String }
            return strings.count == value.count ? strings : nil
        }
        return nil
    }

    private func dateValue(_ value: CKRecordValue?) -> Date? {
        if let value = value as? Date { return value }
        return (value as? NSDate).map { $0 as Date }
    }
}

nonisolated struct CloudPayloadRecordOwnership: Equatable {
    let recordID: CKRecord.ID
    let recordType: String
    let scope: String
    let projectID: String
    let chapterID: String?
    let requiresCompleteMetadata: Bool

    func matches(_ record: CKRecord) -> Bool {
        guard record.recordID == recordID,
              record.recordType == recordType,
              metadataValue(
                in: record,
                key: "scope",
                expectedValue: scope
              ),
              metadataValue(
                in: record,
                key: "projectID",
                expectedValue: projectID
              ) else {
            return false
        }
        if let chapterID {
            return metadataValue(
                in: record,
                key: "chapterID",
                expectedValue: chapterID
            )
        }
        return true
    }

    private func metadataValue(
        in record: CKRecord,
        key: String,
        expectedValue: String
    ) -> Bool {
        guard record[key] != nil else {
            return !requiresCompleteMetadata
        }
        if let value = record[key] as? String {
            return value == expectedValue
        }
        if let value = record[key] as? NSString {
            return String(value) == expectedValue
        }
        return false
    }
}

nonisolated struct PendingCleanupReservation: Codable, Equatable {
    let recordName: String
    let recordType: String
    let scope: String
    let projectID: String
    let chapterID: String?
    let payloadHash: String

    var recordID: CKRecord.ID {
        CKRecord.ID(recordName: recordName)
    }
}

nonisolated struct PendingCleanupManifest: Equatable {
    enum ManifestError: Error {
        case invalid
    }

    let reservations: [PendingCleanupReservation]
    let legacyRecordNames: [String]

    init(
        reservations: [PendingCleanupReservation],
        legacyRecordNames: [String]
    ) throws {
        let orderedReservations = reservations.sorted {
            $0.recordName < $1.recordName
        }
        let reservationNames = orderedReservations.map(\.recordName)
        guard reservationNames.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }),
        Set(reservationNames).count == reservationNames.count else {
            throw ManifestError.invalid
        }

        let structuredNames = Set(reservationNames)
        let orderedLegacyNames = Array(
            Set(legacyRecordNames).subtracting(structuredNames)
        ).sorted()
        guard orderedLegacyNames.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw ManifestError.invalid
        }

        self.reservations = orderedReservations
        self.legacyRecordNames = orderedLegacyNames
    }

    var recordNames: [String] {
        (reservations.map(\.recordName) + legacyRecordNames).sorted()
    }

    func merging(
        _ other: PendingCleanupManifest
    ) throws -> PendingCleanupManifest {
        var reservationsByName = Dictionary(
            uniqueKeysWithValues: reservations.map { ($0.recordName, $0) }
        )
        for reservation in other.reservations {
            if let existing = reservationsByName[reservation.recordName],
               existing != reservation {
                throw ManifestError.invalid
            }
            reservationsByName[reservation.recordName] = reservation
        }
        return try PendingCleanupManifest(
            reservations: Array(reservationsByName.values),
            legacyRecordNames: legacyRecordNames + other.legacyRecordNames
        )
    }

    func retaining(
        recordNames retainedRecordNames: Set<String>
    ) throws -> PendingCleanupManifest {
        try PendingCleanupManifest(
            reservations: reservations.filter {
                retainedRecordNames.contains($0.recordName)
            },
            legacyRecordNames: legacyRecordNames.filter(
                retainedRecordNames.contains
            )
        )
    }
}

nonisolated struct ValidatedCleanupPlan {
    let recordIDsToDelete: [CKRecord.ID]
    let retainedPendingManifest: PendingCleanupManifest
}

nonisolated struct ContentAddressedUploadPlan {
    enum PlanError: LocalizedError {
        case contentCollision(String)

        var errorDescription: String? {
            switch self {
            case let .contentCollision(recordName):
                return "内容寻址记录 \(recordName) 已存在但 payload hash 不一致。"
            }
        }
    }

    let recordIDsToCreate: [CKRecord.ID]
    let publishesIndex = true

    static var createOnlySavePolicy:
        CKModifyRecordsOperation.RecordSavePolicy {
        .ifServerRecordUnchanged
    }

    func savePolicy(
        for recordID: CKRecord.ID
    ) -> CKModifyRecordsOperation.RecordSavePolicy? {
        recordIDsToCreate.contains(recordID)
            ? Self.createOnlySavePolicy
            : nil
    }

    static func build(
        desired targets: [ContentAddressedPayloadTarget],
        existingRecordIDs: Set<CKRecord.ID>,
        existingPayloadHashes: [CKRecord.ID: String]
    ) throws -> ContentAddressedUploadPlan {
        var recordIDsToCreate: [CKRecord.ID] = []
        for target in targets {
            guard existingRecordIDs.contains(target.recordID) else {
                recordIDsToCreate.append(target.recordID)
                continue
            }
            guard existingPayloadHashes[target.recordID] == target.payloadHash else {
                throw PlanError.contentCollision(target.recordID.recordName)
            }
        }
        return ContentAddressedUploadPlan(recordIDsToCreate: recordIDsToCreate)
    }
}

nonisolated enum CloudIndexCASDecision: Equatable {
    case alreadyPublished
    case retry
    case fail
}

nonisolated enum CloudIndexOperationConfiguration {
    static var savePolicy: CKModifyRecordsOperation.RecordSavePolicy {
        .ifServerRecordUnchanged
    }

    static var atomically: Bool {
        true
    }
}

nonisolated enum ICloudRecordBatching {
    static let maximumRecordsPerOperation = 200
    static let maximumCleanupDeletesPerOperation =
        maximumRecordsPerOperation - 1

    static func batches<Element>(_ elements: [Element]) -> [[Element]] {
        stride(from: 0, to: elements.count, by: maximumRecordsPerOperation).map { start in
            Array(elements[start..<min(start + maximumRecordsPerOperation, elements.count)])
        }
    }

    static func cleanupTransactions(
        deleting recordIDs: [CKRecord.ID],
        deletionManifest: PendingCleanupManifest,
        retainedManifest: PendingCleanupManifest,
        revision: String
    ) throws -> [CloudCleanupTransactionPlan] {
        let orderedRecordIDs = recordIDs.sorted {
            $0.recordName < $1.recordName
        }
        guard deletionManifest.recordNames
                == orderedRecordIDs.map(\.recordName) else {
            throw PendingCleanupManifest.ManifestError.invalid
        }
        guard !orderedRecordIDs.isEmpty else {
            return [
                CloudCleanupTransactionPlan(
                    expectedRevision: revision,
                    deletingRecordIDs: [],
                    remainingCleanupManifest: retainedManifest
                )
            ]
        }

        return try stride(
            from: 0,
            to: orderedRecordIDs.count,
            by: maximumCleanupDeletesPerOperation
        ).map { start in
            let end = min(
                start + maximumCleanupDeletesPerOperation,
                orderedRecordIDs.count
            )
            let remainingRecordNames = Set(
                orderedRecordIDs[end...].map(\.recordName)
            )
            let remainingDeletionManifest = try deletionManifest.retaining(
                recordNames: remainingRecordNames
            )
            return CloudCleanupTransactionPlan(
                expectedRevision: revision,
                deletingRecordIDs: Array(orderedRecordIDs[start..<end]),
                remainingCleanupManifest: try retainedManifest.merging(
                    remainingDeletionManifest
                )
            )
        }
    }
}

nonisolated struct CloudCleanupTransactionPlan {
    let expectedRevision: String
    let deletingRecordIDs: [CKRecord.ID]
    let remainingCleanupManifest: PendingCleanupManifest

    var remainingCleanupRecordNames: [String] {
        remainingCleanupManifest.recordNames
    }

    var savePolicy: CKModifyRecordsOperation.RecordSavePolicy {
        CloudIndexOperationConfiguration.savePolicy
    }

    var atomically: Bool {
        CloudIndexOperationConfiguration.atomically
    }

    var operationRecordCount: Int {
        deletingRecordIDs.count + 1
    }
}

enum ICloudSyncAvailability {
    case available
    case unavailable(String)

    var message: String {
        switch self {
        case .available:
            return "iCloud 已连接，项目会自动同步。"
        case let .unavailable(reason):
            return reason
        }
    }
}

enum NativeAppleServiceAvailability {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        switch self {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    var message: String {
        switch self {
        case .available:
            return ""
        case let .unavailable(reason):
            return reason
        }
    }
}

enum NativeAppleAccountRuntime {
    nonisolated static func signInWithAppleAvailability(bundle: Bundle = .main) -> NativeAppleServiceAvailability {
        guard let bundleIdentifier = bundle.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .unavailable("当前应用没有可用的 Bundle ID，无法发起 Apple ID 登录。")
        }

        guard let signInEntitlement = entitlementArray(for: "com.apple.developer.applesignin"),
              !signInEntitlement.isEmpty
        else {
            return .unavailable("当前预览包没有启用“Sign in with Apple”能力，所以这里无法完成 Apple ID 登录。需要把宿主 App 用带该 capability 的签名重新打包。")
        }

        return .available
    }

    nonisolated static func iCloudEntitlementAvailability() -> NativeAppleServiceAvailability {
        let hasICloudEntitlement = iCloudContainerIdentifier() != nil

        if hasICloudEntitlement {
            return .available
        }

        return .unavailable("当前预览包没有启用 iCloud capability，所以只能显示本机保存状态。")
    }

    nonisolated static func cloudKitContainer() -> CKContainer? {
        guard let identifier = iCloudContainerIdentifier() else {
            return nil
        }

        return CKContainer(identifier: identifier)
    }

    private nonisolated static func iCloudContainerIdentifier() -> String? {
        let identifiers =
            entitlementArray(for: "com.apple.developer.icloud-container-identifiers") ??
            entitlementArray(for: "com.apple.developer.ubiquity-container-identifiers")

        return identifiers?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private nonisolated static func entitlementArray(for key: String) -> [String]? {
        guard let task = SecTaskCreateFromSelf(nil),
              let rawValue = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        else {
            return nil
        }

        if let stringValue = rawValue as? String {
            return [stringValue]
        }

        if let arrayValue = rawValue as? [String] {
            return arrayValue
        }

        if let nsArray = rawValue as? NSArray {
            return nsArray.compactMap { $0 as? String }
        }

        return nil
    }
}

actor ICloudProjectStore {
    nonisolated static let deletedProjectIDsFieldName = "deletedProjectIDs"
    nonisolated static let deletedProjectDatesFieldName = "deletedProjectDates"
    nonisolated static let maximumIndexCASAttempts = 3

    enum StoreError: LocalizedError {
        case notSignedIntoICloud
        case missingContainer
        case missingPayload
        case writeFailed(String)
        case readFailed(String)
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIntoICloud:
                return "当前系统没有登录可用的 iCloud 账户。"
            case .missingContainer:
                return "当前构建还没有启用 iCloud 容器能力。"
            case .missingPayload:
                return "CloudKit 记录里缺少项目快照内容。"
            case let .writeFailed(message):
                return "写入 CloudKit 失败：\(message)"
            case let .readFailed(message):
                return "读取 CloudKit 失败：\(message)"
            case let .decodeFailed(message):
                return "解析 CloudKit 数据失败：\(message)"
            }
        }
    }

    private enum CloudKitKey {
        static let recordType = "ProjectSnapshot"
        static let projectRecordType = "ProjectPayload"
        static let chapterRecordType = "ChapterPayload"
        static let payloadAsset = "payloadAsset"
        static let updatedAt = "updatedAt"
        static let scope = "scope"
        static let activeProjectID = "activeProjectID"
        static let projectIDs = "projectIDs"
        static let projectRecordNames = "projectRecordNames"
        static let payloadRevision = "payloadRevision"
        static let pendingCleanupRecordNames = "pendingCleanupRecordNames"
        static let pendingCleanupReservations = "pendingCleanupReservations"
        static let deletedProjectIDs = ICloudProjectStore.deletedProjectIDsFieldName
        static let deletedProjectDates = ICloudProjectStore.deletedProjectDatesFieldName
        static let projectID = "projectID"
        static let chapterIDs = "chapterIDs"
        static let chapterRecordNames = "chapterRecordNames"
        static let chapterID = "chapterID"
        static let payloadHash = "payloadHash"
    }

    private let container: CKContainer?
    private let database: CKDatabase?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        container: CKContainer? = NativeAppleAccountRuntime.cloudKitContainer(),
        fileManager: FileManager = .default
    ) {
        self.container = container
        self.database = container?.privateCloudDatabase
        self.fileManager = fileManager

        self.encoder = CloudProjectJSONCoding.makeEncoder()
        self.decoder = CloudProjectJSONCoding.makeDecoder()
    }

    func availability() async -> ICloudSyncAvailability {
        do {
            let (container, _) = try configuredContainerAndDatabase()
            let status = try await accountStatus(using: container)
            switch status {
            case .available:
                _ = try await container.userRecordID()
                return .available
            case .noAccount:
                return .unavailable("当前系统没有登录可用的 iCloud 账户，项目会继续保存在本机。")
            case .restricted:
                return .unavailable("当前系统限制了 iCloud 访问，项目会继续保存在本机。")
            case .couldNotDetermine:
                return .unavailable("暂时无法确认 iCloud 状态，请稍后重试。")
            case .temporarilyUnavailable:
                return .unavailable("iCloud 当前暂时不可用，请稍后重试。")
            @unknown default:
                return .unavailable("当前无法访问 iCloud，项目会继续保存在本机。")
            }
        } catch let error as StoreError {
            return .unavailable(error.localizedDescription)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func loadSnapshot(for scope: String) async throws -> AccountProjectSnapshot? {
        try Task.checkCancellation()
        let (container, database) = try configuredContainerAndDatabase()
        guard try await accountStatus(using: container) == .available else {
            throw StoreError.notSignedIntoICloud
        }
        try Task.checkCancellation()

        let recordID = Self.snapshotRecordID(for: scope)
        let fetchedRecords = try await database.records(for: [recordID])
        try Task.checkCancellation()
        guard let result = fetchedRecords[recordID] else { return nil }

        let record: CKRecord
        switch result {
        case let .success(resolvedRecord):
            record = resolvedRecord
        case let .failure(error as CKError) where error.code == CKError.Code.unknownItem:
            return nil
        case let .failure(error):
            throw StoreError.readFailed(error.localizedDescription)
        }

        return try await resolvedSnapshot(
            from: record,
            scope: scope,
            database: database
        )
    }

    func saveSnapshot(_ snapshot: AccountProjectSnapshot, for scope: String) async throws {
        try await saveSnapshot(
            snapshot,
            for: scope,
            indexCASAttempt: 0
        )
    }

    private func saveSnapshot(
        _ snapshot: AccountProjectSnapshot,
        for scope: String,
        indexCASAttempt: Int
    ) async throws {
        try Task.checkCancellation()
        let (container, database) = try configuredContainerAndDatabase()
        guard try await accountStatus(using: container) == .available else {
            throw StoreError.notSignedIntoICloud
        }
        try Task.checkCancellation()

        do {
            try Self.validateSnapshotForWrite(snapshot)
            let sanitizedScope = Self.scopeIdentifier(for: scope)
            let snapshotRecordID = Self.snapshotRecordID(for: scope)
            var existingRecordsByID = try await existingRecords(for: [snapshotRecordID], in: database)
            try Task.checkCancellation()
            let previousIndexRecord = existingRecordsByID[snapshotRecordID]
            let snapshotToSave: AccountProjectSnapshot
            if let previousIndexRecord {
                let remoteSnapshot = try await resolvedSnapshot(
                    from: previousIndexRecord,
                    scope: scope,
                    database: database
                )
                try Task.checkCancellation()
                snapshotToSave = Self.mergedSnapshotForFreshWrite(
                    local: snapshot,
                    remote: remoteSnapshot
                )
            } else {
                snapshotToSave = Self.mergedSnapshotForFreshWrite(
                    local: snapshot,
                    remote: nil
                )
            }
            try Task.checkCancellation()
            try Self.validateSnapshotForWrite(snapshotToSave)
            let previousRevision: String?
            let previousPendingCleanupManifest: PendingCleanupManifest
            if let previousIndexRecord {
                try Self.validateIndexRecordForRewrite(
                    previousIndexRecord,
                    scope: scope
                )
                previousRevision = try Self.validatedPayloadRevision(
                    from: previousIndexRecord
                )
                _ = try Self.deletionTombstones(from: previousIndexRecord)
                previousPendingCleanupManifest = try Self.pendingCleanupManifest(
                    from: previousIndexRecord,
                    scope: scope
                )
            } else {
                previousRevision = nil
                previousPendingCleanupManifest = try PendingCleanupManifest(
                    reservations: [],
                    legacyRecordNames: []
                )
            }
            let previousProjectIDs: [String]
            let previousProjectRecordIDs: [CKRecord.ID]
            let previousUsesExplicitProjectManifest: Bool
            if let previousIndexRecord,
               previousIndexRecord[CloudKitKey.projectIDs] != nil
                    || previousIndexRecord[CloudKitKey.projectRecordNames] != nil {
                guard let resolvedProjectIDs = Self.projectIDs(from: previousIndexRecord),
                      Self.isValidManifestValues(resolvedProjectIDs) else {
                    throw StoreError.writeFailed("CloudKit 项目索引包含空白、重复或格式错误的 project ID。")
                }
                guard let resolvedRecordIDs = try Self.validatedIndexedProjectRecordIDs(
                    from: previousIndexRecord,
                    scope: scope
                ) else {
                    throw StoreError.writeFailed("CloudKit 项目索引中的 record names 数量不匹配。")
                }
                previousProjectIDs = resolvedProjectIDs
                previousProjectRecordIDs = resolvedRecordIDs
                previousUsesExplicitProjectManifest =
                    previousIndexRecord[CloudKitKey.projectRecordNames] != nil
            } else {
                previousProjectIDs = []
                previousProjectRecordIDs = []
                previousUsesExplicitProjectManifest = false
            }
            let missingPreviousProjectRecordIDs = previousProjectRecordIDs.filter { existingRecordsByID[$0] == nil }
            if !missingPreviousProjectRecordIDs.isEmpty {
                let previousProjectRecords = try await existingRecords(for: missingPreviousProjectRecordIDs, in: database)
                existingRecordsByID.merge(previousProjectRecords) { current, _ in current }
            }

            var cleanupExpectations: [CKRecord.ID: CloudPayloadRecordOwnership] = [:]
            var previousProjectDataByID: [String: Data] = [:]
            for (expectedProjectID, projectRecordID) in zip(
                previousProjectIDs,
                previousProjectRecordIDs
            ) {
                try Self.insertCleanupExpectation(
                    CloudPayloadRecordOwnership(
                        recordID: projectRecordID,
                        recordType: CloudKitKey.projectRecordType,
                        scope: sanitizedScope,
                        projectID: expectedProjectID,
                        chapterID: nil,
                        requiresCompleteMetadata: previousUsesExplicitProjectManifest
                    ),
                    into: &cleanupExpectations
                )
                guard let record = existingRecordsByID[projectRecordID] else {
                    throw StoreError.writeFailed(
                        "CloudKit 旧项目记录 \(projectRecordID.recordName) 不可读取，已停止覆盖写入。"
                    )
                }
                let preservedPayload = try Self.preservedProjectPayloadData(
                    from: record,
                    expectedProjectID: expectedProjectID,
                    scope: scope,
                    requiresCompleteMetadata: previousUsesExplicitProjectManifest
                )
                let projectID = preservedPayload.projectID
                previousProjectDataByID[projectID] = preservedPayload.data
                let chapterManifest: (
                    chapterIDs: [String],
                    recordIDs: [CKRecord.ID],
                    usesExplicitRecordNames: Bool
                )
                do {
                    chapterManifest = try Self.validatedChapterManifest(
                        from: record,
                        projectID: projectID,
                        scope: scope,
                        revision: previousRevision,
                        requiresExplicitManifest: previousUsesExplicitProjectManifest
                    )
                } catch {
                    throw StoreError.writeFailed(
                        "CloudKit 旧项目 \(projectID) 的章节索引不完整或格式错误，已停止覆盖写入。"
                    )
                }
                for (chapterID, chapterRecordID) in zip(
                    chapterManifest.chapterIDs,
                    chapterManifest.recordIDs
                ) {
                    try Self.insertCleanupExpectation(
                        CloudPayloadRecordOwnership(
                            recordID: chapterRecordID,
                            recordType: CloudKitKey.chapterRecordType,
                            scope: sanitizedScope,
                            projectID: projectID,
                            chapterID: chapterID,
                            requiresCompleteMetadata:
                                chapterManifest.usesExplicitRecordNames
                        ),
                        into: &cleanupExpectations
                    )
                }
            }

            let encoder = self.encoder
            try Task.checkCancellation()
            var chapterPayloads: [
                (
                    projectID: String,
                    chapterID: String,
                    updatedAt: Date,
                    data: Data,
                    payloadHash: String,
                    recordName: String
                )
            ] = []
            for project in snapshotToSave.recentProjects {
                try Task.checkCancellation()
                for chapterDraft in project.chapterDrafts {
                    try Task.checkCancellation()
                    let data = try encoder.encode(chapterDraft)
                    let payloadHash = CloudProjectPayloadCodec.payloadHash(for: data)
                    let revision = CloudProjectPayloadCodec.chapterRevision(
                        payloadHash: payloadHash
                    )
                    chapterPayloads.append(
                        (
                            projectID: project.id,
                            chapterID: chapterDraft.id,
                            updatedAt: chapterDraft.savedAtDate,
                            data: data,
                            payloadHash: payloadHash,
                            recordName: Self.chapterRecordName(
                                for: chapterDraft.id,
                                projectID: project.id,
                                scope: scope,
                                revision: revision
                            )
                        )
                    )
                }
            }
            try Task.checkCancellation()
            var chapterRecordNamesByProjectID: [String: [String]] = [:]
            for payload in chapterPayloads {
                chapterRecordNamesByProjectID[payload.projectID, default: []].append(payload.recordName)
            }
            let resolvedChapterRecordNamesByProjectID = chapterRecordNamesByProjectID
            let resolvedPreviousProjectDataByID = previousProjectDataByID
            try Task.checkCancellation()
            var projectPayloads: [
                (
                    projectID: String,
                    updatedAt: Date,
                    chapterIDs: [String],
                    chapterRecordNames: [String],
                    data: Data,
                    payloadHash: String,
                    recordName: String
                )
            ] = []
            for project in snapshotToSave.recentProjects {
                try Task.checkCancellation()
                var metadata = project
                let chapterIDs = project.chapterDrafts.map(\.id)
                let chapterRecordNames =
                    resolvedChapterRecordNamesByProjectID[project.id] ?? []
                guard chapterIDs.count == chapterRecordNames.count else {
                    throw StoreError.writeFailed(
                        "CloudKit 章节 payload 与 record name 数量不匹配。"
                    )
                }
                let chapterReferences = zip(chapterIDs, chapterRecordNames)
                    .map {
                        (chapterID: $0.0, recordName: $0.1)
                    }
                    .sorted {
                        if $0.chapterID != $1.chapterID {
                            return $0.chapterID < $1.chapterID
                        }
                        return $0.recordName < $1.recordName
                    }
                metadata.chapterDrafts = []
                let data = try CloudProjectPayloadCodec.encodeMacProject(
                    metadata,
                    preserving: resolvedPreviousProjectDataByID[project.id]
                )
                let payloadHash = CloudProjectPayloadCodec.payloadHash(for: data)
                let revision = CloudProjectPayloadCodec.projectRevision(
                    payloadHash: payloadHash,
                    chapterReferences: chapterReferences
                )
                projectPayloads.append(
                    (
                        projectID: project.id,
                        updatedAt: project.updatedAtDate,
                        chapterIDs: chapterReferences.map(\.chapterID),
                        chapterRecordNames: chapterReferences.map(\.recordName),
                        data: data,
                        payloadHash: payloadHash,
                        recordName: Self.projectRecordName(
                            for: project.id,
                            scope: scope,
                            revision: revision
                        )
                    )
                )
            }
            try Task.checkCancellation()
            let targetProjectRecordIDs = projectPayloads.map { CKRecord.ID(recordName: $0.recordName) }
            let targetChapterRecordIDs = chapterPayloads.map { CKRecord.ID(recordName: $0.recordName) }
            let targetRecordIDs = targetProjectRecordIDs + targetChapterRecordIDs
            let missingTargetRecordIDs = targetRecordIDs.filter { existingRecordsByID[$0] == nil }
            if !missingTargetRecordIDs.isEmpty {
                let targetRecords = try await existingRecords(for: missingTargetRecordIDs, in: database)
                existingRecordsByID.merge(targetRecords) { current, _ in current }
            }
            let normalizedDeletedProjects = ProjectDeletionTombstone.normalized(
                snapshotToSave.deletedProjects
            )
            let previousPendingCleanupRecordIDs = Set(
                previousPendingCleanupManifest.recordNames.map {
                    CKRecord.ID(recordName: $0)
                }
            )
            let targetRecordIDSet = Set(targetRecordIDs)
            let cleanupCandidateRecordIDs = Set(cleanupExpectations.keys)
                .union(previousPendingCleanupRecordIDs)
                .subtracting(targetRecordIDSet)
            let missingCleanupCandidateRecordIDs =
                cleanupCandidateRecordIDs.filter {
                    existingRecordsByID[$0] == nil
                }
            if !missingCleanupCandidateRecordIDs.isEmpty {
                let cleanupCandidateRecords = try await existingRecords(
                    for: Array(missingCleanupCandidateRecordIDs),
                    in: database
                )
                existingRecordsByID.merge(cleanupCandidateRecords) { current, _ in current }
            }
            let cleanupPlan = try Self.validatedCleanupPlan(
                candidateRecordIDs: cleanupCandidateRecordIDs,
                recordsByID: existingRecordsByID,
                manifestExpectations: cleanupExpectations,
                pendingCleanupManifest: previousPendingCleanupManifest,
                scope: scope
            )
            let desiredPayloadTargets =
                projectPayloads.map {
                    ContentAddressedPayloadTarget(
                        recordID: CKRecord.ID(recordName: $0.recordName),
                        payloadHash: $0.payloadHash,
                        recordType: CloudKitKey.projectRecordType,
                        scope: sanitizedScope,
                        projectID: $0.projectID,
                        updatedAt: $0.updatedAt,
                        chapterIDs: $0.chapterIDs,
                        chapterRecordNames: $0.chapterRecordNames
                    )
                }
                + chapterPayloads.map {
                    ContentAddressedPayloadTarget(
                        recordID: CKRecord.ID(recordName: $0.recordName),
                        payloadHash: $0.payloadHash,
                        recordType: CloudKitKey.chapterRecordType,
                        scope: sanitizedScope,
                        projectID: $0.projectID,
                        chapterID: $0.chapterID,
                        updatedAt: $0.updatedAt
                    )
                }
            let existingTargetRecordIDs = Set(existingRecordsByID.keys).intersection(targetRecordIDSet)
            var desiredTargetByRecordID: [
                CKRecord.ID: ContentAddressedPayloadTarget
            ] = [:]
            for target in desiredPayloadTargets {
                guard desiredTargetByRecordID.updateValue(
                    target,
                    forKey: target.recordID
                ) == nil else {
                    throw StoreError.writeFailed(
                        "CloudKit payload record name \(target.recordID.recordName) 重复，已停止覆盖写入。"
                    )
                }
            }
            var existingTargetPayloadHashes: [CKRecord.ID: String] = [:]
            for recordID in existingTargetRecordIDs {
                guard let record = existingRecordsByID[recordID],
                      let target = desiredTargetByRecordID[recordID],
                      let hash = Self.verifiedExistingPayloadHash(
                        for: record,
                        matching: target
                      ) else {
                    continue
                }
                existingTargetPayloadHashes[recordID] = hash
            }
            let uploadPlan = try ContentAddressedUploadPlan.build(
                desired: desiredPayloadTargets,
                existingRecordIDs: existingTargetRecordIDs,
                existingPayloadHashes: existingTargetPayloadHashes
            )
            let recordIDsToCreate = Set(uploadPlan.recordIDsToCreate)
            let newPayloadRevision = CloudProjectPayloadCodec.manifestRevision(
                projectReferences: projectPayloads.map {
                    (projectID: $0.projectID, recordName: $0.recordName)
                },
                deletedProjects: snapshotToSave.deletedProjects
            )
            var indexRecord = existingRecordsByID[snapshotRecordID]
                ?? CKRecord(
                    recordType: CloudKitKey.recordType,
                    recordID: snapshotRecordID
                )
            if existingRecordsByID[snapshotRecordID] == nil {
                indexRecord[CloudKitKey.scope] =
                    sanitizedScope as NSString
                indexRecord[CloudKitKey.updatedAt] =
                    snapshotToSave.updatedAt as NSDate
                indexRecord[CloudKitKey.activeProjectID] = nil
                indexRecord[CloudKitKey.projectIDs] = [] as NSArray
                indexRecord[CloudKitKey.projectRecordNames] =
                    [] as NSArray
                indexRecord[CloudKitKey.payloadRevision] =
                    CloudProjectPayloadCodec.manifestRevision(
                        projectReferences: []
                    ) as NSString
                indexRecord[CloudKitKey.deletedProjectIDs] =
                    [] as NSArray
                indexRecord[CloudKitKey.deletedProjectDates] =
                    [] as NSArray
                indexRecord[CloudKitKey.payloadAsset] = nil
            }
            if !recordIDsToCreate.isEmpty {
                let uploadingTargets = recordIDsToCreate.compactMap {
                    desiredTargetByRecordID[$0]
                }
                guard uploadingTargets.count == recordIDsToCreate.count else {
                    throw StoreError.writeFailed(
                        "CloudKit 待上传 payload 缺少完整所有权元数据。"
                    )
                }
                indexRecord[CloudKitKey.scope] =
                    sanitizedScope as NSString
                let reservedManifest = try Self.pendingCleanupReservation(
                    existing: previousPendingCleanupManifest,
                    uploadingTargets: uploadingTargets
                )
                try Self.setPendingCleanupManifest(
                    reservedManifest,
                    on: indexRecord
                )
                indexRecord = try await publishIndexRecordCAS(
                    indexRecord,
                    deleting: [],
                    database: database,
                    attempt: indexCASAttempt
                )
            }

            let projectRecords = try projectPayloads.compactMap { payload -> (CKRecord, URL)? in
                let recordID = CKRecord.ID(recordName: payload.recordName)
                guard recordIDsToCreate.contains(recordID) else { return nil }
                let payloadURL = try writeTemporaryPayload(
                    payload.data,
                    identifier: payload.recordName
                )
                let record = CKRecord(recordType: CloudKitKey.projectRecordType, recordID: recordID)
                record[CloudKitKey.scope] = sanitizedScope as NSString
                record[CloudKitKey.projectID] = payload.projectID as NSString
                record[CloudKitKey.updatedAt] = payload.updatedAt as NSDate
                record[CloudKitKey.chapterIDs] = payload.chapterIDs as NSArray
                record[CloudKitKey.chapterRecordNames] = payload.chapterRecordNames as NSArray
                record[CloudKitKey.payloadHash] = payload.payloadHash as NSString
                record[CloudKitKey.payloadAsset] = CKAsset(fileURL: payloadURL)
                return (record, payloadURL)
            }
            let chapterRecords = try chapterPayloads.compactMap { payload -> (CKRecord, URL)? in
                let recordID = CKRecord.ID(recordName: payload.recordName)
                guard recordIDsToCreate.contains(recordID) else { return nil }
                let payloadURL = try writeTemporaryPayload(
                    payload.data,
                    identifier: payload.recordName
                )
                let record = CKRecord(recordType: CloudKitKey.chapterRecordType, recordID: recordID)
                record[CloudKitKey.scope] = sanitizedScope as NSString
                record[CloudKitKey.projectID] = payload.projectID as NSString
                record[CloudKitKey.chapterID] = payload.chapterID as NSString
                record[CloudKitKey.updatedAt] = payload.updatedAt as NSDate
                record[CloudKitKey.payloadHash] = payload.payloadHash as NSString
                record[CloudKitKey.payloadAsset] = CKAsset(fileURL: payloadURL)
                return (record, payloadURL)
            }

            defer {
                for (_, payloadURL) in projectRecords {
                    try? fileManager.removeItem(at: payloadURL)
                }
                for (_, payloadURL) in chapterRecords {
                    try? fileManager.removeItem(at: payloadURL)
                }
            }

            indexRecord[CloudKitKey.scope] = sanitizedScope as NSString
            indexRecord[CloudKitKey.updatedAt] = snapshotToSave.updatedAt as NSDate
            indexRecord[CloudKitKey.activeProjectID] =
                snapshotToSave.activeProjectID.map { $0 as NSString }
            indexRecord[CloudKitKey.projectIDs] =
                snapshotToSave.recentProjects.map(\.id) as NSArray
            indexRecord[CloudKitKey.projectRecordNames] = projectPayloads.map(\.recordName) as NSArray
            indexRecord[CloudKitKey.payloadRevision] = newPayloadRevision as NSString
            indexRecord[CloudKitKey.deletedProjectIDs] =
                normalizedDeletedProjects.map(\.projectID) as NSArray
            indexRecord[CloudKitKey.deletedProjectDates] =
                normalizedDeletedProjects.map { $0.deletedAt as NSDate } as NSArray
            indexRecord[CloudKitKey.payloadAsset] = nil

            for batch in ICloudRecordBatching.batches(chapterRecords.map { $0.0 }) {
                try Task.checkCancellation()
                let results = try await database.modifyRecords(
                    saving: batch,
                    deleting: [],
                    savePolicy:
                        ContentAddressedUploadPlan.createOnlySavePolicy,
                    atomically: false
                )
                try Task.checkCancellation()
                try verifyCompleteWrite(results, saving: batch.map(\.recordID), deleting: [])
            }

            for batch in ICloudRecordBatching.batches(projectRecords.map { $0.0 }) {
                try Task.checkCancellation()
                let results = try await database.modifyRecords(
                    saving: batch,
                    deleting: [],
                    savePolicy:
                        ContentAddressedUploadPlan.createOnlySavePolicy,
                    atomically: false
                )
                try Task.checkCancellation()
                try verifyCompleteWrite(results, saving: batch.map(\.recordID), deleting: [])
            }

            let deletionManifest = try Self.pendingCleanupDeletionManifest(
                for: cleanupPlan.recordIDsToDelete,
                recordsByID: existingRecordsByID,
                existingPendingManifest: previousPendingCleanupManifest,
                scope: scope
            )
            let cleanupTransactions = try ICloudRecordBatching.cleanupTransactions(
                deleting: cleanupPlan.recordIDsToDelete,
                deletionManifest: deletionManifest,
                retainedManifest: cleanupPlan.retainedPendingManifest,
                revision: newPayloadRevision
            )
            var cleanupIndexRecord = indexRecord
            for transaction in cleanupTransactions {
                try Task.checkCancellation()
                guard transaction.operationRecordCount
                        <= ICloudRecordBatching.maximumRecordsPerOperation else {
                    throw StoreError.writeFailed(
                        "CloudKit 清理事务超过单次 200 条记录上限。"
                    )
                }
                try Self.validateCleanupIndexRecord(
                    cleanupIndexRecord,
                    expectedRevision: transaction.expectedRevision
                )
                try Self.setPendingCleanupManifest(
                    transaction.remainingCleanupManifest,
                    on: cleanupIndexRecord
                )

                let publishedIndexRecord = try await publishIndexRecordCAS(
                    cleanupIndexRecord,
                    deleting: transaction.deletingRecordIDs,
                    database: database,
                    attempt: indexCASAttempt
                )
                try Self.validateCleanupIndexRecord(
                    publishedIndexRecord,
                    expectedRevision: transaction.expectedRevision
                )
                cleanupIndexRecord = publishedIndexRecord
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error where Self.cloudKitErrorCode(in: error)
                == .serverRecordChanged {
            guard indexCASAttempt + 1 < Self.maximumIndexCASAttempts else {
                throw StoreError.writeFailed(
                    "CloudKit 索引在 \(Self.maximumIndexCASAttempts) 次 CAS 尝试内持续发生并发更新。"
                )
            }
            try await saveSnapshot(
                snapshot,
                for: scope,
                indexCASAttempt: indexCASAttempt + 1
            )
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    static func mergedSnapshotForFreshWrite(
        local: AccountProjectSnapshot,
        remote: AccountProjectSnapshot?
    ) -> AccountProjectSnapshot {
        let mergedState =
            CloudProjectMergePolicy.mergeCloudProjectStateForFreshWrite(
            local: local.recentProjects,
            localDeletedProjects: local.deletedProjects,
            remote: remote?.recentProjects ?? [],
            remoteDeletedProjects: remote?.deletedProjects ?? []
        )
        let projectIDs = Set(mergedState.projects.map(\.id))
        let activeProjectID = CloudProjectMergePolicy.preservedCloudSelection(
            selectedProjectID: nil,
            activeProjectID: local.activeProjectID,
            snapshotActiveProjectID: remote?.activeProjectID,
            projectIDs: projectIDs
        )
        return AccountProjectSnapshot(
            activeProjectID: activeProjectID,
            recentProjects: mergedState.projects,
            deletedProjects: mergedState.deletedProjects,
            updatedAt: max(local.updatedAt, remote?.updatedAt ?? local.updatedAt)
        )
    }

    nonisolated static func validateSnapshotForWrite(
        _ snapshot: AccountProjectSnapshot
    ) throws {
        let projectIDs = snapshot.recentProjects.map(\.id)
        guard isValidManifestValues(projectIDs) else {
            throw StoreError.writeFailed(
                "CloudKit 待写入快照包含空白或重复的 project ID。"
            )
        }

        for project in snapshot.recentProjects {
            let chapterDraftIDs = project.chapterDrafts.map(\.id)
            guard isValidManifestValues(chapterDraftIDs) else {
                throw StoreError.writeFailed(
                    "CloudKit 项目 \(project.id) 包含空白或重复的 chapterDraft ID。"
                )
            }

            let chapterCatalogIDs = project.chapterCatalog.map(\.id)
            guard isValidManifestValues(chapterCatalogIDs) else {
                throw StoreError.writeFailed(
                    "CloudKit 项目 \(project.id) 包含空白或重复的 chapterCatalog ID。"
                )
            }

            guard Set(chapterCatalogIDs).isSubset(
                of: Set(chapterDraftIDs)
            ) else {
                throw StoreError.writeFailed(
                    "CloudKit 项目 \(project.id) 的 chapterCatalog 引用了不存在的 chapterDraft。"
                )
            }
        }
    }

    private func resolvedSnapshot(
        from record: CKRecord,
        scope: String,
        database: CKDatabase
    ) async throws -> AccountProjectSnapshot {
        try Task.checkCancellation()
        if let indexSnapshot = try await loadIndexedSnapshot(
            from: record,
            scope: scope,
            database: database
        ) {
            try Task.checkCancellation()
            return indexSnapshot
        }

        guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL
        else {
            throw StoreError.missingPayload
        }

        do {
            try Task.checkCancellation()
            let data = try Data(contentsOf: assetURL)
            try Task.checkCancellation()
            let decoder = self.decoder
            let snapshot = try decoder.decode(AccountProjectSnapshot.self, from: data)
            try Task.checkCancellation()
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.decodeFailed(error.localizedDescription)
        }
    }

    private func configuredContainerAndDatabase() throws -> (CKContainer, CKDatabase) {
        guard let container, let database else {
            throw StoreError.missingContainer
        }

        return (container, database)
    }

    private func existingRecords(
        for recordIDs: [CKRecord.ID],
        in database: CKDatabase
    ) async throws -> [CKRecord.ID: CKRecord] {
        guard !recordIDs.isEmpty else { return [:] }

        try Task.checkCancellation()
        var recordsByID: [CKRecord.ID: CKRecord] = [:]
        for batch in ICloudRecordBatching.batches(recordIDs) {
            try Task.checkCancellation()
            let fetchedRecords = try await database.records(for: batch)
            try Task.checkCancellation()
            let resolvedBatch = try Self.validatedFetchedRecords(
                fetchedRecords,
                requested: batch
            )
            recordsByID.merge(resolvedBatch) { current, _ in current }
        }

        return recordsByID
    }

    nonisolated static func validatedFetchedRecords(
        _ fetchedRecords: [
            CKRecord.ID: Result<CKRecord, Error>
        ],
        requested recordIDs: [CKRecord.ID]
    ) throws -> [CKRecord.ID: CKRecord] {
        var recordsByID: [CKRecord.ID: CKRecord] = [:]
        for recordID in recordIDs {
            guard let result = fetchedRecords[recordID] else {
                throw StoreError.readFailed(
                    "CloudKit 未返回 \(recordID.recordName) 的读取结果。"
                )
            }
            switch result {
            case let .success(record):
                guard record.recordID == recordID else {
                    throw StoreError.readFailed(
                        "CloudKit 为 \(recordID.recordName) 返回了不匹配的记录。"
                    )
                }
                recordsByID[recordID] = record
            case let .failure(error) where isUnknownItem(error):
                continue
            case let .failure(error):
                throw StoreError.readFailed(error.localizedDescription)
            }
        }
        return recordsByID
    }

    private func publishIndexRecordCAS(
        _ record: CKRecord,
        deleting recordIDs: [CKRecord.ID],
        database: CKDatabase,
        attempt: Int
    ) async throws -> CKRecord {
        do {
            let results = try await database.modifyRecords(
                saving: [record],
                deleting: recordIDs,
                savePolicy: CloudIndexOperationConfiguration.savePolicy,
                atomically: CloudIndexOperationConfiguration.atomically
            )
            try Task.checkCancellation()
            try verifyCompleteWrite(
                results,
                saving: [record.recordID],
                deleting: recordIDs
            )
            guard case let .success(publishedRecord)? =
                    results.saveResults[record.recordID] else {
                throw StoreError.writeFailed(
                    "CloudKit 未返回已发布的快照索引。"
                )
            }
            return publishedRecord
        } catch let error where Self.cloudKitErrorCode(in: error)
                == .serverRecordChanged {
            let currentRecords = try await existingRecords(
                for: [record.recordID],
                in: database
            )
            let serverRecord = currentRecords[record.recordID]
            switch Self.indexCASDecision(
                serverRecord: serverRecord,
                expectedRecord: record,
                attempt: attempt
            ) {
            case .alreadyPublished:
                guard let serverRecord else {
                    throw error
                }
                return serverRecord
            case .retry, .fail:
                throw error
            }
        }
    }

    nonisolated static func preservedProjectPayloadData(
        from record: CKRecord,
        expectedProjectID: String,
        scope: String,
        requiresCompleteMetadata: Bool
    ) throws -> (projectID: String, data: Data) {
        let projectID = expectedProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectID.isEmpty else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目记录 \(record.recordID.recordName) 的索引 project ID 为空，已停止覆盖写入。"
            )
        }
        guard record.recordType == CloudKitKey.projectRecordType else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的记录类型为 \(record.recordType)，已停止覆盖写入。"
            )
        }

        try validatePreservedScopeMetadata(
            in: record,
            key: CloudKitKey.scope,
            scope: scope,
            projectID: projectID,
            isRequired: requiresCompleteMetadata
        )
        try validatePreservedStringMetadata(
            in: record,
            key: CloudKitKey.projectID,
            expectedValue: projectID,
            label: "project ID",
            projectID: projectID,
            isRequired: requiresCompleteMetadata
        )
        try validatePreservedDateMetadata(
            in: record,
            key: CloudKitKey.updatedAt,
            label: "updatedAt",
            payloadLabel: "项目 \(projectID)",
            isRequired: requiresCompleteMetadata
        )

        guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL
        else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 缺少 payload，已停止覆盖写入。"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: assetURL)
        } catch {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的 payload 不可读取，已停止覆盖写入：\(error.localizedDescription)"
            )
        }

        let actualHash = CloudProjectPayloadCodec.payloadHash(for: data)
        if record[CloudKitKey.payloadHash] != nil {
            guard let storedHash = Self.storedPayloadHash(in: record),
                  !storedHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StoreError.writeFailed(
                    "CloudKit 旧项目 \(projectID) 的 payloadHash 格式错误，已停止覆盖写入。"
                )
            }
            guard storedHash == actualHash else {
                throw StoreError.writeFailed(
                    "CloudKit 旧项目 \(projectID) 的 payloadHash 与资产内容不一致，已停止覆盖写入。"
                )
            }
        } else if requiresCompleteMetadata {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 缺少 payloadHash，已停止覆盖写入。"
            )
        }

        let payloadProjectID: String
        do {
            payloadProjectID = try CloudProjectPayloadCodec.projectID(in: data)
        } catch {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的 payload 结构不可验证，已停止覆盖写入：\(error.localizedDescription)"
            )
        }
        guard payloadProjectID == projectID else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的 payload project ID 为 \(payloadProjectID)，已停止覆盖写入。"
            )
        }
        return (projectID, data)
    }

    nonisolated static func preservedChapterPayloadData(
        from record: CKRecord,
        expectedProjectID: String,
        expectedChapterID: String,
        scope: String,
        requiresCompleteMetadata: Bool
    ) throws -> Data {
        let projectID = expectedProjectID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let chapterID = expectedChapterID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !projectID.isEmpty, !chapterID.isEmpty else {
            throw StoreError.writeFailed(
                "CloudKit 旧章节记录 \(record.recordID.recordName) 的索引 ID 为空，已停止覆盖写入。"
            )
        }
        guard record.recordType == CloudKitKey.chapterRecordType else {
            throw StoreError.writeFailed(
                "CloudKit 旧章节 \(chapterID) 的记录类型为 \(record.recordType)，已停止覆盖写入。"
            )
        }

        try validatePreservedScopeMetadata(
            in: record,
            key: CloudKitKey.scope,
            scope: scope,
            projectID: "\(projectID)/\(chapterID)",
            isRequired: requiresCompleteMetadata
        )
        try validatePreservedStringMetadata(
            in: record,
            key: CloudKitKey.projectID,
            expectedValue: projectID,
            label: "project ID",
            projectID: "\(projectID)/\(chapterID)",
            isRequired: requiresCompleteMetadata
        )
        try validatePreservedStringMetadata(
            in: record,
            key: CloudKitKey.chapterID,
            expectedValue: chapterID,
            label: "chapter ID",
            projectID: "\(projectID)/\(chapterID)",
            isRequired: requiresCompleteMetadata
        )
        try validatePreservedDateMetadata(
            in: record,
            key: CloudKitKey.updatedAt,
            label: "updatedAt",
            payloadLabel: "章节 \(projectID)/\(chapterID)",
            isRequired: requiresCompleteMetadata
        )

        guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw StoreError.writeFailed(
                "CloudKit 旧章节 \(projectID)/\(chapterID) 缺少 payload，已停止覆盖写入。"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: assetURL)
        } catch {
            throw StoreError.writeFailed(
                "CloudKit 旧章节 \(projectID)/\(chapterID) 的 payload 不可读取，已停止覆盖写入：\(error.localizedDescription)"
            )
        }

        let actualHash = CloudProjectPayloadCodec.payloadHash(for: data)
        if record[CloudKitKey.payloadHash] != nil {
            guard let storedHash = Self.storedPayloadHash(in: record),
                  !storedHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  storedHash == actualHash else {
                throw StoreError.writeFailed(
                    "CloudKit 旧章节 \(projectID)/\(chapterID) 的 payloadHash 无效，已停止覆盖写入。"
                )
            }
        } else if requiresCompleteMetadata {
            throw StoreError.writeFailed(
                "CloudKit 旧章节 \(projectID)/\(chapterID) 缺少 payloadHash，已停止覆盖写入。"
            )
        }

        let payloadChapterID: String
        do {
            payloadChapterID = try CloudProjectJSONCoding.makeDecoder()
                .decode(ChapterDraft.self, from: data)
                .id
        } catch {
            throw StoreError.writeFailed(
                "CloudKit 旧章节 \(projectID)/\(chapterID) 的 payload 结构不可验证，已停止覆盖写入：\(error.localizedDescription)"
            )
        }
        guard payloadChapterID == chapterID else {
            throw StoreError.writeFailed(
                "CloudKit 旧章节 \(projectID)/\(chapterID) 的 payload chapter ID 为 \(payloadChapterID)，已停止覆盖写入。"
            )
        }
        return data
    }

    private nonisolated static func validatePreservedStringMetadata(
        in record: CKRecord,
        key: String,
        expectedValue: String,
        label: String,
        projectID: String,
        isRequired: Bool
    ) throws {
        guard record[key] != nil else {
            if isRequired {
                throw StoreError.writeFailed(
                    "CloudKit 旧项目 \(projectID) 缺少 \(label)，已停止覆盖写入。"
                )
            }
            return
        }
        guard let storedValue = storedString(in: record, key: key),
              !storedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的 \(label) 格式错误，已停止覆盖写入。"
            )
        }
        guard storedValue == expectedValue else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的 \(label) 为 \(storedValue)，已停止覆盖写入。"
            )
        }
    }

    private nonisolated static func validatePreservedScopeMetadata(
        in record: CKRecord,
        key: String,
        scope: String,
        projectID: String,
        isRequired: Bool
    ) throws {
        guard record[key] != nil else {
            if isRequired {
                throw StoreError.writeFailed(
                    "CloudKit 旧项目 \(projectID) 缺少 scope，已停止覆盖写入。"
                )
            }
            return
        }
        guard let storedValue = storedString(in: record, key: key),
              !storedValue.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的 scope 格式错误，已停止覆盖写入。"
            )
        }
        guard isScopeIdentifier(storedValue, compatibleWith: scope) else {
            throw StoreError.writeFailed(
                "CloudKit 旧项目 \(projectID) 的 scope 为 \(storedValue)，已停止覆盖写入。"
            )
        }
    }

    private nonisolated static func validatePreservedDateMetadata(
        in record: CKRecord,
        key: String,
        label: String,
        payloadLabel: String,
        isRequired: Bool
    ) throws {
        guard record[key] != nil else {
            if isRequired {
                throw StoreError.writeFailed(
                    "CloudKit 旧\(payloadLabel)缺少 \(label)，已停止覆盖写入。"
                )
            }
            return
        }
        guard record[key] is Date || record[key] is NSDate else {
            throw StoreError.writeFailed(
                "CloudKit 旧\(payloadLabel)的 \(label) 格式错误，已停止覆盖写入。"
            )
        }
    }

    nonisolated static func verifiedExistingPayloadHash(
        for record: CKRecord,
        matching target: ContentAddressedPayloadTarget
    ) -> String? {
        guard target.matchesMetadata(in: record),
              storedPayloadHash(in: record) == target.payloadHash,
              let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL,
              let data = try? Data(contentsOf: assetURL) else {
            return nil
        }
        let actualHash = CloudProjectPayloadCodec.payloadHash(for: data)
        guard actualHash == target.payloadHash else { return nil }
        return actualHash
    }

    nonisolated static func pendingCleanupRecordIsOwned(
        _ record: CKRecord,
        by reservation: PendingCleanupReservation,
        scope: String
    ) -> Bool {
        guard (try? validatePendingCleanupReservation(
            reservation,
            compatibleWith: scope
        )) != nil,
        record.recordID == reservation.recordID,
        record.recordType == reservation.recordType,
        storedString(in: record, key: CloudKitKey.scope)
            == reservation.scope,
        storedString(in: record, key: CloudKitKey.projectID)
            == reservation.projectID,
        storedPayloadHash(in: record) == reservation.payloadHash else {
            return false
        }

        if reservation.recordType == CloudKitKey.chapterRecordType {
            guard storedString(in: record, key: CloudKitKey.chapterID)
                    == reservation.chapterID else {
                return false
            }
        } else {
            guard record[CloudKitKey.chapterID] == nil,
                  let chapterIDs = stringArray(
                    from: record,
                    key: CloudKitKey.chapterIDs
                  ),
                  let chapterRecordNames = stringArray(
                    from: record,
                    key: CloudKitKey.chapterRecordNames
                  ),
                  chapterIDs.count == chapterRecordNames.count,
                  isValidManifestValues(chapterIDs),
                  isValidManifestValues(chapterRecordNames) else {
                return false
            }
            let chapterReferences = zip(chapterIDs, chapterRecordNames)
                .map {
                    (chapterID: $0.0, recordName: $0.1)
                }
            let orderedChapterReferences = chapterReferences.sorted {
                if $0.chapterID != $1.chapterID {
                    return $0.chapterID < $1.chapterID
                }
                return $0.recordName < $1.recordName
            }
            guard chapterReferences.map({
                "\($0.chapterID):\($0.recordName)"
            }) == orderedChapterReferences.map({
                "\($0.chapterID):\($0.recordName)"
            }) else {
                return false
            }
            let revision = CloudProjectPayloadCodec.projectRevision(
                payloadHash: reservation.payloadHash,
                chapterReferences: orderedChapterReferences
            )
            guard projectRecordName(
                for: reservation.projectID,
                scope: reservation.scope,
                revision: revision
            ) == reservation.recordName else {
                return false
            }
        }

        guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL,
              let data = try? Data(contentsOf: assetURL) else {
            return false
        }
        return CloudProjectPayloadCodec.payloadHash(for: data)
            == reservation.payloadHash
    }

    nonisolated static func validatedCleanupPlan(
        candidateRecordIDs: Set<CKRecord.ID>,
        recordsByID: [CKRecord.ID: CKRecord],
        manifestExpectations: [CKRecord.ID: CloudPayloadRecordOwnership],
        pendingCleanupManifest: PendingCleanupManifest,
        scope: String
    ) throws -> ValidatedCleanupPlan {
        var validatedRecordIDs: [CKRecord.ID] = []
        var retainedReservations: [PendingCleanupReservation] = []
        var retainedLegacyRecordNames: [String] = []
        let reservationsByRecordID = Dictionary(
            uniqueKeysWithValues: pendingCleanupManifest.reservations.map {
                ($0.recordID, $0)
            }
        )
        let legacyRecordIDs = Set(
            pendingCleanupManifest.legacyRecordNames.map {
                CKRecord.ID(recordName: $0)
            }
        )

        for recordID in candidateRecordIDs.sorted(by: {
            $0.recordName < $1.recordName
        }) {
            guard let record = recordsByID[recordID] else {
                continue
            }
            guard record.recordID == recordID else {
                throw StoreError.writeFailed(
                    "CloudKit 清理候选 \(recordID.recordName) 返回了不匹配的 record ID。"
                )
            }

            let expectation = manifestExpectations[recordID]
            if let expectation {
                guard expectation.matches(record) else {
                    throw StoreError.writeFailed(
                        "CloudKit 清理候选 \(recordID.recordName) 不属于当前账户清单，已停止发布新索引。"
                    )
                }
            }

            if let reservation = reservationsByRecordID[recordID] {
                guard pendingCleanupRecordIsOwned(
                    record,
                    by: reservation,
                    scope: scope
                ) else {
                    retainedReservations.append(reservation)
                    continue
                }
            } else if legacyRecordIDs.contains(recordID) {
                guard expectation != nil else {
                    retainedLegacyRecordNames.append(recordID.recordName)
                    continue
                }
            } else if expectation == nil {
                throw StoreError.writeFailed(
                    "CloudKit 清理候选 \(recordID.recordName) 不在当前账户清单中，已停止发布新索引。"
                )
            }
            validatedRecordIDs.append(recordID)
        }

        return ValidatedCleanupPlan(
            recordIDsToDelete: validatedRecordIDs,
            retainedPendingManifest: try PendingCleanupManifest(
                reservations: retainedReservations,
                legacyRecordNames: retainedLegacyRecordNames
            )
        )
    }

    nonisolated static func pendingCleanupDeletionManifest(
        for recordIDs: [CKRecord.ID],
        recordsByID: [CKRecord.ID: CKRecord],
        existingPendingManifest: PendingCleanupManifest,
        scope: String
    ) throws -> PendingCleanupManifest {
        let existingReservations = Dictionary(
            uniqueKeysWithValues: existingPendingManifest.reservations.map {
                ($0.recordID, $0)
            }
        )
        var reservations: [PendingCleanupReservation] = []
        var legacyRecordNames: [String] = []
        for recordID in recordIDs {
            if let reservation = existingReservations[recordID] {
                reservations.append(reservation)
                continue
            }
            guard let record = recordsByID[recordID] else {
                throw StoreError.writeFailed(
                    "CloudKit 清理候选 \(recordID.recordName) 在事务规划前消失。"
                )
            }
            if let reservation = pendingCleanupReservation(
                from: record,
                compatibleWith: scope
            ) {
                reservations.append(reservation)
            } else {
                legacyRecordNames.append(recordID.recordName)
            }
        }
        return try PendingCleanupManifest(
            reservations: reservations,
            legacyRecordNames: legacyRecordNames
        )
    }

    nonisolated static func pendingCleanupReservation(
        existing: PendingCleanupManifest,
        uploadingTargets: [ContentAddressedPayloadTarget]
    ) throws -> PendingCleanupManifest {
        let uploadingManifest = try PendingCleanupManifest(
            reservations: uploadingTargets.map {
                try pendingCleanupReservation(from: $0)
            },
            legacyRecordNames: []
        )
        return try existing.merging(uploadingManifest)
    }

    nonisolated static func pendingCleanupReservation(
        from target: ContentAddressedPayloadTarget
    ) throws -> PendingCleanupReservation {
        guard let recordType = target.recordType,
              let scope = target.scope,
              let projectID = target.projectID else {
            throw StoreError.writeFailed(
                "CloudKit 内容寻址 payload 缺少待清理所有权字段。"
            )
        }
        let reservation = PendingCleanupReservation(
            recordName: target.recordID.recordName,
            recordType: recordType,
            scope: scope,
            projectID: projectID,
            chapterID: target.chapterID,
            payloadHash: target.payloadHash
        )
        try validatePendingCleanupReservation(
            reservation,
            compatibleWith: scope
        )
        return reservation
    }

    nonisolated static func pendingCleanupReservation(
        from record: CKRecord,
        compatibleWith scope: String
    ) -> PendingCleanupReservation? {
        guard let storedScope = storedString(
                in: record,
                key: CloudKitKey.scope
              ),
              isScopeIdentifier(storedScope, compatibleWith: scope),
              let projectID = storedString(
                in: record,
                key: CloudKitKey.projectID
              ),
              let payloadHash = storedPayloadHash(in: record) else {
            return nil
        }
        let reservation: PendingCleanupReservation
        switch record.recordType {
        case CloudKitKey.projectRecordType:
            reservation = PendingCleanupReservation(
                recordName: record.recordID.recordName,
                recordType: record.recordType,
                scope: storedScope,
                projectID: projectID,
                chapterID: nil,
                payloadHash: payloadHash
            )
        case CloudKitKey.chapterRecordType:
            guard let chapterID = storedString(
                    in: record,
                    key: CloudKitKey.chapterID
                  ) else {
                return nil
            }
            reservation = PendingCleanupReservation(
                recordName: record.recordID.recordName,
                recordType: record.recordType,
                scope: storedScope,
                projectID: projectID,
                chapterID: chapterID,
                payloadHash: payloadHash
            )
        default:
            return nil
        }
        guard (try? validatePendingCleanupReservation(
            reservation,
            compatibleWith: scope
        )) != nil,
        pendingCleanupRecordIsOwned(
            record,
            by: reservation,
            scope: scope
        ) else {
            return nil
        }
        return reservation
    }

    nonisolated static func validatePendingCleanupReservation(
        _ reservation: PendingCleanupReservation,
        compatibleWith scope: String
    ) throws {
        let normalizedScope = scopeIdentifier(for: scope)
        let nonemptyValues = [
            reservation.recordName,
            reservation.recordType,
            reservation.scope,
            reservation.projectID,
            reservation.payloadHash
        ]
        guard reservation.scope == normalizedScope,
              nonemptyValues.allSatisfy({
                  !$0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty
              }),
              reservation.payloadHash.count == 64,
              reservation.payloadHash == reservation.payloadHash.lowercased(),
              reservation.payloadHash.allSatisfy(\.isHexDigit) else {
            throw StoreError.missingPayload
        }

        switch reservation.recordType {
        case CloudKitKey.projectRecordType:
            guard reservation.chapterID == nil else {
                throw StoreError.missingPayload
            }
        case CloudKitKey.chapterRecordType:
            guard let chapterID = reservation.chapterID,
                  !chapterID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                throw StoreError.missingPayload
            }
            let revision = CloudProjectPayloadCodec.chapterRevision(
                payloadHash: reservation.payloadHash
            )
            let expectedRecordName = chapterRecordName(
                for: chapterID,
                projectID: reservation.projectID,
                scope: reservation.scope,
                revision: revision
            )
            guard reservation.recordName == expectedRecordName else {
                throw StoreError.missingPayload
            }
        default:
            throw StoreError.missingPayload
        }
    }

    nonisolated static func insertCleanupExpectation(
        _ expectation: CloudPayloadRecordOwnership,
        into expectations: inout [CKRecord.ID: CloudPayloadRecordOwnership]
    ) throws {
        if let existing = expectations[expectation.recordID],
           existing != expectation {
            throw StoreError.writeFailed(
                "CloudKit 清理清单对 \(expectation.recordID.recordName) 给出了冲突的所有权信息。"
            )
        }
        expectations[expectation.recordID] = expectation
    }

    nonisolated static func failedDeletionRecordIDs(
        _ deleteResults: [CKRecord.ID: Result<Void, Error>],
        expected recordIDs: [CKRecord.ID]
    ) -> [CKRecord.ID] {
        recordIDs.filter { recordID in
            guard let result = deleteResults[recordID] else { return true }
            switch result {
            case .success:
                return false
            case let .failure(error):
                return !isUnknownItem(error)
            }
        }
    }

    private nonisolated static func isUnknownItem(_ error: Error) -> Bool {
        if let cloudKitError = error as? CKError {
            return cloudKitError.code == .unknownItem
        }
        let nsError = error as NSError
        return nsError.domain == CKErrorDomain
            && nsError.code == CKError.Code.unknownItem.rawValue
    }

    nonisolated static func cloudKitErrorCode(
        in error: Error
    ) -> CKError.Code? {
        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain,
              let directCode = CKError.Code(
                rawValue: nsError.code
              ) else {
            return nil
        }
        guard directCode == .partialFailure,
              let partialErrors =
                nsError.userInfo[CKPartialErrorsByItemIDKey]
                    as? NSDictionary else {
            return directCode
        }
        for value in partialErrors.allValues {
            guard let partialError = value as? Error else {
                continue
            }
            if let code = cloudKitErrorCode(in: partialError),
               code == .serverRecordChanged {
                return code
            }
        }
        return directCode
    }

    nonisolated static func indexCASDecision(
        serverRecord: CKRecord?,
        expectedRecord: CKRecord,
        attempt: Int,
        maximumAttempts: Int = maximumIndexCASAttempts
    ) -> CloudIndexCASDecision {
        if let serverRecord,
           indexRecordsHaveSamePublication(
            serverRecord,
            expectedRecord
           ) {
            return .alreadyPublished
        }
        return attempt + 1 < maximumAttempts ? .retry : .fail
    }

    private nonisolated static func indexRecordsHaveSamePublication(
        _ lhs: CKRecord,
        _ rhs: CKRecord
    ) -> Bool {
        guard lhs.recordID == rhs.recordID,
              lhs.recordType == rhs.recordType,
              storedString(in: lhs, key: CloudKitKey.scope)
                == storedString(in: rhs, key: CloudKitKey.scope),
              storedString(in: lhs, key: CloudKitKey.activeProjectID)
                == storedString(in: rhs, key: CloudKitKey.activeProjectID),
              storedString(in: lhs, key: CloudKitKey.payloadRevision)
                == storedString(in: rhs, key: CloudKitKey.payloadRevision),
              stringArray(from: lhs, key: CloudKitKey.projectIDs)
                == stringArray(from: rhs, key: CloudKitKey.projectIDs),
              stringArray(
                from: lhs,
                key: CloudKitKey.projectRecordNames
              ) == stringArray(
                from: rhs,
                key: CloudKitKey.projectRecordNames
              ),
              stringArray(
                from: lhs,
                key: CloudKitKey.deletedProjectIDs
              ) == stringArray(
                from: rhs,
                key: CloudKitKey.deletedProjectIDs
              ),
              stringArray(
                from: lhs,
                key: CloudKitKey.pendingCleanupRecordNames
              ) == stringArray(
                from: rhs,
                key: CloudKitKey.pendingCleanupRecordNames
              ),
              storedData(
                in: lhs,
                key: CloudKitKey.pendingCleanupReservations
              ) == storedData(
                in: rhs,
                key: CloudKitKey.pendingCleanupReservations
              ),
              let lhsUpdatedAt =
                lhs[CloudKitKey.updatedAt] as? NSDate,
              let rhsUpdatedAt =
                rhs[CloudKitKey.updatedAt] as? NSDate,
              CloudProjectJSONCoding.representsSamePersistedInstant(
                lhsUpdatedAt as Date,
                rhsUpdatedAt as Date
              ) else {
            return false
        }
        let lhsDeletedDates = dateArray(
            from: lhs,
            key: CloudKitKey.deletedProjectDates
        )?.map { CloudProjectJSONCoding.string(from: $0) }
        let rhsDeletedDates = dateArray(
            from: rhs,
            key: CloudKitKey.deletedProjectDates
        )?.map { CloudProjectJSONCoding.string(from: $0) }
        return lhsDeletedDates == rhsDeletedDates
    }

    private func verifyCompleteWrite(
        _ results: (
            saveResults: [CKRecord.ID: Result<CKRecord, Error>],
            deleteResults: [CKRecord.ID: Result<Void, Error>]
        ),
        saving savedRecordIDs: [CKRecord.ID],
        deleting deletedRecordIDs: [CKRecord.ID]
    ) throws {
        for recordID in savedRecordIDs {
            guard let result = results.saveResults[recordID] else {
                throw StoreError.writeFailed("CloudKit 未返回 \(recordID.recordName) 的写入结果。")
            }
            if case let .failure(error) = result {
                if Self.cloudKitErrorCode(in: error) != nil {
                    throw error
                }
                throw StoreError.writeFailed("CloudKit 未能写入 \(recordID.recordName)：\(error.localizedDescription)")
            }
        }

        for recordID in deletedRecordIDs {
            guard let result = results.deleteResults[recordID] else {
                throw StoreError.writeFailed("CloudKit 未返回 \(recordID.recordName) 的删除结果。")
            }
            if case let .failure(error) = result,
               !Self.isUnknownItem(error) {
                if Self.cloudKitErrorCode(in: error) != nil {
                    throw error
                }
                throw StoreError.writeFailed("CloudKit 未能删除 \(recordID.recordName)：\(error.localizedDescription)")
            }
        }
    }

    private func accountStatus(using container: CKContainer) async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    nonisolated static func cloudKitRecordPlan(
        for snapshot: AccountProjectSnapshot,
        scope: String,
        previousProjectIDs: [String] = [],
        previousChapterIDsByProjectID: [String: [String]] = [:]
    ) -> ICloudSnapshotRecordPlan {
        let projectIDs = snapshot.recentProjects.map(\.id)
        let projectRecordNames = projectIDs.map { projectRecordName(for: $0, scope: scope) }
        let chapterRecordNames = snapshot.recentProjects.flatMap { project in
            project.chapterDrafts.map { chapterRecordName(for: $0.id, projectID: project.id, scope: scope) }
        }
        let currentProjectIDs = Set(projectIDs)
        let currentChapterRecordNames = Set(chapterRecordNames)
        let deletedProjectRecordNames = Set(previousProjectIDs)
            .subtracting(currentProjectIDs)
            .map { projectRecordName(for: $0, scope: scope) }
        let deletedChapterRecordNames = previousChapterIDsByProjectID.flatMap { projectID, chapterIDs in
            chapterIDs.map { chapterRecordName(for: $0, projectID: projectID, scope: scope) }
        }
        .filter { !currentChapterRecordNames.contains($0) }

        return ICloudSnapshotRecordPlan(
            snapshotRecordName: snapshotRecordName(for: scope),
            projectRecordNames: projectRecordNames,
            chapterRecordNames: chapterRecordNames,
            deletedRecordNames: (deletedProjectRecordNames + deletedChapterRecordNames).sorted()
        )
    }

    nonisolated static func snapshotRecordName(for scope: String) -> String {
        "snapshot_\(scopeIdentifier(for: scope))"
    }

    nonisolated static func payloadRevision(from indexRecord: CKRecord) -> String? {
        storedString(in: indexRecord, key: CloudKitKey.payloadRevision)
    }

    nonisolated static func validateIndexRecordForRewrite(
        _ indexRecord: CKRecord,
        scope: String
    ) throws {
        guard indexRecord.recordType == CloudKitKey.recordType else {
            throw StoreError.missingPayload
        }

        let hasExplicitManifest =
            indexRecord[CloudKitKey.projectRecordNames] != nil
        if indexRecord[CloudKitKey.scope] != nil {
            guard storedString(
                in: indexRecord,
                key: CloudKitKey.scope
            ).map({
                isScopeIdentifier($0, compatibleWith: scope)
            }) == true else {
                throw StoreError.missingPayload
            }
        } else if hasExplicitManifest {
            throw StoreError.missingPayload
        }

        guard indexRecord[CloudKitKey.activeProjectID] != nil else {
            return
        }
        guard let activeProjectID = storedString(
            in: indexRecord,
            key: CloudKitKey.activeProjectID
        ),
        !activeProjectID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw StoreError.missingPayload
        }

        if indexRecord[CloudKitKey.projectIDs] != nil {
            guard let projectIDs = projectIDs(from: indexRecord),
                  isValidManifestValues(projectIDs),
                  projectIDs.contains(activeProjectID) else {
                throw StoreError.missingPayload
            }
        }
    }

    nonisolated static func validatedPayloadRevision(
        from indexRecord: CKRecord
    ) throws -> String? {
        guard indexRecord[CloudKitKey.payloadRevision] != nil else {
            return nil
        }
        guard let revision = payloadRevision(from: indexRecord),
              !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.missingPayload
        }
        return revision
    }

    nonisolated static func validateCleanupIndexRecord(
        _ indexRecord: CKRecord,
        expectedRevision: String
    ) throws {
        guard try validatedPayloadRevision(from: indexRecord)
                == expectedRevision else {
            throw StoreError.writeFailed(
                "CloudKit 清理事务失去当前 payload revision 所有权，已停止删除旧记录。"
            )
        }
        guard let scope = storedString(
                in: indexRecord,
                key: CloudKitKey.scope
              ) else {
            throw StoreError.writeFailed(
                "CloudKit 清理事务的索引缺少 scope。"
            )
        }
        do {
            _ = try pendingCleanupManifest(
                from: indexRecord,
                scope: scope
            )
        } catch {
            throw StoreError.writeFailed(
                "CloudKit 清理事务的 pending-cleanup 元数据不完整。"
            )
        }
    }

    nonisolated static func indexedProjectRecordIDs(
        from indexRecord: CKRecord,
        scope: String
    ) -> [CKRecord.ID]? {
        try? validatedIndexedProjectRecordIDs(
            from: indexRecord,
            scope: scope
        )
    }

    nonisolated static func validatedIndexedProjectRecordIDs(
        from indexRecord: CKRecord,
        scope: String
    ) throws -> [CKRecord.ID]? {
        guard let projectIDs = projectIDs(from: indexRecord) else {
            return nil
        }
        guard isValidManifestValues(projectIDs) else {
            throw StoreError.missingPayload
        }
        if indexRecord[CloudKitKey.projectRecordNames] != nil {
            guard let explicitNames = stringArray(
                from: indexRecord,
                key: CloudKitKey.projectRecordNames
            ) else {
                throw StoreError.missingPayload
            }
            guard explicitNames.count == projectIDs.count,
                  isValidManifestValues(explicitNames) else {
                throw StoreError.missingPayload
            }
            return explicitNames.map { CKRecord.ID(recordName: $0) }
        }
        let revision = try validatedPayloadRevision(from: indexRecord)
        return projectIDs.map { projectRecordID(for: $0, scope: scope, revision: revision) }
    }

    nonisolated static func indexedChapterRecordIDs(
        from projectRecordsByID: [CKRecord.ID: CKRecord],
        indexRecord: CKRecord,
        scope: String
    ) throws -> [CKRecord.ID] {
        guard let projectIDs = projectIDs(from: indexRecord) else { return [] }
        guard let projectRecordIDs = try validatedIndexedProjectRecordIDs(
            from: indexRecord,
            scope: scope
        ),
              projectRecordIDs.count == projectIDs.count else {
            throw StoreError.missingPayload
        }
        let revision = try validatedPayloadRevision(from: indexRecord)
        let requiresExplicitManifest =
            indexRecord[CloudKitKey.projectRecordNames] != nil

        var recordIDs: [CKRecord.ID] = []
        for (projectID, projectRecordID) in zip(projectIDs, projectRecordIDs) {
            guard let projectRecord = projectRecordsByID[projectRecordID] else {
                throw StoreError.missingPayload
            }
            let manifest = try validatedChapterManifest(
                from: projectRecord,
                projectID: projectID,
                scope: scope,
                revision: revision,
                requiresExplicitManifest: requiresExplicitManifest
            )
            recordIDs.append(contentsOf: manifest.recordIDs)
        }
        guard Set(recordIDs).count == recordIDs.count else {
            throw StoreError.missingPayload
        }
        return recordIDs
    }

    nonisolated static func validatedChapterManifest(
        from projectRecord: CKRecord,
        projectID: String,
        scope: String,
        revision: String?,
        requiresExplicitManifest: Bool
    ) throws -> (
        chapterIDs: [String],
        recordIDs: [CKRecord.ID],
        usesExplicitRecordNames: Bool
    ) {
        let hasChapterIDs = projectRecord[CloudKitKey.chapterIDs] != nil
        let hasChapterRecordNames =
            projectRecord[CloudKitKey.chapterRecordNames] != nil

        if requiresExplicitManifest {
            guard hasChapterIDs, hasChapterRecordNames else {
                throw StoreError.missingPayload
            }
        } else if hasChapterRecordNames, !hasChapterIDs {
            throw StoreError.missingPayload
        }

        let chapterIDs: [String]
        if hasChapterIDs {
            guard let storedChapterIDs = Self.chapterIDs(from: projectRecord),
                  isValidManifestValues(storedChapterIDs) else {
                throw StoreError.missingPayload
            }
            chapterIDs = storedChapterIDs
        } else {
            chapterIDs = []
        }

        if hasChapterRecordNames {
            guard let explicitNames = stringArray(
                from: projectRecord,
                key: CloudKitKey.chapterRecordNames
            ),
            explicitNames.count == chapterIDs.count,
            isValidManifestValues(explicitNames) else {
                throw StoreError.missingPayload
            }
            return (
                chapterIDs,
                explicitNames.map { CKRecord.ID(recordName: $0) },
                true
            )
        }

        return (
            chapterIDs,
            chapterIDs.map {
                chapterRecordID(
                    for: $0,
                    projectID: projectID,
                    scope: scope,
                    revision: revision
                )
            },
            false
        )
    }

    private nonisolated static func isValidManifestValues(
        _ values: [String]
    ) -> Bool {
        values.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && Set(values).count == values.count
    }

    nonisolated static func deletionTombstones(
        from indexRecord: CKRecord
    ) throws -> [ProjectDeletionTombstone] {
        let hasProjectIDs = indexRecord[CloudKitKey.deletedProjectIDs] != nil
        let hasDeletedDates = indexRecord[CloudKitKey.deletedProjectDates] != nil
        guard hasProjectIDs || hasDeletedDates else { return [] }
        let projectIDs = stringArray(
            from: indexRecord,
            key: CloudKitKey.deletedProjectIDs
        )
        let deletedDates = dateArray(
            from: indexRecord,
            key: CloudKitKey.deletedProjectDates
        )
        guard let projectIDs,
              let deletedDates,
              projectIDs.count == deletedDates.count,
              Set(projectIDs).count == projectIDs.count,
              projectIDs.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              })
        else {
            throw StoreError.missingPayload
        }
        return ProjectDeletionTombstone.normalized(
            zip(projectIDs, deletedDates).map {
                ProjectDeletionTombstone(projectID: $0.0, deletedAt: $0.1)
            }
        )
    }

    nonisolated static func pendingCleanupRecordNames(
        from indexRecord: CKRecord
    ) throws -> [String] {
        guard indexRecord[CloudKitKey.pendingCleanupRecordNames] != nil else {
            return []
        }
        guard let recordNames = stringArray(
            from: indexRecord,
            key: CloudKitKey.pendingCleanupRecordNames
        ),
        isValidManifestValues(recordNames) else {
            throw StoreError.missingPayload
        }
        return recordNames
    }

    nonisolated static func pendingCleanupManifest(
        from indexRecord: CKRecord,
        scope: String
    ) throws -> PendingCleanupManifest {
        let recordNames = try pendingCleanupRecordNames(from: indexRecord)
        guard indexRecord[CloudKitKey.pendingCleanupReservations] != nil else {
            return try PendingCleanupManifest(
                reservations: [],
                legacyRecordNames: recordNames
            )
        }
        guard recordNames == recordNames.sorted(),
              let data = storedData(
                in: indexRecord,
                key: CloudKitKey.pendingCleanupReservations
              ),
              let reservations = try? JSONDecoder().decode(
                [PendingCleanupReservation].self,
                from: data
              ),
              reservations == reservations.sorted(by: {
                  $0.recordName < $1.recordName
              }) else {
            throw StoreError.missingPayload
        }
        for reservation in reservations {
            try validatePendingCleanupReservation(
                reservation,
                compatibleWith: scope
            )
        }
        let structuredNames = Set(reservations.map(\.recordName))
        guard structuredNames.isSubset(of: Set(recordNames)) else {
            throw StoreError.missingPayload
        }
        let manifest = try PendingCleanupManifest(
            reservations: reservations,
            legacyRecordNames: recordNames.filter {
                !structuredNames.contains($0)
            }
        )
        guard manifest.recordNames == recordNames else {
            throw StoreError.missingPayload
        }
        return manifest
    }

    nonisolated static func setPendingCleanupManifest(
        _ manifest: PendingCleanupManifest,
        on indexRecord: CKRecord
    ) throws {
        guard let indexScope = storedString(
                in: indexRecord,
                key: CloudKitKey.scope
              ) else {
            throw StoreError.writeFailed(
                "CloudKit 索引缺少 pending-cleanup scope。"
            )
        }
        for reservation in manifest.reservations {
            try validatePendingCleanupReservation(
                reservation,
                compatibleWith: indexScope
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest.reservations)
        indexRecord[CloudKitKey.pendingCleanupRecordNames] =
            manifest.recordNames as NSArray
        indexRecord[CloudKitKey.pendingCleanupReservations] =
            data as NSData
    }

    nonisolated static func projectRecordName(
        for projectID: String,
        scope: String,
        revision: String? = nil
    ) -> String {
        let revisionPart =
            revision.map { "_\(recordNameComponent($0))" } ?? ""
        return "project_\(scopeIdentifier(for: scope))\(revisionPart)_\(recordNameComponent(projectID))"
    }

    nonisolated static func chapterRecordName(
        for chapterID: String,
        projectID: String,
        scope: String,
        revision: String? = nil
    ) -> String {
        let revisionPart =
            revision.map { "_\(recordNameComponent($0))" } ?? ""
        return "chapter_\(scopeIdentifier(for: scope))\(revisionPart)_\(recordNameComponent(projectID))_\(recordNameComponent(chapterID))"
    }

    private nonisolated static func snapshotRecordID(for scope: String) -> CKRecord.ID {
        CKRecord.ID(recordName: snapshotRecordName(for: scope))
    }

    private nonisolated static func projectRecordID(
        for projectID: String,
        scope: String,
        revision: String? = nil
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: legacyProjectRecordName(
                for: projectID,
                scope: scope,
                revision: revision
            )
        )
    }

    private nonisolated static func chapterRecordID(
        for chapterID: String,
        projectID: String,
        scope: String,
        revision: String? = nil
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: legacyChapterRecordName(
                for: chapterID,
                projectID: projectID,
                scope: scope,
                revision: revision
            )
        )
    }

    private nonisolated static func legacyProjectRecordName(
        for projectID: String,
        scope: String,
        revision: String?
    ) -> String {
        let revisionPart = revision.map { "_\(sanitized($0))" } ?? ""
        return "project_\(sanitized(scope))\(revisionPart)_\(sanitized(projectID))"
    }

    private nonisolated static func legacyChapterRecordName(
        for chapterID: String,
        projectID: String,
        scope: String,
        revision: String?
    ) -> String {
        let revisionPart = revision.map { "_\(sanitized($0))" } ?? ""
        return "chapter_\(sanitized(scope))\(revisionPart)_\(sanitized(projectID))_\(sanitized(chapterID))"
    }

    private func loadIndexedSnapshot(
        from indexRecord: CKRecord,
        scope: String,
        database: CKDatabase
    ) async throws -> AccountProjectSnapshot? {
        let hasProjectIDs = indexRecord[CloudKitKey.projectIDs] != nil
        let hasProjectRecordNames =
            indexRecord[CloudKitKey.projectRecordNames] != nil
        guard hasProjectIDs || hasProjectRecordNames else {
            return nil
        }
        guard indexRecord.recordType == CloudKitKey.recordType else {
            throw StoreError.missingPayload
        }
        if indexRecord[CloudKitKey.scope] != nil {
            guard Self.storedString(
                in: indexRecord,
                key: CloudKitKey.scope
            ).map({
                Self.isScopeIdentifier($0, compatibleWith: scope)
            }) == true else {
                throw StoreError.missingPayload
            }
        } else if hasProjectRecordNames {
            throw StoreError.missingPayload
        }
        guard let projectIDs = Self.projectIDs(from: indexRecord),
              Self.isValidManifestValues(projectIDs),
              let projectRecordIDs = try Self.validatedIndexedProjectRecordIDs(
                from: indexRecord,
                scope: scope
              ) else {
            throw StoreError.missingPayload
        }

        guard let updatedAt = indexRecord[CloudKitKey.updatedAt] as? NSDate else {
            throw StoreError.missingPayload
        }

        let activeProjectID: String?
        if indexRecord[CloudKitKey.activeProjectID] != nil {
            guard let storedActiveProjectID = Self.storedString(
                in: indexRecord,
                key: CloudKitKey.activeProjectID
            ),
            !storedActiveProjectID.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            projectIDs.contains(storedActiveProjectID) else {
                throw StoreError.missingPayload
            }
            activeProjectID = storedActiveProjectID
        } else {
            activeProjectID = nil
        }
        let deletedProjects = try Self.deletionTombstones(from: indexRecord)
        let revision = try Self.validatedPayloadRevision(from: indexRecord)
        let usesExplicitProjectManifest =
            indexRecord[CloudKitKey.projectRecordNames] != nil
        try Task.checkCancellation()
        let fetchedRecords = try await existingRecords(for: projectRecordIDs, in: database)
        try Task.checkCancellation()
        var projectRecordIDByProjectID: [String: CKRecord.ID] = [:]
        for (projectID, recordID) in zip(projectIDs, projectRecordIDs) {
            guard projectRecordIDByProjectID.updateValue(
                recordID,
                forKey: projectID
            ) == nil else {
                throw StoreError.missingPayload
            }
        }
        var projectDataByID: [String: Data] = [:]
        var chapterIDsByProjectID: [String: [String]] = [:]
        var chapterRecordIDsByProjectID: [String: [CKRecord.ID]] = [:]
        var usesExplicitChapterManifestByProjectID: [String: Bool] = [:]

        for projectID in projectIDs {
            guard let recordID = projectRecordIDByProjectID[projectID] else {
                throw StoreError.missingPayload
            }
            guard let record = fetchedRecords[recordID] else {
                throw StoreError.missingPayload
            }

            do {
                let projectData: Data
                do {
                    projectData = try Self.preservedProjectPayloadData(
                        from: record,
                        expectedProjectID: projectID,
                        scope: scope,
                        requiresCompleteMetadata: usesExplicitProjectManifest
                    ).data
                } catch {
                    throw StoreError.missingPayload
                }
                let manifest = try Self.validatedChapterManifest(
                    from: record,
                    projectID: projectID,
                    scope: scope,
                    revision: revision,
                    requiresExplicitManifest: usesExplicitProjectManifest
                )
                chapterIDsByProjectID[projectID] = manifest.chapterIDs
                chapterRecordIDsByProjectID[projectID] = manifest.recordIDs
                usesExplicitChapterManifestByProjectID[projectID] =
                    manifest.usesExplicitRecordNames
                projectDataByID[projectID] = projectData
            } catch {
                if error is StoreError { throw error }
                throw StoreError.decodeFailed(error.localizedDescription)
            }
        }

        let chapterRecordIDs = try Self.indexedChapterRecordIDs(
            from: fetchedRecords,
            indexRecord: indexRecord,
            scope: scope
        )
        try Task.checkCancellation()
        let fetchedChapterRecords = try await existingRecords(for: chapterRecordIDs, in: database)
        try Task.checkCancellation()
        var chapterDataByProjectID: [String: [Data]] = [:]

        for projectID in projectIDs {
            let chapterIDs = chapterIDsByProjectID[projectID] ?? []
            let recordIDs = chapterRecordIDsByProjectID[projectID] ?? []
            for (chapterID, recordID) in zip(chapterIDs, recordIDs) {
                guard let record = fetchedChapterRecords[recordID] else {
                    throw StoreError.missingPayload
                }

                do {
                    let chapterData: Data
                    do {
                        chapterData = try Self.preservedChapterPayloadData(
                            from: record,
                            expectedProjectID: projectID,
                            expectedChapterID: chapterID,
                            scope: scope,
                            requiresCompleteMetadata:
                                usesExplicitChapterManifestByProjectID[projectID]
                                    == true
                        )
                    } catch {
                        throw StoreError.missingPayload
                    }
                    chapterDataByProjectID[projectID, default: []].append(chapterData)
                } catch {
                    if error is StoreError { throw error }
                    throw StoreError.decodeFailed(error.localizedDescription)
                }
            }
        }

        let decoder = self.decoder
        let resolvedProjectDataByID = projectDataByID
        let resolvedChapterDataByProjectID = chapterDataByProjectID
        let resolvedChapterIDsByProjectID = chapterIDsByProjectID
        try Task.checkCancellation()
        var recentProjects: [NovelProject] = []
        for projectID in projectIDs {
            try Task.checkCancellation()
            guard let data = resolvedProjectDataByID[projectID] else {
                throw StoreError.missingPayload
            }

            var project = try CloudProjectPayloadCodec.decodeMacProject(from: data)
            guard project.id == projectID else {
                throw StoreError.missingPayload
            }
            if let chapterIDs = resolvedChapterIDsByProjectID[projectID],
               !chapterIDs.isEmpty {
                var chapters: [ChapterDraft] = []
                for chapterData in resolvedChapterDataByProjectID[
                    projectID,
                    default: []
                ] {
                    try Task.checkCancellation()
                    chapters.append(
                        try decoder.decode(ChapterDraft.self, from: chapterData)
                    )
                }
                guard chapters.map(\.id) == chapterIDs else {
                    throw StoreError.missingPayload
                }
                project.chapterDrafts = chapters.sorted(by: ChapterDraft.sortDescending)
            }
            recentProjects.append(project)
        }
        try Task.checkCancellation()

        return AccountProjectSnapshot(
            activeProjectID: activeProjectID,
            recentProjects: recentProjects,
            deletedProjects: deletedProjects,
            updatedAt: updatedAt as Date
        )
    }

    private func existingProjectIDs(from indexRecord: CKRecord?) -> [String] {
        guard let indexRecord else { return [] }
        return Self.projectIDs(from: indexRecord) ?? []
    }

    nonisolated static func projectIDs(from indexRecord: CKRecord) -> [String]? {
        if let direct = indexRecord[CloudKitKey.projectIDs] as? [String] {
            return direct
        }

        if let array = indexRecord[CloudKitKey.projectIDs] as? [NSString] {
            return array.map(String.init)
        }

        if let array = indexRecord[CloudKitKey.projectIDs] as? NSArray {
            let values = array.compactMap { $0 as? String }
            return values.count == array.count ? values : nil
        }

        return nil
    }

    nonisolated static func chapterIDs(from record: CKRecord) -> [String]? {
        stringArray(from: record, key: CloudKitKey.chapterIDs)
    }

    private nonisolated static func stringArray(from record: CKRecord, key: String) -> [String]? {
        if let direct = record[key] as? [String] {
            return direct
        }

        if let array = record[key] as? [NSString] {
            return array.map(String.init)
        }

        if let array = record[key] as? NSArray {
            let values = array.compactMap { $0 as? String }
            return values.count == array.count ? values : nil
        }

        return nil
    }

    private nonisolated static func dateArray(from record: CKRecord, key: String) -> [Date]? {
        if let direct = record[key] as? [Date] {
            return direct
        }
        if let array = record[key] as? [NSDate] {
            return array.map { $0 as Date }
        }
        if let array = record[key] as? NSArray {
            let dates = array.compactMap { value -> Date? in
                if let value = value as? Date { return value }
                return (value as? NSDate).map { $0 as Date }
            }
            return dates.count == array.count ? dates : nil
        }
        return nil
    }

    nonisolated static func storedPayloadHash(in record: CKRecord) -> String? {
        storedString(in: record, key: CloudKitKey.payloadHash)
    }

    private nonisolated static func storedString(
        in record: CKRecord,
        key: String
    ) -> String? {
        if let value = record[key] as? String { return value }
        return (record[key] as? NSString).map(String.init)
    }

    private nonisolated static func storedData(
        in record: CKRecord,
        key: String
    ) -> Data? {
        if let value = record[key] as? Data { return value }
        return (record[key] as? NSData).map { $0 as Data }
    }

    private func writeTemporaryPayload(_ data: Data, identifier: String) throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory
            .appendingPathComponent(Self.sanitized(identifier), isDirectory: false)
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("OpenWritingCloudKitPayloads", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    private nonisolated static func sanitized(_ value: String) -> String {
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

    nonisolated static func scopeIdentifier(for scope: String) -> String {
        recordNameComponent(scope)
    }

    private nonisolated static func isScopeIdentifier(
        _ storedValue: String,
        compatibleWith scope: String
    ) -> Bool {
        storedValue == scopeIdentifier(for: scope)
            || storedValue == sanitized(scope)
    }

    private nonisolated static func recordNameComponent(
        _ value: String
    ) -> String {
        let maximumLength = 64
        let isSafeASCII = !value.isEmpty
            && value.utf8.count <= maximumLength
            && value.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 48...57, 65...90, 97...122:
                    return true
                case 45, 46, 95:
                    return true
                default:
                    return false
                }
            }
        if isSafeASCII {
            return value
        }

        let hash = CloudProjectPayloadCodec.payloadHash(
            for: Data(value.utf8)
        )
        let hashSuffix = String(hash.prefix(24))
        let prefixLimit = maximumLength - hashSuffix.count - 1
        let readablePrefix = value.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 46, 95:
                return Character(String(scalar))
            default:
                return "_"
            }
        }
        let boundedPrefix = String(readablePrefix.prefix(prefixLimit))
        let prefix = boundedPrefix.isEmpty ? "_" : boundedPrefix
        return "\(prefix)-\(hashSuffix)"
    }
}
