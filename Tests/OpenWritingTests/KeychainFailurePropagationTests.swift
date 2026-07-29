import Foundation
import Security
import XCTest
@testable import OpenWriting

nonisolated private final class RejectingCredentialStore: CredentialStoring {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var storedCallCount = 0
    private var removedCallCount = 0
    private var removeCallCounts: [String: Int] = [:]
    private var storeSucceeds: Bool
    private var removeSucceeds: Bool
    private var removeResults: [String: Bool] = [:]
    private var readResults: [String: CredentialReadResult] = [:]

    init(
        storeSucceeds: Bool = false,
        removeSucceeds: Bool = false
    ) {
        self.storeSucceeds = storeSucceeds
        self.removeSucceeds = removeSucceeds
    }

    var storeCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCallCount
    }

    var removeCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return removedCallCount
    }

    func value(service: String, account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key(service: service, account: account)]
    }

    func readResult(
        service: String,
        account: String
    ) -> CredentialReadResult {
        lock.lock()
        defer { lock.unlock() }
        let storageKey = key(service: service, account: account)
        if let result = readResults[storageKey] {
            return result
        }
        return values[storageKey].map(CredentialReadResult.value) ?? .notFound
    }

    @discardableResult
    func store(_ value: String, service: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storedCallCount += 1
        guard storeSucceeds else { return false }
        values[key(service: service, account: account)] = value
        return true
    }

    @discardableResult
    func remove(service: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let storageKey = key(service: service, account: account)
        removedCallCount += 1
        removeCallCounts[storageKey, default: 0] += 1
        let didRemove = removeResults[storageKey] ?? removeSucceeds
        if didRemove {
            values.removeValue(forKey: storageKey)
        }
        return didRemove
    }

    func seed(_ value: String, service: String, account: String) {
        lock.lock()
        values[key(service: service, account: account)] = value
        lock.unlock()
    }

    func setRemoveResult(_ result: Bool, service: String, account: String) {
        lock.lock()
        removeResults[key(service: service, account: account)] = result
        lock.unlock()
    }

    func setReadResult(
        _ result: CredentialReadResult,
        service: String,
        account: String
    ) {
        lock.lock()
        readResults[key(service: service, account: account)] = result
        lock.unlock()
    }

    func removeCallCount(service: String, account: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return removeCallCounts[key(service: service, account: account), default: 0]
    }

    private func key(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}

@MainActor
final class KeychainFailurePropagationTests: XCTestCase {
    private let expectedFailureMessage =
        "API Key 未能写入系统 Keychain，请检查钥匙串访问后重试。"
    private let expectedRemovalFailureMessage =
        "API Key 未能从系统 Keychain 删除，请检查钥匙串访问后重试。"
    private let expectedReadFailureMessage = AppState.apiKeyReadFailureMessage
    private let expectedOfficialReadFailureMessage =
        AppState.officialCredentialReadFailureMessage
    private let expectedOfficialRemovalFailureMessage =
        "登录凭据未能从系统 Keychain 删除，请检查钥匙串访问后重试。"
    private let expectedManagedMigrationFailureMessage =
        "OpenWriting 托管凭据未能从钥匙串移除；旧凭据仍被保留，请检查钥匙串权限后重试。"

    func testSecurityKeychainRemovalStatusAcceptsOnlyDeletedOrMissingItems() {
        XCTAssertTrue(
            SecurityKeychainCredentialStore.isSuccessfulRemovalStatus(errSecSuccess)
        )
        XCTAssertTrue(
            SecurityKeychainCredentialStore.isSuccessfulRemovalStatus(errSecItemNotFound)
        )
        XCTAssertFalse(
            SecurityKeychainCredentialStore.isSuccessfulRemovalStatus(errSecAuthFailed)
        )
    }

    @MainActor
    func testPersistAPIKeyReturnsFailureAndPublishesVisibleStatus() {
        let credentialStore = RejectingCredentialStore()
        let appState = makeAppState(credentialStore: credentialStore)
        appState.apiKey = "  sk-rejected  "
        appState.apiKeyPersistTask?.cancel()
        appState.apiKeyPersistTask = nil

        XCTAssertFalse(appState.persistAPIKey())

        XCTAssertEqual(credentialStore.storeCallCount, 1)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedFailureMessage)
    }

    @MainActor
    func testFlushAPIKeyPersistenceCancelsDebounceAndReturnsFailure() async {
        let credentialStore = RejectingCredentialStore()
        let appState = makeAppState(credentialStore: credentialStore)
        appState.apiKey = "sk-latest"

        XCTAssertNotNil(appState.apiKeyPersistTask)
        XCTAssertFalse(appState.flushAPIKeyPersistence())
        XCTAssertNil(appState.apiKeyPersistTask)
        XCTAssertEqual(credentialStore.storeCallCount, 1)

        try? await Task.sleep(for: .milliseconds(750))

        XCTAssertEqual(
            credentialStore.storeCallCount,
            1,
            "The cancelled debounce must not attempt a second Keychain write."
        )
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedFailureMessage)
    }

    @MainActor
    func testConfigurationValidationStopsWhenAPIKeyCannotBePersisted() {
        let credentialStore = RejectingCredentialStore()
        let appState = makeAppState(credentialStore: credentialStore)
        appState.hasAcceptedAIDataTransfer = true
        appState.modelName = "test-model"
        appState.baseURL = "https://example.com/v1"
        appState.apiKey = "sk-rejected"

        appState.validateConfiguration()

        XCTAssertNil(
            appState.validationTask,
            "Connection validation must not start with an API key that was not persisted."
        )
        XCTAssertEqual(credentialStore.storeCallCount, 1)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedFailureMessage)
    }

    @MainActor
    func testAccountBindingStopsBeforeChangingScopeWhenAPIKeyCannotBePersisted() async {
        let credentialStore = RejectingCredentialStore()
        let appState = makeAppState(credentialStore: credentialStore)
        let targetAccount = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        appState.apiKey = "sk-rejected"

        let didBind = await appState.bindAppleAccount(targetAccount)

        XCTAssertFalse(didBind)
        XCTAssertNil(appState.activeAccount)
        XCTAssertEqual(credentialStore.storeCallCount, 1)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedFailureMessage)
    }

    @MainActor
    func testTerminationCoordinatorReceivesAPIKeyFlushFailure() async {
        let credentialStore = RejectingCredentialStore()
        let appState = makeAppState(credentialStore: credentialStore)
        let coordinator = TerminationFlushCoordinator(timeout: .seconds(1))
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []
        appState.apiKey = "sk-rejected"

        XCTAssertTrue(coordinator.begin(
            flush: {
                let didFlushAPIKey = appState.flushAPIKeyPersistence()
                let didFlushProjects = true
                return didFlushAPIKey && didFlushProjects
            },
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        ))

        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(replies, [false])
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedFailureMessage)
    }

    @MainActor
    func testClearingAPIKeyReturnsFailureAndKeepsOldCredentialWhenRemovalFails() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: false
        )
        credentialStore.seed(
            "sk-existing",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.customAccount
        )
        let appState = makeAppState(credentialStore: credentialStore)
        XCTAssertEqual(appState.apiKey, "sk-existing")

        appState.apiKey = " "

        XCTAssertFalse(appState.flushAPIKeyPersistence())
        XCTAssertEqual(
            credentialStore.value(
                service: ModelConnectionConfigurationStore.KeychainKey.service,
                account: ModelConnectionConfigurationStore.KeychainKey.customAccount
            ),
            "sk-existing"
        )
        XCTAssertEqual(
            credentialStore.removeCallCount(
                service: ModelConnectionConfigurationStore.KeychainKey.service,
                account: ModelConnectionConfigurationStore.KeychainKey.customAccount
            ),
            1
        )
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedRemovalFailureMessage)
    }

    @MainActor
    func testProviderSwitchRejectsStoreFailureAndPreservesCompleteDraft() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: false,
            removeSucceeds: true
        )
        let appState = makeAppState(credentialStore: credentialStore)
        appState.modelName = "custom-model-draft"
        appState.baseURL = "https://custom.example.com/v1"
        appState.apiKey = "sk-custom-draft"

        appState.selectedProvider = .anthropic

        XCTAssertEqual(appState.selectedProvider, .custom)
        XCTAssertEqual(appState.modelName, "custom-model-draft")
        XCTAssertEqual(appState.baseURL, "https://custom.example.com/v1")
        XCTAssertEqual(appState.apiKey, "sk-custom-draft")
        XCTAssertEqual(
            appState.userDefaults.string(
                forKey: AppState.StorageKey.selectedProvider
            ),
            ModelProvider.custom.rawValue
        )
        XCTAssertEqual(credentialStore.storeCallCount, 1)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedFailureMessage)
    }

    @MainActor
    func testProviderSwitchRejectsRemovalFailureAndPreservesCompleteDraft() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        credentialStore.seed(
            "sk-existing",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.customAccount
        )
        credentialStore.setRemoveResult(
            false,
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.customAccount
        )
        let appState = makeAppState(credentialStore: credentialStore)
        appState.modelName = "custom-model-draft"
        appState.baseURL = "https://custom.example.com/v1"
        appState.apiKey = "  "

        appState.selectedProvider = .anthropic

        XCTAssertEqual(appState.selectedProvider, .custom)
        XCTAssertEqual(appState.modelName, "custom-model-draft")
        XCTAssertEqual(appState.baseURL, "https://custom.example.com/v1")
        XCTAssertEqual(appState.apiKey, "  ")
        XCTAssertEqual(
            appState.userDefaults.string(
                forKey: AppState.StorageKey.selectedProvider
            ),
            ModelProvider.custom.rawValue
        )
        XCTAssertEqual(
            credentialStore.value(
                service: ModelConnectionConfigurationStore.KeychainKey.service,
                account: ModelConnectionConfigurationStore.KeychainKey.customAccount
            ),
            "sk-existing"
        )
        XCTAssertEqual(
            credentialStore.removeCallCount(
                service: ModelConnectionConfigurationStore.KeychainKey.service,
                account: ModelConnectionConfigurationStore.KeychainKey.customAccount
            ),
            1
        )
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedRemovalFailureMessage)
    }

    @MainActor
    func testProviderSwitchPersistsAndRestoresCompleteDraftWhenKeychainSucceeds() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let appState = makeAppState(credentialStore: credentialStore)
        appState.modelName = "custom-model-draft"
        appState.baseURL = "https://custom.example.com/v1"
        appState.apiKey = "sk-custom-draft"

        appState.selectedProvider = .anthropic

        XCTAssertEqual(appState.selectedProvider, .anthropic)
        XCTAssertEqual(
            appState.userDefaults.string(
                forKey: AppState.StorageKey.selectedProvider
            ),
            ModelProvider.anthropic.rawValue
        )
        appState.modelName = "anthropic-model-draft"
        appState.baseURL = "https://anthropic.example.com/v1"
        appState.apiKey = "sk-anthropic-draft"

        appState.selectedProvider = .custom

        XCTAssertEqual(appState.selectedProvider, .custom)
        XCTAssertEqual(appState.modelName, "custom-model-draft")
        XCTAssertEqual(appState.baseURL, "https://custom.example.com/v1")
        XCTAssertEqual(appState.apiKey, "sk-custom-draft")
        XCTAssertEqual(
            appState.userDefaults.string(
                forKey: AppState.StorageKey.selectedProvider
            ),
            ModelProvider.custom.rawValue
        )

        appState.selectedProvider = .anthropic

        XCTAssertEqual(appState.selectedProvider, .anthropic)
        XCTAssertEqual(appState.modelName, "anthropic-model-draft")
        XCTAssertEqual(appState.baseURL, "https://anthropic.example.com/v1")
        XCTAssertEqual(appState.apiKey, "sk-anthropic-draft")
        XCTAssertEqual(appState.connectionStatus, .idle)
        XCTAssertNotEqual(appState.validationMessage, expectedFailureMessage)
        XCTAssertNotEqual(appState.validationMessage, expectedRemovalFailureMessage)
    }

    @MainActor
    func testProviderSwitchRejectsCurrentProviderReadFailureWithoutDeletingKey() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let service = ModelConnectionConfigurationStore.KeychainKey.service
        let account =
            ModelConnectionConfigurationStore.KeychainKey.customAccount
        credentialStore.seed(
            "sk-existing",
            service: service,
            account: account
        )
        credentialStore.setReadResult(
            .failure("interaction not allowed"),
            service: service,
            account: account
        )
        let appState = makeAppState(credentialStore: credentialStore)
        appState.modelName = "custom-model-draft"
        appState.baseURL = "https://custom.example.com/v1"

        appState.selectedProvider = .anthropic

        XCTAssertEqual(appState.selectedProvider, .custom)
        XCTAssertEqual(appState.modelName, "custom-model-draft")
        XCTAssertEqual(appState.baseURL, "https://custom.example.com/v1")
        XCTAssertEqual(
            credentialStore.value(service: service, account: account),
            "sk-existing"
        )
        XCTAssertEqual(
            credentialStore.removeCallCount(
                service: service,
                account: account
            ),
            0
        )
        XCTAssertEqual(credentialStore.storeCallCount, 0)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedReadFailureMessage)
    }

    @MainActor
    func testTargetProviderReadFailureRollsBackWithoutOverwritingCurrentDraft() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let service = ModelConnectionConfigurationStore.KeychainKey.service
        credentialStore.seed(
            "sk-custom-draft",
            service: service,
            account: ModelConnectionConfigurationStore.KeychainKey.customAccount
        )
        credentialStore.setReadResult(
            .failure("authentication failed"),
            service: service,
            account: ModelConnectionConfigurationStore.KeychainKey.anthropicAccount
        )
        let appState = makeAppState(credentialStore: credentialStore)
        appState.modelName = "custom-model-draft"
        appState.baseURL = "https://custom.example.com/v1"

        appState.selectedProvider = .anthropic

        XCTAssertEqual(appState.selectedProvider, .custom)
        XCTAssertEqual(appState.modelName, "custom-model-draft")
        XCTAssertEqual(appState.baseURL, "https://custom.example.com/v1")
        XCTAssertEqual(appState.apiKey, "sk-custom-draft")
        XCTAssertEqual(
            appState.userDefaults.string(
                forKey: AppState.StorageKey.selectedProvider
            ),
            ModelProvider.custom.rawValue
        )
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedReadFailureMessage)
    }

    @MainActor
    func testMissingTargetProviderKeyRemainsAValidEmptyConfiguration() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        credentialStore.seed(
            "sk-custom",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.customAccount
        )
        let appState = makeAppState(credentialStore: credentialStore)

        appState.selectedProvider = .anthropic

        XCTAssertEqual(appState.selectedProvider, .anthropic)
        XCTAssertEqual(appState.apiKey, "")
        XCTAssertFalse(
            appState.apiKeyReadFailureProviders.contains(.anthropic)
        )
        XCTAssertNotEqual(appState.validationMessage, expectedReadFailureMessage)
    }

    @MainActor
    func testExplicitAPIKeyEditUnlocksProviderAfterReadFailure() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let service = ModelConnectionConfigurationStore.KeychainKey.service
        let account =
            ModelConnectionConfigurationStore.KeychainKey.customAccount
        credentialStore.setReadResult(
            .failure("authentication failed"),
            service: service,
            account: account
        )
        let appState = makeAppState(credentialStore: credentialStore)

        appState.apiKey = "sk-replacement"
        credentialStore.setReadResult(
            .value("sk-replacement"),
            service: service,
            account: account
        )

        XCTAssertTrue(appState.flushAPIKeyPersistence())
        XCTAssertFalse(appState.apiKeyReadFailureProviders.contains(.custom))
        XCTAssertEqual(
            credentialStore.value(service: service, account: account),
            "sk-replacement"
        )
        XCTAssertNotEqual(appState.validationMessage, expectedReadFailureMessage)
    }

    @MainActor
    func testEmptyAPIKeyAssignmentAfterReadFailureKeepsCredentialLocked() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let service = ModelConnectionConfigurationStore.KeychainKey.service
        let account =
            ModelConnectionConfigurationStore.KeychainKey.customAccount
        credentialStore.seed(
            "sk-existing",
            service: service,
            account: account
        )
        credentialStore.setReadResult(
            .failure("interaction not allowed"),
            service: service,
            account: account
        )
        let appState = makeAppState(credentialStore: credentialStore)

        appState.apiKey = " "
        appState.modelName = "edited-while-keychain-is-locked"

        XCTAssertFalse(appState.flushAPIKeyPersistence())
        XCTAssertTrue(appState.apiKeyReadFailureProviders.contains(.custom))
        XCTAssertEqual(
            credentialStore.value(service: service, account: account),
            "sk-existing"
        )
        XCTAssertEqual(
            credentialStore.removeCallCount(
                service: service,
                account: account
            ),
            0
        )
        XCTAssertEqual(credentialStore.storeCallCount, 0)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(appState.validationMessage, expectedReadFailureMessage)
    }

    func testOfficialCredentialRemovalFailureIsNotReportedAsSuccess() {
        let credentialStore = RejectingCredentialStore()
        credentialStore.seed(
            "credential-that-must-remain",
            service: OfficialChannelCredentialStore.service,
            account: OfficialChannelCredentialStore.account
        )

        XCTAssertFalse(
            OfficialChannelCredentialStore.save(
                nil,
                credentialStore: credentialStore
            )
        )
        XCTAssertEqual(credentialStore.removeCallCount, 1)
        XCTAssertEqual(
            credentialStore.value(
                service: OfficialChannelCredentialStore.service,
                account: OfficialChannelCredentialStore.account
            ),
            "credential-that-must-remain"
        )
    }

    func testConfigurationLoaderDistinguishesMissingAPIKeyFromReadFailure() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let suiteName = "OpenWritingKeychainLoaderTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.set(
            ModelProvider.custom.rawValue,
            forKey: ModelConnectionConfigurationStore.StorageKey.selectedProvider
        )
        userDefaults.set(
            "custom-model",
            forKey: ModelConnectionConfigurationStore.StorageKey.customModelName
        )
        userDefaults.set(
            "https://example.com/v1",
            forKey: ModelConnectionConfigurationStore.StorageKey.customBaseURL
        )
        credentialStore.setReadResult(
            .failure("interaction not allowed"),
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.customAccount
        )
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertThrowsError(
            try ModelConnectionConfigurationStore.loadConnectionConfiguration(
                userDefaults: userDefaults,
                credentialStore: credentialStore
            )
        ) { error in
            guard let configurationError =
                    error as? ModelConnectionConfigurationError,
                  case let .apiKeyReadFailed(provider) = configurationError
            else {
                return XCTFail("Expected apiKeyReadFailed, got \(error)")
            }
            XCTAssertEqual(provider, .custom)
        }
    }

    func testConfigurationLoaderPropagatesOfficialCredentialReadFailure() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let suiteName =
            "OpenWritingOfficialCredentialLoaderTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.set(
            ModelProvider.openAICompatible.rawValue,
            forKey: ModelConnectionConfigurationStore.StorageKey.selectedProvider
        )
        credentialStore.setReadResult(
            .failure("authentication failed"),
            service: OfficialChannelCredentialStore.service,
            account: OfficialChannelCredentialStore.account
        )
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertThrowsError(
            try ModelConnectionConfigurationStore.loadConnectionConfiguration(
                userDefaults: userDefaults,
                credentialStore: credentialStore
            )
        ) { error in
            guard let configurationError =
                    error as? ModelConnectionConfigurationError,
                  case .officialCredentialReadFailed = configurationError
            else {
                return XCTFail(
                    "Expected officialCredentialReadFailed, got \(error)"
                )
            }
        }
    }

    @MainActor
    func testOfficialCredentialReadFailureLocksLogoutWithoutDeletingStoredSession() async throws {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let account = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        let credential = OfficialChannelCredential(
            accessToken: "official-access-token",
            refreshToken: "official-refresh-token",
            expiresAt: Date().addingTimeInterval(600)
        )
        let encodedCredential = String(
            data: try JSONEncoder().encode(credential),
            encoding: .utf8
        )!
        credentialStore.seed(
            encodedCredential,
            service: OfficialChannelCredentialStore.service,
            account: OfficialChannelCredentialStore.account
        )
        credentialStore.setReadResult(
            .failure("interaction not allowed"),
            service: OfficialChannelCredentialStore.service,
            account: OfficialChannelCredentialStore.account
        )
        let appState = makeAppState(
            credentialStore: credentialStore,
            activeAccount: account
        )

        XCTAssertTrue(appState.officialChannelCredentialReadFailed)
        XCTAssertNil(appState.officialChannelCredential)
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(
            appState.validationMessage,
            expectedOfficialReadFailureMessage
        )

        let didLogout = await appState.logoutAccount()

        XCTAssertFalse(didLogout)
        XCTAssertEqual(appState.activeAccount, account)
        XCTAssertEqual(
            credentialStore.value(
                service: OfficialChannelCredentialStore.service,
                account: OfficialChannelCredentialStore.account
            ),
            encodedCredential
        )
        XCTAssertEqual(
            credentialStore.removeCallCount(
                service: OfficialChannelCredentialStore.service,
                account: OfficialChannelCredentialStore.account
            ),
            0
        )
        XCTAssertEqual(
            appState.validationMessage,
            expectedOfficialReadFailureMessage
        )
    }

    @MainActor
    func testNewOfficialCredentialReplacesLockedUnreadableSession() {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        credentialStore.setReadResult(
            .failure("authentication failed"),
            service: OfficialChannelCredentialStore.service,
            account: OfficialChannelCredentialStore.account
        )
        let appState = makeAppState(credentialStore: credentialStore)
        let replacement = OfficialChannelCredential(
            accessToken: "replacement-token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(600)
        )

        XCTAssertTrue(appState.updateOfficialChannelCredential(replacement))

        XCTAssertFalse(appState.officialChannelCredentialReadFailed)
        XCTAssertEqual(appState.officialChannelCredential, replacement)
        XCTAssertNotEqual(
            appState.validationMessage,
            expectedOfficialReadFailureMessage
        )
    }

    @MainActor
    func testLegacyMigrationReportsManagedKeyRemovalFailureWhilePurgingPlaintext() {
        let suiteName = "OpenWritingKeychainMigrationFailureTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let credentialStore = RejectingCredentialStore(removeSucceeds: false)
        userDefaults.set("legacy-api-key", forKey: AppState.StorageKey.apiKey)
        userDefaults.set(
            "older-legacy-api-key",
            forKey: AppState.LegacyStorageKey.apiKey
        )
        credentialStore.seed(
            "managed-key-that-must-remain",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
        )
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertFalse(
            AppState.migrateAPIKeysToKeychainIfNeeded(
                userDefaults,
                credentialStore: credentialStore
            )
        )

        XCTAssertNil(userDefaults.string(forKey: AppState.StorageKey.apiKey))
        XCTAssertNil(userDefaults.string(forKey: AppState.LegacyStorageKey.apiKey))
        XCTAssertEqual(
            credentialStore.value(
                service: ModelConnectionConfigurationStore.KeychainKey.service,
                account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
            ),
            "managed-key-that-must-remain"
        )
    }

    @MainActor
    func testAppStateInitializationPublishesManagedKeyMigrationFailure() {
        let credentialStore = RejectingCredentialStore(removeSucceeds: false)
        credentialStore.seed(
            "managed-key-that-must-remain",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
        )

        let appState = makeAppState(
            credentialStore: credentialStore,
            managedMigrationRemoveSucceeds: false
        )

        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(
            appState.validationMessage,
            expectedManagedMigrationFailureMessage
        )
        XCTAssertEqual(
            credentialStore.value(
                service: ModelConnectionConfigurationStore.KeychainKey.service,
                account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
            ),
            "managed-key-that-must-remain"
        )
    }

    @MainActor
    func testLogoutStopsWhenOfficialCredentialRemovalFails() async throws {
        let credentialStore = RejectingCredentialStore(
            storeSucceeds: true,
            removeSucceeds: true
        )
        let account = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        let officialCredential = OfficialChannelCredential(
            accessToken: "official-access-token",
            refreshToken: "official-refresh-token",
            expiresAt: Date().addingTimeInterval(600)
        )
        let encodedCredential = String(
            data: try JSONEncoder().encode(officialCredential),
            encoding: .utf8
        )!
        credentialStore.seed(
            "sk-existing",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.customAccount
        )
        credentialStore.seed(
            encodedCredential,
            service: OfficialChannelCredentialStore.service,
            account: OfficialChannelCredentialStore.account
        )
        credentialStore.setRemoveResult(
            false,
            service: OfficialChannelCredentialStore.service,
            account: OfficialChannelCredentialStore.account
        )
        let appState = makeAppState(
            credentialStore: credentialStore,
            activeAccount: account
        )

        let didLogout = await appState.logoutAccount()

        XCTAssertFalse(didLogout)
        XCTAssertEqual(appState.activeAccount, account)
        XCTAssertEqual(appState.officialChannelCredential, officialCredential)
        XCTAssertNotNil(
            credentialStore.value(
                service: OfficialChannelCredentialStore.service,
                account: OfficialChannelCredentialStore.account
            )
        )
        XCTAssertEqual(appState.connectionStatus, .needsAttention)
        XCTAssertEqual(
            appState.validationMessage,
            expectedOfficialRemovalFailureMessage
        )
    }

    @MainActor
    private func makeAppState(
        credentialStore: RejectingCredentialStore,
        activeAccount: AppleAccountProfile? = nil,
        managedMigrationRemoveSucceeds: Bool = true
    ) -> AppState {
        credentialStore.setRemoveResult(
            managedMigrationRemoveSucceeds,
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
        )
        let suiteName = "OpenWritingKeychainFailureTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(
            ModelProvider.custom.rawValue,
            forKey: AppState.StorageKey.selectedProvider
        )
        userDefaults.set(false, forKey: AppState.StorageKey.autoValidateOnLaunch)
        userDefaults.set(
            true,
            forKey: ModelConnectionConfigurationStore.StorageKey.didClearBundledCustomDefaults
        )
        if let activeAccount {
            userDefaults.set(
                activeAccount.userID,
                forKey: AppState.StorageKey.activeAppleUserID
            )
            userDefaults.set(
                activeAccount.email,
                forKey: AppState.StorageKey.activeAppleUserEmail
            )
            userDefaults.set(
                activeAccount.fullName,
                forKey: AppState.StorageKey.activeAppleUserName
            )
        }

        let baseDirectoryName = "OpenWritingKeychainFailureTests-\(UUID().uuidString)"
        let baseDirectoryURL = FileManager.default.temporaryDirectory
        let projectStore = ProjectFileStore(
            baseDirectoryURL: baseDirectoryURL,
            baseDirectoryName: baseDirectoryName
        )
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(
                at: baseDirectoryURL.appendingPathComponent(
                    baseDirectoryName,
                    isDirectory: true
                )
            )
        }

        return AppState(
            userDefaults: userDefaults,
            projectStore: projectStore,
            credentialStore: credentialStore
        )
    }
}
