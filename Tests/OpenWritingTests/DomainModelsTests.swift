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
        XCTAssertEqual(ModelProvider.openAICompatible.title, "OpenW")
        XCTAssertEqual(ModelProvider.custom.title, "自定义")
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
}
