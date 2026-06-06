import Combine
import Foundation

// MARK: - Strand Weave Rhythm System
// Inspired by webnovel-writer's narrative rhythm control

/// Strand 类型（叙事线索类型）
enum StrandType: String, Codable, CaseIterable {
    case quest = "Quest"           // 主线剧情
    case fire = "Fire"             // 感情线
    case constellation = "Constellation" // 世界观扩展
    
    var displayName: String {
        switch self {
        case .quest: return "主线剧情"
        case .fire: return "感情线"
        case .constellation: return "世界观扩展"
        }
    }
    
    var icon: String {
        switch self {
        case .quest: return "⚔️"
        case .fire: return "❤️‍🔥"
        case .constellation: return "🌌"
        }
    }
    
    var description: String {
        switch self {
        case .quest: return "推动核心冲突与主线发展"
        case .fire: return "人物关系与情感发展"
        case .constellation: return "世界观、势力、设定扩展"
        }
    }
}

/// 章节 Strand 记录
struct ChapterStrandRecord: Codable, Identifiable {
    let id: UUID
    let chapterNumber: Int
    let primaryStrand: StrandType
    let secondaryStrand: StrandType?
    let confidence: Double // 0-1, AI 判断的置信度
    let notes: String?
    let recordedAt: Date
    
    init(chapterNumber: Int, primaryStrand: StrandType, secondaryStrand: StrandType? = nil,
         confidence: Double = 0.8, notes: String? = nil) {
        self.id = UUID()
        self.chapterNumber = chapterNumber
        self.primaryStrand = primaryStrand
        self.secondaryStrand = secondaryStrand
        self.confidence = confidence
        self.notes = notes
        self.recordedAt = Date()
    }
}

/// 节奏红线告警
struct RhythmAlert: Identifiable {
    let id = UUID()
    let type: AlertType
    let strand: StrandType
    let message: String
    let severity: AlertSeverity
    
    enum AlertType {
        case consecutiveExcess  // 连续超标
        case gapExcess          // 断档超标
        case ratioImbalance     // 比例失衡
    }
    
    enum AlertSeverity {
        case warning    // 警告
        case critical   // 严重
    }
}

/// Strand Weave 追踪器
class StrandWeaveTracker: ObservableObject, Codable {
    /// 章节记录
    @Published var records: [ChapterStrandRecord]
    
    /// 理想比例（默认 Quest 60%, Fire 20%, Constellation 20%）
    @Published var idealRatio: [StrandType: Double]
    
    /// 节奏红线配置
    @Published var redLineConfig: RhythmRedLineConfig
    
    enum CodingKeys: String, CodingKey {
        case records, questRatio, fireRatio, constellationRatio
        case maxConsecutiveQuest, maxGapFire, maxGapConstellation
    }
    
    init(idealRatio: [StrandType: Double] = [.quest: 0.6, .fire: 0.2, .constellation: 0.2],
         redLineConfig: RhythmRedLineConfig = RhythmRedLineConfig()) {
        self.records = []
        self.idealRatio = idealRatio
        self.redLineConfig = redLineConfig
    }
    
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([ChapterStrandRecord].self, forKey: .records) ?? []
        let q = try c.decodeIfPresent(Double.self, forKey: .questRatio) ?? 0.6
        let f = try c.decodeIfPresent(Double.self, forKey: .fireRatio) ?? 0.2
        let con = try c.decodeIfPresent(Double.self, forKey: .constellationRatio) ?? 0.2
        idealRatio = [.quest: q, .fire: f, .constellation: con]
        let maxCQ = try c.decodeIfPresent(Int.self, forKey: .maxConsecutiveQuest) ?? 5
        let maxGF = try c.decodeIfPresent(Int.self, forKey: .maxGapFire) ?? 10
        let maxGC = try c.decodeIfPresent(Int.self, forKey: .maxGapConstellation) ?? 15
        redLineConfig = RhythmRedLineConfig(
            maxConsecutiveQuest: maxCQ, maxGapFire: maxGF, maxGapConstellation: maxGC
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(records, forKey: .records)
        try c.encode(idealRatio[.quest] ?? 0.6, forKey: .questRatio)
        try c.encode(idealRatio[.fire] ?? 0.2, forKey: .fireRatio)
        try c.encode(idealRatio[.constellation] ?? 0.2, forKey: .constellationRatio)
        try c.encode(redLineConfig.maxConsecutiveQuest, forKey: .maxConsecutiveQuest)
        try c.encode(redLineConfig.maxGapFire, forKey: .maxGapFire)
        try c.encode(redLineConfig.maxGapConstellation, forKey: .maxGapConstellation)
    }
    
    // MARK: - Recording
    
    /// 记录章节的 Strand 类型
    func recordChapter(_ record: ChapterStrandRecord) {
        // 移除同章节的旧记录
        records.removeAll { $0.chapterNumber == record.chapterNumber }
        records.append(record)
        records.sort { $0.chapterNumber < $1.chapterNumber }
    }
    
    /// AI 自动判断章节的 Strand 类型
    func classifyChapter(chapterContent: String, configuration: AIConnectionConfiguration) async throws -> ChapterStrandRecord {
        let systemPrompt = """
        你是一位叙事结构分析专家。请判断给定章节的主要叙事线索类型。
        
        Strand 类型：
        - Quest（主线剧情）：推动核心冲突，主角面对主要挑战
        - Fire（感情线）：人物关系发展，情感互动
        - Constellation（世界观扩展）：背景设定、势力介绍、世界观展开
        
        请输出 JSON：
        ```json
        {
          "primary": "quest",
          "secondary": "fire",
          "confidence": 0.85,
          "reason": "判断理由"
        }
        ```
        
        primary 和 secondary 的值只能是: quest, fire, constellation
        secondary 可以为 null（如果章节只有一种明显线索）
        """
        
        let response = try await AIWritingService.generateText(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: "请分析以下章节：\n\n\(chapterContent)",
            temperature: 0.2,
            maxTokens: 500
        )
        
        return parseClassification(response: response, chapterContent: chapterContent)
    }
    
    // MARK: - Analysis
    
    /// 计算当前比例
    func currentRatio() -> [StrandType: Double] {
        guard !records.isEmpty else {
            return [.quest: 0, .fire: 0, .constellation: 0]
        }
        
        let counts = Dictionary(grouping: records, by: { $0.primaryStrand })
            .mapValues { Double($0.count) }
        let total = Double(records.count)
        
        return [
            .quest: (counts[.quest] ?? 0) / total,
            .fire: (counts[.fire] ?? 0) / total,
            .constellation: (counts[.constellation] ?? 0) / total
        ]
    }
    
    /// 检查节奏红线
    func checkRedLines() -> [RhythmAlert] {
        var alerts: [RhythmAlert] = []
        
        // 1. 检查 Quest 连续超标
        let consecutiveQuest = countRecentConsecutive(.quest)
        if consecutiveQuest >= redLineConfig.maxConsecutiveQuest {
            alerts.append(RhythmAlert(
                type: .consecutiveExcess,
                strand: .quest,
                message: "主线剧情已连续 \(consecutiveQuest) 章（上限 \(redLineConfig.maxConsecutiveQuest)），建议插入感情线或世界观扩展",
                severity: .critical
            ))
        }
        
        // 2. 检查 Fire 断档
        let fireGap = countGapSince(.fire)
        if fireGap >= redLineConfig.maxGapFire {
            alerts.append(RhythmAlert(
                type: .gapExcess,
                strand: .fire,
                message: "感情线已断档 \(fireGap) 章（上限 \(redLineConfig.maxGapFire)），建议补充感情线内容",
                severity: .warning
            ))
        }
        
        // 3. 检查 Constellation 断档
        let constellationGap = countGapSince(.constellation)
        if constellationGap >= redLineConfig.maxGapConstellation {
            alerts.append(RhythmAlert(
                type: .gapExcess,
                strand: .constellation,
                message: "世界观扩展已断档 \(constellationGap) 章（上限 \(redLineConfig.maxGapConstellation)），建议补充世界观内容",
                severity: .warning
            ))
        }
        
        // 4. 检查比例失衡
        let ratio = currentRatio()
        for strand in StrandType.allCases {
            let current = ratio[strand] ?? 0
            let ideal = idealRatio[strand] ?? 0.33
            let deviation = abs(current - ideal) / ideal
            if deviation > 0.5 && records.count >= 10 {
                alerts.append(RhythmAlert(
                    type: .ratioImbalance,
                    strand: strand,
                    message: "\(strand.displayName)比例偏离理想值（当前 \(Int(current * 100))%，理想 \(Int(ideal * 100))%）",
                    severity: .warning
                ))
            }
        }
        
        return alerts
    }
    
    /// 建议下一章的 Strand 类型
    func suggestNextStrand() -> StrandType {
        let alerts = checkRedLines()
        
        // 优先处理严重告警
        if let critical = alerts.first(where: { $0.severity == .critical }) {
            switch critical.strand {
            case .quest:
                // Quest 连续超标，建议切到 Fire 或 Constellation
                let fireGap = countGapSince(.fire)
                let constGap = countGapSince(.constellation)
                return fireGap > constGap ? .fire : .constellation
            case .fire:
                return .quest
            case .constellation:
                return .quest
            }
        }
        
        // 处理断档告警
        if let gapAlert = alerts.first(where: { $0.type == .gapExcess }) {
            return gapAlert.strand
        }
        
        // 按理想比例推荐
        let ratio = currentRatio()
        var maxDeficit: Double = -1
        var suggested: StrandType = .quest
        
        for strand in StrandType.allCases {
            let current = ratio[strand] ?? 0
            let ideal = idealRatio[strand] ?? 0.33
            let deficit = ideal - current
            if deficit > maxDeficit {
                maxDeficit = deficit
                suggested = strand
            }
        }
        
        return suggested
    }
    
    // MARK: - Helpers
    
    /// 计算最近连续同类型章节数
    private func countRecentConsecutive(_ strand: StrandType) -> Int {
        var count = 0
        for record in records.reversed() {
            if record.primaryStrand == strand {
                count += 1
            } else {
                break
            }
        }
        return count
    }
    
    /// 计算距离上次出现某类型的间隔章节数
    private func countGapSince(_ strand: StrandType) -> Int {
        guard let lastIndex = records.lastIndex(where: { $0.primaryStrand == strand }) else {
            return records.count
        }
        return records.count - 1 - lastIndex
    }
    
    /// 解析 AI 分类结果
    private func parseClassification(response: String, chapterContent: String) -> ChapterStrandRecord {
        let jsonString = extractJSON(from: response)
        
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let primaryStr = parsed["primary"] as? String else {
            // Fallback: 默认为 Quest
            return ChapterStrandRecord(chapterNumber: records.count + 1, primaryStrand: .quest, confidence: 0.5)
        }
        
        let primary = StrandType(rawValue: primaryStr.capitalized) ?? .quest
        let secondary: StrandType? = (parsed["secondary"] as? String).flatMap { StrandType(rawValue: $0.capitalized) }
        let confidence = parsed["confidence"] as? Double ?? 0.7
        let reason = parsed["reason"] as? String
        
        return ChapterStrandRecord(
            chapterNumber: records.count + 1,
            primaryStrand: primary,
            secondaryStrand: secondary,
            confidence: confidence,
            notes: reason
        )
    }
    
    private func extractJSON(from text: String) -> String {
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", range: startRange.upperBound..<text.endIndex) {
            return String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startRange = text.range(of: "{"),
           let endRange = text.range(of: "}", options: .backwards, range: startRange.upperBound..<text.endIndex) {
            return String(text[startRange.lowerBound...endRange.upperBound])
        }
        return text
    }
}

/// 节奏红线配置
struct RhythmRedLineConfig: Codable {
    /// Quest 连续章节数上限
    var maxConsecutiveQuest: Int
    /// Fire 断档章节数上限
    var maxGapFire: Int
    /// Constellation 断档章节数上限
    var maxGapConstellation: Int
    
    init(maxConsecutiveQuest: Int = 5, maxGapFire: Int = 10, maxGapConstellation: Int = 15) {
        self.maxConsecutiveQuest = maxConsecutiveQuest
        self.maxGapFire = maxGapFire
        self.maxGapConstellation = maxGapConstellation
    }
}

// MARK: - Lightweight Strand State

struct StrandWeaveState: Codable, Hashable {
    struct Entry: Identifiable, Codable, Hashable {
        let id: String
        let volumeNumber: Int
        let chapterNumber: Int
        let dominant: StrandType
        let recordedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case volumeNumber
            case chapterNumber
            case dominant
            case recordedAt
        }

        init(volumeNumber: Int = 1, chapterNumber: Int, dominant: StrandType, recordedAt: Date = Date()) {
            let safeVolumeNumber = max(volumeNumber, 1)
            let safeChapterNumber = max(chapterNumber, 1)
            self.id = "\(safeVolumeNumber)-\(safeChapterNumber)-\(dominant.rawValue)"
            self.volumeNumber = safeVolumeNumber
            self.chapterNumber = safeChapterNumber
            self.dominant = dominant
            self.recordedAt = recordedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            volumeNumber = try container.decodeIfPresent(Int.self, forKey: .volumeNumber) ?? 1
            chapterNumber = try container.decode(Int.self, forKey: .chapterNumber)
            dominant = try container.decode(StrandType.self, forKey: .dominant)
            recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt) ?? Date()
            id = try container.decodeIfPresent(String.self, forKey: .id)
                ?? "\(volumeNumber)-\(chapterNumber)-\(dominant.rawValue)"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(volumeNumber, forKey: .volumeNumber)
            try container.encode(chapterNumber, forKey: .chapterNumber)
            try container.encode(dominant, forKey: .dominant)
            try container.encode(recordedAt, forKey: .recordedAt)
        }
    }

    struct PacingWarning: Identifiable, Codable, Hashable {
        let id: String
        let strand: StrandType
        let message: String
        let isCritical: Bool

        init(strand: StrandType, message: String, isCritical: Bool) {
            self.id = "\(strand.rawValue)-\(message)"
            self.strand = strand
            self.message = message
            self.isCritical = isCritical
        }
    }

    var entries: [Entry]
    var questTarget: Double
    var fireTarget: Double
    var constellationTarget: Double
    var questMaxConsecutive: Int
    var fireMaxGap: Int
    var constellationMaxGap: Int

    static let empty = StrandWeaveState(
        entries: [],
        questTarget: 0.60,
        fireTarget: 0.20,
        constellationTarget: 0.20,
        questMaxConsecutive: 5,
        fireMaxGap: 10,
        constellationMaxGap: 15
    )

    mutating func recordChapter(_ chapterNumber: Int, volumeNumber: Int = 1, dominant: StrandType) {
        entries.removeAll {
            $0.volumeNumber == max(volumeNumber, 1) && $0.chapterNumber == max(chapterNumber, 1)
        }
        entries.append(Entry(volumeNumber: volumeNumber, chapterNumber: chapterNumber, dominant: dominant))
        entries.sort {
            if $0.volumeNumber == $1.volumeNumber {
                return $0.chapterNumber < $1.chapterNumber
            }
            return $0.volumeNumber < $1.volumeNumber
        }
    }

    mutating func removeChapter(_ chapterNumber: Int, volumeNumber: Int = 1) {
        entries.removeAll {
            $0.volumeNumber == max(volumeNumber, 1) && $0.chapterNumber == max(chapterNumber, 1)
        }
    }

    func checkRedLines(currentChapter: Int) -> [PacingWarning] {
        var warnings: [PacingWarning] = []
        let questStreak = recentConsecutive(.quest)
        if questStreak >= questMaxConsecutive {
            warnings.append(PacingWarning(
                strand: .quest,
                message: "主线剧情已连续 \(questStreak) 章，建议插入感情线或世界观扩展。",
                isCritical: true
            ))
        }

        let fireGap = gapSince(.fire)
        if fireGap >= fireMaxGap {
            warnings.append(PacingWarning(
                strand: .fire,
                message: "感情线已断档 \(fireGap) 章，建议补一段关系推进。",
                isCritical: false
            ))
        }

        let constellationGap = gapSince(.constellation)
        if constellationGap >= constellationMaxGap {
            warnings.append(PacingWarning(
                strand: .constellation,
                message: "世界观扩展已断档 \(constellationGap) 章，建议补充规则、势力或背景信息。",
                isCritical: false
            ))
        }

        return warnings
    }

    var ratios: [StrandType: Double] {
        guard !entries.isEmpty else {
            return [.quest: 0, .fire: 0, .constellation: 0]
        }

        let total = Double(entries.count)
        let counts = Dictionary(grouping: entries, by: \.dominant).mapValues { Double($0.count) }
        return [
            .quest: (counts[.quest] ?? 0) / total,
            .fire: (counts[.fire] ?? 0) / total,
            .constellation: (counts[.constellation] ?? 0) / total
        ]
    }

    var formattedForContext: String {
        let current = ratios
        let rows = StrandType.allCases.map { strand -> String in
            let percent = Int((current[strand] ?? 0) * 100)
            return "- \(strand.rawValue): \(percent)%"
        }
        let warnings = checkRedLines(currentChapter: entries.last?.chapterNumber ?? 1)
            .map { "- \($0.message)" }

        return (["当前 Strand 比例："] + rows + (warnings.isEmpty ? ["暂无节奏红线告警。"] : ["节奏告警："] + warnings))
            .joined(separator: "\n")
    }

    private func recentConsecutive(_ strand: StrandType) -> Int {
        var count = 0
        for entry in entries.reversed() {
            guard entry.dominant == strand else { break }
            count += 1
        }
        return count
    }

    private func gapSince(_ strand: StrandType) -> Int {
        guard let latestIndex = entries.lastIndex(where: { $0.dominant == strand }) else {
            return entries.count
        }
        return max(0, entries.count - latestIndex - 1)
    }
}
