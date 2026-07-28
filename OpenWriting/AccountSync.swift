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
        if let value = value as? NSArray { return value.compactMap { $0 as? String } }
        return nil
    }

    private func dateValue(_ value: CKRecordValue?) -> Date? {
        if let value = value as? Date { return value }
        return (value as? NSDate).map { $0 as Date }
    }
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

nonisolated enum ICloudRecordBatching {
    static let maximumRecordsPerOperation = 200

    static func batches<Element>(_ elements: [Element]) -> [[Element]] {
        stride(from: 0, to: elements.count, by: maximumRecordsPerOperation).map { start in
            Array(elements[start..<min(start + maximumRecordsPerOperation, elements.count)])
        }
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
        let (container, database) = try configuredContainerAndDatabase()
        guard try await accountStatus(using: container) == .available else {
            throw StoreError.notSignedIntoICloud
        }

        let recordID = Self.snapshotRecordID(for: scope)
        let fetchedRecords = try await database.records(for: [recordID])
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

        if let indexSnapshot = try await loadIndexedSnapshot(
            from: record,
            scope: scope,
            database: database
        ) {
            return indexSnapshot
        }

        guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL
        else {
            throw StoreError.missingPayload
        }

        do {
            let data = try Data(contentsOf: assetURL)
            let decoder = self.decoder
            return try await MainActor.run {
                try decoder.decode(AccountProjectSnapshot.self, from: data)
            }
        } catch {
            throw StoreError.decodeFailed(error.localizedDescription)
        }
    }

    func saveSnapshot(_ snapshot: AccountProjectSnapshot, for scope: String) async throws {
        let (container, database) = try configuredContainerAndDatabase()
        guard try await accountStatus(using: container) == .available else {
            throw StoreError.notSignedIntoICloud
        }

        do {
            let snapshotRecordID = Self.snapshotRecordID(for: scope)
            var existingRecordsByID = try await existingRecords(for: [snapshotRecordID], in: database)
            let previousIndexRecord = existingRecordsByID[snapshotRecordID]
            let previousRevision = previousIndexRecord.flatMap(Self.payloadRevision(from:))
            let previousProjectRecordIDs: [CKRecord.ID]
            if let previousIndexRecord,
               Self.projectIDs(from: previousIndexRecord) != nil {
                guard let resolvedRecordIDs = Self.indexedProjectRecordIDs(
                    from: previousIndexRecord,
                    scope: scope
                ) else {
                    throw StoreError.writeFailed("CloudKit 项目索引中的 record names 数量不匹配。")
                }
                previousProjectRecordIDs = resolvedRecordIDs
            } else {
                previousProjectRecordIDs = []
            }
            let missingPreviousProjectRecordIDs = previousProjectRecordIDs.filter { existingRecordsByID[$0] == nil }
            if !missingPreviousProjectRecordIDs.isEmpty {
                let previousProjectRecords = try await existingRecords(for: missingPreviousProjectRecordIDs, in: database)
                existingRecordsByID.merge(previousProjectRecords) { current, _ in current }
            }

            var previousChapterRecordIDs: [CKRecord.ID] = []
            var previousProjectDataByID: [String: Data] = [:]
            for projectRecordID in previousProjectRecordIDs {
                guard let record = existingRecordsByID[projectRecordID] else { continue }
                let projectID = ((record[CloudKitKey.projectID] as? NSString) as String?) ?? ""
                if let data = try? payloadData(from: record) {
                    previousProjectDataByID[projectID] = data
                }
                let chapterIDs = Self.chapterIDs(from: record) ?? []
                guard Self.isValidManifestValues(chapterIDs) else {
                    throw StoreError.writeFailed("CloudKit 章节索引包含空白或重复 chapter ID。")
                }
                if let explicitNames = Self.stringArray(from: record, key: CloudKitKey.chapterRecordNames) {
                    guard explicitNames.count == chapterIDs.count,
                          Self.isValidManifestValues(explicitNames) else {
                        throw StoreError.writeFailed("CloudKit 章节索引中的 record names 数量不匹配。")
                    }
                    previousChapterRecordIDs.append(contentsOf: explicitNames.map { CKRecord.ID(recordName: $0) })
                } else {
                    previousChapterRecordIDs.append(contentsOf: chapterIDs.map {
                        Self.chapterRecordID(
                            for: $0,
                            projectID: projectID,
                            scope: scope,
                            revision: previousRevision
                        )
                    })
                }
            }

            let encoder = self.encoder
            let sanitizedScope = Self.sanitized(scope)
            let chapterPayloads = try await MainActor.run {
                try snapshot.recentProjects.flatMap { project in
                    try project.chapterDrafts.map { chapterDraft in
                        let data = try encoder.encode(chapterDraft)
                        let revision = CloudProjectPayloadCodec.chapterRevision(
                            payloadHash: CloudProjectPayloadCodec.payloadHash(for: data)
                        )
                        return (
                            projectID: project.id,
                            chapterID: chapterDraft.id,
                            updatedAt: chapterDraft.savedAtDate,
                            data: data,
                            recordName: Self.chapterRecordName(
                                for: chapterDraft.id,
                                projectID: project.id,
                                scope: scope,
                                revision: revision
                            )
                        )
                    }
                }
            }
            var chapterRecordNamesByProjectID: [String: [String]] = [:]
            for payload in chapterPayloads {
                chapterRecordNamesByProjectID[payload.projectID, default: []].append(payload.recordName)
            }
            let resolvedChapterRecordNamesByProjectID = chapterRecordNamesByProjectID
            let resolvedPreviousProjectDataByID = previousProjectDataByID
            let projectPayloads = try await MainActor.run {
                try snapshot.recentProjects.map { project -> (
                    projectID: String,
                    updatedAt: Date,
                    chapterIDs: [String],
                    chapterRecordNames: [String],
                    data: Data,
                    recordName: String
                ) in
                    var metadata = project
                    let chapterIDs = project.chapterDrafts.map(\.id)
                    let chapterRecordNames = resolvedChapterRecordNamesByProjectID[project.id] ?? []
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
                    let revision = CloudProjectPayloadCodec.projectRevision(
                        payloadHash: CloudProjectPayloadCodec.payloadHash(for: data),
                        chapterReferences: chapterReferences
                    )
                    return (
                        projectID: project.id,
                        updatedAt: project.updatedAtDate,
                        chapterIDs: chapterReferences.map(\.chapterID),
                        chapterRecordNames: chapterReferences.map(\.recordName),
                        data: data,
                        recordName: Self.projectRecordName(
                            for: project.id,
                            scope: scope,
                            revision: revision
                        )
                    )
                }
            }
            let targetProjectRecordIDs = projectPayloads.map { CKRecord.ID(recordName: $0.recordName) }
            let targetChapterRecordIDs = chapterPayloads.map { CKRecord.ID(recordName: $0.recordName) }
            let targetRecordIDs = targetProjectRecordIDs + targetChapterRecordIDs
            let missingTargetRecordIDs = targetRecordIDs.filter { existingRecordsByID[$0] == nil }
            if !missingTargetRecordIDs.isEmpty {
                let targetRecords = try await existingRecords(for: missingTargetRecordIDs, in: database)
                existingRecordsByID.merge(targetRecords) { current, _ in current }
            }
            let desiredPayloadTargets =
                projectPayloads.map {
                    ContentAddressedPayloadTarget(
                        recordID: CKRecord.ID(recordName: $0.recordName),
                        payloadHash: CloudProjectPayloadCodec.payloadHash(for: $0.data),
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
                        payloadHash: CloudProjectPayloadCodec.payloadHash(for: $0.data),
                        recordType: CloudKitKey.chapterRecordType,
                        scope: sanitizedScope,
                        projectID: $0.projectID,
                        chapterID: $0.chapterID,
                        updatedAt: $0.updatedAt
                    )
                }
            let targetRecordIDSet = Set(targetRecordIDs)
            let existingTargetRecordIDs = Set(existingRecordsByID.keys).intersection(targetRecordIDSet)
            let desiredTargetByRecordID = Dictionary(
                uniqueKeysWithValues: desiredPayloadTargets.map { ($0.recordID, $0) }
            )
            let existingTargetPayloadHashes: [CKRecord.ID: String] = Dictionary(
                uniqueKeysWithValues: existingTargetRecordIDs.compactMap { recordID -> (CKRecord.ID, String)? in
                    guard let record = existingRecordsByID[recordID],
                          let target = desiredTargetByRecordID[recordID],
                          let hash = Self.verifiedExistingPayloadHash(
                            for: record,
                            matching: target
                          ) else {
                        return nil
                    }
                    return (recordID, hash)
                }
            )
            let uploadPlan = try ContentAddressedUploadPlan.build(
                desired: desiredPayloadTargets,
                existingRecordIDs: existingTargetRecordIDs,
                existingPayloadHashes: existingTargetPayloadHashes
            )
            let recordIDsToCreate = Set(uploadPlan.recordIDsToCreate)

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
                record[CloudKitKey.payloadHash] = CloudProjectPayloadCodec.payloadHash(for: payload.data) as NSString
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
                record[CloudKitKey.payloadHash] = CloudProjectPayloadCodec.payloadHash(for: payload.data) as NSString
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

            let indexRecord = existingRecordsByID[snapshotRecordID]
                ?? CKRecord(recordType: CloudKitKey.recordType, recordID: snapshotRecordID)
            let targetRecordNames = Set(targetRecordIDs.map(\.recordName))
            let previousPendingCleanupNames = previousIndexRecord.flatMap {
                Self.stringArray(from: $0, key: CloudKitKey.pendingCleanupRecordNames)
            } ?? []
            let staleRecordNames = Set(
                previousProjectRecordIDs.map(\.recordName)
                    + previousChapterRecordIDs.map(\.recordName)
                    + previousPendingCleanupNames
            )
            .subtracting(targetRecordNames)
            .sorted()
            let newPayloadRevision = CloudProjectPayloadCodec.manifestRevision(
                projectReferences: projectPayloads.map {
                    (projectID: $0.projectID, recordName: $0.recordName)
                },
                deletedProjects: snapshot.deletedProjects
            )
            let normalizedDeletedProjects = ProjectDeletionTombstone.normalized(
                snapshot.deletedProjects
            )
            indexRecord[CloudKitKey.scope] = sanitizedScope as NSString
            indexRecord[CloudKitKey.updatedAt] = snapshot.updatedAt as NSDate
            indexRecord[CloudKitKey.activeProjectID] = snapshot.activeProjectID.map { $0 as NSString }
            indexRecord[CloudKitKey.projectIDs] = snapshot.recentProjects.map(\.id) as NSArray
            indexRecord[CloudKitKey.projectRecordNames] = projectPayloads.map(\.recordName) as NSArray
            indexRecord[CloudKitKey.payloadRevision] = newPayloadRevision as NSString
            indexRecord[CloudKitKey.pendingCleanupRecordNames] = staleRecordNames as NSArray
            indexRecord[CloudKitKey.deletedProjectIDs] =
                normalizedDeletedProjects.map(\.projectID) as NSArray
            indexRecord[CloudKitKey.deletedProjectDates] =
                normalizedDeletedProjects.map { $0.deletedAt as NSDate } as NSArray
            indexRecord[CloudKitKey.payloadAsset] = nil

            for batch in ICloudRecordBatching.batches(chapterRecords.map { $0.0 }) {
                let results = try await database.modifyRecords(
                    saving: batch,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
                try verifyCompleteWrite(results, saving: batch.map(\.recordID), deleting: [])
            }

            for batch in ICloudRecordBatching.batches(projectRecords.map { $0.0 }) {
                let results = try await database.modifyRecords(
                    saving: batch,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
                try verifyCompleteWrite(results, saving: batch.map(\.recordID), deleting: [])
            }

            let indexResults = try await database.modifyRecords(
                saving: [indexRecord],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )
            try verifyCompleteWrite(indexResults, saving: [indexRecord.recordID], deleting: [])

            var failedCleanupNames: [String] = []
            let staleRecordIDs = staleRecordNames.map { CKRecord.ID(recordName: $0) }
            for batch in ICloudRecordBatching.batches(staleRecordIDs) {
                do {
                    let deleteResults = try await database.modifyRecords(
                        saving: [],
                        deleting: batch,
                        savePolicy: .changedKeys,
                        atomically: false
                    )
                    let failedRecordIDs = Self.failedDeletionRecordIDs(
                        deleteResults.deleteResults,
                        expected: batch
                    )
                    failedCleanupNames.append(contentsOf: failedRecordIDs.map(\.recordName))
                    if !failedRecordIDs.isEmpty {
                        AppLogger.sync.error(
                            "CloudKit published revision \(newPayloadRevision, privacy: .public), but \(failedRecordIDs.count, privacy: .public) stale payload deletions failed."
                        )
                    }
                } catch {
                    failedCleanupNames.append(contentsOf: batch.map(\.recordName))
                    AppLogger.sync.error(
                        "CloudKit published revision \(newPayloadRevision, privacy: .public), but stale payload cleanup failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            let sortedFailedCleanupNames = failedCleanupNames.sorted()
            if sortedFailedCleanupNames != staleRecordNames,
               case let .success(publishedIndexRecord)? = indexResults.saveResults[snapshotRecordID] {
                publishedIndexRecord[CloudKitKey.pendingCleanupRecordNames] = sortedFailedCleanupNames as NSArray
                do {
                    let cleanupIndexResults = try await database.modifyRecords(
                        saving: [publishedIndexRecord],
                        deleting: [],
                        savePolicy: .changedKeys,
                        atomically: true
                    )
                    try verifyCompleteWrite(
                        cleanupIndexResults,
                        saving: [publishedIndexRecord.recordID],
                        deleting: []
                    )
                } catch {
                    AppLogger.sync.error(
                        "CloudKit cleanup manifest update failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
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

        var recordsByID: [CKRecord.ID: CKRecord] = [:]
        for batch in ICloudRecordBatching.batches(recordIDs) {
            let fetchedRecords = try await database.records(for: batch)
            for recordID in batch {
                guard let result = fetchedRecords[recordID] else { continue }

                switch result {
                case let .success(record):
                    recordsByID[recordID] = record
                case let .failure(error as CKError) where error.code == CKError.Code.unknownItem:
                    continue
                case let .failure(error):
                    throw StoreError.readFailed(error.localizedDescription)
                }
            }
        }

        return recordsByID
    }

    private func payloadData(from record: CKRecord) throws -> Data {
        guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL
        else {
            throw StoreError.missingPayload
        }
        return try Data(contentsOf: assetURL)
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
                throw StoreError.writeFailed("CloudKit 未能写入 \(recordID.recordName)：\(error.localizedDescription)")
            }
        }

        for recordID in deletedRecordIDs {
            guard let result = results.deleteResults[recordID] else {
                throw StoreError.writeFailed("CloudKit 未返回 \(recordID.recordName) 的删除结果。")
            }
            if case let .failure(error) = result,
               !Self.isUnknownItem(error) {
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
        "snapshot_\(sanitized(scope))"
    }

    nonisolated static func payloadRevision(from indexRecord: CKRecord) -> String? {
        (indexRecord[CloudKitKey.payloadRevision] as? NSString).map(String.init)
    }

    nonisolated static func indexedProjectRecordIDs(
        from indexRecord: CKRecord,
        scope: String
    ) -> [CKRecord.ID]? {
        guard let projectIDs = projectIDs(from: indexRecord) else { return nil }
        guard isValidManifestValues(projectIDs) else { return nil }
        if let explicitNames = stringArray(from: indexRecord, key: CloudKitKey.projectRecordNames) {
            guard explicitNames.count == projectIDs.count,
                  isValidManifestValues(explicitNames) else {
                return nil
            }
            return explicitNames.map { CKRecord.ID(recordName: $0) }
        }
        let revision = payloadRevision(from: indexRecord)
        return projectIDs.map { projectRecordID(for: $0, scope: scope, revision: revision) }
    }

    nonisolated static func indexedChapterRecordIDs(
        from projectRecordsByID: [CKRecord.ID: CKRecord],
        indexRecord: CKRecord,
        scope: String
    ) throws -> [CKRecord.ID] {
        guard let projectIDs = projectIDs(from: indexRecord) else { return [] }
        guard let projectRecordIDs = indexedProjectRecordIDs(from: indexRecord, scope: scope),
              projectRecordIDs.count == projectIDs.count else {
            throw StoreError.missingPayload
        }
        let revision = payloadRevision(from: indexRecord)

        let recordIDs = try zip(projectIDs, projectRecordIDs).flatMap { projectID, projectRecordID in
            guard let projectRecord = projectRecordsByID[projectRecordID] else {
                throw StoreError.missingPayload
            }
            let chapterIDs = chapterIDs(from: projectRecord) ?? []
            guard isValidManifestValues(chapterIDs) else {
                throw StoreError.missingPayload
            }
            if let explicitNames = stringArray(from: projectRecord, key: CloudKitKey.chapterRecordNames) {
                guard explicitNames.count == chapterIDs.count,
                      isValidManifestValues(explicitNames) else {
                    throw StoreError.missingPayload
                }
                return explicitNames.map { CKRecord.ID(recordName: $0) }
            }
            return chapterIDs.map {
                chapterRecordID(for: $0, projectID: projectID, scope: scope, revision: revision)
            }
        }
        guard Set(recordIDs).count == recordIDs.count else {
            throw StoreError.missingPayload
        }
        return recordIDs
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
        let projectIDs = stringArray(
            from: indexRecord,
            key: CloudKitKey.deletedProjectIDs
        )
        let deletedDates = dateArray(
            from: indexRecord,
            key: CloudKitKey.deletedProjectDates
        )
        guard projectIDs != nil || deletedDates != nil else { return [] }
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

    nonisolated static func projectRecordName(
        for projectID: String,
        scope: String,
        revision: String? = nil
    ) -> String {
        let revisionPart = revision.map { "_\(sanitized($0))" } ?? ""
        return "project_\(sanitized(scope))\(revisionPart)_\(sanitized(projectID))"
    }

    nonisolated static func chapterRecordName(
        for chapterID: String,
        projectID: String,
        scope: String,
        revision: String? = nil
    ) -> String {
        let revisionPart = revision.map { "_\(sanitized($0))" } ?? ""
        return "chapter_\(sanitized(scope))\(revisionPart)_\(sanitized(projectID))_\(sanitized(chapterID))"
    }

    private nonisolated static func snapshotRecordID(for scope: String) -> CKRecord.ID {
        CKRecord.ID(recordName: snapshotRecordName(for: scope))
    }

    private nonisolated static func projectRecordID(
        for projectID: String,
        scope: String,
        revision: String? = nil
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: projectRecordName(for: projectID, scope: scope, revision: revision))
    }

    private nonisolated static func chapterRecordID(
        for chapterID: String,
        projectID: String,
        scope: String,
        revision: String? = nil
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: chapterRecordName(
                for: chapterID,
                projectID: projectID,
                scope: scope,
                revision: revision
            )
        )
    }

    private func loadIndexedSnapshot(
        from indexRecord: CKRecord,
        scope: String,
        database: CKDatabase
    ) async throws -> AccountProjectSnapshot? {
        guard let projectIDs = Self.projectIDs(from: indexRecord) else {
            return nil
        }
        guard let projectRecordIDs = Self.indexedProjectRecordIDs(from: indexRecord, scope: scope) else {
            throw StoreError.missingPayload
        }

        guard let updatedAt = indexRecord[CloudKitKey.updatedAt] as? NSDate else {
            throw StoreError.missingPayload
        }

        let activeProjectID = (indexRecord[CloudKitKey.activeProjectID] as? NSString) as String?
        let deletedProjects = try Self.deletionTombstones(from: indexRecord)
        let revision = Self.payloadRevision(from: indexRecord)
        let usesExplicitProjectManifest =
            Self.stringArray(from: indexRecord, key: CloudKitKey.projectRecordNames) != nil
        let fetchedRecords = try await existingRecords(for: projectRecordIDs, in: database)
        let projectRecordIDByProjectID = Dictionary(
            uniqueKeysWithValues: zip(projectIDs, projectRecordIDs)
        )
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

            guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
                  let assetURL = asset.fileURL
            else {
                throw StoreError.missingPayload
            }

            do {
                let projectData = try Data(contentsOf: assetURL)
                let chapterIDs = Self.chapterIDs(from: record) ?? []
                guard Self.isValidManifestValues(chapterIDs) else {
                    throw StoreError.missingPayload
                }
                chapterIDsByProjectID[projectID] = chapterIDs
                if let explicitNames = Self.stringArray(from: record, key: CloudKitKey.chapterRecordNames) {
                    guard explicitNames.count == chapterIDs.count,
                          Self.isValidManifestValues(explicitNames) else {
                        throw StoreError.missingPayload
                    }
                    chapterRecordIDsByProjectID[projectID] = explicitNames.map { CKRecord.ID(recordName: $0) }
                    usesExplicitChapterManifestByProjectID[projectID] = true
                } else {
                    chapterRecordIDsByProjectID[projectID] = chapterIDs.map {
                        Self.chapterRecordID(
                            for: $0,
                            projectID: projectID,
                            scope: scope,
                            revision: revision
                        )
                    }
                    usesExplicitChapterManifestByProjectID[projectID] = false
                }
                if usesExplicitProjectManifest {
                    let target = ContentAddressedPayloadTarget(
                        recordID: recordID,
                        payloadHash: CloudProjectPayloadCodec.payloadHash(for: projectData),
                        recordType: CloudKitKey.projectRecordType,
                        scope: Self.sanitized(scope),
                        projectID: projectID,
                        updatedAt: (record[CloudKitKey.updatedAt] as? NSDate).map { $0 as Date },
                        chapterIDs: chapterIDs,
                        chapterRecordNames: chapterRecordIDsByProjectID[projectID]?.map(\.recordName)
                    )
                    guard target.matchesMetadata(in: record),
                          Self.storedPayloadHash(in: record)
                            == CloudProjectPayloadCodec.payloadHash(for: projectData) else {
                        throw StoreError.missingPayload
                    }
                }
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
        let fetchedChapterRecords = try await existingRecords(for: chapterRecordIDs, in: database)
        var chapterDataByProjectID: [String: [Data]] = [:]

        for projectID in projectIDs {
            let chapterIDs = chapterIDsByProjectID[projectID] ?? []
            let recordIDs = chapterRecordIDsByProjectID[projectID] ?? []
            for (chapterID, recordID) in zip(chapterIDs, recordIDs) {
                guard let record = fetchedChapterRecords[recordID] else {
                    throw StoreError.missingPayload
                }

                guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
                      let assetURL = asset.fileURL
                else {
                    throw StoreError.missingPayload
                }

                do {
                    let chapterData = try Data(contentsOf: assetURL)
                    if usesExplicitChapterManifestByProjectID[projectID] == true {
                        let target = ContentAddressedPayloadTarget(
                            recordID: recordID,
                            payloadHash: CloudProjectPayloadCodec.payloadHash(for: chapterData),
                            recordType: CloudKitKey.chapterRecordType,
                            scope: Self.sanitized(scope),
                            projectID: projectID,
                            chapterID: chapterID,
                            updatedAt: (record[CloudKitKey.updatedAt] as? NSDate).map { $0 as Date }
                        )
                        guard target.matchesMetadata(in: record),
                              Self.storedPayloadHash(in: record)
                                == CloudProjectPayloadCodec.payloadHash(for: chapterData) else {
                            throw StoreError.missingPayload
                        }
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
        let recentProjects: [NovelProject] = try await MainActor.run {
            try projectIDs.map { projectID in
                guard let data = resolvedProjectDataByID[projectID] else {
                    throw StoreError.missingPayload
                }

                var project = try CloudProjectPayloadCodec.decodeMacProject(from: data)
                guard project.id == projectID else {
                    throw StoreError.missingPayload
                }
                if let chapterIDs = resolvedChapterIDsByProjectID[projectID], !chapterIDs.isEmpty {
                    let chapters = try resolvedChapterDataByProjectID[projectID, default: []].map {
                        try decoder.decode(ChapterDraft.self, from: $0)
                    }
                    guard chapters.map(\.id) == chapterIDs else {
                        throw StoreError.missingPayload
                    }
                    project.chapterDrafts = chapters.sorted(by: ChapterDraft.sortDescending)
                }
                return project
            }
        }

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
        if let value = record[CloudKitKey.payloadHash] as? String { return value }
        return (record[CloudKitKey.payloadHash] as? NSString).map(String.init)
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
}
