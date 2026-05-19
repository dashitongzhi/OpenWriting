import Foundation

nonisolated enum PersistedTimestampDisplayStyle {
    case project
    case compact
}

nonisolated enum PersistedTimestampCodec {
    static func now() -> Date {
        Date()
    }

    static func parse(_ rawValue: String) -> Date? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        if let seconds = Double(trimmedValue) {
            return Date(timeIntervalSince1970: seconds)
        }

        if let date = iso8601Formatter(withFractionalSeconds: true).date(from: trimmedValue)
            ?? iso8601Formatter(withFractionalSeconds: false).date(from: trimmedValue) {
            return date
        }

        if let todayTime = parseClockTime(from: trimmedValue, prefix: "今天 ") {
            return date(bySetting: todayTime, on: Date())
        }

        if let yesterdayTime = parseClockTime(from: trimmedValue, prefix: "昨天 "),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) {
            return date(bySetting: yesterdayTime, on: yesterday)
        }

        if let sameDayTime = parseClockTime(from: trimmedValue, prefix: nil) {
            return date(bySetting: sameDayTime, on: Date())
        }

        return nil
    }

    static func parseOptional(_ rawValue: String) -> Date? {
        parse(rawValue)
    }

    static func decodeRequired<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date {
        if let date = decodeOptional(container, forKey: key) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected a persisted timestamp."
        )
    }

    static func decodeOptional<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Date? {
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: doubleValue)
        }

        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: Double(intValue))
        }

        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return parse(stringValue)
        }

        return nil
    }

    static func encode<Key: CodingKey>(
        _ date: Date,
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        try container.encode(date.timeIntervalSince1970, forKey: key)
    }

    static func encodeIfPresent<Key: CodingKey>(
        _ date: Date?,
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        guard let date else { return }
        try encode(date, to: &container, forKey: key)
    }

    static func displayLabel(for date: Date?, style: PersistedTimestampDisplayStyle) -> String {
        guard let date else { return "" }

        if calendar.isDateInToday(date) {
            switch style {
            case .project:
                return formatter("今天 HH:mm").string(from: date)
            case .compact:
                return formatter("HH:mm").string(from: date)
            }
        }

        if calendar.isDateInYesterday(date) {
            return formatter("昨天 HH:mm").string(from: date)
        }

        let currentYear = calendar.component(.year, from: Date())
        let targetYear = calendar.component(.year, from: date)

        switch style {
        case .project:
            return formatter(targetYear == currentYear ? "M月d日 HH:mm" : "yyyy年M月d日 HH:mm").string(from: date)
        case .compact:
            return formatter(targetYear == currentYear ? "M/d HH:mm" : "yy/M/d HH:mm").string(from: date)
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        return calendar
    }

    private static func iso8601Formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = format
        return formatter
    }

    private static func parseClockTime(from value: String, prefix: String?) -> DateComponents? {
        let timeString: String
        if let prefix {
            guard value.hasPrefix(prefix) else { return nil }
            timeString = String(value.dropFirst(prefix.count))
        } else {
            timeString = value
        }

        let parts = timeString.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else {
            return nil
        }

        return DateComponents(hour: hour, minute: minute)
    }

    private static func date(bySetting time: DateComponents, on baseDate: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }
}

enum NovelLength: String, CaseIterable, Codable, Identifiable {
    case short
    case medium
    case long

    var id: Self { self }

    var title: String {
        switch self {
        case .short:
            return "短篇"
        case .medium:
            return "中篇"
        case .long:
            return "长篇"
        }
    }

    var summary: String {
        switch self {
        case .short:
            return "适合单一冲突闭环、强情绪转折或一次真相揭示。"
        case .medium:
            return "适合一条主线搭配少量副线，让人物变化完整展开。"
        case .long:
            return "适合分卷连载、长线伏笔、多角色弧线和世界状态持续演化。"
        }
    }

    var targetRangeSummary: String {
        switch self {
        case .short:
            return "全文约 0.6 万到 1.5 万字"
        case .medium:
            return "全文约 3 万到 12 万字"
        case .long:
            return "全文约 30 万字以上"
        }
    }

    var creationChecklist: [String] {
        switch self {
        case .short:
            return [
                "主线尽量单一，角色和场景控制在必要范围内",
                "开场尽快给出钩子，中段加压，结尾形成闭环",
                "不依赖复杂章节树，重点盯住节奏和回收"
            ]
        case .medium:
            return [
                "主线之外最多保留 1 到 2 条副线，避免信息发散",
                "按阶段推进角色关系和主要冲突，适合 8 到 20 章规模",
                "中段需要反转或升级，尾段要完成阶段回收"
            ]
        case .long:
            return [
                "先定分卷目标，再拆当前卷章节点和卷末回收点",
                "持续维护在途线索、人物长期状态和未回收伏笔",
                "避免单章透支底牌，关键真相分阶段揭示"
            ]
        }
    }

    var promptDirective: String {
        switch self {
        case .short:
            return "按短篇模式创作：冲突集中、场景精简、结尾要形成明确闭环。"
        case .medium:
            return "按中篇模式创作：允许阶段推进和关系变化，但要持续围绕主线，不要支线蔓延。"
        case .long:
            return "按长篇模式创作：强调分卷推进、长期伏笔、角色长期变化和阶段性回收，避免一次性把底牌说透。"
        }
    }

    var outlineDirective: String {
        switch self {
        case .short:
            return "大纲要突出单次事件闭环、关键转折和结尾回收点。"
        case .medium:
            return "大纲要明确阶段推进、主要转折和主副线配比。"
        case .long:
            return "大纲必须明确分卷/阶段目标、卷末回收、长期反派压力和多条在途线索的衔接。"
        }
    }

    var continuityDirective: String {
        switch self {
        case .short:
            return "重点维护叙事视角、情绪线和结尾闭环，不要拖出无必要的远期悬念。"
        case .medium:
            return "重点维护主线推进、关系线变化和阶段伏笔回收，避免中段散掉。"
        case .long:
            return "重点维护分卷目标、在途线索、人物长期状态和跨章信息一致性。"
        }
    }

    var supportsThreadTracking: Bool {
        self != .short
    }

    var supportsVolumePlanning: Bool {
        self == .long
    }
}

enum ModelProvider: String, CaseIterable, Identifiable {
    case openAICompatible
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .openAICompatible:
            return "OpenW"
        case .custom:
            return "自定义"
        }
    }
}

enum ConnectionStatus {
    case idle
    case checking
    case ready
    case needsAttention

    var label: String {
        switch self {
        case .idle:
            return "等待配置"
        case .checking:
            return "正在验证"
        case .ready:
            return "配置就绪"
        case .needsAttention:
            return "需要检查"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "circle.dashed"
        case .checking:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .ready:
            return "checkmark.seal.fill"
        case .needsAttention:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct DashboardStat: Identifiable {
    let title: String
    let value: String
    let detail: String
    let symbolName: String
    let destination: SidebarItem

    var id: String { title }
}

enum ChapterDraftSaveResult {
    case created(ChapterDraft)
    case updated(ChapterDraft)

    var chapterDraft: ChapterDraft {
        switch self {
        case let .created(chapterDraft), let .updated(chapterDraft):
            return chapterDraft
        }
    }

    var isUpdate: Bool {
        switch self {
        case .created:
            return false
        case .updated:
            return true
        }
    }
}

nonisolated struct ChapterDraftVersion: Identifiable, Codable, Hashable {
    let id: String
    var chapterTitle: String
    var content: String
    var reason: String
    private var savedAtTimestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case chapterTitle
        case content
        case reason
        case savedAt
    }

    var savedAt: String {
        get { PersistedTimestampCodec.displayLabel(for: savedAtTimestamp, style: .project) }
        set { savedAtTimestamp = PersistedTimestampCodec.parse(newValue) ?? PersistedTimestampCodec.now() }
    }

    var savedAtDate: Date {
        get { savedAtTimestamp }
        set { savedAtTimestamp = newValue }
    }

    var wordCount: Int {
        Self.wordCount(in: content)
    }

    init(
        id: String = UUID().uuidString,
        chapterTitle: String,
        content: String,
        reason: String,
        savedAt: String
    ) {
        self.id = id
        self.chapterTitle = chapterTitle
        self.content = content
        self.reason = reason
        self.savedAtTimestamp = PersistedTimestampCodec.parse(savedAt) ?? PersistedTimestampCodec.now()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        chapterTitle = try container.decode(String.self, forKey: .chapterTitle)
        content = try container.decode(String.self, forKey: .content)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "历史版本"
        savedAtTimestamp = try PersistedTimestampCodec.decodeRequired(container, forKey: .savedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(chapterTitle, forKey: .chapterTitle)
        try container.encode(content, forKey: .content)
        try container.encode(reason, forKey: .reason)
        try PersistedTimestampCodec.encode(savedAtTimestamp, to: &container, forKey: .savedAt)
    }

    static func wordCount(in text: String) -> Int {
        text
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }
}

nonisolated struct ChapterDraft: Identifiable, Codable, Hashable {
    let id: String
    var volumeNumber: Int
    var chapterNumber: Int
    var chapterTitle: String
    var content: String
    private var savedAtTimestamp: Date
    var versionHistory: [ChapterDraftVersion]

    enum CodingKeys: String, CodingKey {
        case id
        case volumeNumber
        case chapterNumber
        case chapterTitle
        case content
        case savedAt
        case versionHistory
    }

    var savedAt: String {
        get { PersistedTimestampCodec.displayLabel(for: savedAtTimestamp, style: .project) }
        set { savedAtTimestamp = PersistedTimestampCodec.parse(newValue) ?? PersistedTimestampCodec.now() }
    }

    var savedAtDate: Date {
        get { savedAtTimestamp }
        set { savedAtTimestamp = newValue }
    }

    init(
        id: String = UUID().uuidString,
        volumeNumber: Int = 1,
        chapterNumber: Int,
        chapterTitle: String,
        content: String,
        savedAt: String,
        versionHistory: [ChapterDraftVersion] = []
    ) {
        self.id = id
        self.volumeNumber = max(volumeNumber, 1)
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.content = content
        self.savedAtTimestamp = PersistedTimestampCodec.parse(savedAt) ?? PersistedTimestampCodec.now()
        self.versionHistory = versionHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        volumeNumber = try container.decodeIfPresent(Int.self, forKey: .volumeNumber) ?? 1
        chapterNumber = try container.decode(Int.self, forKey: .chapterNumber)
        chapterTitle = try container.decode(String.self, forKey: .chapterTitle)
        content = try container.decode(String.self, forKey: .content)
        savedAtTimestamp = try PersistedTimestampCodec.decodeRequired(container, forKey: .savedAt)
        versionHistory = try container.decodeIfPresent([ChapterDraftVersion].self, forKey: .versionHistory) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(volumeNumber, forKey: .volumeNumber)
        try container.encode(chapterNumber, forKey: .chapterNumber)
        try container.encode(chapterTitle, forKey: .chapterTitle)
        try container.encode(content, forKey: .content)
        try PersistedTimestampCodec.encode(savedAtTimestamp, to: &container, forKey: .savedAt)
        try container.encode(versionHistory, forKey: .versionHistory)
    }

    var chapterLabel: String {
        volumeNumber > 1 ? "第 \(volumeNumber) 卷 · 第 \(chapterNumber) 章" : "第 \(chapterNumber) 章"
    }

    var chapterSummary: String {
        "\(chapterLabel) · \(chapterTitle)"
    }

    var wordCount: Int {
        ChapterDraftVersion.wordCount(in: content)
    }

    var versionCount: Int {
        versionHistory.count
    }

    func versionSnapshot(reason: String, savedAt: String) -> ChapterDraftVersion {
        ChapterDraftVersion(
            chapterTitle: chapterTitle,
            content: content,
            reason: reason,
            savedAt: savedAt
        )
    }

    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }

    nonisolated static func sortDescending(_ lhs: ChapterDraft, _ rhs: ChapterDraft) -> Bool {
        if lhs.volumeNumber != rhs.volumeNumber {
            return lhs.volumeNumber > rhs.volumeNumber
        }

        if lhs.chapterNumber == rhs.chapterNumber {
            return lhs.savedAtTimestamp > rhs.savedAtTimestamp
        }

        return lhs.chapterNumber > rhs.chapterNumber
    }
}

nonisolated struct ChapterDraftMetadata: Identifiable, Codable, Hashable {
    let id: String
    var volumeNumber: Int
    var chapterNumber: Int
    var chapterTitle: String
    var chapterSummary: String
    var wordCount: Int
    var savedAt: String
    var previewText: String

    init(chapterDraft: ChapterDraft) {
        id = chapterDraft.id
        volumeNumber = max(chapterDraft.volumeNumber, 1)
        chapterNumber = max(chapterDraft.chapterNumber, 1)
        chapterTitle = chapterDraft.chapterTitle
        chapterSummary = chapterDraft.chapterSummary
        wordCount = chapterDraft.wordCount
        savedAt = chapterDraft.savedAt
        previewText = chapterDraft.previewText
    }

    var savedAtDate: Date {
        PersistedTimestampCodec.parse(savedAt) ?? .distantPast
    }

    nonisolated static func sortDescending(_ lhs: ChapterDraftMetadata, _ rhs: ChapterDraftMetadata) -> Bool {
        if lhs.volumeNumber != rhs.volumeNumber {
            return lhs.volumeNumber > rhs.volumeNumber
        }
        if lhs.chapterNumber != rhs.chapterNumber {
            return lhs.chapterNumber > rhs.chapterNumber
        }
        return lhs.savedAtDate > rhs.savedAtDate
    }
}

struct OutlineGenerationProfile: Codable, Hashable {
    var storyFlow: String
    var worldDescription: String
    var protagonistTraits: String
    var expectedLength: String
    var endingPreference: String
    var sellingPoints: String
    var keyEvents: String
    var storyPacing: String
    var motivations: String
    var relationshipMap: String
    var antagonistPortrait: String
    var foreshadowingNotes: String

    static let empty = OutlineGenerationProfile(
        storyFlow: "",
        worldDescription: "",
        protagonistTraits: "",
        expectedLength: "",
        endingPreference: "",
        sellingPoints: "",
        keyEvents: "",
        storyPacing: "",
        motivations: "",
        relationshipMap: "",
        antagonistPortrait: "",
        foreshadowingNotes: ""
    )

    var completedRequiredFieldCount: Int {
        [
            storyFlow,
            worldDescription,
            protagonistTraits,
            expectedLength,
            endingPreference
        ]
        .filter { Self.hasContent($0) }
        .count
    }

    var filledOptionalFieldCount: Int {
        [
            sellingPoints,
            keyEvents,
            storyPacing,
            motivations,
            relationshipMap,
            antagonistPortrait,
            foreshadowingNotes
        ]
        .filter { Self.hasContent($0) }
        .count
    }

    var missingRequiredFieldLabels: [String] {
        var labels: [String] = []

        if !Self.hasContent(storyFlow) {
            labels.append("总体流程")
        }

        if !Self.hasContent(worldDescription) {
            labels.append("世界观描述")
        }

        if !Self.hasContent(protagonistTraits) {
            labels.append("主角性格标签")
        }

        if !Self.hasContent(expectedLength) {
            labels.append("预期字数")
        }

        if !Self.hasContent(endingPreference) {
            labels.append("结局偏好")
        }

        return labels
    }

    var hasMinimumRequirements: Bool {
        missingRequiredFieldLabels.isEmpty
    }

    var minimumRequirementSummary: String {
        if hasMinimumRequirements {
            return "最简可用的 5 项已准备完成，可以直接生成大纲。"
        }

        return "还差 \(missingRequiredFieldLabels.joined(separator: "、"))。"
    }

    private static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum LongformSearchResultKind: String, CaseIterable, Identifiable {
    case chapter
    case reference
    case memory
    case outline
    case entity

    var id: Self { self }

    var title: String {
        switch self {
        case .chapter:
            return "章节"
        case .reference:
            return "素材"
        case .memory:
            return "记忆"
        case .outline:
            return "大纲"
        case .entity:
            return "实体"
        }
    }
}

struct LongformSearchResult: Identifiable, Hashable {
    let id: String
    let kind: LongformSearchResultKind
    let title: String
    let subtitle: String
    let excerpt: String
    let score: Int
    let chapterID: ChapterDraft.ID?
    let referenceDocumentID: ReferenceDocument.ID?
}

struct GlobalMemorySnapshot: Codable, Hashable {
    enum Section: String, CaseIterable {
        case recentDevelopments = "前情推进"
        case characterRelations = "人物关系"
        case identityChanges = "身份变化"
        case injuries = "伤势状态"
        case factions = "阵营立场"
        case locations = "关键地点"
        case items = "关键道具"
        case worldState = "世界状态"
        case unresolvedForeshadowing = "未回收伏笔"
    }

    var recentDevelopments: String
    var characterRelations: String
    var identityChanges: String
    var injuries: String
    var factions: String
    var locations: String
    var items: String
    var worldState: String
    var unresolvedForeshadowing: String

    static let empty = GlobalMemorySnapshot(
        recentDevelopments: "",
        characterRelations: "",
        identityChanges: "",
        injuries: "",
        factions: "",
        locations: "",
        items: "",
        worldState: "",
        unresolvedForeshadowing: ""
    )

    var populatedSectionCount: Int {
        Section.allCases
            .map(value(for:))
            .filter { Self.hasContent($0) }
            .count
    }

    var hasStructuredContent: Bool {
        populatedSectionCount > 0
    }

    var formattedText: String {
        Section.allCases
            .map { section in
                "\(section.rawValue)：\n\(formattedValue(for: section))"
            }
            .joined(separator: "\n\n")
    }

    func value(for section: Section) -> String {
        switch section {
        case .recentDevelopments:
            return recentDevelopments
        case .characterRelations:
            return characterRelations
        case .identityChanges:
            return identityChanges
        case .injuries:
            return injuries
        case .factions:
            return factions
        case .locations:
            return locations
        case .items:
            return items
        case .worldState:
            return worldState
        case .unresolvedForeshadowing:
            return unresolvedForeshadowing
        }
    }

    mutating func setValue(_ value: String, for section: Section) {
        switch section {
        case .recentDevelopments:
            recentDevelopments = value
        case .characterRelations:
            characterRelations = value
        case .identityChanges:
            identityChanges = value
        case .injuries:
            injuries = value
        case .factions:
            factions = value
        case .locations:
            locations = value
        case .items:
            items = value
        case .worldState:
            worldState = value
        case .unresolvedForeshadowing:
            unresolvedForeshadowing = value
        }
    }

    static func parse(from text: String) -> GlobalMemorySnapshot {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return .empty }

        var snapshot = GlobalMemorySnapshot.empty
        var currentSection: Section?

        for rawLine in trimmedText.components(separatedBy: CharacterSet.newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let matchedSection = matchedSection(for: line) {
                currentSection = matchedSection
                let header = matchedSection.rawValue
                let remainder = line
                    .replacingOccurrences(of: header, with: "", options: [.anchored])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "：: "))

                if !remainder.isEmpty {
                    append(remainder, to: matchedSection, in: &snapshot)
                }

                continue
            }

            if let currentSection {
                append(line, to: currentSection, in: &snapshot)
            }
        }

        if !snapshot.hasStructuredContent {
            snapshot.recentDevelopments = trimmedText
        }

        return snapshot
    }

    private func formattedValue(for section: Section) -> String {
        let trimmed = value(for: section).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.placeholder(for: section) : trimmed
    }

    private static func append(_ line: String, to section: Section, in snapshot: inout GlobalMemorySnapshot) {
        let existing = snapshot.value(for: section).trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            snapshot.setValue(line, for: section)
        } else {
            snapshot.setValue(existing + "\n" + line, for: section)
        }
    }

    private static func matchedSection(for line: String) -> Section? {
        Section.allCases.first { section in
            line.hasPrefix(section.rawValue)
        }
    }

    private static func placeholder(for section: Section) -> String {
        switch section {
        case .recentDevelopments:
            return "- 待补当前长期记忆中的前情推进。"
        case .characterRelations:
            return "- 暂无人际关系的新变化。"
        case .identityChanges:
            return "- 暂无身份或立场变化。"
        case .injuries:
            return "- 暂无明确伤势变化。"
        case .factions:
            return "- 暂无阵营归属更新。"
        case .locations:
            return "- 暂无关键地点状态更新。"
        case .items:
            return "- 暂无关键道具变化。"
        case .worldState:
            return "- 暂无世界状态的新变化。"
        case .unresolvedForeshadowing:
            return "- 暂无新增待回收伏笔。"
        }
    }

    private static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - ForeshadowEntry (结构化伏笔追踪)

/// 结构化伏笔条目，追踪每条伏笔的状态和生命周期
struct ForeshadowEntry: Codable, Identifiable, Hashable {
    let id: String
    var title: String                      // 伏笔标题/描述
    var description: String                // 详细描述
    var firstChapter: Int                 // 首次出现章节
    var volumeNumber: Int                // 所属卷
    var status: ForeshadowStatus          // 当前状态
    var importance: ForeshadowImportance  // 重要程度
    var threads: [String]                // 关联的叙事线/线程
    var lastAdvancedChapter: Int         // 最后推进的章节
    var plantedChapter: Int             // 埋下的章节
    var resolutionChapter: Int?         // 回收的章节（resolved时填充）
    var expectedResolutionChapter: Int?  // 预期回收章节
    var createdAt: Date                 // 创建时间
    var updatedAt: Date                // 更新时间
    var notes: String                 // 额外备注

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        firstChapter: Int,
        volumeNumber: Int = 1,
        status: ForeshadowStatus = .active,
        importance: ForeshadowImportance = .minor,
        threads: [String] = [],
        lastAdvancedChapter: Int = 0,
        plantedChapter: Int = 0,
        resolutionChapter: Int? = nil,
        expectedResolutionChapter: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.firstChapter = firstChapter
        self.volumeNumber = volumeNumber
        self.status = status
        self.importance = importance
        self.threads = threads
        self.lastAdvancedChapter = lastAdvancedChapter
        self.plantedChapter = plantedChapter
        self.resolutionChapter = resolutionChapter
        self.expectedResolutionChapter = expectedResolutionChapter
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
    }

    /// 推进伏笔到下一状态
    mutating func advance(to chapter: Int) {
        lastAdvancedChapter = chapter
        updatedAt = Date()

        switch status {
        case .active:
            status = .advanced
        case .advanced:
            // 保持 advanced 状态，可以多次推进
            break
        case .resolved, .retconned, .overdue:
            // 已解决或过期的伏笔不再推进
            break
        }
    }

    /// 标记伏笔为已回收
    mutating func resolve(at chapter: Int) {
        status = .resolved
        resolutionChapter = chapter
        updatedAt = Date()
    }

    /// 标记伏笔为已废弃（retcon）
    mutating func markRetconned() {
        status = .retconned
        updatedAt = Date()
    }

    /// 检查伏笔是否超时（超过预期章节仍未回收）
    var isOverdue: Bool {
        guard let expected = expectedResolutionChapter else { return false }
        return status != .resolved && lastAdvancedChapter > expected
    }

    /// 伏笔活跃天数
    var activeDays: Int {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
    }

    /// 是否在近N章内被推进
    func wasRecent(chaptersAgo: Int, currentChapter: Int) -> Bool {
        currentChapter - lastAdvancedChapter <= chaptersAgo
    }
}

/// 伏笔状态
enum ForeshadowStatus: String, Codable, CaseIterable {
    case active      // 活跃，未推进
    case advanced    // 已推进
    case resolved    // 已回收
    case retconned   // 已废弃/取消
    case overdue     // 超时未回收

    var displayName: String {
        switch self {
        case .active: return "活跃"
        case .advanced: return "推进中"
        case .resolved: return "已回收"
        case .retconned: return "已废弃"
        case .overdue: return "超时"
        }
    }

    var symbolName: String {
        switch self {
        case .active: return "flag.fill"
        case .advanced: return "flag.fill"
        case .resolved: return "checkmark.circle.fill"
        case .retconned: return "xmark.circle.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .active: return "#4A90D9"
        case .advanced: return "#50C878"
        case .resolved: return "#808080"
        case .retconned: return "#FF6B6B"
        case .overdue: return "#FFA500"
        }
    }
}

/// 伏笔重要程度
enum ForeshadowImportance: String, Codable, CaseIterable {
    case major   // 重要伏笔（主线相关）
    case minor   // 次要伏笔（支线/装饰性）

    var displayName: String {
        switch self {
        case .major: return "重要"
        case .minor: return "次要"
        }
    }
}

/// 伏笔列表（用于NovelProject中）
struct ForeshadowList: Codable, Hashable {
    var entries: [ForeshadowEntry]

    init(entries: [ForeshadowEntry] = []) {
        self.entries = entries
    }

    // MARK: - 查询方法

    var activeEntries: [ForeshadowEntry] {
        entries.filter { $0.status == .active || $0.status == .advanced }
    }

    var resolvedEntries: [ForeshadowEntry] {
        entries.filter { $0.status == .resolved }
    }

    var overdueEntries: [ForeshadowEntry] {
        entries.filter { $0.isOverdue }
    }

    func entries(forVolume volume: Int) -> [ForeshadowEntry] {
        entries.filter { $0.volumeNumber == volume }
    }

    func entries(forThread thread: String) -> [ForeshadowEntry] {
        entries.filter { $0.threads.contains(thread) }
    }

    // MARK: - 状态统计

    var totalCount: Int { entries.count }
    var activeCount: Int { activeEntries.count }
    var resolvedCount: Int { resolvedEntries.count }
    var overdueCount: Int { overdueEntries.count }

    var resolutionRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(resolvedCount) / Double(totalCount)
    }

    // MARK: - 操作方法

    mutating func add(_ entry: ForeshadowEntry) {
        entries.append(entry)
    }

    mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    mutating func update(_ entry: ForeshadowEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        }
    }

    mutating func advanceForeshadow(id: String, to chapter: Int) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].advance(to: chapter)
        }
    }

    mutating func resolveForeshadow(id: String, at chapter: Int) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].resolve(at: chapter)
        }
    }

    /// 清理已解决的旧伏笔（保留最近N条）
    mutating func pruneResolved(keeping last: Int = 50) {
        let resolved = entries.filter { $0.status == .resolved }
        let other = entries.filter { $0.status != .resolved }
        let toKeep = resolved.suffix(last)
        entries = other + Array(toKeep)
    }
}

struct NovelProject: Identifiable, Codable {
    let id: String
    let title: String
    let genre: String
    let summary: String
    var storyLength: NovelLength
    private var updatedAtTimestamp: Date
    var currentChapterTitle: String
    var currentVolumeNumber: Int
    var currentChapterNumber: Int
    var writtenChapters: Int
    var chapterFocus: String
    var draftText: String
    var outlineText: String
    var outlineGenerationProfile: OutlineGenerationProfile
    var structureNotes: String
    var sceneProgressNotes: String
    var characterArcNotes: String
    var foreshadowNotes: String
    var volumePlanNotes: String
    var activeThreadsNotes: String
    var outlineSummary: String
    private var outlineSummaryUpdatedAtTimestamp: Date?
    var referenceContextText: String
    var specialRequirements: String
    var wordTargetText: String
    var continuityNotes: String
    var globalMemorySnapshot: GlobalMemorySnapshot
    private var globalMemoryUpdatedAtTimestamp: Date?
    var referenceDocuments: [ReferenceDocument]
    var chapterDrafts: [ChapterDraft]
    var chapterCatalog: [ChapterDraftMetadata]
    /// 题材模板 ID（可选，关联 GenreTemplate）
    var genreTemplateId: String?
    /// Strand Weave 节奏追踪器
    var strandWeaveTracker: StrandWeaveTracker
    /// 质量审查报告历史
    var qualityReviewReports: [QualityReviewReport]
    /// 结构化伏笔列表
    var foreshadowList: ForeshadowList

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case genre
        case summary
        case storyLength
        case updatedAt
        case currentChapterTitle
        case currentVolumeNumber
        case currentChapterNumber
        case writtenChapters
        case chapterFocus
        case draftText
        case outlineText
        case outlineGenerationProfile
        case structureNotes
        case sceneProgressNotes
        case characterArcNotes
        case foreshadowNotes
        case volumePlanNotes
        case activeThreadsNotes
        case outlineSummary
        case outlineSummaryUpdatedAt
        case referenceContextText
        case specialRequirements
        case wordTargetText
        case continuityNotes
        case globalMemorySnapshot
        case globalMemoryUpdatedAt
        case referenceDocuments
        case chapterDrafts
        case chapterCatalog
        case chapters
        case genreTemplateId
        case strandWeaveTracker
        case qualityReviewReports
        case foreshadowList
    }

    init(
        id: String,
        title: String,
        genre: String,
        summary: String,
        storyLength: NovelLength = .long,
        updatedAt: String,
        currentChapterTitle: String,
        currentVolumeNumber: Int = 1,
        currentChapterNumber: Int,
        writtenChapters: Int,
        chapterFocus: String,
        draftText: String,
        outlineText: String,
        outlineGenerationProfile: OutlineGenerationProfile = .empty,
        structureNotes: String = "",
        sceneProgressNotes: String = "",
        characterArcNotes: String = "",
        foreshadowNotes: String = "",
        volumePlanNotes: String = "",
        activeThreadsNotes: String = "",
        outlineSummary: String = "",
        outlineSummaryUpdatedAt: String = "",
        referenceContextText: String,
        specialRequirements: String,
        wordTargetText: String,
        continuityNotes: String,
        globalMemorySnapshot: GlobalMemorySnapshot = .empty,
        globalMemoryUpdatedAt: String = "",
        referenceDocuments: [ReferenceDocument],
        chapterDrafts: [ChapterDraft] = [],
        chapterCatalog: [ChapterDraftMetadata] = [],
        genreTemplateId: String? = nil,
        strandWeaveTracker: StrandWeaveTracker? = nil,
        qualityReviewReports: [QualityReviewReport]? = nil
    ) {
        self.id = id
        self.title = title
        self.genre = genre
        self.summary = summary
        self.storyLength = storyLength
        self.updatedAtTimestamp = PersistedTimestampCodec.parse(updatedAt) ?? PersistedTimestampCodec.now()
        self.currentChapterTitle = currentChapterTitle
        self.currentVolumeNumber = max(currentVolumeNumber, 1)
        self.currentChapterNumber = currentChapterNumber
        self.writtenChapters = writtenChapters
        self.chapterFocus = chapterFocus
        self.draftText = draftText
        self.outlineText = outlineText
        self.outlineGenerationProfile = outlineGenerationProfile
        self.structureNotes = structureNotes
        self.sceneProgressNotes = sceneProgressNotes
        self.characterArcNotes = characterArcNotes
        self.foreshadowNotes = foreshadowNotes
        self.volumePlanNotes = volumePlanNotes
        self.activeThreadsNotes = activeThreadsNotes
        self.outlineSummary = outlineSummary
        self.outlineSummaryUpdatedAtTimestamp = PersistedTimestampCodec.parseOptional(outlineSummaryUpdatedAt)
        self.referenceContextText = referenceContextText
        self.specialRequirements = specialRequirements
        self.wordTargetText = wordTargetText
        self.continuityNotes = continuityNotes
        let normalizedGlobalMemory = globalMemorySnapshot.hasStructuredContent
            ? globalMemorySnapshot
            : GlobalMemorySnapshot.parse(from: continuityNotes)
        self.globalMemorySnapshot = normalizedGlobalMemory
        self.globalMemoryUpdatedAtTimestamp = PersistedTimestampCodec.parseOptional(globalMemoryUpdatedAt)
        self.referenceDocuments = referenceDocuments
        self.chapterDrafts = chapterDrafts
        self.chapterCatalog = chapterCatalog.isEmpty
            ? chapterDrafts.map(ChapterDraftMetadata.init).sorted(by: ChapterDraftMetadata.sortDescending)
            : chapterCatalog
        self.genreTemplateId = genreTemplateId
        self.strandWeaveTracker = strandWeaveTracker ?? StrandWeaveTracker()
        self.qualityReviewReports = qualityReviewReports ?? []
        self.foreshadowList = ForeshadowList()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        genre = try container.decode(String.self, forKey: .genre)
        summary = try container.decode(String.self, forKey: .summary)
        storyLength = try container.decodeIfPresent(NovelLength.self, forKey: .storyLength) ?? .long
        updatedAtTimestamp = try PersistedTimestampCodec.decodeRequired(container, forKey: .updatedAt)
        currentChapterTitle = try container.decodeIfPresent(String.self, forKey: .currentChapterTitle) ?? "开篇设定"
        currentVolumeNumber = try container.decodeIfPresent(Int.self, forKey: .currentVolumeNumber) ?? 1
        currentChapterNumber = try container.decodeIfPresent(Int.self, forKey: .currentChapterNumber) ?? 1
        writtenChapters = try container.decodeIfPresent(Int.self, forKey: .writtenChapters)
            ?? container.decodeIfPresent(Int.self, forKey: .chapters)
            ?? max(currentChapterNumber, 1)
        chapterFocus = try container.decodeIfPresent(String.self, forKey: .chapterFocus)
            ?? "继续补齐当前章节的目标、冲突和场景节奏。"
        draftText = try container.decodeIfPresent(String.self, forKey: .draftText) ?? ""
        outlineText = try container.decodeIfPresent(String.self, forKey: .outlineText) ?? ""
        outlineGenerationProfile = try container.decodeIfPresent(OutlineGenerationProfile.self, forKey: .outlineGenerationProfile) ?? .empty
        structureNotes = try container.decodeIfPresent(String.self, forKey: .structureNotes) ?? ""
        sceneProgressNotes = try container.decodeIfPresent(String.self, forKey: .sceneProgressNotes) ?? ""
        characterArcNotes = try container.decodeIfPresent(String.self, forKey: .characterArcNotes) ?? ""
        foreshadowNotes = try container.decodeIfPresent(String.self, forKey: .foreshadowNotes) ?? ""
        volumePlanNotes = try container.decodeIfPresent(String.self, forKey: .volumePlanNotes) ?? ""
        activeThreadsNotes = try container.decodeIfPresent(String.self, forKey: .activeThreadsNotes) ?? ""
        outlineSummary = try container.decodeIfPresent(String.self, forKey: .outlineSummary) ?? ""
        outlineSummaryUpdatedAtTimestamp = PersistedTimestampCodec.decodeOptional(container, forKey: .outlineSummaryUpdatedAt)
        referenceContextText = try container.decodeIfPresent(String.self, forKey: .referenceContextText) ?? ""
        specialRequirements = try container.decodeIfPresent(String.self, forKey: .specialRequirements) ?? ""
        wordTargetText = try container.decodeIfPresent(String.self, forKey: .wordTargetText) ?? ""
        continuityNotes = try container.decodeIfPresent(String.self, forKey: .continuityNotes) ?? ""
        globalMemorySnapshot = try container.decodeIfPresent(GlobalMemorySnapshot.self, forKey: .globalMemorySnapshot)
            ?? GlobalMemorySnapshot.parse(from: continuityNotes)
        globalMemoryUpdatedAtTimestamp = PersistedTimestampCodec.decodeOptional(container, forKey: .globalMemoryUpdatedAt)
        referenceDocuments = try container.decodeIfPresent([ReferenceDocument].self, forKey: .referenceDocuments) ?? []
        chapterDrafts = try container.decodeIfPresent([ChapterDraft].self, forKey: .chapterDrafts) ?? []
        chapterCatalog = try container.decodeIfPresent([ChapterDraftMetadata].self, forKey: .chapterCatalog)
            ?? chapterDrafts.map(ChapterDraftMetadata.init).sorted(by: ChapterDraftMetadata.sortDescending)
        genreTemplateId = try container.decodeIfPresent(String.self, forKey: .genreTemplateId)
        strandWeaveTracker = try container.decodeIfPresent(StrandWeaveTracker.self, forKey: .strandWeaveTracker) ?? StrandWeaveTracker()
        qualityReviewReports = try container.decodeIfPresent([QualityReviewReport].self, forKey: .qualityReviewReports) ?? []
        foreshadowList = try container.decodeIfPresent(ForeshadowList.self, forKey: .foreshadowList) ?? ForeshadowList()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(genre, forKey: .genre)
        try container.encode(summary, forKey: .summary)
        try container.encode(storyLength, forKey: .storyLength)
        try PersistedTimestampCodec.encode(updatedAtTimestamp, to: &container, forKey: .updatedAt)
        try container.encode(currentChapterTitle, forKey: .currentChapterTitle)
        try container.encode(currentVolumeNumber, forKey: .currentVolumeNumber)
        try container.encode(currentChapterNumber, forKey: .currentChapterNumber)
        try container.encode(writtenChapters, forKey: .writtenChapters)
        try container.encode(chapterFocus, forKey: .chapterFocus)
        try container.encode(draftText, forKey: .draftText)
        try container.encode(outlineText, forKey: .outlineText)
        try container.encode(outlineGenerationProfile, forKey: .outlineGenerationProfile)
        try container.encode(structureNotes, forKey: .structureNotes)
        try container.encode(sceneProgressNotes, forKey: .sceneProgressNotes)
        try container.encode(characterArcNotes, forKey: .characterArcNotes)
        try container.encode(foreshadowNotes, forKey: .foreshadowNotes)
        try container.encode(volumePlanNotes, forKey: .volumePlanNotes)
        try container.encode(activeThreadsNotes, forKey: .activeThreadsNotes)
        try container.encode(outlineSummary, forKey: .outlineSummary)
        try PersistedTimestampCodec.encodeIfPresent(outlineSummaryUpdatedAtTimestamp, to: &container, forKey: .outlineSummaryUpdatedAt)
        try container.encode(referenceContextText, forKey: .referenceContextText)
        try container.encode(specialRequirements, forKey: .specialRequirements)
        try container.encode(wordTargetText, forKey: .wordTargetText)
        try container.encode(continuityNotes, forKey: .continuityNotes)
        try container.encode(globalMemorySnapshot, forKey: .globalMemorySnapshot)
        try PersistedTimestampCodec.encodeIfPresent(globalMemoryUpdatedAtTimestamp, to: &container, forKey: .globalMemoryUpdatedAt)
        try container.encode(referenceDocuments, forKey: .referenceDocuments)
        try container.encode(chapterDrafts, forKey: .chapterDrafts)
        try container.encode(chapterCatalog, forKey: .chapterCatalog)
        try container.encodeIfPresent(genreTemplateId, forKey: .genreTemplateId)
        try container.encode(strandWeaveTracker, forKey: .strandWeaveTracker)
        try container.encode(qualityReviewReports, forKey: .qualityReviewReports)
    }

    var currentChapterLabel: String {
        currentVolumeNumber > 1 ? "第 \(currentVolumeNumber) 卷 · 第 \(currentChapterNumber) 章" : "第 \(currentChapterNumber) 章"
    }

    var currentChapterSummary: String {
        "\(currentChapterLabel) · \(currentChapterTitle)"
    }

    var storyLengthTitle: String {
        storyLength.title
    }

    var updatedAt: String {
        get { PersistedTimestampCodec.displayLabel(for: updatedAtTimestamp, style: .project) }
        set { updatedAtTimestamp = PersistedTimestampCodec.parse(newValue) ?? PersistedTimestampCodec.now() }
    }

    var updatedAtDate: Date {
        get { updatedAtTimestamp }
        set { updatedAtTimestamp = newValue }
    }

    var outlineSummaryUpdatedAt: String {
        get { PersistedTimestampCodec.displayLabel(for: outlineSummaryUpdatedAtTimestamp, style: .project) }
        set { outlineSummaryUpdatedAtTimestamp = PersistedTimestampCodec.parseOptional(newValue) }
    }

    var outlineSummaryUpdatedAtDate: Date? {
        get { outlineSummaryUpdatedAtTimestamp }
        set { outlineSummaryUpdatedAtTimestamp = newValue }
    }

    var globalMemoryUpdatedAt: String {
        get { PersistedTimestampCodec.displayLabel(for: globalMemoryUpdatedAtTimestamp, style: .project) }
        set { globalMemoryUpdatedAtTimestamp = PersistedTimestampCodec.parseOptional(newValue) }
    }

    var globalMemoryUpdatedAtDate: Date? {
        get { globalMemoryUpdatedAtTimestamp }
        set { globalMemoryUpdatedAtTimestamp = newValue }
    }

    var savedChapterCount: Int {
        sortedChapterCatalog.count
    }

    var sortedChapterCatalog: [ChapterDraftMetadata] {
        if chapterCatalog.isEmpty {
            return chapterDrafts
                .map(ChapterDraftMetadata.init)
                .sorted(by: ChapterDraftMetadata.sortDescending)
        }

        return chapterCatalog.sorted(by: ChapterDraftMetadata.sortDescending)
    }

    var duplicateChapterNumbers: [Int] {
        let grouped = Dictionary(grouping: sortedChapterCatalog, by: \.chapterNumber)
        return grouped
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    var missingChapterNumbers: [Int] {
        let chapterNumbers = Set(sortedChapterCatalog.map(\.chapterNumber))
        guard let highest = chapterNumbers.max(), highest > 1 else { return [] }
        return (1...highest).filter { !chapterNumbers.contains($0) }
    }

    var chapterIntegrityStatusLabel: String {
        if duplicateChapterNumbers.isEmpty && missingChapterNumbers.isEmpty {
            return "目录连续"
        }

        var issues: [String] = []
        if !missingChapterNumbers.isEmpty {
            issues.append("缺 \(missingChapterNumbers.count) 章")
        }
        if !duplicateChapterNumbers.isEmpty {
            issues.append("重 \(duplicateChapterNumbers.count) 处")
        }
        return issues.joined(separator: " · ")
    }

    var sortedChapterDrafts: [ChapterDraft] {
        chapterDrafts.sorted(by: ChapterDraft.sortDescending)
    }

    var hasSavedCurrentChapter: Bool {
        chapterDrafts.contains(where: {
            $0.volumeNumber == currentVolumeNumber && $0.chapterNumber == currentChapterNumber
        })
    }

    var materialCategoriesWithContent: [ReferenceMaterialCategory] {
        ReferenceMaterialCategory.allCases.filter { category in
            referenceDocuments.contains(where: { $0.category == category })
        }
    }

    func referenceDocuments(in category: ReferenceMaterialCategory) -> [ReferenceDocument] {
        referenceDocuments.filter { $0.category == category }
    }

    var hasOutline: Bool {
        !outlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasStructureNotes: Bool {
        !structureNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSceneProgressNotes: Bool {
        !sceneProgressNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCharacterArcNotes: Bool {
        !characterArcNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasForeshadowNotes: Bool {
        !foreshadowNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasVolumePlanNotes: Bool {
        !volumePlanNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasActiveThreadsNotes: Bool {
        !activeThreadsNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasContinuityNotes: Bool {
        !continuityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasGlobalMemory: Bool {
        hasContinuityNotes || globalMemorySnapshot.hasStructuredContent
    }

    var hasOutlineSummary: Bool {
        !outlineSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var outlineStatusLabel: String {
        hasOutline ? "已导入" : "待补充"
    }

    var structureStatusLabel: String {
        hasStructureNotes ? "\(structureNodeCount) 节点" : "待拆分"
    }

    var sceneProgressStatusLabel: String {
        hasSceneProgressNotes ? "\(sceneProgressNodeCount) 场景" : "待拆分"
    }

    var characterArcStatusLabel: String {
        hasCharacterArcNotes ? "\(characterArcNodeCount) 条" : "待补充"
    }

    var foreshadowStatusLabel: String {
        hasForeshadowNotes ? "\(foreshadowNodeCount) 条" : "待标记"
    }

    // MARK: - 结构化伏笔列表计算属性

    var foreshadowListActiveCount: Int {
        foreshadowList.activeCount
    }

    var foreshadowListResolvedCount: Int {
        foreshadowList.resolvedCount
    }

    var foreshadowListOverdueCount: Int {
        foreshadowList.overdueCount
    }

    var foreshadowListResolutionRate: String {
        String(format: "%.0f%%", foreshadowList.resolutionRate * 100)
    }

    var hasForeshadowList: Bool {
        !foreshadowList.entries.isEmpty
    }

    var foreshadowListStatusLabel: String {
        "\(foreshadowList.activeCount) 活跃 / \(foreshadowList.resolvedCount) 已回收"
    }

    var volumePlanStatusLabel: String {
        guard storyLength.supportsVolumePlanning else { return "非分卷模式" }
        return hasVolumePlanNotes ? "\(volumePlanNodeCount) 节点" : "待规划"
    }

    var activeThreadsStatusLabel: String {
        guard storyLength.supportsThreadTracking else { return "单篇闭环" }
        return hasActiveThreadsNotes ? "\(activeThreadNodeCount) 条" : "待记录"
    }

    var continuityStatusLabel: String {
        hasGlobalMemory ? "已记录" : "待补充"
    }

    var globalMemoryStatusLabel: String {
        hasGlobalMemory ? (globalMemoryUpdatedAt.isEmpty ? "已更新" : globalMemoryUpdatedAt) : "待生成"
    }

    var outlineSummaryStatusLabel: String {
        hasOutlineSummary ? (outlineSummaryUpdatedAt.isEmpty ? "已生成" : outlineSummaryUpdatedAt) : "待生成"
    }

    var referenceStatusLabel: String {
        referenceDocuments.isEmpty ? "未导入" : "\(referenceDocuments.count) 份"
    }

    var structureNodeCount: Int {
        Self.outlineNodeCount(in: hasStructureNotes ? structureNotes : outlineText)
    }

    var sceneProgressNodeCount: Int {
        Self.outlineNodeCount(in: sceneProgressNotes)
    }

    var characterArcNodeCount: Int {
        Self.outlineNodeCount(in: characterArcNotes)
    }

    var foreshadowNodeCount: Int {
        Self.outlineNodeCount(in: foreshadowNotes)
    }

    var volumePlanNodeCount: Int {
        Self.outlineNodeCount(in: volumePlanNotes)
    }

    var activeThreadNodeCount: Int {
        Self.outlineNodeCount(in: activeThreadsNotes)
    }

    var draftWordCount: Int {
        draftText
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }

    var savedChapterWordCount: Int {
        chapterDrafts.reduce(0) { $0 + $1.wordCount }
    }

    var manuscriptWordCount: Int {
        savedChapterWordCount + draftWordCount
    }

    var estimatedTargetWordCount: Int? {
        Self.estimatedWordTarget(from: wordTargetText)
            ?? Self.estimatedWordTarget(from: outlineGenerationProfile.expectedLength)
    }

    var completionPercentage: Int? {
        guard let estimatedTargetWordCount, estimatedTargetWordCount > 0 else { return nil }
        return min(999, Int((Double(manuscriptWordCount) / Double(estimatedTargetWordCount)) * 100))
    }

    var completionStatusLabel: String {
        guard let completionPercentage else { return "未设定" }
        return "\(completionPercentage)%"
    }

    var draftParagraphCount: Int {
        let paragraphs = draftText
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.count
    }

    var draftPreview: String {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "正文还没有展开，可以先写下当前场景的起笔句。" }
        guard trimmed.count > 120 else { return trimmed }
        return String(trimmed.suffix(120))
    }

    var draftContinuationCache: String {
        let source = previousChapterDraftForContinuation?.content ?? ""
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > 400 else { return trimmed }
        return String(trimmed.suffix(400))
    }

    var draftContinuationCacheCount: Int {
        draftContinuationCache.count
    }

    var previousChapterDraftForContinuation: ChapterDraft? {
        let sortedDrafts = sortedChapterDrafts

        if let directPrevious = sortedDrafts.first(where: { $0.chapterNumber == currentChapterNumber - 1 }) {
            return directPrevious
        }

        return sortedDrafts
            .filter { $0.chapterNumber < currentChapterNumber }
            .max { $0.chapterNumber < $1.chapterNumber }
    }

    private static func outlineNodeCount(in text: String) -> Int {
        text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private static func estimatedWordTarget(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let rangePattern = #"(\d+(?:\.\d+)?)\s*(万|千)?\s*[-~—–至到]\s*(\d+(?:\.\d+)?)\s*(万|千)?\s*字?"#
        let singlePattern = #"(\d+(?:\.\d+)?)\s*(万|千)?\s*字"#
        let projectKeywords = ["全书", "全文", "总字数", "总计", "预计", "完本", "全稿"]

        func normalizedValue(_ numberText: String, unit: String?) -> Int? {
            guard let base = Double(numberText) else { return nil }
            switch unit {
            case "万":
                return Int(base * 10_000)
            case "千":
                return Int(base * 1_000)
            default:
                return Int(base)
            }
        }

        func context(for range: NSRange) -> String {
            let lowerBound = max(0, range.location - 14)
            let upperBound = min(nsText.length, range.location + range.length + 14)
            return nsText.substring(with: NSRange(location: lowerBound, length: upperBound - lowerBound))
        }

        if let rangeExpression = try? NSRegularExpression(pattern: rangePattern) {
            let candidates = rangeExpression.matches(in: trimmed, range: fullRange).compactMap { match -> (value: Int, score: Int)? in
                guard match.numberOfRanges >= 5 else { return nil }
                let lowerText = nsText.substring(with: match.range(at: 1))
                let lowerUnit = match.range(at: 2).location == NSNotFound ? nil : nsText.substring(with: match.range(at: 2))
                let upperText = nsText.substring(with: match.range(at: 3))
                let upperUnit = match.range(at: 4).location == NSNotFound ? lowerUnit : nsText.substring(with: match.range(at: 4))
                guard
                    let lower = normalizedValue(lowerText, unit: lowerUnit),
                    let upper = normalizedValue(upperText, unit: upperUnit)
                else { return nil }
                let value = max(lower, upper)
                let score = projectKeywords.contains(where: context(for: match.range).contains) ? 2 : 1
                return (value, score)
            }

            if let best = candidates.max(by: { lhs, rhs in
                lhs.score == rhs.score ? lhs.value < rhs.value : lhs.score < rhs.score
            }) {
                return best.value
            }
        }

        if let singleExpression = try? NSRegularExpression(pattern: singlePattern) {
            let candidates = singleExpression.matches(in: trimmed, range: fullRange).compactMap { match -> (value: Int, score: Int)? in
                guard match.numberOfRanges >= 3 else { return nil }
                let numberText = nsText.substring(with: match.range(at: 1))
                let unit = match.range(at: 2).location == NSNotFound ? nil : nsText.substring(with: match.range(at: 2))
                guard let value = normalizedValue(numberText, unit: unit), value >= 10_000 else { return nil }
                let score = projectKeywords.contains(where: context(for: match.range).contains) ? 2 : 1
                return (value, score)
            }

            if let best = candidates.max(by: { lhs, rhs in
                lhs.score == rhs.score ? lhs.value < rhs.value : lhs.score < rhs.score
            }) {
                return best.value
            }
        }

        return nil
    }
}

struct ReferenceDocument: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let content: String
    private var importedAtTimestamp: Date
    var category: ReferenceMaterialCategory

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case importedAt
        case category
    }

    var importedAt: String {
        get { PersistedTimestampCodec.displayLabel(for: importedAtTimestamp, style: .compact) }
        set { importedAtTimestamp = PersistedTimestampCodec.parse(newValue) ?? PersistedTimestampCodec.now() }
    }

    var importedAtDate: Date {
        get { importedAtTimestamp }
        set { importedAtTimestamp = newValue }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        importedAt: String,
        category: ReferenceMaterialCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.importedAtTimestamp = PersistedTimestampCodec.parse(importedAt) ?? PersistedTimestampCodec.now()
        self.category = category ?? ReferenceMaterialCategory.infer(fromTitle: title, content: content)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        importedAtTimestamp = try PersistedTimestampCodec.decodeRequired(container, forKey: .importedAt)
        category = try container.decodeIfPresent(ReferenceMaterialCategory.self, forKey: .category)
            ?? ReferenceMaterialCategory.infer(fromTitle: title, content: content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try PersistedTimestampCodec.encode(importedAtTimestamp, to: &container, forKey: .importedAt)
        try container.encode(category, forKey: .category)
    }

    var wordCount: Int {
        content
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }

    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 140 else { return trimmed }
        return String(trimmed.prefix(140)) + "…"
    }
}

enum ReferenceMaterialCategory: String, CaseIterable, Codable, Identifiable {
    case character
    case location
    case organization
    case worldbuilding
    case plot
    case research
    case reference

    var id: Self { self }

    var title: String {
        switch self {
        case .character:
            return "人物"
        case .location:
            return "地点"
        case .organization:
            return "组织"
        case .worldbuilding:
            return "世界观"
        case .plot:
            return "剧情"
        case .research:
            return "考据"
        case .reference:
            return "参考"
        }
    }

    var symbolName: String {
        switch self {
        case .character:
            return "person.crop.circle"
        case .location:
            return "map"
        case .organization:
            return "building.2"
        case .worldbuilding:
            return "globe.asia.australia"
        case .plot:
            return "timeline.selection"
        case .research:
            return "magnifyingglass"
        case .reference:
            return "book.closed"
        }
    }

    var summary: String {
        switch self {
        case .character:
            return "角色设定、关系卡、人物小传"
        case .location:
            return "地点、地图、场景空间信息"
        case .organization:
            return "组织、家族、阵营与势力资料"
        case .worldbuilding:
            return "世界规则、历史、制度与背景"
        case .plot:
            return "剧情节点、大纲补充与场景草案"
        case .research:
            return "考据、资料摘录与外部研究"
        case .reference:
            return "风格参考与暂未细分的素材"
        }
    }

    static func infer(fromTitle title: String, content: String) -> ReferenceMaterialCategory {
        let source = "\(title)\n\(content)".lowercased()

        if source.contains(anyOf: ["角色", "人物", "主角", "配角", "反派", "小传", "关系"]) {
            return .character
        }

        if source.contains(anyOf: ["地点", "地图", "城市", "港口", "山脉", "村", "街区", "场景"]) {
            return .location
        }

        if source.contains(anyOf: ["组织", "家族", "阵营", "公司", "宗门", "议会", "协会"]) {
            return .organization
        }

        if source.contains(anyOf: ["世界观", "设定", "规则", "历史", "神话", "纪年", "文明"]) {
            return .worldbuilding
        }

        if source.contains(anyOf: ["剧情", "大纲", "章节", "场景推进", "转折", "主线", "支线"]) {
            return .plot
        }

        if source.contains(anyOf: ["资料", "考据", "研究", "参考文献", "访谈", "历史原型"]) {
            return .research
        }

        return .reference
    }
}

struct StoryPillar: Identifiable {
    let title: String
    let detail: String

    var id: String { title }
}

struct InspirationSignal: Identifiable {
    let title: String
    let description: String

    var id: String { title }
}

enum ChapterTreeSectionMergeDecision {
    case accepted
    case protected
    case ignored

    var accepted: Bool {
        if case .accepted = self { return true }
        return false
    }

    var protectedLocalChange: Bool {
        if case .protected = self { return true }
        return false
    }
}

private extension String {
    func contains(anyOf keywords: [String]) -> Bool {
        keywords.contains(where: { contains($0.lowercased()) })
    }
}
