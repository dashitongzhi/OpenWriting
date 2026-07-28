import AuthenticationServices
import CloudKit
import XCTest
@testable import OpenWriting

nonisolated private struct FailingAppleCredentialStateProvider:
    AppleCredentialStateProviding {
    struct LookupFailure: Error {}

    func credentialState(
        for userID: String
    ) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        throw LookupFailure()
    }
}

nonisolated private struct InjectedPersistenceFailure: Error {}

final class DomainModelsTests: XCTestCase {
    func testNovelProjectInitializerCarriesStructuredForeshadowAndPlotThreads() {
        let foreshadow = ForeshadowEntry(title: "旧钥匙", firstChapter: 1)
        let thread = PlotThread(title: "追查身世")
        let project = NovelProject(
            id: "structured-project",
            title: "结构化项目",
            genre: "悬疑",
            summary: "摘要",
            updatedAt: "2026-07-27T00:00:00Z",
            currentChapterTitle: "第一章",
            currentChapterNumber: 1,
            writtenChapters: 0,
            chapterFocus: "",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: [],
            foreshadowList: ForeshadowList(entries: [foreshadow]),
            plotThreadList: PlotThreadList(threads: [thread])
        )

        XCTAssertEqual(project.foreshadowList.entries.map(\.id), [foreshadow.id])
        XCTAssertEqual(project.plotThreadList.threads.map(\.id), [thread.id])
    }

    // MARK: - NovelLength Tests

    func testNovelLengthLabels() {
        XCTAssertEqual(NovelLength.short.title, "短篇")
        XCTAssertEqual(NovelLength.medium.title, "中篇")
        XCTAssertEqual(NovelLength.long.title, "长篇")
    }

    func testNovelLengthTargetRangeSummary() {
        XCTAssertEqual(NovelLength.short.targetRangeSummary, "全文约 0.6 万到 1.5 万字")
        XCTAssertEqual(NovelLength.medium.targetRangeSummary, "全文约 3 万到 12 万字")
        XCTAssertEqual(NovelLength.long.targetRangeSummary, "全文约 30 万字以上")
    }

    // MARK: - ModelProvider Tests

    func testModelProviderCases() {
        XCTAssertEqual(ModelProvider.openAICompatible.title, "OpenWriting")
        XCTAssertEqual(ModelProvider.custom.title, "自定义 OpenAI")
        XCTAssertEqual(ModelProvider.anthropic.title, "自定义 Anthropic")
        XCTAssertFalse(ModelProvider.openAICompatible.requiresAPIKey)
        XCTAssertTrue(ModelProvider.custom.requiresAPIKey)
        XCTAssertTrue(ModelProvider.anthropic.requiresAPIKey)
    }

    func testTextFileDecodingPrefersGB18030BeforeBOMLessUTF16() throws {
        let gb18030Bytes = Data([0xD6, 0xD0, 0xCE, 0xC4, 0xB2, 0xE2, 0xCA, 0xD4])

        XCTAssertEqual(try TextFileDecoding.decodeText(from: gb18030Bytes), "中文测试")
    }

    func testMergedAntiPatternsIsStableDeduplicatedAndBounded() {
        let existing = (0..<60).map { "existing-\($0)" }
        let incoming = ["new-2", "new-1", "new-2", "existing-3"]

        let first = NovelProject.mergedAntiPatterns(existing: existing, incoming: incoming)
        let second = NovelProject.mergedAntiPatterns(existing: existing, incoming: incoming)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Array(first.prefix(3)), ["new-2", "new-1", "existing-3"])
        XCTAssertEqual(first.count, 50)
        XCTAssertEqual(Set(first).count, first.count)
    }

    @MainActor
    func testAPIKeyPersistenceDebouncesTypingAndFlushesLatestValue() async {
        let defaults = makeIsolatedUserDefaults()
        defaults.set(ModelProvider.custom.rawValue, forKey: AppState.StorageKey.selectedProvider)
        let credentialStore = InMemoryCredentialStore()
        let appState = AppState(
            userDefaults: defaults,
            projectStore: makeIsolatedProjectStore(),
            credentialStore: credentialStore
        )
        let baselineStoreCount = credentialStore.storeCallCount

        appState.apiKey = "sk-a"
        appState.apiKey = "sk-ab"
        appState.apiKey = "sk-final"
        XCTAssertEqual(credentialStore.storeCallCount, baselineStoreCount)

        try? await Task.sleep(for: .milliseconds(750))

        XCTAssertEqual(credentialStore.storeCallCount, baselineStoreCount + 1)
        XCTAssertEqual(
            credentialStore.value(
                service: ModelConnectionConfigurationStore.KeychainKey.service,
                account: ModelConnectionConfigurationStore.KeychainKey.customAccount
            ),
            "sk-final"
        )
    }

    @MainActor
    func testAIConfigurationResolutionHasNoObservableSideEffects() {
        let defaults = makeIsolatedUserDefaults()
        defaults.set(ModelProvider.custom.rawValue, forKey: AppState.StorageKey.selectedProvider)
        let appState = AppState(
            userDefaults: defaults,
            projectStore: makeIsolatedProjectStore(),
            credentialStore: InMemoryCredentialStore()
        )
        appState.hasAcceptedAIDataTransfer = true
        appState.modelName = "test-model"
        appState.apiKey = "sk-test"
        appState.baseURL = " https://example.com/v1/ "
        appState.connectionStatus = .idle
        appState.validationMessage = "sentinel"
        let defaultsBeforeResolution = defaults.dictionaryRepresentation()

        XCTAssertNotNil(appState.aiConfiguration)
        XCTAssertTrue(appState.isConfigurationReady)
        XCTAssertEqual(appState.baseURL, " https://example.com/v1/ ")
        XCTAssertEqual(appState.connectionStatus, .idle)
        XCTAssertEqual(appState.validationMessage, "sentinel")
        XCTAssertTrue(
            (defaults.dictionaryRepresentation() as NSDictionary)
                .isEqual(to: defaultsBeforeResolution)
        )
        appState.flushAPIKeyPersistence()
    }

    @MainActor
    func testProjectFlushDoesNotRewriteUnchangedAPIKey() async {
        let defaults = makeIsolatedUserDefaults()
        defaults.set(ModelProvider.custom.rawValue, forKey: AppState.StorageKey.selectedProvider)
        let credentialStore = InMemoryCredentialStore()
        let appState = AppState(
            userDefaults: defaults,
            projectStore: makeIsolatedProjectStore(),
            credentialStore: credentialStore
        )
        appState.apiKey = "sk-stable"
        appState.flushAPIKeyPersistence()
        let baselineStoreCount = credentialStore.storeCallCount

        let firstFlushSucceeded = await appState.flushProjectPersistence()
        let secondFlushSucceeded = await appState.flushProjectPersistence()
        XCTAssertTrue(firstFlushSucceeded)
        XCTAssertTrue(secondFlushSucceeded)

        XCTAssertEqual(credentialStore.storeCallCount, baselineStoreCount)
    }

    @MainActor
    func testFinalProjectFlushFailureWritesEmergencySnapshot() async throws {
        let store = makeIsolatedProjectStore(
            testHooks: .init(beforeAtomicWrite: { url in
                if url.lastPathComponent == "index.json" {
                    throw InjectedPersistenceFailure()
                }
            })
        )
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        let project = makeProject(
            id: "emergency-final",
            title: "终止保存项目",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000.125)
        )
        appState.recentProjects = [project]

        let didFlush = await appState.flushProjectPersistence()

        XCTAssertFalse(didFlush)
        let emergencyURL = try XCTUnwrap(appState.lastEmergencySnapshotURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: emergencyURL.path))
        let emergency = try JSONDecoder().decode(
            ProjectEmergencySnapshot.self,
            from: Data(contentsOf: emergencyURL)
        )
        XCTAssertEqual(emergency.projects.map(\.id), [project.id])
        XCTAssertTrue(
            appState.lastProjectPersistenceErrorMessage?
                .contains("应急副本") == true
        )
    }

    @MainActor
    func testAutosaveFailureWritesRetryableEmergencySnapshot() async throws {
        let store = makeIsolatedProjectStore(
            testHooks: .init(beforeAtomicWrite: { url in
                if url.lastPathComponent == "index.json" {
                    throw InjectedPersistenceFailure()
                }
            })
        )
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        let project = makeProject(
            id: "emergency-autosave",
            title: "自动保存项目",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000.125)
        )

        appState.recentProjects = [project]
        try await Task.sleep(for: .milliseconds(550))

        let emergencyURL = try XCTUnwrap(appState.lastEmergencySnapshotURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: emergencyURL.path))
        let emergency = try JSONDecoder().decode(
            ProjectEmergencySnapshot.self,
            from: Data(contentsOf: emergencyURL)
        )
        XCTAssertEqual(emergency.projects.map(\.id), [project.id])
        XCTAssertEqual(appState.cloudSyncTitle, "保存失败")
    }

    @MainActor
    func testStorageHealthGetterDoesNotScanDiskAndExplicitRefreshDoes() async {
        nonisolated(unsafe) var scanCount = 0
        let store = makeIsolatedProjectStore(
            testHooks: .init(onStorageHealthScan: { scanCount += 1 })
        )
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: store,
            credentialStore: InMemoryCredentialStore()
        )
        let project = makeProject(
            id: "storage-health-explicit-refresh",
            title: "存储健康检查",
            updatedAt: Date()
        )
        appState.recentProjects = [project]
        appState.activeProjectID = project.id
        let projectID = project.id

        _ = appState.storageHealthReport(for: projectID)
        _ = appState.storageHealthReport(for: projectID)
        XCTAssertEqual(scanCount, 0)

        await appState.refreshStorageHealthReport(for: projectID)
        XCTAssertEqual(scanCount, 1)
    }

    @MainActor
    func testRapidStorageHealthInvalidationsDebounceToOneScan() async {
        nonisolated(unsafe) var scanCount = 0
        let store = makeIsolatedProjectStore(
            testHooks: .init(onStorageHealthScan: { scanCount += 1 })
        )
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: store,
            credentialStore: InMemoryCredentialStore()
        )
        let project = makeProject(
            id: "storage-health-debounce",
            title: "存储健康去抖",
            updatedAt: Date()
        )
        appState.recentProjects = [project]
        appState.activeProjectID = project.id
        let projectID = project.id

        appState.invalidateStorageHealthCache(for: projectID)
        appState.invalidateStorageHealthCache(for: projectID)
        appState.invalidateStorageHealthCache(for: projectID)
        try? await Task.sleep(for: .milliseconds(1_200))

        XCTAssertEqual(scanCount, 1)
    }

    @MainActor
    func testOpenWritingDefaultConnectionUsesServerManagedBackend() {
        let userDefaults = makeIsolatedUserDefaults()

        XCTAssertEqual(AppState.defaultModelName(for: .openAICompatible), "gpt-5.4-mini")
        XCTAssertEqual(AppState.defaultBaseURL(for: .openAICompatible), "https://openwriting.kralplus.asia/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralplus.asia/api/model/v1")
    }

    @MainActor
    func testOpenWritingServerManagedConnectionIncludesClientContextHeaders() throws {
        let userDefaults = makeIsolatedUserDefaults()

        let configuration = try ModelConnectionConfigurationStore.loadConnectionConfiguration(userDefaults: userDefaults)

        XCTAssertEqual(configuration.apiKey, "")
        XCTAssertEqual(configuration.additionalHeaders["X-OpenWriting-Client"], "macOS")
        let installationID = try XCTUnwrap(configuration.additionalHeaders["X-OpenWriting-Installation-ID"])
        XCTAssertNotNil(UUID(uuidString: installationID))
        XCTAssertNil(configuration.additionalHeaders["X-OpenWriting-Account-ID"])
    }

    @MainActor
    func testOpenWritingServerManagedConnectionIgnoresLegacyKeychainAPIKey() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let credentialStore = makeCredentialStore()
        credentialStore.store(
            "sk-legacy-openai-key",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
        )

        let configuration = try ModelConnectionConfigurationStore.loadConnectionConfiguration(
            userDefaults: userDefaults,
            credentialStore: credentialStore
        )

        XCTAssertEqual(configuration.apiKey, "")
    }

    func testOfficialChannelCredentialStoreKeepsRefreshTokenOutOfRequestToken() throws {
        let credentialStore = InMemoryCredentialStore()
        let credential = OfficialChannelCredential(
            accessToken: " short-lived-access ",
            refreshToken: "refresh-token-never-sent",
            expiresAt: Date().addingTimeInterval(300)
        )

        XCTAssertTrue(
            OfficialChannelCredentialStore.save(
                credential,
                credentialStore: credentialStore
            )
        )
        let loaded = try XCTUnwrap(
            OfficialChannelCredentialStore.load(credentialStore: credentialStore)
        )

        XCTAssertEqual(loaded.validAccessToken(), "short-lived-access")
        XCTAssertEqual(loaded.refreshToken, "refresh-token-never-sent")
    }

    func testOfficialChannelFailsClosedBeforeNetworkWithoutCredential() async {
        let configuration = AIConnectionConfiguration(
            baseURL: URL(string: "https://openwriting.kralplus.asia/api/model/v1")!,
            apiKey: "",
            modelName: "gpt-5.4-mini",
            additionalHeaders: ["X-OpenWriting-Client": "macOS"],
            requiresOfficialAuthentication: true
        )
        nonisolated(unsafe) var loaderCalled = false

        do {
            _ = try await AIWritingService.completeOpenAIText(
                configuration: configuration,
                systemPrompt: "system",
                userPrompt: "user",
                temperature: 0.1,
                maxTokens: 16,
                loader: { _ in
                    loaderCalled = true
                    throw URLError(.badServerResponse)
                }
            )
            XCTFail("Expected authenticationRequired")
        } catch AIWritingError.authenticationRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(loaderCalled)
    }

    @MainActor
    func testOpenWritingAPIKeyMigrationPurgesLegacyManagedKeyStorage() {
        let userDefaults = makeIsolatedUserDefaults()
        let credentialStore = makeCredentialStore()
        userDefaults.set("sk-userdefaults-key", forKey: AppState.StorageKey.apiKey)
        userDefaults.set("sk-legacy-userdefaults-key", forKey: AppState.LegacyStorageKey.apiKey)
        credentialStore.store(
            "sk-keychain-key",
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
        )

        AppState.migrateAPIKeysToKeychainIfNeeded(userDefaults, credentialStore: credentialStore)

        XCTAssertNil(userDefaults.string(forKey: AppState.StorageKey.apiKey))
        XCTAssertNil(userDefaults.string(forKey: AppState.LegacyStorageKey.apiKey))
        XCTAssertNil(credentialStore.value(
            service: ModelConnectionConfigurationStore.KeychainKey.service,
            account: ModelConnectionConfigurationStore.KeychainKey.openWAccount
        ))
    }

    @MainActor
    func testOpenWritingServerManagedHeadersSanitizeAccountID() {
        let userDefaults = makeIsolatedUserDefaults()

        let headers = ModelConnectionConfigurationStore.serverManagedAdditionalHeaders(
            accountID: " user\nid\t ",
            userDefaults: userDefaults
        )

        XCTAssertEqual(headers["X-OpenWriting-Account-ID"], "userid")
        let installationID = headers["X-OpenWriting-Installation-ID"] ?? ""
        XCTAssertNotNil(UUID(uuidString: installationID))
    }

    func testModelBaseURLRequiresHTTPSExceptForLoopbackDevelopment() {
        XCTAssertNil(
            ModelConnectionConfigurationStore.normalizedBaseURLString(
                from: "http://api.example.com/v1"
            )
        )
        XCTAssertEqual(
            ModelConnectionConfigurationStore.normalizedBaseURLString(
                from: "http://localhost:8080/v1/"
            ),
            "http://localhost:8080/v1"
        )
        XCTAssertEqual(
            ModelConnectionConfigurationStore.normalizedBaseURLString(
                from: "http://127.0.0.1:8080"
            ),
            "http://127.0.0.1:8080/v1"
        )
        XCTAssertEqual(
            ModelConnectionConfigurationStore.normalizedBaseURLString(
                from: "http://[::1]:8080/v1"
            ),
            "http://[::1]:8080/v1"
        )
        XCTAssertEqual(
            ModelConnectionConfigurationStore.normalizedBaseURLString(
                from: "https://api.example.com/v1/"
            ),
            "https://api.example.com/v1"
        )
    }

    func testCommerceEntitlementDefaultsToFreeWhenAppleCommerceIsDeferred() {
        let timestamp = Date(timeIntervalSince1970: 1_772_000_000)

        let snapshot = CommerceEntitlementSnapshot.localDefault(updatedAt: timestamp)

        XCTAssertEqual(snapshot.tier, .free)
        XCTAssertEqual(snapshot.status, .notConfigured)
        XCTAssertEqual(snapshot.source, .localDefault)
        XCTAssertFalse(snapshot.grantsPaidAccess)
        XCTAssertEqual(snapshot.updatedAt, timestamp)
    }

    func testDeferredAppleCommerceProviderDoesNotStartOnlinePayment() async {
        let provider = DeferredAppleCommerceProvider {
            Date(timeIntervalSince1970: 1_772_000_000)
        }

        let entitlement = await provider.currentEntitlements(accountID: "apple-user")
        let outcome = await provider.purchase(
            CommercePurchaseRequest(productID: "future.product", expectedTier: .authorPro),
            accountID: "apple-user"
        )
        let restored = await provider.restorePurchases(accountID: "apple-user")

        XCTAssertEqual(entitlement, .localDefault(updatedAt: Date(timeIntervalSince1970: 1_772_000_000)))
        XCTAssertEqual(restored, entitlement)
        XCTAssertEqual(outcome, .unavailable(reason: DeferredAppleCommerceProvider.unavailableReason))
        XCTAssertTrue(AppleCommerceProductCatalog.storeKitIntegrationIsDeferred)
        XCTAssertTrue(AppleCommerceProductCatalog.reservedProducts.isEmpty)
    }

    @MainActor
    func testRetiredOpenWDefaultBaseURLMigratesToServerManagedBackend() {
        let userDefaults = makeIsolatedUserDefaults()
        let retiredDefaultBaseURL = "https://ai." + "xxread.top/v1"
        userDefaults.set(retiredDefaultBaseURL, forKey: AppState.StorageKey.baseURL)

        AppState.migrateRetiredOpenAICompatibleDefaults(userDefaults)

        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.baseURL), "https://openwriting.kralplus.asia/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralplus.asia/api/model/v1")
    }

    @MainActor
    func testPreviousKralAPIBaseURLMigratesToServerManagedBackend() {
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set("https://kralapi.kralai.tech/v1", forKey: AppState.StorageKey.baseURL)

        AppState.migrateRetiredOpenAICompatibleDefaults(userDefaults)

        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.baseURL), "https://openwriting.kralplus.asia/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralplus.asia/api/model/v1")
    }

    @MainActor
    func testLegacyCustomKralAPIProviderMigratesToServerManagedOpenWriting() {
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set(ModelProvider.custom.rawValue, forKey: AppState.StorageKey.selectedProvider)
        userDefaults.set("gpt-5.4-mini", forKey: AppState.StorageKey.customModelName)
        userDefaults.set("https://kralapi.kralai.tech/v1", forKey: AppState.StorageKey.customBaseURL)

        AppState.migrateRetiredOpenAICompatibleDefaults(userDefaults)

        XCTAssertEqual(ModelConnectionConfigurationStore.loadSelectedProvider(userDefaults: userDefaults), .openAICompatible)
        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.selectedProvider), ModelProvider.openAICompatible.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.baseURL), "https://openwriting.kralplus.asia/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralplus.asia/api/model/v1")
    }

    @MainActor
    func testPreviousOpenWritingBaseURLMigratesToWorkingServerManagedBackend() {
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set("https://openwriting.kralai.tech/api/model/v1", forKey: AppState.StorageKey.baseURL)

        AppState.migrateRetiredOpenAICompatibleDefaults(userDefaults)

        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.baseURL), "https://openwriting.kralplus.asia/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralplus.asia/api/model/v1")
    }

    // MARK: - ConnectionStatus Tests

    func testConnectionStatusIdle() {
        let status = ConnectionStatus.idle
        XCTAssertEqual(status.label, "等待配置")
        XCTAssertEqual(status.symbolName, "circle.dashed")
    }

    func testConnectionStatusChecking() {
        let status = ConnectionStatus.checking
        XCTAssertEqual(status.label, "正在验证")
        XCTAssertEqual(status.symbolName, "arrow.triangle.2.circlepath.circle.fill")
    }

    func testConnectionStatusReady() {
        let status = ConnectionStatus.ready
        XCTAssertEqual(status.label, "配置就绪")
        XCTAssertEqual(status.symbolName, "checkmark.seal.fill")
    }

    func testConnectionStatusNeedsAttention() {
        let status = ConnectionStatus.needsAttention
        XCTAssertEqual(status.label, "需要检查")
        XCTAssertEqual(status.symbolName, "exclamationmark.triangle.fill")
    }

    // MARK: - ChapterDraftSaveResult Tests

    func testChapterDraftSaveResultCreated() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "测试",
            content: "内容"
        )
        let result = ChapterDraftSaveResult.created(draft)

        switch result {
        case .created(let d):
            XCTAssertEqual(d.chapterTitle, "测试")
        case .updated:
            XCTFail("Expected .created but got .updated")
        }
    }

    func testChapterDraftSaveResultUpdated() {
        let draft = ChapterDraft(
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "测试",
            content: "内容"
        )
        let result = ChapterDraftSaveResult.updated(draft)

        switch result {
        case .created:
            XCTFail("Expected .updated but got .created")
        case .updated(let d):
            XCTAssertEqual(d.chapterTitle, "测试")
        }
    }

    // MARK: - ReferenceMaterialCategory Tests

    func testReferenceMaterialCategoryTitles() {
        XCTAssertEqual(ReferenceMaterialCategory.character.title, "人物")
        XCTAssertEqual(ReferenceMaterialCategory.location.title, "地点")
        XCTAssertEqual(ReferenceMaterialCategory.organization.title, "组织")
        XCTAssertEqual(ReferenceMaterialCategory.worldbuilding.title, "世界观")
        XCTAssertEqual(ReferenceMaterialCategory.plot.title, "剧情")
        XCTAssertEqual(ReferenceMaterialCategory.research.title, "考据")
        XCTAssertEqual(ReferenceMaterialCategory.reference.title, "参考")
    }

    func testReferenceMaterialCategoryInference() {
        // Character inference
        XCTAssertEqual(
            ReferenceMaterialCategory.infer(fromTitle: "主角设定", content: ""),
            .character
        )
        XCTAssertEqual(
            ReferenceMaterialCategory.infer(fromTitle: "配角资料", content: ""),
            .character
        )

        // Location inference
        XCTAssertEqual(
            ReferenceMaterialCategory.infer(fromTitle: "地图", content: "城市"),
            .location
        )

        // Organization inference
        XCTAssertEqual(
            ReferenceMaterialCategory.infer(fromTitle: "宗门设定", content: ""),
            .organization
        )
        XCTAssertEqual(
            ReferenceMaterialCategory.infer(fromTitle: "公司资料", content: ""),
            .organization
        )

        // Worldbuilding inference
        XCTAssertEqual(
            ReferenceMaterialCategory.infer(fromTitle: "世界观", content: ""),
            .worldbuilding
        )

        // Default case
        XCTAssertEqual(
            ReferenceMaterialCategory.infer(fromTitle: "未知标题", content: ""),
            .reference
        )
    }

    // MARK: - PersistedTimestampCodec Tests

    func testPersistedTimestampCodecRoundTrip() {
        let now = Date()
        let timestamp = ISO8601DateFormatter().string(from: now)
        let decoded = PersistedTimestampCodec.parse(timestamp)

        // Allow 1 second tolerance
        XCTAssertNotNil(decoded)
        if let decoded = decoded {
            XCTAssertEqual(Int(decoded.timeIntervalSince1970), Int(now.timeIntervalSince1970))
        }
    }

    func testPersistedTimestampCodecFromDouble() {
        let doubleValue: Double = 1704067200
        let decoded = PersistedTimestampCodec.parse(String(doubleValue))

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.timeIntervalSince1970, doubleValue)
    }

    func testPersistedTimestampCodecFromInt() {
        let intValue: Int = 1704067200
        let decoded = PersistedTimestampCodec.parse(String(intValue))

        XCTAssertNotNil(decoded)
    }

    func testPersistedTimestampCodecParsesLegacyDateLabels() {
        let dateOnly = PersistedTimestampCodec.parse("2026-06-06")
        let chineseDateTime = PersistedTimestampCodec.parse("2026年6月6日 14:30")
        let currentYearDisplay = PersistedTimestampCodec.parse("6月6日 14:30")

        XCTAssertNotNil(dateOnly)
        XCTAssertNotNil(chineseDateTime)
        XCTAssertNotNil(currentYearDisplay)
    }

    // MARK: - OutlineGenerationProfile Tests

    func testOutlineGenerationProfileCompletion() {
        let profile = OutlineGenerationProfile(
            storyFlow: "故事流程",
            worldDescription: "世界观描述",
            protagonistTraits: "主角特征",
            expectedLength: "预期长度",
            endingPreference: "结局偏好"
        )

        XCTAssertEqual(profile.completedRequiredFieldCount, 5)
        XCTAssertTrue(profile.hasMinimumRequirements)
        XCTAssertEqual(profile.missingRequiredFieldLabels.count, 0)
    }

    func testOutlineGenerationProfileMissingFields() {
        let profile = OutlineGenerationProfile(
            storyFlow: "故事流程",
            worldDescription: "", // Missing
            protagonistTraits: "", // Missing
            expectedLength: "", // Missing
            endingPreference: ""  // Missing
        )

        XCTAssertEqual(profile.completedRequiredFieldCount, 1)
        XCTAssertFalse(profile.hasMinimumRequirements)
        XCTAssertEqual(profile.missingRequiredFieldLabels.count, 4)
    }

    func testOutlineGenerationProfileOptionalFields() {
        let profile = OutlineGenerationProfile(
            storyFlow: "故事流程",
            worldDescription: "世界观",
            protagonistTraits: "主角",
            expectedLength: "长度",
            endingPreference: "结局",
            sellingPoints: "卖点",
            keyEvents: "关键事件",
            storyPacing: "节奏",
            motivations: "动机",
            relationshipMap: "关系图",
            antagonistPortrait: "反派描述",
            foreshadowingNotes: "伏笔"
        )

        XCTAssertEqual(profile.filledOptionalFieldCount, 7)
    }

    func testPersistedTimestampCodecRejectsAmbiguousSmallEpochNumbers() {
        XCTAssertNil(PersistedTimestampCodec.parse("2026"))
        XCTAssertNotNil(PersistedTimestampCodec.parse("1717603200"))
    }

    func testLegacyNovelProjectPayloadDecodesWithCurrentSchemaAndTimestampFallbacks() throws {
        let legacyJSON = """
        {
          "id": "legacy-project",
          "title": "旧项目",
          "genre": "玄幻",
          "summary": "旧版本保存的项目",
          "currentChapterNumber": 3,
          "writtenChapters": 2,
          "chapterDrafts": [
            {
              "id": "chapter-without-saved-at",
              "chapterNumber": 2,
              "chapterTitle": "旧章",
              "content": "旧章节正文"
            }
          ],
          "referenceDocuments": [
            {
              "id": "reference-without-imported-at",
              "title": "人物设定",
              "content": "沈青袖持有玄铁令"
            }
          ],
          "continuityNotes": "人物关系\\n- 沈青袖与陆白互相信任"
        }
        """

        let project = try JSONDecoder().decode(NovelProject.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(project.schemaVersion, NovelProject.currentSchemaVersion)
        XCTAssertEqual(project.id, "legacy-project")
        XCTAssertEqual(project.storyLength, .long)
        XCTAssertEqual(project.currentChapterTitle, "开篇设定")
        XCTAssertEqual(project.chapterDrafts.first?.chapterTitle, "旧章")
        XCTAssertEqual(project.referenceDocuments.first?.category, .character)
        XCTAssertTrue(project.globalMemorySnapshot.hasStructuredContent)
        XCTAssertFalse(project.updatedAt.isEmpty)
        XCTAssertFalse(project.chapterDrafts.first?.savedAt.isEmpty ?? true)
        XCTAssertFalse(project.referenceDocuments.first?.importedAt.isEmpty ?? true)
    }

    func testProjectDocumentCodecMigratesLegacyPayloadAndRejectsFutureSchema() throws {
        let legacyJSON = """
        {
          "id": "legacy-project",
          "title": "旧项目",
          "genre": "玄幻",
          "summary": "旧版本保存的项目"
        }
        """

        let decoded = try ProjectDocumentCodec().decode(Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.sourceVersion, 1)
        XCTAssertTrue(decoded.didMigrate)
        XCTAssertEqual(decoded.project.schemaVersion, NovelProject.currentSchemaVersion)

        let futureJSON = """
        {
          "schemaVersion": \(NovelProject.currentSchemaVersion + 1),
          "id": "future-project",
          "title": "未来项目",
          "genre": "科幻",
          "summary": "未来版本保存的项目"
        }
        """

        XCTAssertThrowsError(try ProjectDocumentCodec().decode(Data(futureJSON.utf8))) { error in
            XCTAssertEqual(
                error as? ProjectDocumentCodecError,
                .unsupportedFutureVersion(NovelProject.currentSchemaVersion + 1)
            )
        }
    }

    func testAccountProjectSnapshotRejectsFutureSchema() throws {
        let futureJSON = """
        {
          "schemaVersion": \(AccountProjectSnapshot.currentSchemaVersion + 1),
          "activeProjectID": null,
          "recentProjects": [],
          "updatedAt": "2026-07-17T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(try decoder.decode(AccountProjectSnapshot.self, from: Data(futureJSON.utf8)))
    }

    func testAccountProjectSnapshotMigratesV1WithoutDeletionTombstones() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "activeProjectID": null,
          "recentProjects": [],
          "updatedAt": "2026-07-17T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(
            AccountProjectSnapshot.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(snapshot.schemaVersion, AccountProjectSnapshot.currentSchemaVersion)
        XCTAssertTrue(snapshot.deletedProjects.isEmpty)
    }

    func testAccountProjectSnapshotNormalizesDeletionTombstonesDeterministically() throws {
        let older = ProjectDeletionTombstone(
            projectID: "project-b",
            deletedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        let newer = ProjectDeletionTombstone(
            projectID: "project-b",
            deletedAt: Date(timeIntervalSince1970: 1_772_000_100)
        )
        let first = ProjectDeletionTombstone(
            projectID: " project-a ",
            deletedAt: Date(timeIntervalSince1970: 1_772_000_050)
        )
        let snapshot = AccountProjectSnapshot(
            activeProjectID: nil,
            recentProjects: [],
            deletedProjects: [older, newer, first],
            updatedAt: Date(timeIntervalSince1970: 1_772_000_200)
        )

        XCTAssertEqual(snapshot.deletedProjects.map(\.projectID), ["project-a", "project-b"])
        XCTAssertEqual(snapshot.deletedProjects.last?.deletedAt, newer.deletedAt)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            AccountProjectSnapshot.self,
            from: encoder.encode(snapshot)
        )
        XCTAssertEqual(decoded.deletedProjects, snapshot.deletedProjects)
    }

    func testCloudProjectJSONCodingUsesFractionalUTCAndReadsLegacyDateForms() throws {
        struct DateProbe: Codable {
            let value: Date
        }

        let expected = Date(timeIntervalSince1970: 1_710_000_000.125)
        let encoded = try CloudProjectJSONCoding.makeEncoder().encode(
            DateProbe(value: expected)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(
            object["value"] as? String,
            "2024-03-09T16:00:00.125Z"
        )

        let decoder = CloudProjectJSONCoding.makeDecoder()
        let fractional = try decoder.decode(
            DateProbe.self,
            from: Data(#"{"value":"2024-03-09T16:00:00.125Z"}"#.utf8)
        )
        let wholeSecond = try decoder.decode(
            DateProbe.self,
            from: Data(#"{"value":"2024-03-09T16:00:00Z"}"#.utf8)
        )
        let epoch = try decoder.decode(
            DateProbe.self,
            from: Data(#"{"value":1710000000.125}"#.utf8)
        )

        XCTAssertEqual(
            fractional.value.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            wholeSecond.value.timeIntervalSince1970,
            1_710_000_000,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            epoch.value.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 0.000_001
        )
    }

    func testDeletionSnapshotAndCloudKitFieldNamesMatchCrossPlatformContract() throws {
        let snapshot = AccountProjectSnapshot(
            activeProjectID: nil,
            recentProjects: [],
            deletedProjects: [
                ProjectDeletionTombstone(
                    projectID: "project-a",
                    deletedAt: Date(timeIntervalSince1970: 1_710_000_000.125)
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 1_710_000_001)
        )
        let data = try CloudProjectJSONCoding.makeEncoder().encode(snapshot)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertNotNil(object["deletedProjects"])
        XCTAssertNil(object["projectDeletionTombstones"])
        XCTAssertEqual(
            ICloudProjectStore.deletedProjectIDsFieldName,
            "deletedProjectIDs"
        )
        XCTAssertEqual(
            ICloudProjectStore.deletedProjectDatesFieldName,
            "deletedProjectDates"
        )
        XCTAssertEqual(
            CloudProjectPayloadCodec.deletionTombstoneRevisionComponent(
                snapshot.deletedProjects[0]
            ),
            "deleted:project-a:1710000000.125"
        )
    }

    @MainActor
    func testAppStateAcceptsInjectedAIService() {
        let userDefaults = makeIsolatedUserDefaults()
        let store = makeIsolatedProjectStore()
        let aiService = MockAIWritingService()

        let appState = AppState(
            userDefaults: userDefaults,
            projectStore: store,
            aiService: aiService,
            credentialStore: makeCredentialStore()
        )

        XCTAssertTrue(appState.aiService is MockAIWritingService)
    }

    @MainActor
    func testAppleCredentialStateLookupFailureFailsClosed() async {
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: makeIsolatedProjectStore(),
            credentialStore: makeCredentialStore(),
            appleCredentialStateProvider: FailingAppleCredentialStateProvider()
        )
        let account = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        appState.activeAccount = account

        let isAuthorized = await appState.refreshActiveAppleCredentialState()

        XCTAssertFalse(isAuthorized)
        XCTAssertEqual(appState.activeAccount, account)
        XCTAssertEqual(appState.cloudSyncTitle, "本机保存")
        XCTAssertEqual(appState.cloudSyncSymbolName, "icloud.slash")
    }

    @MainActor
    func testLogoutWithLocalCleanupCancelsPendingAccountPersistence() async throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = makeIsolatedProjectStore()
        let account = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        let project = makeProject(
            id: "account-project",
            title: "账号项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        let encodedProjects = try JSONEncoder().encode([project])
        userDefaults.set(project.id, forKey: AppState.activeProjectIDStorageKey(for: account.userID))
        userDefaults.set(encodedProjects, forKey: AppState.recentProjectsStorageKey(for: account.userID))
        userDefaults.set(1_772_000_000.0, forKey: AppState.projectSnapshotTimestampStorageKey(for: account.userID))

        let appState = AppState(
            userDefaults: userDefaults,
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        appState.activeAccount = account
        appState.recentProjects = [project]

        let didLogout = await appState.logoutAccount(removingLocalData: true)
        XCTAssertTrue(didLogout)
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertNil(store.loadProjects(for: account.userID))
        XCTAssertNil(userDefaults.object(forKey: AppState.activeProjectIDStorageKey(for: account.userID)))
        XCTAssertNil(userDefaults.object(forKey: AppState.recentProjectsStorageKey(for: account.userID)))
        XCTAssertNil(userDefaults.object(forKey: AppState.projectSnapshotTimestampStorageKey(for: account.userID)))
        XCTAssertNil(appState.activeAccount)
    }

    @MainActor
    func testLogoutFlushesPendingAccountProjectsBeforeSwitchingScope() async throws {
        let store = makeIsolatedProjectStore()
        let account = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        let project = makeProject(
            id: "pending-account-project",
            title: "退出前保存",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        appState.activeAccount = account
        appState.recentProjects = [project]

        let didLogout = await appState.logoutAccount()
        XCTAssertTrue(didLogout)
        XCTAssertEqual(store.loadProjects(for: account.userID)?.map(\.id), [project.id])
    }

    @MainActor
    func testAccountBindingFlushesLocalProjectsBeforeCopyingScope() async throws {
        let store = makeIsolatedProjectStore()
        let project = makeProject(
            id: "pending-local-project",
            title: "登录前保存",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        let account = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        appState.recentProjects = [project]

        let didBind = await appState.bindAppleAccount(account)
        XCTAssertTrue(didBind)
        XCTAssertEqual(store.loadProjects(for: account.userID)?.map(\.id), [project.id])
    }

    @MainActor
    func testRecentProjectsAutosavePersistsThroughActor() async throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = makeIsolatedProjectStore()
        let appState = AppState(
            userDefaults: userDefaults,
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        let project = makeProject(
            id: "actor-autosave-project",
            title: "后台保存项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )

        appState.recentProjects = [project]
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(store.loadProjects(for: nil)?.map(\.title), ["后台保存项目"])
    }

    @MainActor
    func testExplicitChapterSaveReturnsOnlyAfterChapterIsOnDisk() async throws {
        let store = makeIsolatedProjectStore()
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        var project = makeProject(
            id: "explicit-save-project",
            title: "显式保存",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        project.draftText = "必须在返回成功前写入磁盘。"
        appState.recentProjects = [project]

        let result = await appState.saveCurrentChapterDraft(for: project.id)

        let savedChapter = try XCTUnwrap(result?.chapterDraft)
        XCTAssertEqual(
            store.loadChapterDraft(savedChapter.id, for: project.id, scope: nil)?.content,
            project.draftText
        )
    }

    @MainActor
    func testRecentProjectsAutosaveFreezesReferenceBackedStateAtActorBoundary() async throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = makeIsolatedProjectStore()
        let appState = AppState(
            userDefaults: userDefaults,
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        let project = makeProject(
            id: "actor-reference-snapshot-project",
            title: "引用隔离项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        project.strandWeaveTracker.recordChapter(ChapterStrandRecord(
            chapterNumber: 1,
            primaryStrand: .quest
        ))

        appState.recentProjects = [project]
        project.strandWeaveTracker.recordChapter(ChapterStrandRecord(
            chapterNumber: 2,
            primaryStrand: .fire
        ))
        try await Task.sleep(for: .milliseconds(350))

        let persistedProject = try XCTUnwrap(store.loadProjects(for: nil)?.first)
        XCTAssertEqual(persistedProject.strandWeaveTracker.records.map(\.chapterNumber), [1])
    }

    @MainActor
    func testLogoutInvalidatesPendingCloudSaveGeneration() async {
        let userDefaults = makeIsolatedUserDefaults()
        let store = makeIsolatedProjectStore()
        let account = AppleAccountProfile(
            userID: "apple-user-\(UUID().uuidString)",
            email: "writer@example.com",
            fullName: "Writer"
        )
        let appState = AppState(
            userDefaults: userDefaults,
            projectStore: store,
            credentialStore: makeCredentialStore()
        )
        appState.activeAccount = account
        appState.cloudSaveGeneration = 41

        let didLogout = await appState.logoutAccount()
        XCTAssertTrue(didLogout)

        XCTAssertNil(appState.cloudSaveTask)
        XCTAssertGreaterThan(appState.cloudSaveGeneration, 41)
        XCTAssertNil(appState.activeAccount)
    }

    func testCloudKitRecordPlanScopesSnapshotRecordsByAccount() {
        var project = makeProject(
            id: "shared-project",
            title: "共享项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        project.chapterDrafts = [
            ChapterDraft(
                id: "chapter-1",
                chapterNumber: 1,
                chapterTitle: "第一章",
                content: "正文"
            )
        ]
        let snapshot = AccountProjectSnapshot(
            activeProjectID: project.id,
            recentProjects: [project],
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )

        let firstAccountPlan = ICloudProjectStore.cloudKitRecordPlan(for: snapshot, scope: "apple-user-1")
        let secondAccountPlan = ICloudProjectStore.cloudKitRecordPlan(for: snapshot, scope: "apple-user-2")

        XCTAssertEqual(firstAccountPlan.snapshotRecordName, "snapshot_apple-user-1")
        XCTAssertEqual(firstAccountPlan.projectRecordNames, ["project_apple-user-1_shared-project"])
        XCTAssertEqual(firstAccountPlan.chapterRecordNames, ["chapter_apple-user-1_shared-project_chapter-1"])
        XCTAssertTrue(firstAccountPlan.deletedRecordNames.isEmpty)
        XCTAssertNotEqual(firstAccountPlan.snapshotRecordName, secondAccountPlan.snapshotRecordName)
        XCTAssertNotEqual(firstAccountPlan.projectRecordNames, secondAccountPlan.projectRecordNames)
        XCTAssertNotEqual(firstAccountPlan.chapterRecordNames, secondAccountPlan.chapterRecordNames)
    }

    func testRevisionQualifiedCloudKitRecordNamesMatchIOSContractAndLegacyLayout() {
        let indexRecord = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_apple_user")
        )
        indexRecord["payloadRevision"] = "revision-7" as NSString

        XCTAssertEqual(ICloudProjectStore.payloadRevision(from: indexRecord), "revision-7")
        XCTAssertEqual(
            ICloudProjectStore.projectRecordName(
                for: "project-1",
                scope: "apple user",
                revision: "revision-7"
            ),
            "project_apple_user_revision-7_project-1"
        )
        XCTAssertEqual(
            ICloudProjectStore.chapterRecordName(
                for: "chapter-1",
                projectID: "project-1",
                scope: "apple user",
                revision: "revision-7"
            ),
            "chapter_apple_user_revision-7_project-1_chapter-1"
        )
        XCTAssertEqual(
            ICloudProjectStore.projectRecordName(for: "project-1", scope: "apple user"),
            "project_apple_user_project-1"
        )
    }

    func testIndexedCloudKitReaderUsesRevisionAndLegacyRecordFixtures() throws {
        let scope = "apple user"
        let revisionIndex = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_apple_user")
        )
        revisionIndex["projectIDs"] = ["project-1"] as NSArray
        revisionIndex["payloadRevision"] = "revision-7" as NSString
        let revisionProjectID = try XCTUnwrap(
            ICloudProjectStore.indexedProjectRecordIDs(from: revisionIndex, scope: scope)?.first
        )
        let revisionProject = CKRecord(recordType: "ProjectPayload", recordID: revisionProjectID)
        revisionProject["chapterIDs"] = ["chapter-1"] as NSArray

        XCTAssertEqual(revisionProjectID.recordName, "project_apple_user_revision-7_project-1")
        XCTAssertEqual(
            try ICloudProjectStore.indexedChapterRecordIDs(
                from: [revisionProjectID: revisionProject],
                indexRecord: revisionIndex,
                scope: scope
            ).map(\.recordName),
            ["chapter_apple_user_revision-7_project-1_chapter-1"]
        )

        let legacyIndex = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_apple_user")
        )
        legacyIndex["projectIDs"] = ["project-1"] as NSArray
        XCTAssertEqual(
            ICloudProjectStore.indexedProjectRecordIDs(from: legacyIndex, scope: scope)?.map(\.recordName),
            ["project_apple_user_project-1"]
        )
    }

    func testIndexedCloudKitReaderUsesExplicitContentAddressedManifest() throws {
        let index = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_scope")
        )
        index["projectIDs"] = ["project-1", "project-2"] as NSArray
        index["projectRecordNames"] = [
            "project_scope_sha256-one_project-1",
            "project_scope_sha256-two_project-2"
        ] as NSArray
        index["payloadRevision"] = "sha256-manifest" as NSString

        let projectRecordIDs = try XCTUnwrap(
            ICloudProjectStore.indexedProjectRecordIDs(from: index, scope: "scope")
        )
        let firstProject = CKRecord(recordType: "ProjectPayload", recordID: projectRecordIDs[0])
        firstProject["chapterIDs"] = ["chapter-1", "chapter-2"] as NSArray
        firstProject["chapterRecordNames"] = [
            "chapter_scope_sha256-a_project-1_chapter-1",
            "chapter_scope_sha256-b_project-1_chapter-2"
        ] as NSArray
        let secondProject = CKRecord(recordType: "ProjectPayload", recordID: projectRecordIDs[1])
        secondProject["chapterIDs"] = ["chapter-3"] as NSArray
        secondProject["chapterRecordNames"] = [
            "chapter_scope_sha256-c_project-2_chapter-3"
        ] as NSArray

        XCTAssertEqual(
            try ICloudProjectStore.indexedChapterRecordIDs(
                from: [
                    projectRecordIDs[0]: firstProject,
                    projectRecordIDs[1]: secondProject
                ],
                indexRecord: index,
                scope: "scope"
            ).map(\.recordName),
            [
                "chapter_scope_sha256-a_project-1_chapter-1",
                "chapter_scope_sha256-b_project-1_chapter-2",
                "chapter_scope_sha256-c_project-2_chapter-3"
            ]
        )
    }

    func testIndexedCloudKitReaderRejectsMismatchedExplicitManifestCounts() throws {
        let index = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_scope")
        )
        index["projectIDs"] = ["project-1", "project-2"] as NSArray
        index["projectRecordNames"] = ["project-only-one"] as NSArray
        XCTAssertNil(ICloudProjectStore.indexedProjectRecordIDs(from: index, scope: "scope"))

        index["projectIDs"] = ["project-1"] as NSArray
        index["projectRecordNames"] = ["project-explicit"] as NSArray
        let projectRecordID = CKRecord.ID(recordName: "project-explicit")
        let project = CKRecord(recordType: "ProjectPayload", recordID: projectRecordID)
        project["chapterIDs"] = ["chapter-1", "chapter-2"] as NSArray
        project["chapterRecordNames"] = ["chapter-only-one"] as NSArray

        XCTAssertThrowsError(
            try ICloudProjectStore.indexedChapterRecordIDs(
                from: [projectRecordID: project],
                indexRecord: index,
                scope: "scope"
            )
        ) { error in
            guard case ICloudProjectStore.StoreError.missingPayload = error else {
                return XCTFail("Expected missingPayload, got \(error)")
            }
        }
    }

    func testIndexedCloudKitReaderRejectsDuplicateManifestEntries() throws {
        let index = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_scope")
        )
        index["projectIDs"] = ["project-1", "project-1"] as NSArray
        index["projectRecordNames"] = ["project-a", "project-b"] as NSArray
        XCTAssertNil(ICloudProjectStore.indexedProjectRecordIDs(from: index, scope: "scope"))

        index["projectIDs"] = ["project-1"] as NSArray
        index["projectRecordNames"] = ["project-a"] as NSArray
        let projectRecordID = CKRecord.ID(recordName: "project-a")
        let project = CKRecord(recordType: "ProjectPayload", recordID: projectRecordID)
        project["chapterIDs"] = ["chapter-1", "chapter-1"] as NSArray
        project["chapterRecordNames"] = ["chapter-a", "chapter-b"] as NSArray

        XCTAssertThrowsError(
            try ICloudProjectStore.indexedChapterRecordIDs(
                from: [projectRecordID: project],
                indexRecord: index,
                scope: "scope"
            )
        )
    }

    func testIndexedCloudKitReaderRejectsBlankManifestEntries() throws {
        let index = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_scope")
        )
        index["projectIDs"] = ["   "] as NSArray
        index["projectRecordNames"] = ["project-a"] as NSArray
        XCTAssertNil(ICloudProjectStore.indexedProjectRecordIDs(from: index, scope: "scope"))

        index["projectIDs"] = ["project-1"] as NSArray
        index["projectRecordNames"] = ["\n"] as NSArray
        XCTAssertNil(ICloudProjectStore.indexedProjectRecordIDs(from: index, scope: "scope"))

        index["projectRecordNames"] = ["project-a"] as NSArray
        let projectRecordID = CKRecord.ID(recordName: "project-a")
        let project = CKRecord(recordType: "ProjectPayload", recordID: projectRecordID)
        project["chapterIDs"] = ["\t"] as NSArray
        project["chapterRecordNames"] = ["chapter-a"] as NSArray
        XCTAssertThrowsError(
            try ICloudProjectStore.indexedChapterRecordIDs(
                from: [projectRecordID: project],
                indexRecord: index,
                scope: "scope"
            )
        )

        project["chapterIDs"] = ["chapter-1"] as NSArray
        project["chapterRecordNames"] = ["  "] as NSArray
        XCTAssertThrowsError(
            try ICloudProjectStore.indexedChapterRecordIDs(
                from: [projectRecordID: project],
                indexRecord: index,
                scope: "scope"
            )
        )
    }

    func testCloudKitDeletionTombstoneManifestRequiresAlignedUniqueFields() throws {
        let index = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_scope")
        )
        XCTAssertEqual(try ICloudProjectStore.deletionTombstones(from: index), [])

        index["deletedProjectIDs"] = ["project-b", "project-a"] as NSArray
        index["deletedProjectDates"] = [
            Date(timeIntervalSince1970: 1_772_000_100) as NSDate,
            Date(timeIntervalSince1970: 1_772_000_000) as NSDate
        ] as NSArray
        XCTAssertEqual(
            try ICloudProjectStore.deletionTombstones(from: index).map(\.projectID),
            ["project-a", "project-b"]
        )

        index["deletedProjectDates"] = [
            Date(timeIntervalSince1970: 1_772_000_100) as NSDate
        ] as NSArray
        XCTAssertThrowsError(try ICloudProjectStore.deletionTombstones(from: index))

        index["deletedProjectIDs"] = ["project-a", "project-a"] as NSArray
        index["deletedProjectDates"] = [
            Date(timeIntervalSince1970: 1_772_000_000) as NSDate,
            Date(timeIntervalSince1970: 1_772_000_100) as NSDate
        ] as NSArray
        XCTAssertThrowsError(try ICloudProjectStore.deletionTombstones(from: index))
    }

    func testCloudKitCleanupKeepsOnlyTrueDeletionFailures() {
        let successID = CKRecord.ID(recordName: "success")
        let alreadyDeletedID = CKRecord.ID(recordName: "already-deleted")
        let failedID = CKRecord.ID(recordName: "failed")
        let missingResultID = CKRecord.ID(recordName: "missing-result")
        let unknownItem = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.unknownItem.rawValue
        )
        let realFailure = NSError(domain: "OpenWritingTests", code: 1)
        let results: [CKRecord.ID: Result<Void, Error>] = [
            successID: .success(()),
            alreadyDeletedID: .failure(unknownItem),
            failedID: .failure(realFailure)
        ]

        XCTAssertEqual(
            ICloudProjectStore.failedDeletionRecordIDs(
                results,
                expected: [successID, alreadyDeletedID, failedID, missingResultID]
            ).map(\.recordName),
            ["failed", "missing-result"]
        )
    }

    func testContentAddressedUploadPlanChangesOnlyOneChapterAndOwningProject() throws {
        func chapterTarget(
            projectID: String,
            chapterID: String,
            payload: String
        ) -> ContentAddressedPayloadTarget {
            let hash = CloudProjectPayloadCodec.payloadHash(for: Data(payload.utf8))
            let revision = CloudProjectPayloadCodec.chapterRevision(payloadHash: hash)
            return ContentAddressedPayloadTarget(
                recordID: CKRecord.ID(
                    recordName: ICloudProjectStore.chapterRecordName(
                        for: chapterID,
                        projectID: projectID,
                        scope: "scope",
                        revision: revision
                    )
                ),
                payloadHash: hash
            )
        }

        func projectTarget(
            projectID: String,
            payload: String,
            chapters: [(String, ContentAddressedPayloadTarget)]
        ) -> ContentAddressedPayloadTarget {
            let hash = CloudProjectPayloadCodec.payloadHash(for: Data(payload.utf8))
            let revision = CloudProjectPayloadCodec.projectRevision(
                payloadHash: hash,
                chapterReferences: chapters.map {
                    (chapterID: $0.0, recordName: $0.1.recordID.recordName)
                }
            )
            return ContentAddressedPayloadTarget(
                recordID: CKRecord.ID(
                    recordName: ICloudProjectStore.projectRecordName(
                        for: projectID,
                        scope: "scope",
                        revision: revision
                    )
                ),
                payloadHash: hash
            )
        }

        let oldA1 = chapterTarget(projectID: "project-a", chapterID: "a1", payload: "old-a1")
        let newA1 = chapterTarget(projectID: "project-a", chapterID: "a1", payload: "new-a1")
        let a2 = chapterTarget(projectID: "project-a", chapterID: "a2", payload: "same-a2")
        let b1 = chapterTarget(projectID: "project-b", chapterID: "b1", payload: "same-b1")
        let oldProjectA = projectTarget(
            projectID: "project-a",
            payload: "project-a",
            chapters: [("a1", oldA1), ("a2", a2)]
        )
        let newProjectA = projectTarget(
            projectID: "project-a",
            payload: "project-a",
            chapters: [("a1", newA1), ("a2", a2)]
        )
        let projectB = projectTarget(
            projectID: "project-b",
            payload: "project-b",
            chapters: [("b1", b1)]
        )
        let desired = [newProjectA, projectB, newA1, a2, b1]
        let existing = [oldProjectA, projectB, oldA1, a2, b1]
        let existingIDs = Set(existing.map(\.recordID))
        let existingHashes = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.recordID, $0.payloadHash) }
        )

        let plan = try ContentAddressedUploadPlan.build(
            desired: desired,
            existingRecordIDs: existingIDs,
            existingPayloadHashes: existingHashes
        )

        XCTAssertEqual(
            Set(plan.recordIDsToCreate.map(\.recordName)),
            Set([newA1.recordID.recordName, newProjectA.recordID.recordName])
        )
        XCTAssertTrue(plan.publishesIndex)

        let identicalPlan = try ContentAddressedUploadPlan.build(
            desired: desired,
            existingRecordIDs: Set(desired.map(\.recordID)),
            existingPayloadHashes: Dictionary(
                uniqueKeysWithValues: desired.map { ($0.recordID, $0.payloadHash) }
            )
        )
        XCTAssertTrue(identicalPlan.recordIDsToCreate.isEmpty)

        XCTAssertThrowsError(
            try ContentAddressedUploadPlan.build(
                desired: [newA1],
                existingRecordIDs: [newA1.recordID],
                existingPayloadHashes: [newA1.recordID: "corrupt-hash"]
            )
        )
    }

    func testContentAddressedTargetVerifiesAssetBytesAndManifestMetadata() throws {
        let payload = Data("expected".utf8)
        let expectedHash = CloudProjectPayloadCodec.payloadHash(for: payload)
        let recordID = CKRecord.ID(recordName: "project-content-addressed")
        let target = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: expectedHash,
            recordType: "ProjectPayload",
            scope: "scope",
            projectID: "project-1",
            chapterIDs: ["chapter-1"],
            chapterRecordNames: ["chapter-record-1"]
        )
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenWriting-content-address-\(UUID().uuidString).json")
        try Data("corrupt".utf8).write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let record = CKRecord(recordType: "ProjectPayload", recordID: recordID)
        record["scope"] = "scope" as NSString
        record["projectID"] = "project-1" as NSString
        record["chapterIDs"] = ["chapter-1"] as NSArray
        record["chapterRecordNames"] = ["wrong-record-name"] as NSArray
        record["payloadHash"] = expectedHash as NSString
        record["payloadAsset"] = CKAsset(fileURL: assetURL)

        XCTAssertFalse(target.matchesMetadata(in: record))

        record["chapterRecordNames"] = ["chapter-record-1"] as NSArray
        XCTAssertNil(ICloudProjectStore.verifiedExistingPayloadHash(for: record, matching: target))
        XCTAssertThrowsError(
            try ContentAddressedUploadPlan.build(
                desired: [target],
                existingRecordIDs: [recordID],
                existingPayloadHashes: [:]
            )
        )

        try payload.write(to: assetURL, options: .atomic)
        record["payloadHash"] = "wrong-hash" as NSString
        XCTAssertNil(ICloudProjectStore.verifiedExistingPayloadHash(for: record, matching: target))

        record["payloadHash"] = expectedHash as NSString
        XCTAssertEqual(
            ICloudProjectStore.verifiedExistingPayloadHash(for: record, matching: target),
            expectedHash
        )

        let wrongTimestampTarget = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: expectedHash,
            recordType: "ProjectPayload",
            scope: "scope",
            projectID: "project-1",
            updatedAt: Date(timeIntervalSince1970: 1),
            chapterIDs: ["chapter-1"],
            chapterRecordNames: ["chapter-record-1"]
        )
        record["updatedAt"] = Date(timeIntervalSince1970: 2) as NSDate
        XCTAssertNil(
            ICloudProjectStore.verifiedExistingPayloadHash(
                for: record,
                matching: wrongTimestampTarget
            )
        )
    }

    func testContentAddressedMetadataUsesCanonicalMillisecondTimestamp() throws {
        let original = Date(timeIntervalSince1970: 1_710_000_000.123_456)
        let encoded = try CloudProjectJSONCoding.makeEncoder().encode(original)
        let roundTripped = try CloudProjectJSONCoding.makeDecoder().decode(
            Date.self,
            from: encoded
        )
        let recordID = CKRecord.ID(recordName: "canonical-timestamp")
        let record = CKRecord(recordType: "ChapterPayload", recordID: recordID)
        record["updatedAt"] = original as NSDate

        let matchingTarget = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: "hash",
            updatedAt: roundTripped
        )
        XCTAssertTrue(matchingTarget.matchesMetadata(in: record))

        let differentMillisecondTarget = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: "hash",
            updatedAt: roundTripped.addingTimeInterval(0.002)
        )
        XCTAssertFalse(differentMillisecondTarget.matchesMetadata(in: record))
    }

    func testContentAddressedMetadataAcceptsLegacyUnsortedChapterManifest() {
        let recordID = CKRecord.ID(recordName: "legacy-unsorted-manifest")
        let target = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: "hash",
            chapterIDs: ["chapter-a", "chapter-b"],
            chapterRecordNames: ["record-a", "record-b"]
        )
        let record = CKRecord(recordType: "ProjectPayload", recordID: recordID)
        record["chapterIDs"] = ["chapter-b", "chapter-a"] as NSArray
        record["chapterRecordNames"] = ["record-b", "record-a"] as NSArray

        XCTAssertTrue(target.matchesMetadata(in: record))

        record["chapterRecordNames"] = ["record-a", "record-b"] as NSArray
        XCTAssertFalse(target.matchesMetadata(in: record))
    }

    func testContentAddressedMetadataRejectsIncompleteOrInvalidManifestTargets() {
        let recordID = CKRecord.ID(recordName: "incomplete-manifest")
        let record = CKRecord(recordType: "ProjectPayload", recordID: recordID)
        record["chapterIDs"] = ["chapter-a"] as NSArray
        record["chapterRecordNames"] = ["record-a"] as NSArray

        let idsOnly = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: "hash",
            chapterIDs: ["chapter-a"]
        )
        let namesOnly = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: "hash",
            chapterRecordNames: ["record-a"]
        )
        let invalidPair = ContentAddressedPayloadTarget(
            recordID: recordID,
            payloadHash: "hash",
            chapterIDs: [""],
            chapterRecordNames: [""]
        )

        XCTAssertFalse(idsOnly.matchesMetadata(in: record))
        XCTAssertFalse(namesOnly.matchesMetadata(in: record))
        record["chapterIDs"] = [""] as NSArray
        record["chapterRecordNames"] = [""] as NSArray
        XCTAssertFalse(invalidPair.matchesMetadata(in: record))
    }

    @MainActor
    func testTerminationFlushCoordinatorRepliesExactlyOnceAfterSuccessfulFlush() async {
        let coordinator = TerminationFlushCoordinator(timeout: .seconds(1))
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []

        XCTAssertTrue(coordinator.begin(
            flush: { true },
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        ))
        XCTAssertFalse(coordinator.begin(flush: { false }, reply: { _ in
            XCTFail("a duplicate termination request must not install another reply")
        }))

        await fulfillment(of: [replied], timeout: 1)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(replies, [true])
        XCTAssertFalse(coordinator.isRunning)
    }

    @MainActor
    func testTerminationFlushCoordinatorTimesOutAndIgnoresLateCompletion() async {
        let coordinator = TerminationFlushCoordinator(timeout: .milliseconds(20))
        let replied = expectation(description: "timeout reply")
        var replies: [Bool] = []

        XCTAssertTrue(coordinator.begin(
            flush: {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    // Simulate a flush implementation that observes cancellation
                    // but still returns after the timeout reply has won the race.
                }
                return true
            },
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        ))

        await fulfillment(of: [replied], timeout: 1)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(replies, [false])
        XCTAssertFalse(coordinator.isRunning)
    }

    func testIndexedCloudKitReaderRejectsMissingRevisionPayload() throws {
        let index = CKRecord(
            recordType: "ProjectSnapshot",
            recordID: CKRecord.ID(recordName: "snapshot_scope")
        )
        index["projectIDs"] = ["project-1"] as NSArray
        index["payloadRevision"] = "revision-7" as NSString

        XCTAssertThrowsError(
            try ICloudProjectStore.indexedChapterRecordIDs(
                from: [:],
                indexRecord: index,
                scope: "scope"
            )
        ) { error in
            guard case ICloudProjectStore.StoreError.missingPayload = error else {
                return XCTFail("Expected missingPayload, got \(error)")
            }
        }
    }

    func testCloudKitBatchingCapsEveryOperationAtTwoHundredRecords() {
        let batches = ICloudRecordBatching.batches(Array(0..<401))

        XCTAssertEqual(batches.map(\.count), [200, 200, 1])
        XCTAssertEqual(batches.flatMap { $0 }, Array(0..<401))
    }

    func testCrossPlatformProjectAndChapterTimestampFixturesDecodeISOAndEpoch() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let isoProject = try decoder.decode(
            NovelProject.self,
            from: Data(#"{"id":"project-iso","title":"ISO","genre":"科幻","summary":"摘要","updatedAt":"2026-07-27T12:34:56Z"}"#.utf8)
        )
        let epochProject = try decoder.decode(
            NovelProject.self,
            from: Data(#"{"id":"project-epoch","title":"Epoch","genre":"科幻","summary":"摘要","updatedAt":1772000000}"#.utf8)
        )
        let isoChapter = try decoder.decode(
            ChapterDraft.self,
            from: Data(#"{"id":"chapter-iso","chapterNumber":1,"chapterTitle":"第一章","content":"正文","savedAt":"2026-07-27T12:34:56Z"}"#.utf8)
        )
        let epochChapter = try decoder.decode(
            ChapterDraft.self,
            from: Data(#"{"id":"chapter-epoch","chapterNumber":2,"chapterTitle":"第二章","content":"正文","savedAt":1772000000}"#.utf8)
        )

        XCTAssertEqual(isoProject.updatedAtDate.timeIntervalSince1970, 1_785_155_696, accuracy: 1)
        XCTAssertEqual(epochProject.updatedAtDate.timeIntervalSince1970, 1_772_000_000, accuracy: 0.001)
        XCTAssertEqual(isoChapter.savedAtDate, isoProject.updatedAtDate)
        XCTAssertEqual(epochChapter.savedAtDate.timeIntervalSince1970, 1_772_000_000, accuracy: 0.001)
    }

    func testCloudKitRecordPlanDeletesOnlyStaleScopedPayloads() {
        var project = makeProject(
            id: "keep-project",
            title: "保留项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        project.chapterDrafts = [
            ChapterDraft(
                id: "chapter-keep",
                chapterNumber: 1,
                chapterTitle: "保留章节",
                content: "正文"
            )
        ]
        let snapshot = AccountProjectSnapshot(
            activeProjectID: project.id,
            recentProjects: [project],
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )

        let plan = ICloudProjectStore.cloudKitRecordPlan(
            for: snapshot,
            scope: "apple-user-1",
            previousProjectIDs: ["keep-project", "stale-project"],
            previousChapterIDsByProjectID: [
                "keep-project": ["chapter-keep", "chapter-stale"],
                "stale-project": ["orphan-chapter"]
            ]
        )

        XCTAssertEqual(plan.deletedRecordNames, [
            "chapter_apple-user-1_keep-project_chapter-stale",
            "chapter_apple-user-1_stale-project_orphan-chapter",
            "project_apple-user-1_stale-project"
        ])
        XCTAssertFalse(plan.deletedRecordNames.contains(plan.snapshotRecordName))
        XCTAssertFalse(plan.deletedRecordNames.contains("project_apple-user-1_keep-project"))
        XCTAssertFalse(plan.deletedRecordNames.contains("chapter_apple-user-1_keep-project_chapter-keep"))
    }

    @MainActor
    func testCloudMergePreservesLocalOnlyProjectAndNewestChapterDraft() {
        var localShared = makeProject(
            id: "shared",
            title: "共享项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        var localChapter = ChapterDraft(
            id: "chapter-1",
            chapterNumber: 1,
            chapterTitle: "本机章节",
            content: "本机更新正文"
        )
        localChapter.savedAtDate = Date(timeIntervalSince1970: 1_772_020_000)
        localShared.chapterDrafts = [localChapter]
        localShared.chapterCatalog = [ChapterDraftMetadata(chapterDraft: localChapter)]

        var remoteShared = makeProject(
            id: "shared",
            title: "共享项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_010_000)
        )
        var remoteChapter = ChapterDraft(
            id: "chapter-1",
            chapterNumber: 1,
            chapterTitle: "远端章节",
            content: "远端旧正文"
        )
        remoteChapter.savedAtDate = Date(timeIntervalSince1970: 1_772_005_000)
        remoteShared.chapterDrafts = [remoteChapter]
        remoteShared.chapterCatalog = [ChapterDraftMetadata(chapterDraft: remoteChapter)]

        let localOnly = makeProject(
            id: "local-only",
            title: "本机独有",
            updatedAt: Date(timeIntervalSince1970: 1_772_015_000)
        )

        let merged = AppState.mergeCloudProjects(local: [localShared, localOnly], remote: [remoteShared])

        XCTAssertTrue(merged.contains { $0.id == localOnly.id })
        let shared = merged.first { $0.id == "shared" }
        XCTAssertEqual(shared?.chapterDrafts.first?.chapterTitle, "本机章节")
        XCTAssertEqual(shared?.chapterDrafts.first?.content, "本机更新正文")
        XCTAssertEqual(shared?.chapterCatalog.first?.chapterTitle, "本机章节")
        XCTAssertEqual(shared?.updatedAtDate, localChapter.savedAtDate)
    }

    @MainActor
    func testCloudMergeKeepsRemoteChapterWhenItIsNewer() {
        var local = makeProject(
            id: "shared",
            title: "共享项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        var localChapter = ChapterDraft(
            id: "chapter-1",
            chapterNumber: 1,
            chapterTitle: "本机章节",
            content: "本机旧正文"
        )
        localChapter.savedAtDate = Date(timeIntervalSince1970: 1_772_005_000)
        local.chapterDrafts = [localChapter]

        var remote = makeProject(
            id: "shared",
            title: "共享项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_010_000)
        )
        var remoteChapter = ChapterDraft(
            id: "chapter-1",
            chapterNumber: 1,
            chapterTitle: "远端章节",
            content: "远端更新正文"
        )
        remoteChapter.savedAtDate = Date(timeIntervalSince1970: 1_772_020_000)
        remote.chapterDrafts = [remoteChapter]

        let merged = AppState.mergeCloudProjects(local: [local], remote: [remote])

        XCTAssertEqual(merged.first?.chapterDrafts.first?.chapterTitle, "远端章节")
        XCTAssertEqual(merged.first?.chapterCatalog.first?.chapterTitle, "远端章节")
        XCTAssertEqual(merged.first?.updatedAtDate, remoteChapter.savedAtDate)
    }

    @MainActor
    func testCloudMergeResolvesMillisecondDeletionAndNewerEditWithoutResurrection() {
        let projectTime = Date(timeIntervalSince1970: 1_710_000_000.121)
        let deletionTime = Date(timeIntervalSince1970: 1_710_000_000.124)
        let deletedProject = makeProject(
            id: "project-a",
            title: "待删除项目",
            updatedAt: projectTime
        )
        let tombstone = ProjectDeletionTombstone(
            projectID: deletedProject.id,
            deletedAt: deletionTime
        )

        let deletionWins = AppState.mergeCloudProjectState(
            local: [deletedProject],
            localDeletedProjects: [],
            remote: [],
            remoteDeletedProjects: [tombstone]
        )
        XCTAssertTrue(deletionWins.projects.isEmpty)
        XCTAssertEqual(deletionWins.deletedProjects, [tombstone])

        let newerProject = makeProject(
            id: deletedProject.id,
            title: "删除后恢复编辑",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000.127)
        )
        let editWins = AppState.mergeCloudProjectState(
            local: [newerProject],
            localDeletedProjects: [],
            remote: [],
            remoteDeletedProjects: [tombstone]
        )
        XCTAssertEqual(editWins.projects.map(\.id), [newerProject.id])
        XCTAssertTrue(editWins.deletedProjects.isEmpty)
    }

    @MainActor
    func testCloudMergePreservesIndependentOutlineMemoryAndReviewUpdates() throws {
        var local = makeProject(
            id: "field-merge",
            title: "字段合并",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_010)
        )
        local.outlineText = "本机新增的大纲"
        var localMemory = GlobalMemorySnapshot.empty
        localMemory.characterRelations = "本机更新人物关系"
        local.globalMemorySnapshot = localMemory
        let localReport = QualityReviewReport(
            chapterNumber: 1,
            chapterTitle: "第一章",
            dimensionResults: [],
            overallSummary: "本机审查"
        )
        local.qualityReviewReports = [localReport]

        var remote = makeProject(
            id: local.id,
            title: "字段合并",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_020)
        )
        remote.structureNotes = "远端新增的章节骨架"
        var remoteMemory = GlobalMemorySnapshot.empty
        remoteMemory.worldState = "远端更新世界状态"
        remote.globalMemorySnapshot = remoteMemory
        let remoteReport = QualityReviewReport(
            chapterNumber: 2,
            chapterTitle: "第二章",
            dimensionResults: [],
            overallSummary: "远端审查"
        )
        remote.qualityReviewReports = [remoteReport]

        let merged = try XCTUnwrap(
            AppState.mergeCloudProjectState(
                local: [local],
                localDeletedProjects: [],
                remote: [remote],
                remoteDeletedProjects: []
            ).projects.first
        )

        XCTAssertEqual(merged.outlineText, local.outlineText)
        XCTAssertEqual(merged.structureNotes, remote.structureNotes)
        XCTAssertEqual(
            merged.globalMemorySnapshot.characterRelations,
            localMemory.characterRelations
        )
        XCTAssertEqual(
            merged.globalMemorySnapshot.worldState,
            remoteMemory.worldState
        )
        XCTAssertEqual(
            Set(merged.qualityReviewReports.map(\.id)),
            Set([localReport.id, remoteReport.id])
        )
    }

    @MainActor
    func testCloudMergeMakesConflictingOutlineVersionsExplicitAndIdempotent() throws {
        var local = makeProject(
            id: "outline-conflict",
            title: "大纲冲突",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_010)
        )
        local.outlineText = "版本甲：主角留在城内"
        var remote = makeProject(
            id: local.id,
            title: "大纲冲突",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_020)
        )
        remote.outlineText = "版本乙：主角离开城池"

        let firstMerge = try XCTUnwrap(
            AppState.mergeCloudProjectState(
                local: [local],
                localDeletedProjects: [],
                remote: [remote],
                remoteDeletedProjects: []
            ).projects.first
        )
        XCTAssertTrue(firstMerge.outlineText.contains("同步冲突"))
        XCTAssertTrue(firstMerge.outlineText.contains(local.outlineText))
        XCTAssertTrue(firstMerge.outlineText.contains(remote.outlineText))

        let repeatedMerge = try XCTUnwrap(
            AppState.mergeCloudProjectState(
                local: [firstMerge],
                localDeletedProjects: [],
                remote: [local],
                remoteDeletedProjects: []
            ).projects.first
        )
        XCTAssertEqual(repeatedMerge.outlineText, firstMerge.outlineText)
    }

    @MainActor
    func testCloudMergeIsCommutativeAndPreservesIndependentStructuredFields() throws {
        let timestamp = Date(timeIntervalSince1970: 1_710_100_000)
        let itemTimestamp = Date(timeIntervalSince1970: 1_710_090_000)
        var local = makeProject(
            id: "commutative-fields",
            title: "交换律",
            updatedAt: timestamp
        )
        local.draftText = "本机草稿"
        local.referenceContextText = "本机参考上下文"
        local.specialRequirements = "本机特殊要求"
        var localDocument = ReferenceDocument(
            id: "document-local",
            title: "本机资料",
            content: "本机资料正文",
            importedAt: "2024-03-10T00:00:00.000Z"
        )
        localDocument.importedAtDate = itemTimestamp
        local.referenceDocuments = [localDocument]
        local.foreshadowList = ForeshadowList(entries: [
            ForeshadowEntry(
                id: "foreshadow-local",
                title: "旧钥匙",
                firstChapter: 1,
                createdAt: itemTimestamp,
                updatedAt: itemTimestamp
            )
        ])
        local.plotThreadList = PlotThreadList(threads: [
            PlotThread(
                id: "thread-local",
                title: "追查旧案",
                createdAt: itemTimestamp,
                updatedAt: itemTimestamp
            )
        ])
        var localMemory = MemoryBuckets.empty
        localMemory.characterState = [
            MemoryItem(
                id: "memory-local",
                category: .characterState,
                subject: "林照",
                field: "位置",
                value: "旧城",
                sourceChapter: 1,
                updatedAt: itemTimestamp
            )
        ]
        local.persistedMemoryBuckets = localMemory
        local.persistedStrandWeaveState = StrandWeaveState(
            entries: [
                StrandWeaveState.Entry(
                    chapterNumber: 1,
                    dominant: .quest,
                    recordedAt: itemTimestamp
                )
            ],
            questTarget: 0.60,
            fireTarget: 0.20,
            constellationTarget: 0.20,
            questMaxConsecutive: 5,
            fireMaxGap: 10,
            constellationMaxGap: 15
        )

        var localChapter = ChapterDraft(
            id: "same-chapter",
            chapterNumber: 1,
            chapterTitle: "本机章名",
            content: "本机正文"
        )
        localChapter.savedAtDate = itemTimestamp
        var localVersion = ChapterDraftVersion(
            id: "version-local",
            chapterTitle: "本机历史",
            content: "本机历史正文",
            reason: "自动保存",
            savedAt: "2024-03-10T00:00:00.000Z"
        )
        localVersion.savedAtDate = itemTimestamp.addingTimeInterval(-20)
        localChapter.versionHistory = [localVersion]
        local.chapterDrafts = [localChapter]

        var remote = makeProject(
            id: local.id,
            title: "交换律",
            updatedAt: timestamp
        )
        remote.draftText = "远端草稿"
        remote.referenceContextText = "远端参考上下文"
        remote.specialRequirements = "远端特殊要求"
        var remoteDocument = ReferenceDocument(
            id: "document-remote",
            title: "远端资料",
            content: "远端资料正文",
            importedAt: "2024-03-10T00:00:00.000Z"
        )
        remoteDocument.importedAtDate = itemTimestamp
        remote.referenceDocuments = [remoteDocument]
        remote.foreshadowList = ForeshadowList(entries: [
            ForeshadowEntry(
                id: "foreshadow-remote",
                title: "断剑",
                firstChapter: 2,
                createdAt: itemTimestamp,
                updatedAt: itemTimestamp
            )
        ])
        remote.plotThreadList = PlotThreadList(threads: [
            PlotThread(
                id: "thread-remote",
                title: "寻找断剑",
                createdAt: itemTimestamp,
                updatedAt: itemTimestamp
            )
        ])
        var remoteMemory = MemoryBuckets.empty
        remoteMemory.worldRules = [
            MemoryItem(
                id: "memory-remote",
                category: .worldRule,
                subject: "旧城",
                field: "宵禁",
                value: "子时封门",
                sourceChapter: 2,
                updatedAt: itemTimestamp
            )
        ]
        remote.persistedMemoryBuckets = remoteMemory
        remote.persistedStrandWeaveState = StrandWeaveState(
            entries: [
                StrandWeaveState.Entry(
                    chapterNumber: 2,
                    dominant: .fire,
                    recordedAt: itemTimestamp
                )
            ],
            questTarget: 0.50,
            fireTarget: 0.30,
            constellationTarget: 0.20,
            questMaxConsecutive: 6,
            fireMaxGap: 9,
            constellationMaxGap: 14
        )

        var remoteChapter = ChapterDraft(
            id: localChapter.id,
            chapterNumber: 1,
            chapterTitle: "远端章名",
            content: "远端正文"
        )
        remoteChapter.savedAtDate = itemTimestamp
        var remoteVersion = ChapterDraftVersion(
            id: "version-remote",
            chapterTitle: "远端历史",
            content: "远端历史正文",
            reason: "自动保存",
            savedAt: "2024-03-10T00:00:00.000Z"
        )
        remoteVersion.savedAtDate = itemTimestamp.addingTimeInterval(-10)
        remoteChapter.versionHistory = [remoteVersion]
        remote.chapterDrafts = [remoteChapter]

        let localRemote = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [local], remote: [remote]).first
        )
        let remoteLocal = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [remote], remote: [local]).first
        )
        let encoder = CloudProjectJSONCoding.makeEncoder()

        XCTAssertEqual(
            try encoder.encode(localRemote),
            try encoder.encode(remoteLocal)
        )
        let absorbedLocal = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [localRemote], remote: [local]).first
        )
        let absorbedRemote = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [localRemote], remote: [remote]).first
        )
        XCTAssertEqual(
            try encoder.encode(localRemote),
            try encoder.encode(absorbedLocal)
        )
        XCTAssertEqual(
            try encoder.encode(localRemote),
            try encoder.encode(absorbedRemote)
        )
        XCTAssertTrue(localRemote.referenceContextText.contains(local.referenceContextText))
        XCTAssertTrue(localRemote.referenceContextText.contains(remote.referenceContextText))
        XCTAssertTrue(localRemote.specialRequirements.contains(local.specialRequirements))
        XCTAssertTrue(localRemote.specialRequirements.contains(remote.specialRequirements))
        XCTAssertEqual(
            Set(localRemote.referenceDocuments.map(\.id)),
            Set(["document-local", "document-remote"])
        )
        XCTAssertEqual(
            Set(localRemote.foreshadowList.entries.map(\.id)),
            Set(["foreshadow-local", "foreshadow-remote"])
        )
        XCTAssertEqual(
            Set(localRemote.plotThreadList.threads.map(\.id)),
            Set(["thread-local", "thread-remote"])
        )
        XCTAssertEqual(
            Set(
                MemoryCategory.allCases.flatMap {
                    localRemote.persistedMemoryBuckets?.bucket(for: $0).map(\.id) ?? []
                }
            ),
            Set(["memory-local", "memory-remote"])
        )
        XCTAssertEqual(
            Set(localRemote.persistedStrandWeaveState?.entries.map(\.chapterNumber) ?? []),
            Set([1, 2])
        )
        XCTAssertEqual(localRemote.chapterDrafts.first?.versionHistory.count, 2)
    }

    @MainActor
    func testCloudMergeDefaultsDoNotEraseConfiguredProjectFields() throws {
        let configuredProfile = OutlineGenerationProfile(
            storyFlow: "追查失踪案",
            worldDescription: "临海旧城",
            protagonistTraits: "谨慎但执着",
            expectedLength: "12 万字",
            endingPreference: "真相揭晓",
            sellingPoints: "双线推理",
            keyEvents: "灯塔失火",
            storyPacing: "前缓后急",
            motivations: "寻找失踪兄长",
            relationshipMap: "记者与刑警互相试探",
            antagonistPortrait: "伪装成证人的幕后人",
            foreshadowingNotes: "旧船票"
        )
        let configuredDate = Date(timeIntervalSince1970: 1_710_200_000)
        let defaultDate = configuredDate.addingTimeInterval(100)
        var configured = makeProject(
            id: "default-aware-fields",
            title: "默认值保护",
            updatedAt: configuredDate
        )
        configured.storyLength = .short
        configured.outlineGenerationProfile = configuredProfile
        configured.genreTemplateId = "suspense-detective"

        var defaults = makeProject(
            id: configured.id,
            title: configured.title,
            updatedAt: defaultDate
        )
        defaults.genreTemplateId = " \n "

        let configuredDefaults = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [configured], remote: [defaults]).first
        )
        let defaultsConfigured = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [defaults], remote: [configured]).first
        )
        let encoder = CloudProjectJSONCoding.makeEncoder()

        XCTAssertEqual(configuredDefaults.storyLength, .short)
        XCTAssertEqual(configuredDefaults.outlineGenerationProfile, configuredProfile)
        XCTAssertEqual(configuredDefaults.genreTemplateId, configured.genreTemplateId)
        XCTAssertEqual(
            try encoder.encode(configuredDefaults),
            try encoder.encode(defaultsConfigured)
        )

        let absorbedConfigured = try XCTUnwrap(
            AppState.mergeCloudProjects(
                local: [configuredDefaults],
                remote: [configured]
            ).first
        )
        let absorbedDefaults = try XCTUnwrap(
            AppState.mergeCloudProjects(
                local: [configuredDefaults],
                remote: [defaults]
            ).first
        )
        XCTAssertEqual(
            try encoder.encode(configuredDefaults),
            try encoder.encode(absorbedConfigured)
        )
        XCTAssertEqual(
            try encoder.encode(configuredDefaults),
            try encoder.encode(absorbedDefaults)
        )
    }

    @MainActor
    func testCloudMergeConfiguredProjectFieldConflictsUseCanonicalWinner() throws {
        let timestamp = Date(timeIntervalSince1970: 1_710_210_000)
        let firstProfile = OutlineGenerationProfile(
            storyFlow: "版本甲",
            worldDescription: "甲世界",
            protagonistTraits: "",
            expectedLength: "8 万字",
            endingPreference: "",
            sellingPoints: "",
            keyEvents: "",
            storyPacing: "",
            motivations: "",
            relationshipMap: "",
            antagonistPortrait: "",
            foreshadowingNotes: ""
        )
        let secondProfile = OutlineGenerationProfile(
            storyFlow: "版本乙",
            worldDescription: "乙世界",
            protagonistTraits: "",
            expectedLength: "18 万字",
            endingPreference: "",
            sellingPoints: "",
            keyEvents: "",
            storyPacing: "",
            motivations: "",
            relationshipMap: "",
            antagonistPortrait: "",
            foreshadowingNotes: ""
        )
        var first = makeProject(
            id: "canonical-configured-fields",
            title: "非默认冲突",
            updatedAt: timestamp
        )
        first.storyLength = .short
        first.outlineGenerationProfile = firstProfile
        first.genreTemplateId = "template-alpha"

        var second = makeProject(
            id: first.id,
            title: first.title,
            updatedAt: timestamp
        )
        second.storyLength = .medium
        second.outlineGenerationProfile = secondProfile
        second.genreTemplateId = "template-omega"

        let firstSecond = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [first], remote: [second]).first
        )
        let secondFirst = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [second], remote: [first]).first
        )
        let encoder = CloudProjectJSONCoding.makeEncoder()

        XCTAssertTrue([NovelLength.short, .medium].contains(firstSecond.storyLength))
        XCTAssertTrue(
            [firstProfile, secondProfile].contains(
                firstSecond.outlineGenerationProfile
            )
        )
        XCTAssertTrue(
            ["template-alpha", "template-omega"].contains(
                firstSecond.genreTemplateId
            )
        )
        XCTAssertEqual(
            try encoder.encode(firstSecond),
            try encoder.encode(secondFirst)
        )

        for operand in [first, second] {
            let absorbed = try XCTUnwrap(
                AppState.mergeCloudProjects(
                    local: [firstSecond],
                    remote: [operand]
                ).first
            )
            XCTAssertEqual(
                try encoder.encode(firstSecond),
                try encoder.encode(absorbed)
            )
        }
    }

    @MainActor
    func testCloudMergeLegacyStrandTrackerIsPositionBasedAndConsistentWithState() throws {
        let timestamp = Date(timeIntervalSince1970: 1_710_220_000)
        let localTracker = StrandWeaveTracker()
        localTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000001",
            chapterNumber: 1,
            dominant: .quest,
            recordedAt: timestamp
        ))
        localTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000002",
            chapterNumber: 2,
            dominant: .fire,
            recordedAt: timestamp
        ))
        localTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000004",
            chapterNumber: 4,
            dominant: .quest,
            recordedAt: timestamp
        ))
        localTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000005",
            chapterNumber: 5,
            dominant: .quest,
            recordedAt: timestamp
        ))
        localTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000006",
            chapterNumber: 6,
            dominant: .quest,
            recordedAt: timestamp
        ))

        let remoteTracker = StrandWeaveTracker(
            idealRatio: [.quest: 0.45, .fire: 0.35, .constellation: 0.20],
            redLineConfig: RhythmRedLineConfig(
                maxConsecutiveQuest: 4,
                maxGapFire: 8,
                maxGapConstellation: 12
            )
        )
        remoteTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000011",
            chapterNumber: 1,
            dominant: .constellation,
            recordedAt: timestamp.addingTimeInterval(10)
        ))
        remoteTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000013",
            chapterNumber: 3,
            dominant: .quest,
            recordedAt: timestamp
        ))
        remoteTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000014",
            chapterNumber: 4,
            dominant: .fire,
            recordedAt: timestamp.addingTimeInterval(10)
        ))
        remoteTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000015",
            chapterNumber: 5,
            dominant: .fire,
            recordedAt: timestamp.addingTimeInterval(10)
        ))
        remoteTracker.recordChapter(try legacyStrandRecord(
            id: "00000000-0000-0000-0000-000000000016",
            chapterNumber: 6,
            dominant: .fire,
            recordedAt: timestamp
        ))

        var local = makeProject(
            id: "legacy-strand-merge",
            title: "旧追踪器合并",
            updatedAt: timestamp
        )
        local.strandWeaveTracker = localTracker
        local.persistedStrandWeaveState = StrandWeaveState(
            entries: [
                StrandWeaveState.Entry(
                    chapterNumber: 1,
                    dominant: .fire,
                    recordedAt: timestamp.addingTimeInterval(20)
                ),
                StrandWeaveState.Entry(
                    volumeNumber: 1,
                    chapterNumber: 5,
                    dominant: .quest,
                    recordedAt: timestamp
                )
            ],
            questTarget: 0.60,
            fireTarget: 0.20,
            constellationTarget: 0.20,
            questMaxConsecutive: 5,
            fireMaxGap: 10,
            constellationMaxGap: 15
        )

        var remote = makeProject(
            id: local.id,
            title: local.title,
            updatedAt: timestamp
        )
        remote.strandWeaveTracker = remoteTracker
        remote.persistedStrandWeaveState = StrandWeaveState(
            entries: [
                StrandWeaveState.Entry(
                    chapterNumber: 2,
                    dominant: .fire,
                    recordedAt: timestamp
                ),
                StrandWeaveState.Entry(
                    volumeNumber: 2,
                    chapterNumber: 5,
                    dominant: .fire,
                    recordedAt: timestamp
                )
            ],
            questTarget: 0.60,
            fireTarget: 0.20,
            constellationTarget: 0.20,
            questMaxConsecutive: 5,
            fireMaxGap: 10,
            constellationMaxGap: 15
        )

        let localRemote = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [local], remote: [remote]).first
        )
        let remoteLocal = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [remote], remote: [local]).first
        )
        let encoder = CloudProjectJSONCoding.makeEncoder()

        XCTAssertEqual(
            localRemote.strandWeaveTracker.records.map(\.chapterNumber),
            [2, 3, 4, 6]
        )
        XCTAssertEqual(
            localRemote.strandWeaveTracker.records.first {
                $0.chapterNumber == 4
            }?.primaryStrand,
            .fire
        )
        XCTAssertFalse(
            localRemote.strandWeaveTracker.records.contains {
                [1, 5].contains($0.chapterNumber)
            }
        )
        XCTAssertEqual(
            try XCTUnwrap(localRemote.strandWeaveTracker.idealRatio[.quest]),
            0.45,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            localRemote.strandWeaveTracker.redLineConfig.maxGapFire,
            8
        )
        XCTAssertEqual(localRemote.persistedStrandWeaveState?.questTarget, 0.45)
        XCTAssertEqual(localRemote.persistedStrandWeaveState?.fireMaxGap, 8)
        XCTAssertFalse(localRemote.strandWeaveTracker === local.strandWeaveTracker)
        XCTAssertFalse(localRemote.strandWeaveTracker === remote.strandWeaveTracker)
        XCTAssertEqual(
            local.strandWeaveTracker.records.map(\.chapterNumber),
            [1, 2, 4, 5, 6]
        )
        XCTAssertEqual(
            remote.strandWeaveTracker.records.map(\.chapterNumber),
            [1, 3, 4, 5, 6]
        )
        XCTAssertEqual(
            try encoder.encode(localRemote),
            try encoder.encode(remoteLocal)
        )

        for operand in [local, remote] {
            let absorbed = try XCTUnwrap(
                AppState.mergeCloudProjects(
                    local: [localRemote],
                    remote: [operand]
                ).first
            )
            XCTAssertEqual(
                try encoder.encode(localRemote),
                try encoder.encode(absorbed)
            )
        }
    }

    @MainActor
    func testCloudMergeUsesCanonicalTieBreakForEqualReviewAndStableProjectOrder() throws {
        let reportID = "9D08082C-F3D1-43F3-A587-73584C99E0D1"
        let reviewedAt = "2024-03-10T12:00:00.000Z"
        func report(summary: String, score: Int) throws -> QualityReviewReport {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": reportID,
                "volumeNumber": 1,
                "chapterNumber": 1,
                "chapterTitle": "第一章",
                "reviewedAt": reviewedAt,
                "dimensionResults": [],
                "overallScore": score,
                "overallSummary": summary
            ])
            return try CloudProjectJSONCoding.makeDecoder().decode(
                QualityReviewReport.self,
                from: data
            )
        }

        let timestamp = Date(timeIntervalSince1970: 1_710_100_000)
        var first = makeProject(id: "project-b", title: "同名", updatedAt: timestamp)
        first.qualityReviewReports = [try report(summary: "版本甲", score: 81)]
        var second = makeProject(id: first.id, title: "同名", updatedAt: timestamp)
        second.qualityReviewReports = [try report(summary: "版本乙", score: 89)]

        let firstSecond = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [first], remote: [second]).first
        )
        let secondFirst = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [second], remote: [first]).first
        )
        let encoder = CloudProjectJSONCoding.makeEncoder()
        XCTAssertEqual(
            try encoder.encode(firstSecond),
            try encoder.encode(secondFirst)
        )
        XCTAssertEqual(firstSecond.qualityReviewReports.count, 1)

        let projectA = makeProject(id: "project-a", title: "同名", updatedAt: timestamp)
        let ordered = AppState.mergeCloudProjects(
            local: [first],
            remote: [projectA]
        )
        XCTAssertEqual(ordered.map(\.id), ["project-a", "project-b"])
    }

    @MainActor
    func testCloudMergePreservesOlderDraftAndRuntimeWhenNewerBaseIsEmpty() throws {
        var newer = makeProject(
            id: "nonloss-base",
            title: "非丢失合并",
            updatedAt: Date(timeIntervalSince1970: 1_710_200_200)
        )
        newer.draftText = ""
        newer.persistedLongformRuntimeState = nil
        newer.persistedLastReviewResult = nil

        var older = makeProject(
            id: newer.id,
            title: "非丢失合并",
            updatedAt: Date(timeIntervalSince1970: 1_710_200_100)
        )
        older.draftText = "需要保留的旧端草稿"
        older.persistedLongformRuntimeState = .empty
        older.persistedLastReviewResult = ChapterReviewResult(
            overallScore: 88,
            dimensionScores: [:],
            issues: [],
            hasBlockingIssues: false,
            antiPatterns: [],
            overallSummary: "需要保留的审查"
        )

        let merged = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [newer], remote: [older]).first
        )

        XCTAssertEqual(merged.draftText, older.draftText)
        XCTAssertNotNil(merged.persistedLongformRuntimeState)
        XCTAssertEqual(
            merged.persistedLastReviewResult?.overallSummary,
            "需要保留的审查"
        )
    }

    @MainActor
    func testCloudMergeKeepsOneLongformCommitWinnerPerChapterPosition() throws {
        func commit(
            id: String,
            status: LongformCommitStatus,
            createdAt: Date
        ) -> LongformChapterCommit {
            LongformChapterCommit(
                id: id,
                chapterNumber: 3,
                volumeNumber: 1,
                chapterTitle: "雨夜追查",
                status: status,
                createdAt: createdAt,
                plannedNodes: [],
                coveredNodes: [],
                missedNodes: [],
                rejectionReasons: status == .rejected ? ["审查未通过"] : [],
                revisionHints: [],
                acceptedEvents: [],
                extractedMemoryItems: [],
                dominantThreadType: .quest,
                reviewStatus: .completed,
                reviewSummary: "已审查",
                projectionStatus: [:]
            )
        }

        let projectTimestamp = Date(timeIntervalSince1970: 1_710_400_000)
        let accepted = commit(
            id: "accepted-old",
            status: .accepted,
            createdAt: projectTimestamp.addingTimeInterval(-10)
        )
        let rejected = commit(
            id: "rejected-new",
            status: .rejected,
            createdAt: projectTimestamp
        )
        var first = makeProject(
            id: "runtime-position",
            title: "运行态位置",
            updatedAt: projectTimestamp
        )
        first.persistedLongformRuntimeState = LongformStoryRuntimeState(
            latestContract: nil,
            latestCommit: accepted,
            latestWriteGate: nil,
            acceptedCommits: [accepted],
            rejectedCommits: []
        )
        var second = makeProject(
            id: first.id,
            title: "运行态位置",
            updatedAt: projectTimestamp
        )
        second.persistedLongformRuntimeState = LongformStoryRuntimeState(
            latestContract: nil,
            latestCommit: rejected,
            latestWriteGate: nil,
            acceptedCommits: [],
            rejectedCommits: [rejected]
        )

        let firstSecond = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [first], remote: [second])
                .first?
                .persistedLongformRuntimeState
        )
        let secondFirst = try XCTUnwrap(
            AppState.mergeCloudProjects(local: [second], remote: [first])
                .first?
                .persistedLongformRuntimeState
        )

        XCTAssertTrue(firstSecond.acceptedCommits.isEmpty)
        XCTAssertEqual(firstSecond.rejectedCommits.map(\.id), [rejected.id])
        XCTAssertEqual(firstSecond.latestCommit?.id, rejected.id)
        XCTAssertEqual(
            try CloudProjectJSONCoding.makeEncoder().encode(firstSecond),
            try CloudProjectJSONCoding.makeEncoder().encode(secondFirst)
        )
    }

    @MainActor
    func testCloudMergeCoalescesDuplicateProjectIDsWithoutTrap() throws {
        let timestamp = Date(timeIntervalSince1970: 1_710_300_000)
        var first = makeProject(
            id: "duplicate-project",
            title: "重复项目",
            updatedAt: timestamp
        )
        first.outlineText = "重复项版本甲"
        var second = makeProject(
            id: first.id,
            title: "重复项目",
            updatedAt: timestamp
        )
        second.outlineText = "重复项版本乙"

        let merged = AppState.mergeCloudProjects(
            local: [first, second],
            remote: []
        )

        let project = try XCTUnwrap(merged.first)
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(project.outlineText.contains(first.outlineText))
        XCTAssertTrue(project.outlineText.contains(second.outlineText))
    }

    func testDeletionDateRoundsNewestDateUpToCrossPlatformMilliseconds() {
        let projectUpdatedAt = Date(timeIntervalSince1970: 1_710_000_000.125_4)
        let earlierNow = Date(timeIntervalSince1970: 1_710_000_000.124)
        let laterNow = Date(timeIntervalSince1970: 1_710_000_000.129_2)

        XCTAssertEqual(
            ProjectDeletionTombstone.deletionDate(
                now: earlierNow,
                projectUpdatedAt: projectUpdatedAt
            ).timeIntervalSince1970,
            1_710_000_000.126,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ProjectDeletionTombstone.deletionDate(
                now: laterNow,
                projectUpdatedAt: projectUpdatedAt
            ).timeIntervalSince1970,
            1_710_000_000.130,
            accuracy: 0.000_001
        )
    }

    func testCloudSaveCompletionRequiresMatchingGenerationAndScope() {
        XCTAssertTrue(AppState.cloudSaveCompletionIsCurrent(
            saveGeneration: 7,
            currentGeneration: 7,
            scope: "account-a",
            currentScope: "account-a"
        ))
        XCTAssertFalse(AppState.cloudSaveCompletionIsCurrent(
            saveGeneration: 7,
            currentGeneration: 8,
            scope: "account-a",
            currentScope: "account-a"
        ))
        XCTAssertFalse(AppState.cloudSaveCompletionIsCurrent(
            saveGeneration: 7,
            currentGeneration: 7,
            scope: "account-a",
            currentScope: "account-b"
        ))
    }

    func testCloudSaveCompletionTimestampNeverRollsBackNewerLocalMutation() {
        let savedSnapshotDate = Date(timeIntervalSince1970: 1_710_000_000)

        XCTAssertEqual(
            AppState.reconciledCloudSnapshotTimestamp(
                current: 1_710_000_100,
                savedSnapshotDate: savedSnapshotDate
            ),
            1_710_000_100
        )
        XCTAssertEqual(
            AppState.reconciledCloudSnapshotTimestamp(
                current: 1_709_999_900,
                savedSnapshotDate: savedSnapshotDate
            ),
            1_710_000_000
        )
    }

    @MainActor
    func testConcurrentCloudSyncQueuesLatestAccountScope() async {
        let appState = AppState(
            userDefaults: makeIsolatedUserDefaults(),
            projectStore: makeIsolatedProjectStore(),
            credentialStore: makeCredentialStore()
        )
        appState.activeAccount = AppleAccountProfile(
            userID: "account-new",
            email: "",
            fullName: ""
        )
        appState.isCloudSynchronizationInProgress = true

        await appState.synchronizeWithICloud(forcePull: true)

        XCTAssertEqual(appState.pendingCloudSynchronizationScope, "account-new")
        XCTAssertTrue(appState.pendingCloudSynchronizationForcePull)
    }

    private func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "OpenWritingTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return userDefaults
    }

    private func makeIsolatedProjectStore(
        testHooks: ProjectFileStore.TestHooks = .none
    ) -> ProjectFileStore {
        let baseDirectoryName = "OpenWritingTests-\(UUID().uuidString)"
        let baseDirectoryURL = FileManager.default.temporaryDirectory
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: baseDirectoryURL.appendingPathComponent(baseDirectoryName, isDirectory: true)
            )
        }
        return ProjectFileStore(
            baseDirectoryURL: baseDirectoryURL,
            baseDirectoryName: baseDirectoryName,
            testHooks: testHooks
        )
    }

    private func makeCredentialStore() -> InMemoryCredentialStore {
        InMemoryCredentialStore()
    }

    private func legacyStrandRecord(
        id: String,
        chapterNumber: Int,
        dominant: StrandType,
        recordedAt: Date
    ) throws -> ChapterStrandRecord {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "chapterNumber": chapterNumber,
            "primaryStrand": dominant.rawValue,
            "confidence": 0.8,
            "recordedAt": recordedAt.timeIntervalSinceReferenceDate
        ])
        return try JSONDecoder().decode(ChapterStrandRecord.self, from: data)
    }

    private func makeProject(
        id: String,
        title: String,
        updatedAt: Date
    ) -> NovelProject {
        var project = NovelProject(
            id: id,
            title: title,
            genre: "都市",
            summary: "摘要",
            updatedAt: "2026-06-06",
            currentChapterTitle: "开篇设定",
            currentChapterNumber: 1,
            writtenChapters: 0,
            chapterFocus: "推进当前章节。",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: []
        )
        project.updatedAtDate = updatedAt
        return project
    }

    // MARK: - Quality Review Schema Tests

    func testQualityReviewerRejectsMissingDimensionScore() {
        let json = reviewJSON(dimensionScores: [
            "setting": 90,
            "timeline": 90,
            "continuity": 90,
            "character": 90,
            "logic": 90,
            "high_point": 90,
            "pacing": 90,
            "reader_pull": 90
        ])

        let result = ChapterQualityReviewer.parseReviewResult(from: json)

        XCTAssertTrue(result.hasBlockingIssues)
        XCTAssertEqual(result.overallScore, 0)
        XCTAssertTrue(result.blockingIssues.contains { $0.description.contains("缺少维度") })
    }

    func testQualityReviewerRejectsUnknownDimensionScore() {
        var scores = completeReviewDimensionScores()
        scores["mystery"] = 90

        let result = ChapterQualityReviewer.parseReviewResult(from: reviewJSON(dimensionScores: scores))

        XCTAssertTrue(result.hasBlockingIssues)
        XCTAssertEqual(result.overallScore, 0)
        XCTAssertTrue(result.blockingIssues.contains { $0.description.contains("未知审查维度") })
    }

    func testQualityReviewerRejectsOutOfRangeOverallScore() {
        let result = ChapterQualityReviewer.parseReviewResult(from: reviewJSON(overallScore: 120))

        XCTAssertTrue(result.hasBlockingIssues)
        XCTAssertEqual(result.overallScore, 0)
        XCTAssertTrue(result.blockingIssues.contains { $0.description.contains("总体分数超出") })
    }

    func testQualityReviewerRequiresEvidenceForHighPriorityIssues() {
        let json = reviewJSON(issues: """
        [
          {
            "dimension": "logic",
            "severity": "high",
            "blocking": false,
            "description": "因果关系缺少铺垫",
            "evidence": "",
            "fix_hint": "补一段决策动机",
            "location": "第3段"
          }
        ]
        """)

        let result = ChapterQualityReviewer.parseReviewResult(from: json)

        XCTAssertTrue(result.hasBlockingIssues)
        XCTAssertTrue(result.blockingIssues.contains { $0.description.contains("缺少原文证据") })
    }

    func testQualityReviewerDefaultsUnknownSeverityToMedium() {
        let json = reviewJSON(issues: """
        [
          {
            "dimension": "logic",
            "severity": "unclear",
            "blocking": false,
            "description": "表达略显笼统",
            "evidence": "",
            "fix_hint": "补充具体动作",
            "location": "第3段"
          }
        ]
        """)

        let result = ChapterQualityReviewer.parseReviewResult(from: json)

        XCTAssertFalse(result.hasBlockingIssues)
        XCTAssertEqual(result.issues.first?.severity, .medium)
    }

    func testQualityReviewerTreatsMissingSummaryAsHighPrioritySchemaIssue() {
        let result = ChapterQualityReviewer.parseReviewResult(from: reviewJSON(summary: ""))

        XCTAssertFalse(result.hasBlockingIssues)
        XCTAssertTrue(result.issues.contains {
            $0.severity == .high && $0.description.contains("缺少整体评价")
        })
    }

    func testQualityReviewerLocalHeuristicsAddActionableIssueForShortLongformChapter() {
        let project = NovelProject(
            title: "长篇项目",
            genre: "玄幻",
            summary: "主角要寻找失落的城。",
            storyLength: .long
        )
        let issues = ChapterQualityReviewer.localHeuristicIssues(
            text: "他推开门，看见远处的灯。",
            project: project
        )

        XCTAssertTrue(issues.contains { $0.dimension == .pacing })
        XCTAssertTrue(issues.contains { $0.dimension == .readerPull })
    }

    func testMemoryBucketsSupersedesCharacterStateFromLaterChapter() {
        var buckets = MemoryBuckets.empty
        let first = MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "境界",
            value: "筑基初期",
            sourceChapter: 10
        )
        let second = MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "境界",
            value: "金丹后期",
            sourceChapter: 11
        )

        XCTAssertFalse(buckets.upsert(first))
        XCTAssertTrue(buckets.upsert(second))

        XCTAssertEqual(buckets.characterState.filter { $0.status == .active }.map(\.value), ["金丹后期"])
        XCTAssertEqual(buckets.characterState.filter { $0.status == .outdated }.map(\.value), ["筑基初期"])
        XCTAssertTrue(buckets.characterState.filter { $0.status == .contradicted }.isEmpty)
        XCTAssertTrue(buckets.conflicts.isEmpty)
    }

    func testMemoryBucketsSupersedesCharacterStateAcrossVolumes() {
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "身份",
            value: "外门弟子",
            sourceVolumeNumber: 1,
            sourceChapter: 120
        ))

        XCTAssertTrue(buckets.upsert(MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "身份",
            value: "巡夜使",
            sourceVolumeNumber: 2,
            sourceChapter: 3
        )))

        XCTAssertEqual(buckets.characterState.first(where: { $0.status == .active })?.value, "巡夜使")
        XCTAssertEqual(buckets.characterState.first(where: { $0.status == .outdated })?.value, "外门弟子")
        XCTAssertTrue(buckets.conflicts.isEmpty)
    }

    func testMemoryBucketsBackfillDoesNotReplaceLaterActiveState() {
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .relationship,
            subject: "林照-沈青袖",
            field: "立场",
            value: "正式结盟",
            sourceVolumeNumber: 3,
            sourceChapter: 18
        ))

        XCTAssertFalse(buckets.upsert(MemoryItem(
            category: .relationship,
            subject: "林照-沈青袖",
            field: "立场",
            value: "互相试探",
            sourceVolumeNumber: 2,
            sourceChapter: 40
        )))

        XCTAssertEqual(buckets.relationships.first(where: { $0.status == .active })?.value, "正式结盟")
        XCTAssertEqual(buckets.relationships.first(where: { $0.value == "互相试探" })?.status, .outdated)
        XCTAssertTrue(buckets.conflicts.isEmpty)
    }

    func testMemoryBucketsImportingHistoricalItemKeepsActiveState() {
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "身份",
            value: "巡夜使",
            sourceVolumeNumber: 2,
            sourceChapter: 10
        ))

        buckets.upsert(MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "身份",
            value: "外门弟子",
            status: .outdated,
            sourceVolumeNumber: 1,
            sourceChapter: 20
        ))

        XCTAssertEqual(buckets.characterState.first(where: { $0.status == .active })?.value, "巡夜使")
        XCTAssertEqual(buckets.characterState.first(where: { $0.status == .outdated })?.value, "外门弟子")
    }

    func testMemoryBucketsWorkingContextFallsBackToRecentUnmatchedFacts() {
        var buckets = MemoryBuckets.empty
        buckets.storyFacts = [
            MemoryItem(
                category: .storyFact,
                subject: "北境来信",
                field: "情报",
                value: "旧盟友将在三日后抵达",
                sourceChapter: 40
            )
        ]

        let items = buckets.workingContextItems(for: "南海商路", relevantLimit: 4, totalLimit: 6)

        XCTAssertEqual(items.first?.subject, "北境来信")
    }

    func testMemoryBucketsWorkingContextCanRecallArchivedState() {
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "身份",
            value: "外门弟子",
            sourceChapter: 10
        ))
        buckets.upsert(MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "身份",
            value: "巡夜使",
            sourceChapter: 20
        ))

        let context = buckets.formattedForWorkingContext(
            buckets.workingContextItems(for: "林照为何不再是外门弟子")
        )

        XCTAssertTrue(context.contains("外门弟子"))
        XCTAssertTrue(context.contains("已过期"))
        XCTAssertTrue(context.contains("巡夜使"))
    }

    func testMemoryBucketsMarksLaterWorldRuleChangeAsContradicted() {
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .worldRule,
            subject: "月潮法则",
            field: "显现条件",
            value: "只能在满月显现",
            sourceChapter: 5
        ))
        buckets.upsert(MemoryItem(
            category: .worldRule,
            subject: "月潮法则",
            field: "显现条件",
            value: "任何夜晚都能显现",
            sourceChapter: 30
        ))

        XCTAssertEqual(buckets.worldRules.filter { $0.status == .active }.count, 1)
        XCTAssertEqual(buckets.worldRules.filter { $0.status == .contradicted }.count, 1)
        XCTAssertEqual(buckets.conflicts.count, 1)
    }

    func testMemoryBucketsMarksBackfilledWorldRuleChangeAsContradicted() {
        var buckets = MemoryBuckets.empty
        buckets.upsert(MemoryItem(
            category: .worldRule,
            subject: "月潮法则",
            field: "显现条件",
            value: "任何夜晚都能显现",
            sourceChapter: 30
        ))
        buckets.upsert(MemoryItem(
            category: .worldRule,
            subject: "月潮法则",
            field: "显现条件",
            value: "只能在满月显现",
            sourceChapter: 5
        ))

        XCTAssertEqual(buckets.worldRules.first(where: { $0.status == .active })?.value, "任何夜晚都能显现")
        XCTAssertEqual(buckets.worldRules.first(where: { $0.status == .contradicted })?.value, "只能在满月显现")
        XCTAssertEqual(buckets.conflicts.count, 1)
    }

    func testMemoryBucketsWorkingContextReservesAlwaysOnCoreUnderRelevantPressure() {
        var buckets = MemoryBuckets.empty
        for index in 1...16 {
            buckets.upsert(MemoryItem(
                category: .storyFact,
                subject: "共同线索\(index)",
                field: "调查记录",
                value: "共同线索已进入第\(index)轮核验",
                sourceChapter: index
            ))
        }
        for index in 1...4 {
            buckets.upsert(MemoryItem(
                category: .characterState,
                subject: "共同线索旧档\(index)",
                field: "状态",
                value: "共同线索历史状态\(index)",
                status: .outdated,
                sourceChapter: index
            ))
        }
        let coreCategories: [MemoryCategory] = [
            .worldRule,
            .characterState,
            .relationship,
            .openLoop,
            .readerPromise
        ]
        for (categoryIndex, category) in coreCategories.enumerated() {
            for itemIndex in 1...2 {
                buckets.upsert(MemoryItem(
                    category: category,
                    subject: "核心\(categoryIndex)-\(itemIndex)",
                    field: "必须保留",
                    value: "长期核心记忆",
                    sourceChapter: 100 + categoryIndex * 2 + itemIndex
                ))
            }
        }

        let items = buckets.workingContextItems(for: "共同线索", relevantLimit: 16, totalLimit: 26)

        XCTAssertTrue(items.contains { $0.category == .openLoop })
        XCTAssertTrue(items.contains { $0.category == .readerPromise })
        XCTAssertTrue(items.contains { $0.status == .outdated })
        XCTAssertLessThanOrEqual(items.count, 26)
    }

    func testMemoryExtractionSamplesChapterBeginningMiddleAndEndWithinLimit() {
        let chapter = "章首身份变化"
            + String(repeating: "甲", count: 11_980)
            + "章中世界规则"
            + String(repeating: "乙", count: 11_980)
            + "章末关键伏笔"

        let sampled = MemoryExtractionService.sampledChapterText(chapter, limit: 8_000)

        XCTAssertLessThanOrEqual(sampled.count, 8_000)
        XCTAssertTrue(sampled.contains("章首身份变化"))
        XCTAssertTrue(sampled.contains("章中世界规则"))
        XCTAssertTrue(sampled.contains("章末关键伏笔"))
        XCTAssertTrue(sampled.contains("【章节中段抽样】"))
        XCTAssertTrue(sampled.contains("【章节末段抽样】"))
    }

    func testMemoryBucketsKeepsDistinctOpenLoopsForSameSubject() {
        var buckets = MemoryBuckets.empty
        let swordShadow = MemoryItem(
            category: .openLoop,
            subject: "林照",
            field: "神秘剑影",
            value: "林照梦中反复出现断剑影子",
            sourceChapter: 3
        )
        let bloodlineSecret = MemoryItem(
            category: .openLoop,
            subject: "林照",
            field: "血脉秘密",
            value: "林照伤口在月下显出银色纹路",
            sourceChapter: 4
        )

        XCTAssertFalse(buckets.upsert(swordShadow))
        XCTAssertFalse(buckets.upsert(bloodlineSecret))

        XCTAssertEqual(buckets.openLoops.filter { $0.status == .active }.count, 2)
        XCTAssertEqual(Set(buckets.openLoops.map(\.dedupKey)).count, 2)
    }

    func testMemoryBucketsCompactionDoesNotDropOpenLoopByResolvedWordsInValue() {
        var buckets = MemoryBuckets.empty
        buckets.openLoops = [
            MemoryItem(
                category: .openLoop,
                subject: "银色纹路",
                field: "真相",
                value: "敌人声称此事已经解决，但主角尚未验证",
                status: .active,
                sourceChapter: 4
            ),
            MemoryItem(
                category: .openLoop,
                subject: "旧线索",
                field: "支线",
                value: "该支线已回收",
                status: .outdated,
                sourceChapter: 2
            )
        ]
        buckets.storyFacts = (0..<501).map { index in
            MemoryItem(
                category: .storyFact,
                subject: "事实\(index)",
                field: "测试",
                value: "测试\(index)",
                sourceChapter: index + 1
            )
        }

        buckets.compact(currentChapter: 80, threshold: 500)

        XCTAssertTrue(buckets.openLoops.contains { $0.subject == "银色纹路" })
        XCTAssertFalse(buckets.openLoops.contains { $0.subject == "旧线索" })
    }

    func testMemoryBucketsRelevantItemsTokenizesChineseWithoutWhitespace() {
        var buckets = MemoryBuckets.empty
        buckets.storyFacts = [
            MemoryItem(
                category: .storyFact,
                subject: "银色纹路",
                field: "血脉线索",
                value: "月下伤口浮现银色纹路",
                sourceChapter: 5
            ),
            MemoryItem(
                category: .storyFact,
                subject: "集市",
                field: "地点",
                value: "主角经过南门集市",
                sourceChapter: 6
            )
        ]

        let results = buckets.relevantActiveItems(for: "伤口银色纹路", limit: 1)

        XCTAssertEqual(results.first?.subject, "银色纹路")
    }

    func testMemoryBucketsMarksConflictingActiveItemAsContradicted() {
        var buckets = MemoryBuckets.empty
        let first = MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "境界",
            value: "筑基初期",
            sourceChapter: 10
        )
        let second = MemoryItem(
            category: .characterState,
            subject: "林照",
            field: "境界",
            value: "金丹后期",
            sourceChapter: 10
        )

        buckets.upsert(first)
        buckets.upsert(second)

        XCTAssertEqual(buckets.allActiveItems.count, 1)
        XCTAssertEqual(buckets.characterState.filter { $0.status == .contradicted }.count, 1)
    }

    func testMemoryBucketsDoesNotDuplicateSameActiveValue() {
        var buckets = MemoryBuckets.empty
        let first = MemoryItem(
            category: .worldRule,
            subject: "灵脉",
            field: "限制",
            value: "夜间潮汐增强",
            sourceChapter: 1
        )
        let second = MemoryItem(
            category: .worldRule,
            subject: "灵脉",
            field: "限制",
            value: "夜间潮汐增强",
            sourceChapter: 2
        )

        buckets.upsert(first)
        buckets.upsert(second)

        XCTAssertEqual(buckets.worldRules.filter { $0.status == .active }.count, 1)
        XCTAssertEqual(buckets.worldRules.filter { $0.status == .outdated }.count, 1)
        XCTAssertEqual(buckets.allActiveItems.first?.sourceChapter, 2)
    }

    func testContextRankerExtractsExtendedCJKEntities() {
        let entity = "𫠝城"

        XCTAssertTrue(ContextRanker.extractEntities(from: "主角进入\(entity)。").contains(entity))
    }

    func testForeshadowOverdueUsesCurrentChapter() {
        let entry = ForeshadowEntry(
            title: "断剑来历",
            firstChapter: 3,
            lastAdvancedChapter: 3,
            expectedResolutionChapter: 8
        )
        let list = ForeshadowList(entries: [entry])

        XCTAssertFalse(entry.isOverdue)
        XCTAssertTrue(entry.isOverdue(at: 9))
        XCTAssertEqual(list.overdueCount(currentChapter: 9), 1)
    }

    func testStrandWeaveGapUsesChapterNumbers() {
        var state = StrandWeaveState.empty
        state.recordChapter(1, dominant: .fire)
        state.recordChapter(12, dominant: .quest)

        let warnings = state.checkRedLines(currentChapter: 12)

        XCTAssertTrue(warnings.contains {
            $0.strand == .fire && $0.message.contains("断档 11 章")
        })
    }

    func testStrandWeaveWarnsWhenRatiosDrift() {
        var state = StrandWeaveState.empty
        for chapter in 1...10 {
            state.recordChapter(chapter, dominant: .quest)
        }

        let warnings = state.checkRedLines(currentChapter: 10)

        XCTAssertTrue(warnings.contains {
            $0.strand == .quest && $0.message.contains("比例偏离目标")
        })
        XCTAssertTrue(warnings.contains {
            $0.strand == .fire && $0.message.contains("比例偏离目标")
        })
    }

    @MainActor
    func testLegacyStrandWeaveTrackerGapUsesChapterNumbers() {
        let tracker = StrandWeaveTracker(
            redLineConfig: RhythmRedLineConfig(
                maxConsecutiveQuest: 5,
                maxGapFire: 10,
                maxGapConstellation: 99
            )
        )
        tracker.recordChapter(ChapterStrandRecord(chapterNumber: 1, primaryStrand: .fire))
        tracker.recordChapter(ChapterStrandRecord(chapterNumber: 12, primaryStrand: .quest))

        let alerts = tracker.checkRedLines()

        XCTAssertTrue(alerts.contains {
            $0.strand == .fire && $0.message.contains("断档 11 章")
        })
    }

    @MainActor
    func testLegacyStrandWeaveTrackerConsecutiveRequiresAdjacentChapters() {
        let tracker = StrandWeaveTracker(
            redLineConfig: RhythmRedLineConfig(
                maxConsecutiveQuest: 2,
                maxGapFire: 99,
                maxGapConstellation: 99
            )
        )
        tracker.recordChapter(ChapterStrandRecord(chapterNumber: 1, primaryStrand: .quest))
        tracker.recordChapter(ChapterStrandRecord(chapterNumber: 3, primaryStrand: .quest))

        let alerts = tracker.checkRedLines()

        XCTAssertFalse(alerts.contains { $0.type == .consecutiveExcess && $0.strand == .quest })
    }

    func testStrandKeywordClassifierDoesNotTreatSingleAiAsFire() {
        let text = "林照热爱修炼，也爱研究古阵。他喜欢在夜里推演剑诀，但本章主要推进宗门试炼。"

        XCTAssertEqual(StrandKeywordClassifier.dominantStrand(in: text), .quest)
    }

    func testStrandKeywordClassifierDetectsRelationshipArc() {
        let text = "她脸红着告白，两人相爱后仍克制拥抱，心跳声在雨夜里格外清晰。"

        XCTAssertEqual(StrandKeywordClassifier.dominantStrand(in: text), .fire)
    }

    func testContextRankerCapsCJKEntityExtraction() {
        let longText = String(repeating: "林照回到灵脉深处继续追查真相", count: 200)

        let entities = ContextRanker.extractEntities(from: longText)

        XCTAssertLessThanOrEqual(entities.count, 256)
        XCTAssertFalse(entities.isEmpty)
    }

    func testRankedContextBudgetIsStableBoundedAndKeepsPinnedDraftFirst() {
        let sections = [
            ContextSection(
                label: "草稿箱当前正文",
                content: String(repeating: "甲", count: 20_000),
                category: .currentDraft
            ),
            ContextSection(
                label: "低优先级参考",
                content: String(repeating: "乙", count: 20_000),
                category: .manualReference
            )
        ]

        let first = RankedContextBudget.render(sections)
        let second = RankedContextBudget.render(sections)

        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(first.count, RankedContextBudget.maximumCharacters)
        XCTAssertTrue(first.hasPrefix("\n\n草稿箱当前正文：\n"))
        XCTAssertTrue(first.contains("[本节上下文已截断]"))
        XCTAssertFalse(first.contains("低优先级参考"))
    }

    func testLegacyLongformRuntimeHealthIssueDecodesControlledKindWithoutKindField() throws {
        let expectedKinds: [(String, LongformRuntimeHealthIssueKind)] = [
            ("写前门禁未通过", .prewriteGate),
            ("分卷目录存在断卷", .missingVolumeSequence),
            ("章节目录存在断章", .missingChapterSequence),
            ("保存章节未进入提交链", .uncommittedSavedChapter),
            ("章节内容与提交链不一致", .staleSavedChapterCommit),
            ("最新章节提交被拒", .latestCommitRejected),
            ("旧版未知问题", .other)
        ]

        for (title, expectedKind) in expectedKinds {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": "legacy-\(title)",
                "status": "blocked",
                "title": title,
                "detail": "旧版详情",
                "repairHint": "旧版修复提示"
            ])
            let issue = try JSONDecoder().decode(LongformRuntimeHealthIssue.self, from: data)

            XCTAssertEqual(issue.kind, expectedKind, "Unexpected kind for \(title)")
        }
    }

    func testLegacyLongformCommitReviewStatusMigrationIsFailClosed() throws {
        func legacyDecodedCommit(
            summary: String,
            rejectionReasons: [String]
        ) throws -> LongformChapterCommit {
            let commit = LongformChapterCommit(
                id: "legacy-review-status",
                chapterNumber: 3,
                volumeNumber: 1,
                chapterTitle: "雨夜追查",
                status: rejectionReasons.isEmpty ? .accepted : .rejected,
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                plannedNodes: [],
                coveredNodes: [],
                missedNodes: [],
                rejectionReasons: rejectionReasons,
                revisionHints: [],
                acceptedEvents: [],
                extractedMemoryItems: [],
                dominantThreadType: .quest,
                reviewStatus: .completed,
                reviewSummary: summary,
                projectionStatus: [:]
            )
            let encoded = try JSONEncoder().encode(commit)
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            object.removeValue(forKey: "reviewStatus")
            return try JSONDecoder().decode(
                LongformChapterCommit.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        XCTAssertEqual(
            try legacyDecodedCommit(
                summary: "暂无写后审查结果。",
                rejectionReasons: []
            ).reviewStatus,
            .missing
        )
        XCTAssertEqual(
            try legacyDecodedCommit(
                summary: "暂无写后审查结果。",
                rejectionReasons: ["当前章审查失败：响应格式错误"]
            ).reviewStatus,
            .failed
        )
        XCTAssertEqual(
            try legacyDecodedCommit(
                summary: "存在阻断项",
                rejectionReasons: ["写后审查存在阻断问题"]
            ).reviewStatus,
            .completed
        )

        let unknown = try legacyDecodedCommit(
            summary: "旧版自由文本摘要",
            rejectionReasons: []
        )
        XCTAssertEqual(unknown.reviewStatus, .unknown)
        XCTAssertEqual(unknown.reviewSummary, "旧版自由文本摘要")
    }

    func testWriteGateUsesTypedReviewStatusInsteadOfDisplaySummary() throws {
        var project = NovelProject(
            title: "长篇审查状态",
            genre: "悬疑",
            summary: "追查旧案。",
            storyLength: .long
        )
        project.currentChapterNumber = 3
        var contract = LongformStorySystem.buildRuntimeContract(for: project)
        contract.review.requiresPostwriteReview = true
        let commit = LongformChapterCommit(
            id: "typed-review-status",
            chapterNumber: 3,
            volumeNumber: 1,
            chapterTitle: "雨夜追查",
            status: .accepted,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            plannedNodes: [],
            coveredNodes: [],
            missedNodes: [],
            rejectionReasons: [],
            revisionHints: [],
            acceptedEvents: [],
            extractedMemoryItems: [],
            dominantThreadType: .quest,
            reviewStatus: .completed,
            reviewSummary: "暂无写后审查结果。",
            projectionStatus: [:]
        )

        let report = LongformStorySystem.buildWriteGateReport(
            commit: commit,
            contract: contract
        )
        let reviewCheck = try XCTUnwrap(report.checks.first { $0.stage == .review })

        XCTAssertEqual(reviewCheck.status, .passed)
        XCTAssertEqual(reviewCheck.message, "写后审查通过")
    }

    func testAIMemoryProjectionFailureBecomesActionableWarning() throws {
        let commit = LongformChapterCommit(
            id: "commit-ai-memory-warning",
            chapterNumber: 3,
            volumeNumber: 1,
            chapterTitle: "雨夜追查",
            status: .accepted,
            createdAt: Date(),
            plannedNodes: [],
            coveredNodes: [],
            missedNodes: [],
            rejectionReasons: [],
            revisionHints: [],
            acceptedEvents: [],
            extractedMemoryItems: [],
            dominantThreadType: .quest,
            reviewStatus: .completed,
            reviewSummary: "可用。",
            projectionStatus: [
                "memory": "done",
                "ai_memory": "failed"
            ]
        )

        let messages = LongformStorySystem.projectionStatusMessages(for: commit)
        let aiMemoryMessage = try XCTUnwrap(messages.first { $0.key == "ai_memory" })

        XCTAssertEqual(aiMemoryMessage.status, .warning)
        XCTAssertTrue(aiMemoryMessage.message.contains("AI 记忆抽取"))
        XCTAssertTrue(aiMemoryMessage.recoveryHint?.contains("重新保存本章") ?? false)
        XCTAssertFalse(aiMemoryMessage.summaryText.contains("ai_memory"))
        XCTAssertFalse(aiMemoryMessage.summaryText.contains("failed"))
    }

    @MainActor
    func testLoadRecentProjectsMigratesLegacySidecarsAfterSuccessfulSave() throws {
        let projectID = "integration-cache-test-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults()
        let store = makeIsolatedProjectStore()
        let project = makeProject(
            id: projectID,
            title: "旧边车项目",
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        try store.saveProjects([project], for: nil)

        let review = ChapterReviewResult(
            overallScore: 88,
            dimensionScores: [:],
            issues: [],
            hasBlockingIssues: false,
            antiPatterns: ["重复句式"],
            overallSummary: "可继续"
        )
        let encodedValues: [(String, Data)] = [
            ("memoryBuckets_\(projectID)", try JSONEncoder().encode(MemoryBuckets.empty)),
            ("strandWeave_\(projectID)", try JSONEncoder().encode(StrandWeaveState.empty)),
            ("lastReview_\(projectID)", try JSONEncoder().encode(review)),
            ("longformRuntime_\(projectID)", try JSONEncoder().encode(LongformStoryRuntimeState.empty))
        ]
        encodedValues.forEach { defaults.set($0.1, forKey: $0.0) }
        defaults.set(["重复句式"], forKey: "antiPatterns_\(projectID)")

        let loaded = try XCTUnwrap(AppState.loadRecentProjects(
            for: nil,
            from: defaults,
            projectStore: store
        )?.first)

        XCTAssertEqual(loaded.persistedMemoryBuckets, .empty)
        XCTAssertEqual(loaded.persistedStrandWeaveState, .empty)
        XCTAssertEqual(loaded.persistedLastReviewResult, review)
        XCTAssertEqual(loaded.persistedAntiPatterns, ["重复句式"])
        XCTAssertEqual(loaded.persistedLongformRuntimeState, .empty)

        let reloaded = try XCTUnwrap(store.loadProjects(for: nil)?.first)
        XCTAssertEqual(reloaded.persistedLastReviewResult, review)
        encodedValues.forEach { XCTAssertNil(defaults.object(forKey: $0.0)) }
        XCTAssertNil(defaults.object(forKey: "antiPatterns_\(projectID)"))
    }

    func testLegacySidecarMigrationRetainsKeysWhenPersistenceFails() throws {
        let projectID = "failed-migration-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults()
        let key = "memoryBuckets_\(projectID)"
        defaults.set(try JSONEncoder().encode(MemoryBuckets.empty), forKey: key)

        let migrated = LegacyProjectSidecarMigrator(userDefaults: defaults).migrate([
            makeProject(
                id: projectID,
                title: "保存失败项目",
                updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
            )
        ]) { _ in false }

        XCTAssertEqual(migrated.first?.persistedMemoryBuckets, .empty)
        XCTAssertNotNil(defaults.object(forKey: key))
    }

    func testLegacySidecarMigrationPreservesUndecodableData() {
        let projectID = "corrupt-migration-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults()
        let key = "memoryBuckets_\(projectID)"
        defaults.set(Data("{ invalid json".utf8), forKey: key)
        var didPersist = false

        _ = LegacyProjectSidecarMigrator(userDefaults: defaults).migrate([
            makeProject(
                id: projectID,
                title: "损坏边车项目",
                updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
            )
        ]) { _ in
            didPersist = true
            return true
        }

        XCTAssertFalse(didPersist)
        XCTAssertNotNil(defaults.object(forKey: key))
    }

    func testCloudProjectPayloadCodecReadsIOSPayloadWithIncompatibleMemorySchemas() throws {
        let fixture = try Data(contentsOf: cloudProjectPayloadFixtureURL())
        let iosPayload = try XCTUnwrap(
            CloudProjectPayloadCodec.platformPayload(named: .iOS, in: fixture)
        )

        let project = try CloudProjectPayloadCodec.decodeMacProject(from: iosPayload)

        XCTAssertEqual(project.id, "cross-platform-project")
        XCTAssertEqual(project.title, "iOS 原始标题")
        XCTAssertEqual(project.currentChapterNumber, 8)
        XCTAssertNil(project.persistedMemoryBuckets)
        XCTAssertNil(project.persistedStrandWeaveState)
    }

    func testCloudProjectPayloadCodecAppliesCommonFieldsOverMacPayload() throws {
        let fixture = try Data(contentsOf: cloudProjectPayloadFixtureURL())

        let project = try CloudProjectPayloadCodec.decodeMacProject(from: fixture)

        XCTAssertEqual(project.title, "跨端封套作品")
        XCTAssertEqual(project.summary, "共同摘要")
        XCTAssertEqual(project.currentVolumeNumber, 2)
        XCTAssertEqual(project.genreTemplateId, "mac-only-template")
    }

    func testIOSStyleEnvelopeRewritePreservesMacPlatformPayloadExactly() throws {
        let fixture = try Data(contentsOf: cloudProjectPayloadFixtureURL())
        let originalMacPayload = try XCTUnwrap(
            CloudProjectPayloadCodec.platformPayload(named: .macOS, in: fixture)
        )
        let iosPayload = try XCTUnwrap(
            CloudProjectPayloadCodec.platformPayload(named: .iOS, in: fixture)
        )

        let rewritten = try CloudProjectPayloadCodec.encodeEnvelope(
            platformPayload: iosPayload,
            platform: .iOS,
            preserving: fixture
        )

        XCTAssertEqual(
            try CloudProjectPayloadCodec.platformPayload(named: .macOS, in: rewritten),
            originalMacPayload
        )
    }

    func testMacEnvelopeRewritePreservesIOSPlatformPayloadExactly() throws {
        let fixture = try Data(contentsOf: cloudProjectPayloadFixtureURL())
        let originalIOSPayload = try XCTUnwrap(
            CloudProjectPayloadCodec.platformPayload(named: .iOS, in: fixture)
        )
        var project = try CloudProjectPayloadCodec.decodeMacProject(from: fixture)
        project.draftText = "macOS 更新后的草稿"
        let memoryItem = MemoryItem(
            id: "mac-memory-1",
            category: .characterState,
            subject: "主角",
            field: "状态",
            value: "macOS 富状态",
            sourceVolumeNumber: 2,
            sourceChapter: 8,
            updatedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        project.persistedMemoryBuckets = MemoryBuckets(
            characterState: [memoryItem],
            relationships: [],
            worldRules: [],
            storyFacts: [],
            timeline: [],
            openLoops: [],
            readerPromises: [],
            lastCompactedAtChapter: 8
        )
        project.persistedStrandWeaveState = StrandWeaveState(
            entries: [
                StrandWeaveState.Entry(
                    volumeNumber: 2,
                    chapterNumber: 8,
                    dominant: .quest,
                    recordedAt: Date(timeIntervalSince1970: 1_772_000_100)
                )
            ],
            questTarget: 0.5,
            fireTarget: 0.3,
            constellationTarget: 0.2,
            questMaxConsecutive: 4,
            fireMaxGap: 5,
            constellationMaxGap: 7
        )

        let rewritten = try CloudProjectPayloadCodec.encodeMacProject(project, preserving: fixture)
        let decoded = try CloudProjectPayloadCodec.decodeMacProject(from: rewritten)

        XCTAssertEqual(
            try CloudProjectPayloadCodec.platformPayload(named: .iOS, in: rewritten),
            originalIOSPayload
        )
        XCTAssertEqual(decoded.draftText, "macOS 更新后的草稿")
        XCTAssertEqual(decoded.persistedMemoryBuckets?.characterState, [memoryItem])
        XCTAssertEqual(decoded.persistedStrandWeaveState, project.persistedStrandWeaveState)
    }

    func testCloudPayloadHashSkipsExistingIdenticalRecordAndUsesStableRevision() {
        let projectPayload = Data("project".utf8)
        let chapterPayload = Data("chapter".utf8)
        let hash = CloudProjectPayloadCodec.payloadHash(for: projectPayload)
        let firstRevision = CloudProjectPayloadCodec.revisionIdentifier(
            projectPayloads: [(id: "project-1", data: projectPayload)],
            chapterPayloads: [(projectID: "project-1", chapterID: "chapter-1", data: chapterPayload)]
        )
        let secondRevision = CloudProjectPayloadCodec.revisionIdentifier(
            projectPayloads: [(id: "project-1", data: projectPayload)],
            chapterPayloads: [(projectID: "project-1", chapterID: "chapter-1", data: chapterPayload)]
        )

        XCTAssertEqual(firstRevision, secondRevision)
        XCTAssertFalse(
            CloudProjectPayloadCodec.payloadNeedsUpload(
                projectPayload,
                existingHash: hash,
                existingData: nil
            )
        )
        XCTAssertTrue(
            CloudProjectPayloadCodec.payloadNeedsUpload(
                Data("changed".utf8),
                existingHash: hash,
                existingData: projectPayload
            )
        )
    }

    func testCrossPlatformContentAddressedRevisionGoldenVector() throws {
        let fixtureData = try Data(contentsOf: cloudProjectPayloadFixtureURL())
        let fixtureObject = try JSONSerialization.jsonObject(with: fixtureData)
        let canonicalFixtureData = try JSONSerialization.data(
            withJSONObject: fixtureObject,
            options: [.sortedKeys]
        )
        let fixtureHash = CloudProjectPayloadCodec.payloadHash(for: canonicalFixtureData)
        XCTAssertEqual(
            fixtureHash,
            "f12d32596bfc7deca0efec3d7b5123f14288ebe3d313a96ed0b6903cf94af723"
        )
        XCTAssertEqual(
            CloudProjectPayloadCodec.contentRevision(components: [fixtureHash]),
            "sha256-32a35f84d5e61ec0c4feb6ad13bc3244"
        )

        let vectorData = Data(#"{"a":1,"b":"跨端"}"#.utf8)
        let vectorHash = CloudProjectPayloadCodec.payloadHash(for: vectorData)
        let chapterRevision = CloudProjectPayloadCodec.chapterRevision(payloadHash: vectorHash)
        let chapterRecordName = ICloudProjectStore.chapterRecordName(
            for: "chapter-1",
            projectID: "project-1",
            scope: "scope",
            revision: chapterRevision
        )
        let projectRevision = CloudProjectPayloadCodec.projectRevision(
            payloadHash: vectorHash,
            chapterReferences: [(chapterID: "chapter-1", recordName: chapterRecordName)]
        )
        let projectRecordName = ICloudProjectStore.projectRecordName(
            for: "project-1",
            scope: "scope",
            revision: projectRevision
        )
        let manifestRevision = CloudProjectPayloadCodec.manifestRevision(
            projectReferences: [(projectID: "project-1", recordName: projectRecordName)]
        )

        XCTAssertEqual(
            projectRecordName,
            "project_scope_sha256-ed386434a6b7641cd1db416323b07ace_project-1"
        )
        XCTAssertEqual(
            manifestRevision,
            "sha256-6c1dd97b207db714434b9c7fe8a95578"
        )
        let reversedChapterRevision = CloudProjectPayloadCodec.projectRevision(
            payloadHash: "0123456789abcdef",
            chapterReferences: [
                (chapterID: "chapter-b", recordName: "record-b"),
                (chapterID: "chapter-a", recordName: "record-a")
            ]
        )
        XCTAssertEqual(
            reversedChapterRevision,
            "sha256-617026b5b86b6c63d3badf3eaa668069"
        )
        XCTAssertEqual(
            reversedChapterRevision,
            CloudProjectPayloadCodec.projectRevision(
                payloadHash: "0123456789abcdef",
                chapterReferences: [
                    (chapterID: "chapter-a", recordName: "record-a"),
                    (chapterID: "chapter-b", recordName: "record-b")
                ]
            )
        )

        let deletion = ProjectDeletionTombstone(
            projectID: "project-old",
            deletedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
        XCTAssertEqual(
            CloudProjectPayloadCodec.deletionTombstoneRevisionComponent(deletion),
            "deleted:project-old:1772000000.000"
        )
        XCTAssertEqual(
            CloudProjectPayloadCodec.manifestRevision(
                projectReferences: [(projectID: "project-1", recordName: projectRecordName)],
                deletedProjects: [deletion]
            ),
            "sha256-d91d3b255b13408a465b6b171c10aa12"
        )
    }

    func testCloudProjectPayloadCodecMigratesLegacyPlatformWithoutMislabeling() throws {
        let currentMacPayload = Data(
            #"{"genre":"科幻","id":"legacy-project","schemaVersion":2,"summary":"","title":"新版","storyLength":"long"}"#.utf8
        )
        let legacyMacPayload = Data(
            #"{"genre":"科幻","id":"legacy-project","macLegacyOnly":"keep","schemaVersion":1,"summary":"","title":"旧版","storyLength":"long"}"#.utf8
        )
        let migratedMac = try CloudProjectPayloadCodec.encodeEnvelope(
            platformPayload: currentMacPayload,
            platform: .macOS,
            preserving: legacyMacPayload
        )
        XCTAssertNil(
            try CloudProjectPayloadCodec.platformPayload(named: .iOS, in: migratedMac)
        )
        let migratedMacPayload = try XCTUnwrap(
            CloudProjectPayloadCodec.platformPayload(named: .macOS, in: migratedMac)
        )
        let migratedMacObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedMacPayload) as? [String: Any]
        )
        XCTAssertEqual(migratedMacObject["macLegacyOnly"] as? String, "keep")
        XCTAssertEqual(migratedMacObject["title"] as? String, "新版")

        let legacyIOSPayload = Data(
            #"{"genre":"科幻","id":"legacy-project","referenceContextItems":[],"summary":"","title":"iOS 旧版","storyLength":"long"}"#.utf8
        )
        let migratedIOS = try CloudProjectPayloadCodec.encodeEnvelope(
            platformPayload: currentMacPayload,
            platform: .macOS,
            preserving: legacyIOSPayload
        )
        XCTAssertEqual(
            try CloudProjectPayloadCodec.platformPayload(named: .iOS, in: migratedIOS),
            try JSONSerialization.data(
                withJSONObject: JSONSerialization.jsonObject(with: legacyIOSPayload),
                options: [.sortedKeys]
            )
        )
    }

    func testCloudProjectPayloadCodecRejectsFutureEnvelopeVersion() throws {
        let futureEnvelope = Data(
            #"{"_cloudProjectPayloadVersion":2,"_common":{},"_platforms":{"iOS":{}}}"#.utf8
        )
        let currentMacPayload = Data(
            #"{"genre":"科幻","id":"future-project","schemaVersion":2,"summary":"","title":"新版","storyLength":"long"}"#.utf8
        )

        XCTAssertThrowsError(try CloudProjectPayloadCodec.decodeMacProject(from: futureEnvelope))
        XCTAssertThrowsError(
            try CloudProjectPayloadCodec.encodeEnvelope(
                platformPayload: currentMacPayload,
                platform: .macOS,
                preserving: futureEnvelope
            )
        )
    }

    func testCloudProjectPayloadCodecRejectsCorruptPreviousEnvelopeAndCrossProjectPlatforms() throws {
        let currentMacPayload = Data(
            #"{"genre":"科幻","id":"project-1","schemaVersion":2,"summary":"","title":"新版","storyLength":"long"}"#.utf8
        )
        XCTAssertThrowsError(
            try CloudProjectPayloadCodec.encodeEnvelope(
                platformPayload: currentMacPayload,
                platform: .macOS,
                preserving: Data("{ invalid".utf8)
            )
        )

        let mismatchedEnvelope = Data(
            #"{"_cloudProjectPayloadVersion":1,"_common":{"id":"project-1"},"_platforms":{"iOS":{"id":"project-2"}}}"#.utf8
        )
        XCTAssertThrowsError(
            try CloudProjectPayloadCodec.decodeMacProject(from: mismatchedEnvelope)
        )
    }

    func testChapterDraftWritesCurrentSchemaAndRejectsFutureSchema() throws {
        let chapter = ChapterDraft(
            id: "chapter-1",
            volumeNumber: 1,
            chapterNumber: 1,
            chapterTitle: "第一章",
            content: "正文",
            savedAt: "2026-07-17T12:00:00Z"
        )
        let encoded = try JSONEncoder().encode(chapter)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(
            (object["schemaVersion"] as? NSNumber)?.intValue,
            ChapterDraft.currentSchemaVersion
        )

        let legacy = try JSONDecoder().decode(
            ChapterDraft.self,
            from: Data(
                #"{"id":"legacy","chapterNumber":1,"chapterTitle":"旧章","content":"正文"}"#.utf8
            )
        )
        XCTAssertEqual(legacy.schemaVersion, ChapterDraft.currentSchemaVersion)

        let future = Data(
            #"{"schemaVersion":3,"id":"future","chapterNumber":1,"chapterTitle":"未来章","content":"正文"}"#.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(ChapterDraft.self, from: future))
    }

    private func cloudProjectPayloadFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/cloud-project-payload-envelope-v1.json")
    }

    private func completeReviewDimensionScores() -> [String: Int] {
        [
            "setting": 90,
            "timeline": 90,
            "continuity": 90,
            "character": 90,
            "logic": 90,
            "high_point": 90,
            "pacing": 90,
            "reader_pull": 90,
            "ai_flavor": 90
        ]
    }

    private func reviewJSON(
        overallScore: Int = 95,
        dimensionScores: [String: Int]? = nil,
        issues: String = "[]",
        summary: String = "整体可用。"
    ) -> String {
        let scores = dimensionScores ?? completeReviewDimensionScores()
        let scorePairs = scores
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\": \($0.value)" }
            .joined(separator: ",\n")
        return """
        {
          "overall_score": \(overallScore),
          "dimension_scores": {
            \(scorePairs)
          },
          "issues": \(issues),
          "anti_patterns": [],
          "overall_summary": "\(summary)"
        }
        """
    }
}

private struct MockAIWritingService: AIWritingServicing {
    enum MockError: Error {
        case unused
    }

    func validateConnection(configuration: AIConnectionConfiguration) async throws -> String {
        await MainActor.run {
            configuration.modelName
        }
    }

    func generateStoryOutline(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        profile: OutlineGenerationProfile
    ) async throws -> String {
        throw MockError.unused
    }

    func continueChapterEnhanced(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        mode: AIWritingMode,
        additionalInstruction: String,
        length: AIWritingLength,
        enableReview: Bool
    ) async throws -> EnhancedWritingResult {
        throw MockError.unused
    }

    func polishFullDraft(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        draft: String,
        instruction: String
    ) async throws -> String {
        throw MockError.unused
    }

    func polishSelection(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        selectedText: String,
        instruction: String,
        fullDraft: String,
        precedingContext: String,
        followingContext: String
    ) async throws -> String {
        throw MockError.unused
    }

    func suggestChapterTitle(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        chapterContent: String
    ) async throws -> String {
        throw MockError.unused
    }

    func refreshGlobalMemory(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        savedChapter: ChapterDraft
    ) async throws -> String {
        throw MockError.unused
    }

    func refreshChapterTree(
        configuration: AIConnectionConfiguration,
        project: NovelProject,
        savedChapter: ChapterDraft
    ) async throws -> ChapterTreeRefresh {
        throw MockError.unused
    }

    func generateText(
        configuration: AIConnectionConfiguration,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        throw MockError.unused
    }
}
