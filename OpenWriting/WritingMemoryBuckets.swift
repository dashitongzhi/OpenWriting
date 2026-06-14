import Foundation

// MARK: - Memory Item

/// A single structured memory fact, inspired by webnovel-writer's memory schema.
/// Each item belongs to a category bucket and carries a lifecycle status.
struct MemoryItem: Identifiable, Codable, Hashable {
    let id: String
    var category: MemoryCategory
    var subject: String
    var field: String
    var value: String
    var status: MemoryItemStatus
    var sourceVolumeNumber: Int
    var sourceChapter: Int
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case subject
        case field
        case value
        case status
        case sourceVolumeNumber
        case sourceChapter
        case updatedAt
    }

    init(
        id: String = UUID().uuidString,
        category: MemoryCategory,
        subject: String,
        field: String,
        value: String,
        status: MemoryItemStatus = .active,
        sourceVolumeNumber: Int = 1,
        sourceChapter: Int,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.subject = subject
        self.field = field
        self.value = value
        self.status = status
        self.sourceVolumeNumber = max(sourceVolumeNumber, 1)
        self.sourceChapter = sourceChapter
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        category = try container.decode(MemoryCategory.self, forKey: .category)
        subject = try container.decode(String.self, forKey: .subject)
        field = try container.decode(String.self, forKey: .field)
        value = try container.decode(String.self, forKey: .value)
        status = try container.decodeIfPresent(MemoryItemStatus.self, forKey: .status) ?? .active
        sourceVolumeNumber = max(try container.decodeIfPresent(Int.self, forKey: .sourceVolumeNumber) ?? 1, 1)
        sourceChapter = try container.decode(Int.self, forKey: .sourceChapter)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(subject, forKey: .subject)
        try container.encode(field, forKey: .field)
        try container.encode(value, forKey: .value)
        try container.encode(status, forKey: .status)
        try container.encode(sourceVolumeNumber, forKey: .sourceVolumeNumber)
        try container.encode(sourceChapter, forKey: .sourceChapter)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var sourceLabel: String {
        sourceVolumeNumber > 1 ? "第\(sourceVolumeNumber)卷第\(sourceChapter)章" : "第\(sourceChapter)章"
    }

    /// Deterministic dedup key based on category rules
    var dedupKey: String {
        switch category {
        case .characterState, .relationship, .worldRule:
            return "\(subject)|\(field)"
        case .storyFact, .timeline:
            return "\(subject)|\(field)|v\(sourceVolumeNumber)|c\(sourceChapter)"
        case .openLoop, .readerPromise:
            return subject
        }
    }
}

// MARK: - Memory Category (7 Buckets)

enum MemoryCategory: String, CaseIterable, Codable, Identifiable {
    case characterState = "character_state"
    case relationship = "relationship"
    case worldRule = "world_rule"
    case storyFact = "story_fact"
    case timeline = "timeline"
    case openLoop = "open_loop"
    case readerPromise = "reader_promise"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .characterState: return "角色状态"
        case .relationship: return "人物关系"
        case .worldRule: return "世界观规则"
        case .storyFact: return "剧情事实"
        case .timeline: return "时间线"
        case .openLoop: return "未回收伏笔"
        case .readerPromise: return "对读者的承诺"
        }
    }

    var priority: Int {
        switch self {
        case .worldRule: return 0
        case .characterState: return 1
        case .relationship: return 2
        case .storyFact: return 3
        case .openLoop: return 4
        case .readerPromise: return 5
        case .timeline: return 6
        }
    }
}

// MARK: - Memory Item Status (4-state lifecycle)

enum MemoryItemStatus: String, Codable, Hashable {
    case active
    case outdated
    case contradicted
    case tentative

    var displayName: String {
        switch self {
        case .active: return "生效"
        case .outdated: return "已过期"
        case .contradicted: return "有矛盾"
        case .tentative: return "待确认"
        }
    }
}

// MARK: - Memory Buckets (Structured Store)

/// The structured memory store replacing the flat `continuityNotes` string.
/// Persists as JSON alongside the project data.
struct MemoryBuckets: Codable, Hashable {
    var characterState: [MemoryItem]
    var relationships: [MemoryItem]
    var worldRules: [MemoryItem]
    var storyFacts: [MemoryItem]
    var timeline: [MemoryItem]
    var openLoops: [MemoryItem]
    var readerPromises: [MemoryItem]
    var lastCompactedAtChapter: Int

    static let empty = MemoryBuckets(
        characterState: [],
        relationships: [],
        worldRules: [],
        storyFacts: [],
        timeline: [],
        openLoops: [],
        readerPromises: [],
        lastCompactedAtChapter: 0
    )

    // MARK: - Bucket Access

    func bucket(for category: MemoryCategory) -> [MemoryItem] {
        switch category {
        case .characterState: return characterState
        case .relationship: return relationships
        case .worldRule: return worldRules
        case .storyFact: return storyFacts
        case .timeline: return timeline
        case .openLoop: return openLoops
        case .readerPromise: return readerPromises
        }
    }

    mutating func setBucket(_ items: [MemoryItem], for category: MemoryCategory) {
        switch category {
        case .characterState: characterState = items
        case .relationship: relationships = items
        case .worldRule: worldRules = items
        case .storyFact: storyFacts = items
        case .timeline: timeline = items
        case .openLoop: openLoops = items
        case .readerPromise: readerPromises = items
        }
    }

    /// Remove memory facts projected from one exact volume/chapter. Used when a
    /// saved chapter is rewritten, rolled back, or rejected by the longform gate.
    mutating func removeItems(sourceVolumeNumber: Int, sourceChapter: Int) {
        let normalizedVolume = max(sourceVolumeNumber, 1)
        for category in MemoryCategory.allCases {
            let filtered = bucket(for: category).filter { item in
                !(item.sourceVolumeNumber == normalizedVolume && item.sourceChapter == sourceChapter)
            }
            setBucket(Self.restoringLatestActiveItems(in: filtered), for: category)
        }
    }

    private static func restoringLatestActiveItems(in items: [MemoryItem]) -> [MemoryItem] {
        var restoredItems = items
        let keys = Set(restoredItems.map(\.dedupKey))

        for key in keys {
            let matchingIndices = restoredItems.indices.filter { restoredItems[$0].dedupKey == key }
            guard !matchingIndices.contains(where: { restoredItems[$0].status == .active }) else {
                continue
            }

            guard let restorationIndex = matchingIndices
                .filter({ restoredItems[$0].status == .outdated })
                .max(by: { lhs, rhs in
                    let left = restoredItems[lhs]
                    let right = restoredItems[rhs]
                    if left.sourceVolumeNumber != right.sourceVolumeNumber {
                        return left.sourceVolumeNumber < right.sourceVolumeNumber
                    }
                    if left.sourceChapter != right.sourceChapter {
                        return left.sourceChapter < right.sourceChapter
                    }
                    return left.updatedAt < right.updatedAt
                })
            else {
                continue
            }

            restoredItems[restorationIndex].status = .active
            restoredItems[restorationIndex].updatedAt = Date()
        }

        return restoredItems
    }

    // MARK: - Upsert (Dedup + Status Transition)

    /// Insert or update a memory item. If an existing active item shares the same
    /// dedup key, demote it to `outdated` and insert the new one as `active`.
    @discardableResult
    mutating func upsert(_ item: MemoryItem) -> Bool {
        var items = bucket(for: item.category)
        let targetKey = item.dedupKey
        var replaced = false

        // Demote existing active items with the same dedup key
        for i in items.indices {
            if items[i].dedupKey == targetKey && items[i].id != item.id {
                if items[i].status == .active {
                    items[i].status = .outdated
                    items[i].updatedAt = Date()
                    replaced = true
                }
            }
        }

        // Replace in-place if same id, otherwise append
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }

        setBucket(items, for: item.category)
        return replaced
    }

    // MARK: - Query Active Items

    /// Returns all active items across all buckets, sorted by category priority then source chapter.
    var allActiveItems: [MemoryItem] {
        MemoryCategory.allCases
            .flatMap { bucket(for: $0) }
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.category.priority != rhs.category.priority {
                    return lhs.category.priority < rhs.category.priority
                }
                if lhs.sourceVolumeNumber != rhs.sourceVolumeNumber {
                    return lhs.sourceVolumeNumber > rhs.sourceVolumeNumber
                }
                return lhs.sourceChapter > rhs.sourceChapter
            }
    }

    /// Returns active items filtered by relevance to a text query.
    func relevantActiveItems(for query: String, limit: Int = 30) -> [MemoryItem] {
        let queryLower = query.lowercased()
        let queryTokens = queryLower
            .components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { $0.count >= 2 }

        guard !queryTokens.isEmpty else {
            return Array(allActiveItems.prefix(limit))
        }

        let scored = allActiveItems.map { item -> (MemoryItem, Int) in
            let haystack = "\(item.subject) \(item.field) \(item.value)".lowercased()
            let score = queryTokens.reduce(0) { sum, token in
                haystack.contains(token) ? sum + token.count : sum
            }
            return (item, score)
        }

        return scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Conflict Detection

    /// Returns categories where multiple active items share the same dedup key.
    var conflicts: [(category: MemoryCategory, key: String, count: Int)] {
        MemoryCategory.allCases.flatMap { category in
            let items = bucket(for: category).filter { $0.status == .active }
            let grouped = Dictionary(grouping: items, by: { $0.dedupKey })
            return grouped
                .filter { $0.value.count > 1 }
                .map { (category: category, key: $0.key, count: $0.value.count) }
        }
    }

    // MARK: - Compaction

    /// Compact memory when items exceed threshold. Keeps latest outdated per key,
    /// removes resolved open loops, merges old timeline items.
    mutating func compact(currentVolumeNumber: Int = 1, currentChapter: Int, threshold: Int = 500) {
        let totalItems = MemoryCategory.allCases.reduce(0) { $0 + bucket(for: $1).count }
        guard totalItems > threshold else { return }
        let normalizedVolume = max(currentVolumeNumber, 1)

        // Stage 1: Keep only latest outdated per dedup key
        for category in MemoryCategory.allCases {
            let items = bucket(for: category)
            var latestOutdated: [String: MemoryItem] = [:]
            var nonOutdated: [MemoryItem] = []

            for item in items {
                if item.status == .outdated {
                    let key = item.dedupKey
                    if let existing = latestOutdated[key] {
                        if item.updatedAt > existing.updatedAt {
                            latestOutdated[key] = item
                        }
                    } else {
                        latestOutdated[key] = item
                    }
                } else {
                    nonOutdated.append(item)
                }
            }

            setBucket(nonOutdated + Array(latestOutdated.values), for: category)
        }

        // Stage 2: Remove resolved open loops
        openLoops = openLoops.filter { item in
            let v = item.value.lowercased()
            return !["已回收", "已解决", "已完成", "已兑现", "resolved", "closed", "done", "paid_off"]
                .contains(where: { v.contains($0) })
        }

        // Stage 3: Merge old timeline items (>50 chapters ago)
        let oldThreshold = max(currentChapter - 50, 1)
        let oldItems = timeline.filter { item in
            guard item.status == .active else { return false }
            if item.sourceVolumeNumber < normalizedVolume { return true }
            return item.sourceVolumeNumber == normalizedVolume && item.sourceChapter < oldThreshold
        }
        if oldItems.count > 3 {
            let summary = oldItems
                .sorted {
                    if $0.sourceVolumeNumber != $1.sourceVolumeNumber {
                        return $0.sourceVolumeNumber < $1.sourceVolumeNumber
                    }
                    return $0.sourceChapter < $1.sourceChapter
                }
                .prefix(8)
                .map { "\($0.sourceLabel): \($0.subject)" }
                .joined(separator: "；")
            let summaryItem = MemoryItem(
                category: .storyFact,
                subject: "timeline_summary",
                field: "历史事件概要",
                value: summary,
                sourceVolumeNumber: normalizedVolume,
                sourceChapter: oldThreshold
            )
            storyFacts.removeAll { $0.subject == "timeline_summary" }
            storyFacts.append(summaryItem)
            timeline.removeAll { item in
                guard item.status == .active else { return false }
                if item.sourceVolumeNumber < normalizedVolume { return true }
                return item.sourceVolumeNumber == normalizedVolume && item.sourceChapter < oldThreshold
            }
        }

        lastCompactedAtChapter = currentChapter
    }

    // MARK: - Migration from GlobalMemorySnapshot

    /// Migrate from the old flat GlobalMemorySnapshot format to structured buckets.
    static func migrate(from snapshot: GlobalMemorySnapshot, currentChapter: Int) -> MemoryBuckets {
        var buckets = MemoryBuckets.empty

        // Parse each section into structured items
        let mappings: [(GlobalMemorySnapshot.Section, MemoryCategory, String)] = [
            (.recentDevelopments, .storyFact, "前情推进"),
            (.characterRelations, .relationship, "人物关系"),
            (.identityChanges, .characterState, "身份变化"),
            (.injuries, .characterState, "伤势状态"),
            (.factions, .characterState, "阵营立场"),
            (.locations, .worldRule, "关键地点"),
            (.items, .worldRule, "关键道具"),
            (.worldState, .worldRule, "世界状态"),
            (.unresolvedForeshadowing, .openLoop, "未回收伏笔"),
        ]

        for (section, category, defaultField) in mappings {
            let text = snapshot.value(for: section).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "- 暂无明确变化" && $0 != "- 暂无新增" }

            for (i, line) in lines.enumerated() {
                let item = MemoryItem(
                    id: "migrated-\(category.rawValue)-\(i)",
                    category: category,
                    subject: defaultField,
                    field: "line_\(i)",
                    value: line.hasPrefix("- ") ? String(line.dropFirst(2)) : line,
                    status: .active,
                    sourceChapter: currentChapter
                )
                buckets.upsert(item)
            }
        }

        return buckets
    }

    // MARK: - Formatting for AI Context

    /// Format active items grouped by category for injection into AI prompts.
    var formattedForContext: String {
        var sections: [String] = []

        for category in MemoryCategory.allCases {
            let activeItems = bucket(for: category)
                .filter { $0.status == .active }
                .sorted {
                    if $0.sourceVolumeNumber != $1.sourceVolumeNumber {
                        return $0.sourceVolumeNumber > $1.sourceVolumeNumber
                    }
                    return $0.sourceChapter > $1.sourceChapter
                }

            guard !activeItems.isEmpty else { continue }

            let lines = activeItems.map { "- [\($0.sourceLabel) · \($0.subject)] \($0.field): \($0.value)" }
            sections.append("\(category.displayName):\n\(lines.joined(separator: "\n"))")
        }

        return sections.isEmpty ? "暂无结构化记忆。" : sections.joined(separator: "\n\n")
    }

    var totalActiveCount: Int {
        allActiveItems.count
    }

    var totalCount: Int {
        MemoryCategory.allCases.reduce(0) { $0 + bucket(for: $1).count }
    }
}
