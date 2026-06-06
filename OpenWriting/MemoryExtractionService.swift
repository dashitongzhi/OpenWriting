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
            allItems(sourceVolumeNumber: 1)
        }

        func allItems(sourceVolumeNumber: Int, sourceChapterNumber: Int? = nil) -> [MemoryItem] {
            var items: [MemoryItem] = []
            let chapter = sourceChapterNumber ?? extractedChapterNumber
            let volume = max(sourceVolumeNumber, 1)

            items += characterStates.map { $0.toMemoryItem(category: .characterState, sourceVolumeNumber: volume, sourceChapter: chapter) }
            items += relationships.map { $0.toMemoryItem(category: .relationship, sourceVolumeNumber: volume, sourceChapter: chapter) }
            items += worldRules.map { $0.toMemoryItem(category: .worldRule, sourceVolumeNumber: volume, sourceChapter: chapter) }
            items += storyFacts.map { $0.toMemoryItem(category: .storyFact, sourceVolumeNumber: volume, sourceChapter: chapter) }
            items += timeline.map { $0.toMemoryItem(category: .timeline, sourceVolumeNumber: volume, sourceChapter: chapter) }
            items += openLoops.map { $0.toMemoryItem(category: .openLoop, sourceVolumeNumber: volume, sourceChapter: chapter) }
            items += readerPromises.map { $0.toMemoryItem(category: .readerPromise, sourceVolumeNumber: volume, sourceChapter: chapter) }

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

        func toMemoryItem(category: MemoryCategory, sourceVolumeNumber: Int, sourceChapter: Int) -> MemoryItem {
            MemoryItem(
                id: Self.stableID(
                    category: category,
                    subject: subject,
                    field: field,
                    value: value,
                    volume: sourceVolumeNumber,
                    chapter: sourceChapter
                ),
                category: category,
                subject: subject,
                field: field,
                value: value,
                sourceVolumeNumber: sourceVolumeNumber,
                sourceChapter: sourceChapter
            )
        }

        private static func stableID(category: MemoryCategory, subject: String, field: String, value: String, volume: Int, chapter: Int) -> String {
            let raw = [category.rawValue, subject, field, value, String(max(volume, 1)), String(chapter)].joined(separator: "|")
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

        你的任务是从给定的章节文本中提取后续创作必须记住的耐久信息，而不是总结所有句子。
        请提取以下7类记忆信息，每类最多返回10条：

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
        - 只提取明确在文本中陈述或强证据暗示的信息，不要过度推断
        - 优先提取会影响后续章节的事实：人物状态变化、关系立场变化、世界规则、关键决定、未解决承诺、伏笔投放或回收
        - 不要提取泛泛氛围、修辞句、普通动作、一次性心理描写、纯风格描述或没有后续影响的寒暄
        - 如果某个旧状态在本章被更新，请提取“当前最新状态”，不要重复旧状态
        - openLoops 和 readerPromises 必须说明后续需要回收/兑现什么；如果本章已经回收，请在 value 中写明“已回收/已兑现”
        - storyFacts 和 timeline 只保留会影响后续理解的关键事件，不要把每个动作都当成事件
        - 每条记忆必须附带evidence字段，引用原文中的关键语句（最多50字）
        - 如果某类没有新信息，返回空数组而非虚构
        - 输出必须是有效的JSON格式，不要包含任何其他文字
        """
    }

    // MARK: - User Prompt

    static func extractionUserPrompt(
        chapterText: String,
        chapterNumber: Int,
        volumeNumber: Int = 1,
        projectContext: String,
        longformContext: String = "",
        existingMemoryContext: String = "",
        reviewContext: String = ""
    ) -> String {
        """
        当前章节：第\(max(volumeNumber, 1))卷第\(chapterNumber)章

        项目背景：
        \(projectContext)

        长篇后台合同与当前章目标：
        \(normalized(longformContext, fallback: "暂无长篇后台合同。"))

        已有结构化记忆摘要（用于判断哪些状态已经存在，避免重复旧信息）：
        \(normalized(existingMemoryContext, fallback: "暂无已有结构化记忆摘要。"))

        写后审查摘要（用于关注需要沉淀的质量风险、承接问题或修订重点）：
        \(normalized(reviewContext, fallback: "暂无写后审查摘要。"))

        章节文本：
        \(chapterText)

        请只提取本章中新出现、被更新、被兑现、或会影响后续章节的结构化记忆信息。
        """
    }

    private static func normalized(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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
