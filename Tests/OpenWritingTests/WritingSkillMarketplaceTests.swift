import XCTest
@testable import OpenWriting

@MainActor
final class WritingSkillMarketplaceTests: XCTestCase {
    func testLegacyWritingSkillJSONStillDecodesWithoutMarketplaceMetadata() throws {
        let json = """
        {
          "id": "legacy-skill",
          "title": "旧版 Skill",
          "summary": "旧数据",
          "instructions": "保持人物语气一致。",
          "category": "voice",
          "origin": "imported",
          "sourceName": "legacy.md",
          "isEnabled": true,
          "importedAt": "2026-07-01T12:00:00Z"
        }
        """

        let skill = try JSONDecoder().decode(WritingSkill.self, from: Data(json.utf8))

        XCTAssertEqual(skill.title, "旧版 Skill")
        XCTAssertNil(skill.marketplaceListing)
    }

    func testPublishingSkillAddsLocalSubmissionToMarketplaceAndInstalledLibrary() {
        let appState = makeAppState()
        let draft = WritingSkill(
            id: "user-dialogue-skill",
            title: "克制对白",
            summary: "让对白保留潜台词。",
            instructions: "对白不要直接解释人物真实意图。",
            category: .voice,
            origin: .custom,
            sourceName: "自建 Skill"
        )

        let published = appState.publishWritingSkills([draft], publisherName: "本机创作者")

        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published[0].origin, .marketplace)
        XCTAssertEqual(published[0].marketplaceListing?.source, .localSubmission)
        XCTAssertEqual(published[0].marketplaceListing?.publisherName, "本机创作者")
        XCTAssertTrue(appState.installedWritingSkillIDs.contains(draft.id))
        XCTAssertEqual(appState.marketplaceWritingSkills.first?.id, draft.id)
        XCTAssertEqual(
            AppState.loadPublishedWritingSkills(from: appState.userDefaults)?.first?.id,
            draft.id
        )
    }

    func testMarketplaceCatalogDoesNotDuplicateCuratedSkillAfterInstallation() {
        let appState = makeAppState()
        let curated = WritingSkillMarketplace.featured[0]

        XCTAssertFalse(appState.marketplaceWritingSkills[0].isEnabled)

        appState.installMarketplaceSkill(curated)
        appState.installMarketplaceSkill(curated)

        XCTAssertEqual(appState.writingSkills.filter { $0.id == curated.id }.count, 1)
        XCTAssertEqual(appState.marketplaceWritingSkills.filter { $0.id == curated.id }.count, 1)
        XCTAssertTrue(appState.writingSkills.first { $0.id == curated.id }?.isEnabled == true)
        XCTAssertTrue(appState.marketplaceWritingSkills.first { $0.id == curated.id }?.isEnabled == true)
    }

    func testDeletingInstalledSubmissionKeepsMarketplaceListingAndAllowsReinstall() throws {
        let appState = makeAppState()
        let published = try XCTUnwrap(appState.publishWritingSkills(
            [
                WritingSkill(
                    id: "reinstallable-skill",
                    title: "可重装 Skill",
                    summary: "发布与安装分离。",
                    instructions: "保留章节目标。",
                    category: .structure,
                    origin: .custom,
                    sourceName: "自建 Skill"
                )
            ],
            publisherName: "本机创作者"
        ).first)

        appState.deleteWritingSkill(published.id)

        XCTAssertFalse(appState.installedWritingSkillIDs.contains(published.id))
        let listed = try XCTUnwrap(appState.marketplaceWritingSkills.first { $0.id == published.id })
        XCTAssertFalse(listed.isEnabled)

        appState.installMarketplaceSkill(listed)

        XCTAssertTrue(appState.installedWritingSkillIDs.contains(published.id))
        XCTAssertTrue(appState.writingSkills.first { $0.id == published.id }?.isEnabled == true)
    }

    func testUploadedMarkdownCanBePublishedIntoMarketplace() throws {
        let appState = makeAppState()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("uploaded-skill-\(UUID().uuidString).md")
        try """
        # 场景推进 Skill
        每一场戏都必须改变人物目标、关系或风险中的至少一项。
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }

        let uploaded = try WritingSkillImporting.skill(
            from: fileURL,
            usingSecurityScopedAccess: false
        )
        let published = appState.publishWritingSkills([uploaded], publisherName: "上传者")

        XCTAssertEqual(published.first?.title, "场景推进 Skill")
        XCTAssertEqual(published.first?.marketplaceListing?.publisherName, "上传者")
        XCTAssertTrue(appState.marketplaceWritingSkills.contains { $0.id == uploaded.id })
    }

    func testReinstallRefreshesMarketplaceSkillVersionInstructionsAndListing() throws {
        let appState = makeAppState()
        let versionOne = WritingSkill(
            id: "versioned-skill",
            title: "版本化 Skill",
            summary: "第一版",
            instructions: "使用第一版规则。",
            category: .revision,
            origin: .marketplace,
            sourceName: "测试市场",
            isEnabled: false,
            marketplaceListing: WritingSkillMarketplaceListing(
                publisherName: "作者甲",
                version: "1.0.0",
                source: .curated,
                publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        var versionTwo = versionOne
        versionTwo.instructions = "使用第二版规则。"
        versionTwo.marketplaceListing?.publisherName = "作者乙"
        versionTwo.marketplaceListing?.version = "2.0.0"

        appState.installMarketplaceSkill(versionOne)
        appState.installMarketplaceSkill(versionTwo)

        let installed = try XCTUnwrap(appState.writingSkills.first { $0.id == versionOne.id })
        XCTAssertEqual(installed.instructions, "使用第二版规则。")
        XCTAssertEqual(installed.marketplaceListing?.publisherName, "作者乙")
        XCTAssertEqual(installed.marketplaceListing?.version, "2.0.0")
        XCTAssertTrue(installed.isEnabled)
    }

    func testCatalogToleratesDuplicatePersistedIDs() {
        let provider = BundledWritingSkillCatalog(curatedSkills: [])
        let submitted = WritingSkill(
            id: "duplicate-id",
            title: "重复投稿",
            summary: "测试旧数据去重。",
            instructions: "只保留第一条。",
            category: .custom,
            origin: .custom,
            sourceName: "测试"
        ).publishedForLocalMarketplace(publisherName: "投稿者")

        let catalog = provider.catalog(
            publishedSkills: [submitted, submitted],
            installedSkills: [submitted, submitted]
        )

        XCTAssertEqual(catalog.map(\.id), [submitted.id])
        XCTAssertTrue(catalog[0].isEnabled)
    }

    func testPersistenceLoadNormalizesDuplicateInstalledAndPublishedIDs() throws {
        let suiteName = "WritingSkillDuplicateLoadTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }

        let duplicate = WritingSkill(
            id: "persisted-duplicate",
            title: "重复持久化 Skill",
            summary: "只应加载一次。",
            instructions: "避免重复注入。",
            category: .custom,
            origin: .custom,
            sourceName: "测试"
        ).publishedForLocalMarketplace(publisherName: "测试者")
        let encoded = try JSONEncoder().encode([duplicate, duplicate])
        userDefaults.set(encoded, forKey: AppState.StorageKey.writingSkills)
        userDefaults.set(encoded, forKey: AppState.StorageKey.publishedWritingSkills)

        XCTAssertEqual(AppState.loadWritingSkills(from: userDefaults)?.map(\.id), [duplicate.id])
        XCTAssertEqual(AppState.loadPublishedWritingSkills(from: userDefaults)?.map(\.id), [duplicate.id])
    }

    func testEnabledPublishedSkillIsInjectedIntoProjectPrompt() {
        let appState = makeAppState()
        let published = appState.publishWritingSkills(
            [
                WritingSkill(
                    id: "continuity-skill",
                    title: "人物状态守门",
                    summary: "避免人物状态跳变。",
                    instructions: "续写前核对上一章人物位置、伤势和目标。",
                    category: .structure,
                    origin: .custom,
                    sourceName: "自建 Skill"
                )
            ],
            publisherName: "本机创作者"
        )

        let project = NovelProject(title: "长篇", genre: "悬疑", summary: "测试")
        let promptProject = appState.projectWithActiveWritingSkills(project)

        XCTAssertEqual(published.first?.isEnabled, true)
        XCTAssertTrue(promptProject.specialRequirements.contains("人物状态守门"))
        XCTAssertTrue(promptProject.specialRequirements.contains("核对上一章人物位置、伤势和目标"))
    }

    private func makeAppState() -> AppState {
        let suiteName = "WritingSkillMarketplaceTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let baseDirectoryName = "WritingSkillMarketplaceTests-\(UUID().uuidString)"
        let baseDirectoryURL = FileManager.default.temporaryDirectory

        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(
                at: baseDirectoryURL.appendingPathComponent(baseDirectoryName, isDirectory: true)
            )
        }

        return AppState(
            userDefaults: userDefaults,
            projectStore: ProjectFileStore(
                baseDirectoryURL: baseDirectoryURL,
                baseDirectoryName: baseDirectoryName
            ),
            credentialStore: InMemoryCredentialStore()
        )
    }
}
