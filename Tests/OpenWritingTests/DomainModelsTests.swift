import XCTest
@testable import OpenWriting

final class DomainModelsTests: XCTestCase {

    // MARK: - NovelLength Tests

    func testNovelLengthLabels() {
        XCTAssertEqual(NovelLength.short.title, "短篇")
        XCTAssertEqual(NovelLength.medium.title, "中篇")
        XCTAssertEqual(NovelLength.long.title, "长篇")
    }

    func testNovelLengthWordRange() {
        XCTAssertEqual(NovelLength.short.wordRangeLabel, "3-10万字")
        XCTAssertEqual(NovelLength.medium.wordRangeLabel, "10-50万字")
        XCTAssertEqual(NovelLength.long.wordRangeLabel, "50万字以上")
    }

    func testNovelLengthChapterRange() {
        XCTAssertEqual(NovelLength.short.chapterRangeLabel, "约30-60章")
        XCTAssertEqual(NovelLength.medium.chapterRangeLabel, "约60-200章")
        XCTAssertEqual(NovelLength.long.chapterRangeLabel, "200章以上")
    }

    // MARK: - ModelProvider Tests

    func testModelProviderCases() {
        XCTAssertEqual(ModelProvider.openAICompatible.displayName, "OpenAI 兼容")
        XCTAssertEqual(ModelProvider.custom.displayName, "自定义")
    }

    // MARK: - ConnectionStatus Tests

    func testConnectionStatusDisconnected() {
        let status = ConnectionStatus.disconnected
        XCTAssertEqual(status.displayText, "未连接")
        XCTAssertEqual(status.colorHex, "#808080")
    }

    func testConnectionStatusConnecting() {
        let status = ConnectionStatus.connecting
        XCTAssertEqual(status.displayText, "连接中")
        XCTAssertEqual(status.colorHex, "#FFA500")
    }

    func testConnectionStatusConnected() {
        let status = ConnectionStatus.connected
        XCTAssertEqual(status.displayText, "已连接")
        XCTAssertEqual(status.colorHex, "#00AA00")
    }

    func testConnectionStatusError() {
        let status = ConnectionStatus.error("测试错误")
        XCTAssertEqual(status.displayText, "错误: 测试错误")
        XCTAssertEqual(status.colorHex, "#FF4444")
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
        XCTAssertEqual(ReferenceMaterialCategory.research.title, "资料")
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
            ReferenceMaterialCategory.infer(fromTitle: "门派设定", content: ""),
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
        let timestamp = PersistedTimestampCodec.encode(now)
        let decoded = PersistedTimestampCodec.decode(timestamp)

        // Allow 1 second tolerance
        XCTAssertNotNil(decoded)
        if let decoded = decoded {
            XCTAssertEqual(Int(decoded.timeIntervalSince1970), Int(now.timeIntervalSince1970))
        }
    }

    func testPersistedTimestampCodecFromDouble() {
        let doubleValue: Double = 1704067200
        let timestamp = PersistedTimestampCodec.encode(doubleValue)
        let decoded = PersistedTimestampCodec.decode(timestamp)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.timeIntervalSince1970, doubleValue)
    }

    func testPersistedTimestampCodecFromInt() {
        let intValue: Int = 1704067200
        let timestamp = PersistedTimestampCodec.encode(intValue)
        let decoded = PersistedTimestampCodec.decode(timestamp)

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
}