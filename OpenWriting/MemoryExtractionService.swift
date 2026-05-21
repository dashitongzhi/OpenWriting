import Foundation

// MARK: - AI-Powered Memory Extraction Service

/// Uses LLM to extract structured memory items from chapter content,
/// supplementing the keyword-based extraction in AppState.
struct MemoryExtractionService {

    // MARK: - Extraction Result

    struct ExtractionResult: Codable {
        var characterStates: [ExtractedMemoryItem]
        var relationships: [ExtractedMemoryItem]
        var worldRules: [ExtractedMemoryItem]
        var storyFacts: [ExtractedMemoryItem]
        var timeline: [ExtractedMemoryItem]
        var openLoops: [ExtractedMemoryItem]
        var readerPromises: [ExtractedMemoryItem]

        var allItems: [MemoryItem] {
            var items: [MemoryItem] = []
            let chapter = extractedChapterNumber

            items += characterStates.map { $0.toMemoryItem(category: .characterState, sourceChapter: chapter) }
            items += relationships.map { $0.toMemoryItem(category: .relationship, sourceChapter: chapter) }
            items += worldRules.map { $0.toMemoryItem(category: .worldRule, sourceChapter: chapter) }
            items += storyFacts.map { $0.toMemoryItem(category: .storyFact, sourceChapter: chapter) }
            items += timeline.map { $0.toMemoryItem(category: .timeline, sourceChapter: chapter) }
            items += openLoops.map { $0.toMemoryItem(category: .openLoop, sourceChapter: chapter) }
            items += readerPromises.map { $0.toMemoryItem(category: .readerPromise, sourceChapter: chapter) }

            return items
        }

        private var extractedChapterNumber: Int = 0

        enum CodingKeys: String, CodingKey {
            case characterStates, relationships, worldRules, storyFacts, timeline, openLoops, readerPromises, chapter
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            characterStates = try container.decodeIfPresent([ExtractedMemoryItem].self, forKey: .characterStates) ?? []
            relationships = try container.decodeIfPresent([ExtractedMemoryItem].self, forKey: .relationships) ?? []
            worldRules = try container.decodeIfPresent([ExtractedMemoryItem].self, forKey: .worldRules) ?? []
            storyFacts = try container.decodeIfPresent([ExtractedMemoryItem].self, forKey: .storyFacts) ?? []
            timeline = try container.decodeIfPresent([ExtractedMemoryItem].self, forKey: .timeline) ?? []
            openLoops = try container.decodeIfPresent([ExtractedMemoryItem].self, forKey: .openLoops) ?? []
            readerPromises = try container.decodeIfPresent([ExtractedMemoryItem].self, forKey: .readerPromises) ?? []
            extractedChapterNumber = try container.decodeIfPresent(Int.self, forKey: .chapter) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(characterStates, forKey: .characterStates)
            try container.encode(relationships, forKey: .relationships)
            try container.encode(worldRules, forKey: .worldRules)
            try container.encode(storyFacts, forKey: .storyFacts)
            try container.encode(timeline, forKey: .timeline)
            try container.encode(openLoops, forKey: .openLoops)
            try container.encode(readerPromises, forKey: .readerPromises)
            try container.encode(extractedChapterNumber, forKey: .chapter)
        }

        init(characterStates: [ExtractedMemoryItem] = [],
             relationships: [ExtractedMemoryItem] = [],
             worldRules: [ExtractedMemoryItem] = [],
             storyFacts: [ExtractedMemoryItem] = [],
             timeline: [ExtractedMemoryItem] = [],
             openLoops: [ExtractedMemoryItem] = [],
             readerPromises: [ExtractedMemoryItem] = [],
             chapterNumber: Int = 0) {
            self.characterStates = characterStates
            self.relationships = relationships
            self.worldRules = worldRules
            self.storyFacts = storyFacts
            self.timeline = timeline
            self.openLoops = openLoops
            self.readerPromises = readerPromises
            self.extractedChapterNumber = chapterNumber
        }
    }

    struct ExtractedMemoryItem: Codable {
        var subject: String
        var field: String
        var value: String
        var evidence: String?

        func toMemoryItem(category: MemoryCategory, sourceChapter: Int) -> MemoryItem {
            MemoryItem(
                id: Self.stableID(category: category, subject: subject, field: field, value: value, chapter: sourceChapter),
                category: category,
                subject: subject,
                field: field,
                value: value,
                sourceChapter: sourceChapter
            )
        }

        private static func stableID(category: MemoryCategory, subject: String, field: String, value: String, chapter: Int) -> String {
            let raw = [category.rawValue, subject, field, value, String(chapter)].joined(separator: "|")
            let hash = raw.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { result, scalar in
                (result ^ UInt64(scalar.value)) &* 1_099_511_628_211
            }
            return "ai-\(String(format: "%016llx", hash))"
        }
    }

    // MARK: - System Prompt

    static var extractionSystemPrompt: String {
        """
        你是一位中文网络小说创作助手，专门负责从章节文本中提取结构化记忆信息。

        你的任务是从给定的章节文本中提取以下7类记忆信息，每类最多返回10条：

        1. **角色状态 (characterStates)**：角色在本章中的新状态、情绪变化、境界提升、伤势变化、身份变化等。
           - subject: 角色名
           - field: 状态类型（如"境界"、"情绪"、"伤势"、"身份"）
           - value: 具体描述

        2. **人物关系 (relationships)**：本章中形成或变化的人物关系，如同盟、敌对、师徒、感情等。
           - subject: 关系双方（如"主角-师父"）
           - field: 关系类型（如"师徒"、"敌对"、"爱慕"）
           - value: 关系描述

        3. **世界观规则 (worldRules)**：本章揭示或强化的世界规则、法术体系、势力格局等。
           - subject: 规则/体系名
           - field: 规则类型（如"修炼体系"、"势力格局"、"地理设定"）
           - value: 规则描述

        4. **剧情事实 (storyFacts)**：本章发生的重要事件、转折、发现等。
           - subject: 事件主题
           - field: 事件类型（如"战斗"、"发现"、"决策"、"揭示"）
           - value: 事件描述

        5. **时间线 (timeline)**：本章涉及的时间推进、季节变化、日月流转等。
           - subject: 时间主题
           - field: 时间类型（如"季节"、"具体时间"、"时间段"）
           - value: 时间描述

        6. **未回收伏笔 (openLoops)**：本章埋下的伏笔、悬念、未解之谜。
           - subject: 伏笔主题
           - field: 伏笔类型（如"悬念"、"承诺"、"未解"）
           - value: 伏笔描述

        7. **读者承诺 (readerPromises)**：本章向读者许下、需要后续兑现的期待，如对决、真相、关系确认、奖励兑现。
           - subject: 承诺主题
           - field: 承诺类型（如"对决"、"真相"、"关系"、"奖励"）
           - value: 需要后续兑现的具体内容

        重要规则：
        - 顶层必须包含 chapter 字段，值为当前章节号
        - 只提取明确在文本中陈述或暗示的信息，不要过度推断
        - 每条记忆必须附带evidence字段，引用原文中的关键语句（最多50字）
        - 如果某类没有新信息，返回空数组而非虚构
        - 输出必须是有效的JSON格式，不要包含任何其他文字
        """
    }

    // MARK: - User Prompt

    static func extractionUserPrompt(chapterText: String, chapterNumber: Int, projectContext: String) -> String {
        """
        当前章节：第\(chapterNumber)章

        项目背景：
        \(projectContext)

        章节文本：
        \(chapterText)

        请提取本章中的所有结构化记忆信息。
        """
    }

    // MARK: - Parse Result

    static func parseExtractionResult(from response: String) -> ExtractionResult? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find JSON block
        var jsonString = trimmed
        if let range = trimmed.range(of: "```json") {
            let start = trimmed.index(range.upperBound, offsetBy: 0)
            if let endRange = trimmed.range(of: "```", range: start..<trimmed.endIndex) {
                jsonString = String(trimmed[start..<endRange.lowerBound])
            }
        } else if let range = trimmed.range(of: "```") {
            let afterFirstTick = trimmed.index(range.upperBound, offsetBy: 0)
            if let endRange = trimmed.range(of: "```", range: afterFirstTick..<trimmed.endIndex) {
                jsonString = String(trimmed[afterFirstTick..<endRange.lowerBound])
            }
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let result = try JSONDecoder().decode(ExtractionResult.self, from: data)
            return result
        } catch {
            // Try removing potential markdown code fences
            let cleaned = jsonString
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let cleanedData = cleaned.data(using: .utf8),
               let result = try? JSONDecoder().decode(ExtractionResult.self, from: cleanedData) {
                return result
            }
            return nil
        }
    }
}
