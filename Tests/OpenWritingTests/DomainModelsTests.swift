import Security
import XCTest
@testable import OpenWriting

final class DomainModelsTests: XCTestCase {

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

    @MainActor
    func testOpenWritingDefaultConnectionUsesServerManagedBackend() {
        let userDefaults = makeIsolatedUserDefaults()

        XCTAssertEqual(AppState.defaultModelName(for: .openAICompatible), "gpt-5.4-mini")
        XCTAssertEqual(AppState.defaultBaseURL(for: .openAICompatible), "https://openwriting.kralai.tech/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralai.tech/api/model/v1")
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
        seedRawOpenWritingAPIKey("sk-legacy-openai-key")
        defer { deleteRawOpenWritingAPIKey() }

        let configuration = try ModelConnectionConfigurationStore.loadConnectionConfiguration(userDefaults: userDefaults)

        XCTAssertEqual(configuration.apiKey, "")
    }

    @MainActor
    func testOpenWritingAPIKeyMigrationPurgesLegacyManagedKeyStorage() {
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set("sk-userdefaults-key", forKey: AppState.StorageKey.apiKey)
        userDefaults.set("sk-legacy-userdefaults-key", forKey: AppState.LegacyStorageKey.apiKey)
        seedRawOpenWritingAPIKey("sk-keychain-key")
        defer { deleteRawOpenWritingAPIKey() }

        AppState.migrateAPIKeysToKeychainIfNeeded(userDefaults)

        XCTAssertNil(userDefaults.string(forKey: AppState.StorageKey.apiKey))
        XCTAssertNil(userDefaults.string(forKey: AppState.LegacyStorageKey.apiKey))
        XCTAssertNil(rawOpenWritingAPIKey())
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

        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.baseURL), "https://openwriting.kralai.tech/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralai.tech/api/model/v1")
    }

    @MainActor
    func testPreviousKralAPIBaseURLMigratesToServerManagedBackend() {
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set("https://kralapi.kralai.tech/v1", forKey: AppState.StorageKey.baseURL)

        AppState.migrateRetiredOpenAICompatibleDefaults(userDefaults)

        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.baseURL), "https://openwriting.kralai.tech/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralai.tech/api/model/v1")
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
        XCTAssertEqual(userDefaults.string(forKey: AppState.StorageKey.baseURL), "https://openwriting.kralai.tech/api/model/v1")
        XCTAssertEqual(AppState.loadBaseURL(for: .openAICompatible, userDefaults: userDefaults), "https://openwriting.kralai.tech/api/model/v1")
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

    private func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "OpenWritingTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func seedRawOpenWritingAPIKey(_ value: String) {
        deleteRawOpenWritingAPIKey()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: ModelConnectionConfigurationStore.KeychainKey.service,
            kSecAttrAccount: ModelConnectionConfigurationStore.KeychainKey.openWAccount,
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func rawOpenWritingAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: ModelConnectionConfigurationStore.KeychainKey.service,
            kSecAttrAccount: ModelConnectionConfigurationStore.KeychainKey.openWAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteRawOpenWritingAPIKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: ModelConnectionConfigurationStore.KeychainKey.service,
            kSecAttrAccount: ModelConnectionConfigurationStore.KeychainKey.openWAccount
        ]
        SecItemDelete(query as CFDictionary)
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

    func testMemoryBucketsMarksConflictingCharacterStateAsContradicted() {
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
        XCTAssertFalse(buckets.upsert(second))

        XCTAssertEqual(buckets.characterState.filter { $0.status == .active }.count, 1)
        XCTAssertEqual(buckets.characterState.filter { $0.status == .contradicted }.count, 1)
        XCTAssertEqual(buckets.conflicts.count, 1)
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

    func testMemoryManagerMarksConflictingActiveItemAsContradicted() {
        let manager = MemoryManager()
        let first = MemoryManagerItem(
            bucket: .characterState,
            subject: "林照",
            field: "境界",
            value: "筑基初期",
            sourceChapter: 10
        )
        let second = MemoryManagerItem(
            bucket: .characterState,
            subject: "林照",
            field: "境界",
            value: "金丹后期",
            sourceChapter: 11
        )

        manager.upsertItem(first)
        manager.upsertItem(second)

        XCTAssertEqual(manager.memoryPack.semanticMemory.allActiveItems.count, 1)
        XCTAssertEqual(manager.memoryPack.semanticMemory.contradictedItems.count, 1)
        XCTAssertEqual(manager.stats.contradictedItems, 1)
    }

    func testMemoryManagerDoesNotDuplicateSameActiveValue() {
        let manager = MemoryManager()
        let first = MemoryManagerItem(
            bucket: .worldRules,
            subject: "灵脉",
            field: "限制",
            value: "夜间潮汐增强",
            sourceChapter: 1,
            evidence: "第一章"
        )
        let second = MemoryManagerItem(
            bucket: .worldRules,
            subject: "灵脉",
            field: "限制",
            value: "夜间潮汐增强",
            sourceChapter: 2,
            evidence: "第二章"
        )

        manager.upsertItem(first)
        manager.upsertItem(second)

        XCTAssertEqual(manager.memoryPack.semanticMemory.items.count, 1)
        XCTAssertEqual(manager.memoryPack.semanticMemory.allActiveItems.first?.evidence, "第二章")
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

    func testClearIntegrationCacheRemovesLegacyDefaults() {
        let projectID = "integration-cache-test-\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        let keys = [
            "memoryBuckets_\(projectID)",
            "strandWeave_\(projectID)",
            "lastReview_\(projectID)",
            "antiPatterns_\(projectID)"
        ]
        keys.forEach { defaults.set(Data("legacy".utf8), forKey: $0) }

        NovelProject.clearIntegrationCache(for: projectID)

        keys.forEach { XCTAssertNil(defaults.object(forKey: $0)) }
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
