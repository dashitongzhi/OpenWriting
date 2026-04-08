import AuthenticationServices
import CloudKit
import Foundation
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
    static func signInWithAppleAvailability(bundle: Bundle = .main) -> NativeAppleServiceAvailability {
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

    static func iCloudEntitlementAvailability() -> NativeAppleServiceAvailability {
        let hasICloudEntitlement =
            (entitlementArray(for: "com.apple.developer.ubiquity-container-identifiers")?.isEmpty == false) ||
            (entitlementArray(for: "com.apple.developer.icloud-container-identifiers")?.isEmpty == false) ||
            (entitlementArray(for: "com.apple.developer.icloud-services")?.isEmpty == false)

        if hasICloudEntitlement {
            return .available
        }

        return .unavailable("当前预览包没有启用 iCloud capability，所以只能显示本机保存状态。")
    }

    private static func entitlementArray(for key: String) -> [String]? {
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
        static let payloadAsset = "payloadAsset"
        static let updatedAt = "updatedAt"
        static let scope = "scope"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        container: CKContainer = .default(),
        fileManager: FileManager = .default
    ) {
        self.container = container
        self.database = container.privateCloudDatabase
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
            let status = try await accountStatus()
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
        guard try await accountStatus() == .available else {
            throw StoreError.notSignedIntoICloud
        }

        let recordID = snapshotRecordID(for: scope)
        let fetchedRecords = try await database.records(for: [recordID])
        guard let result = fetchedRecords[recordID] else { return nil }

        let record: CKRecord
        switch result {
        case let .success(resolvedRecord):
            record = resolvedRecord
        case let .failure(error as CKError) where error.code == .unknownItem:
            return nil
        case let .failure(error):
            throw StoreError.readFailed(error.localizedDescription)
        }

        guard let asset = record[CloudKitKey.payloadAsset] as? CKAsset,
              let assetURL = asset.fileURL
        else {
            throw StoreError.missingPayload
        }

        do {
            let data = try Data(contentsOf: assetURL)
            return try decoder.decode(AccountProjectSnapshot.self, from: data)
        } catch {
            throw StoreError.decodeFailed(error.localizedDescription)
        }
    }

    func saveSnapshot(_ snapshot: AccountProjectSnapshot, for scope: String) async throws {
        guard try await accountStatus() == .available else {
            throw StoreError.notSignedIntoICloud
        }

        do {
            let data = try encoder.encode(snapshot)
            let payloadURL = try writeTemporaryPayload(data, scope: scope)
            defer { try? fileManager.removeItem(at: payloadURL) }

            let recordID = snapshotRecordID(for: scope)
            let record = try await existingRecord(for: recordID)
                ?? CKRecord(recordType: CloudKitKey.recordType, recordID: recordID)
            record[CloudKitKey.scope] = sanitized(scope) as NSString
            record[CloudKitKey.updatedAt] = snapshot.updatedAt as NSDate
            record[CloudKitKey.payloadAsset] = CKAsset(fileURL: payloadURL)

            _ = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    private func existingRecord(for recordID: CKRecord.ID) async throws -> CKRecord? {
        let fetchedRecords = try await database.records(for: [recordID])
        guard let result = fetchedRecords[recordID] else { return nil }

        switch result {
        case let .success(record):
            return record
        case let .failure(error as CKError) where error.code == .unknownItem:
            return nil
        case let .failure(error):
            throw StoreError.readFailed(error.localizedDescription)
        }
    }

    private func accountStatus() async throws -> CKAccountStatus {
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

    private func snapshotRecordID(for scope: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "snapshot_\(sanitized(scope))")
    }

    private func writeTemporaryPayload(_ data: Data, scope: String) throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory
            .appendingPathComponent(sanitized(scope), isDirectory: false)
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

    private func sanitized(_ value: String) -> String {
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
