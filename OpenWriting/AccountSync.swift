import AuthenticationServices
import CloudKit
import Foundation
import OSLog
import Security

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

struct AccountProjectSnapshot: Codable {
    var activeProjectID: NovelProject.ID?
    var recentProjects: [NovelProject]
    var updatedAt: Date
}

struct ICloudSnapshotRecordPlan: Equatable {
    var snapshotRecordName: String
    var projectRecordNames: [String]
    var chapterRecordNames: [String]
    var deletedRecordNames: [String]
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
        static let projectID = "projectID"
        static let chapterIDs = "chapterIDs"
        static let chapterID = "chapterID"
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
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

        do {
            if let indexSnapshot = try await loadIndexedSnapshot(from: record, scope: scope, database: database) {
                return indexSnapshot
            }
        } catch {
            AppLogger.sync.error("CloudKit indexed snapshot failed, falling back to asset: \(error.localizedDescription, privacy: .private(mask: .hash))")
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
            let projectRecordIDs = snapshot.recentProjects.map { Self.projectRecordID(for: $0.id, scope: scope) }
            let chapterRecordIDs = snapshot.recentProjects.flatMap { project in
                project.chapterDrafts.map { Self.chapterRecordID(for: $0.id, projectID: project.id, scope: scope) }
            }
            var recordIDsToFetch = projectRecordIDs
            recordIDsToFetch.append(contentsOf: chapterRecordIDs)
            recordIDsToFetch.append(snapshotRecordID)
            var existingRecordsByID = try await existingRecords(for: recordIDsToFetch, in: database)

            let previousProjectIDs = existingProjectIDs(from: existingRecordsByID[snapshotRecordID])
            let previousProjectRecordIDs = previousProjectIDs.map { Self.projectRecordID(for: $0, scope: scope) }
            let missingPreviousProjectRecordIDs = previousProjectRecordIDs.filter { existingRecordsByID[$0] == nil }
            if !missingPreviousProjectRecordIDs.isEmpty {
                let previousProjectRecords = try await existingRecords(for: missingPreviousProjectRecordIDs, in: database)
                existingRecordsByID.merge(previousProjectRecords) { current, _ in current }
            }

            let previousChapterIDsByProjectID: [String: [String]] = Dictionary(uniqueKeysWithValues: previousProjectIDs.map { projectID in
                let recordID = Self.projectRecordID(for: projectID, scope: scope)
                let previousChapterIDs: [String] = existingRecordsByID[recordID].flatMap { self.chapterIDs(from: $0) } ?? []
                return (projectID, previousChapterIDs)
            })
            let recordPlan = Self.cloudKitRecordPlan(
                for: snapshot,
                scope: scope,
                previousProjectIDs: previousProjectIDs,
                previousChapterIDsByProjectID: previousChapterIDsByProjectID
            )
            let deletedRecordIDs = recordPlan.deletedRecordNames.map {
                CKRecord.ID(recordName: $0)
            }

            let encoder = self.encoder
            let sanitizedScope = Self.sanitized(scope)
            let projectPayloads = try await MainActor.run {
                try snapshot.recentProjects.map { project -> (projectID: String, updatedAt: Date, chapterIDs: [String], data: Data) in
                    var metadata = project
                    let chapterIDs = project.chapterDrafts.map(\.id)
                    metadata.chapterDrafts = []
                    return (
                        projectID: project.id,
                        updatedAt: project.updatedAtDate,
                        chapterIDs: chapterIDs,
                        data: try encoder.encode(metadata)
                    )
                }
            }
            let chapterPayloads = try await MainActor.run {
                try snapshot.recentProjects.flatMap { project in
                    try project.chapterDrafts.map { chapterDraft in
                        (
                            projectID: project.id,
                            chapterID: chapterDraft.id,
                            updatedAt: chapterDraft.savedAtDate,
                            data: try encoder.encode(chapterDraft)
                        )
                    }
                }
            }

            let snapshotPayloadData = try await MainActor.run {
                try encoder.encode(snapshot)
            }
            let snapshotPayloadURL = try writeTemporaryPayload(
                snapshotPayloadData,
                identifier: "snapshot_\(sanitizedScope)"
            )
            let projectRecords = try projectPayloads.map { payload in
                let payloadURL = try writeTemporaryPayload(
                    payload.data,
                    identifier: "project_\(sanitizedScope)_\(Self.sanitized(payload.projectID))"
                )
                let recordID = Self.projectRecordID(for: payload.projectID, scope: scope)
                let record = existingRecordsByID[recordID]
                    ?? CKRecord(recordType: CloudKitKey.projectRecordType, recordID: recordID)
                record[CloudKitKey.scope] = sanitizedScope as NSString
                record[CloudKitKey.projectID] = payload.projectID as NSString
                record[CloudKitKey.updatedAt] = payload.updatedAt as NSDate
                record[CloudKitKey.chapterIDs] = payload.chapterIDs as NSArray
                record[CloudKitKey.payloadAsset] = CKAsset(fileURL: payloadURL)
                return (record, payloadURL)
            }
            let chapterRecords = try chapterPayloads.map { payload in
                let payloadURL = try writeTemporaryPayload(
                    payload.data,
                    identifier: "chapter_\(sanitizedScope)_\(Self.sanitized(payload.projectID))_\(Self.sanitized(payload.chapterID))"
                )
                let recordID = Self.chapterRecordID(for: payload.chapterID, projectID: payload.projectID, scope: scope)
                let record = existingRecordsByID[recordID]
                    ?? CKRecord(recordType: CloudKitKey.chapterRecordType, recordID: recordID)
                record[CloudKitKey.scope] = sanitizedScope as NSString
                record[CloudKitKey.projectID] = payload.projectID as NSString
                record[CloudKitKey.chapterID] = payload.chapterID as NSString
                record[CloudKitKey.updatedAt] = payload.updatedAt as NSDate
                record[CloudKitKey.payloadAsset] = CKAsset(fileURL: payloadURL)
                return (record, payloadURL)
            }

            defer {
                try? fileManager.removeItem(at: snapshotPayloadURL)
                for (_, payloadURL) in projectRecords {
                    try? fileManager.removeItem(at: payloadURL)
                }
                for (_, payloadURL) in chapterRecords {
                    try? fileManager.removeItem(at: payloadURL)
                }
            }

            let indexRecord = existingRecordsByID[snapshotRecordID]
                ?? CKRecord(recordType: CloudKitKey.recordType, recordID: snapshotRecordID)
            indexRecord[CloudKitKey.scope] = sanitizedScope as NSString
            indexRecord[CloudKitKey.updatedAt] = snapshot.updatedAt as NSDate
            indexRecord[CloudKitKey.activeProjectID] = snapshot.activeProjectID.map { $0 as NSString }
            indexRecord[CloudKitKey.projectIDs] = snapshot.recentProjects.map(\.id) as NSArray
            indexRecord[CloudKitKey.payloadAsset] = CKAsset(fileURL: snapshotPayloadURL)

            let payloadRecords = projectRecords.map { $0.0 } + chapterRecords.map { $0.0 }
            if !payloadRecords.isEmpty {
                _ = try await database.modifyRecords(
                    saving: payloadRecords,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
            }

            _ = try await database.modifyRecords(
                saving: [indexRecord],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )

            if !deletedRecordIDs.isEmpty {
                do {
                    _ = try await database.modifyRecords(
                        saving: [],
                        deleting: deletedRecordIDs,
                        savePolicy: .changedKeys,
                        atomically: false
                    )
                } catch {
                    AppLogger.sync.error("CloudKit stale payload cleanup failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
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

        let fetchedRecords = try await database.records(for: recordIDs)
        var recordsByID: [CKRecord.ID: CKRecord] = [:]

        for recordID in recordIDs {
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

        return recordsByID
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

    nonisolated static func projectRecordName(for projectID: String, scope: String) -> String {
        "project_\(sanitized(scope))_\(sanitized(projectID))"
    }

    nonisolated static func chapterRecordName(
        for chapterID: String,
        projectID: String,
        scope: String
    ) -> String {
        "chapter_\(sanitized(scope))_\(sanitized(projectID))_\(sanitized(chapterID))"
    }

    private nonisolated static func snapshotRecordID(for scope: String) -> CKRecord.ID {
        CKRecord.ID(recordName: snapshotRecordName(for: scope))
    }

    private nonisolated static func projectRecordID(for projectID: String, scope: String) -> CKRecord.ID {
        CKRecord.ID(recordName: projectRecordName(for: projectID, scope: scope))
    }

    private nonisolated static func chapterRecordID(
        for chapterID: String,
        projectID: String,
        scope: String
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: chapterRecordName(for: chapterID, projectID: projectID, scope: scope))
    }

    private func loadIndexedSnapshot(
        from indexRecord: CKRecord,
        scope: String,
        database: CKDatabase
    ) async throws -> AccountProjectSnapshot? {
        guard let projectIDs = projectIDs(from: indexRecord) else {
            return nil
        }

        guard let updatedAt = indexRecord[CloudKitKey.updatedAt] as? NSDate else {
            throw StoreError.missingPayload
        }

        let activeProjectID = (indexRecord[CloudKitKey.activeProjectID] as? NSString) as String?
        let projectRecordIDs = projectIDs.map { Self.projectRecordID(for: $0, scope: scope) }
        let fetchedRecords = try await existingRecords(for: projectRecordIDs, in: database)
        var projectDataByID: [String: Data] = [:]
        var chapterIDsByProjectID: [String: [String]] = [:]

        for projectID in projectIDs {
            let recordID = Self.projectRecordID(for: projectID, scope: scope)
            guard let record = fetchedRecords[recordID] else {
                throw StoreError.missingPayload
            }

            guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
                  let assetURL = asset.fileURL
            else {
                throw StoreError.missingPayload
            }

            do {
                projectDataByID[projectID] = try Data(contentsOf: assetURL)
                chapterIDsByProjectID[projectID] = chapterIDs(from: record) ?? []
            } catch {
                throw StoreError.decodeFailed(error.localizedDescription)
            }
        }

        let chapterRecordIDs = chapterIDsByProjectID.flatMap { projectID, chapterIDs in
            chapterIDs.map { Self.chapterRecordID(for: $0, projectID: projectID, scope: scope) }
        }
        let fetchedChapterRecords = try await existingRecords(for: chapterRecordIDs, in: database)
        var chapterDataByProjectID: [String: [Data]] = [:]

        for (projectID, chapterIDs) in chapterIDsByProjectID {
            for chapterID in chapterIDs {
                let recordID = Self.chapterRecordID(for: chapterID, projectID: projectID, scope: scope)
                guard let record = fetchedChapterRecords[recordID] else {
                    throw StoreError.missingPayload
                }

                guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
                      let assetURL = asset.fileURL
                else {
                    throw StoreError.missingPayload
                }

                do {
                    chapterDataByProjectID[projectID, default: []].append(try Data(contentsOf: assetURL))
                } catch {
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

                var project = try decoder.decode(NovelProject.self, from: data)
                if let chapterIDs = resolvedChapterIDsByProjectID[projectID], !chapterIDs.isEmpty {
                    let chapters = try resolvedChapterDataByProjectID[projectID, default: []].map {
                        try decoder.decode(ChapterDraft.self, from: $0)
                    }
                    project.chapterDrafts = chapters.sorted(by: ChapterDraft.sortDescending)
                }
                return project
            }
        }

        return AccountProjectSnapshot(
            activeProjectID: activeProjectID,
            recentProjects: recentProjects,
            updatedAt: updatedAt as Date
        )
    }

    private func existingProjectIDs(from indexRecord: CKRecord?) -> [String] {
        guard let indexRecord else { return [] }
        return projectIDs(from: indexRecord) ?? []
    }

    private nonisolated func projectIDs(from indexRecord: CKRecord) -> [String]? {
        if let direct = indexRecord[CloudKitKey.projectIDs] as? [String] {
            return direct
        }

        if let array = indexRecord[CloudKitKey.projectIDs] as? [NSString] {
            return array.map(String.init)
        }

        if let array = indexRecord[CloudKitKey.projectIDs] as? NSArray {
            return array.compactMap { $0 as? String }
        }

        return nil
    }

    private nonisolated func chapterIDs(from record: CKRecord) -> [String]? {
        if let direct = record[CloudKitKey.chapterIDs] as? [String] {
            return direct
        }

        if let array = record[CloudKitKey.chapterIDs] as? [NSString] {
            return array.map(String.init)
        }

        if let array = record[CloudKitKey.chapterIDs] as? NSArray {
            return array.compactMap { $0 as? String }
        }

        return nil
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
