import Combine
import Foundation

// MARK: - Enhanced Memory System
// Three-layer memory architecture inspired by webnovel-writer

/// 记忆状态
enum MemoryStatus: String, Codable {
    case active = "active"         // 当前有效
    case outdated = "outdated"     // 已过时（被新值替代）
    case contradicted = "contradicted" // 存在矛盾
    case tentative = "tentative"   // 待确认
}

/// 记忆分桶
enum MemoryBucket: String, Codable, CaseIterable {
    case characterState = "character_state"
    case storyFacts = "story_facts"
    case worldRules = "world_rules"
    case timeline = "timeline"
    case openLoops = "open_loops"
    case readerPromises = "reader_promises"
    case relationships = "relationships"
    
    var displayName: String {
        switch self {
        case .characterState: return "角色状态"
        case .storyFacts: return "剧情事实"
        case .worldRules: return "世界观规则"
        case .timeline: return "时间线"
        case .openLoops: return "未回收伏笔"
        case .readerPromises: return "读者承诺"
        case .relationships: return "角色关系"
        }
    }
    
    var icon: String {
        switch self {
        case .characterState: return "👤"
        case .storyFacts: return "📖"
        case .worldRules: return "🌍"
        case .timeline: return "📅"
        case .openLoops: return "🔄"
        case .readerPromises: return "🤝"
        case .relationships: return "🕸️"
        }
    }
}

/// 单条记忆项
struct MemoryManagerItem: Codable, Identifiable {
    let id: UUID
    let bucket: MemoryBucket
    let subject: String
    let field: String
    var value: String
    var status: MemoryStatus
    let sourceChapter: Int
    var evidence: String?
    let createdAt: Date
    var updatedAt: Date
    
    init(bucket: MemoryBucket, subject: String, field: String, value: String,
         status: MemoryStatus = .active, sourceChapter: Int, evidence: String? = nil) {
        self.id = UUID()
        self.bucket = bucket
        self.subject = subject
        self.field = field
        self.value = value
        self.status = status
        self.sourceChapter = sourceChapter
        self.evidence = evidence
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// 去重 key
    var deduplicationKey: String {
        "\(bucket.rawValue):\(subject.lowercased()):\(field.lowercased())"
    }
}

/// 三层记忆架构
struct MemoryPack: Codable {
    /// Working Memory — 当前写作时的临时上下文
    var workingMemory: WorkingMemory
    /// Episodic Memory — 近期结构化历史证据
    var episodicMemory: [EpisodicMemoryEntry]
    /// Semantic Memory — 长期语义事实缓存
    var semanticMemory: SemanticMemoryStore
}

/// 工作记忆（不落盘，运行时组装）
struct WorkingMemory: Codable {
    var currentChapterOutline: String
    var recentSummaries: [String]
    var protagonistState: String
    var activePlotThreads: [String]
    var pendingDisambiguations: [String]
}

/// 情景记忆条目
struct EpisodicMemoryEntry: Codable, Identifiable {
    let id: UUID
    let chapterNumber: Int
    let eventType: String
    let description: String
    let timestamp: Date
    
    init(chapterNumber: Int, eventType: String, description: String) {
        self.id = UUID()
        self.chapterNumber = chapterNumber
        self.eventType = eventType
        self.description = description
        self.timestamp = Date()
    }
}

/// 语义记忆存储（长期记忆主真源）
struct SemanticMemoryStore: Codable {
    var items: [MemoryManagerItem]
    var lastCompactedAt: Date?
    var totalCompressions: Int
    
    init() {
        items = []
        lastCompactedAt = nil
        totalCompressions = 0
    }
    
    /// 按分桶获取活跃记忆
    func activeItems(in bucket: MemoryBucket) -> [MemoryManagerItem] {
        items.filter { $0.bucket == bucket && $0.status == .active }
    }
    
    /// 获取所有活跃记忆
    var allActiveItems: [MemoryManagerItem] {
        items.filter { $0.status == .active }
    }
    
    /// 获取冲突记忆
    var contradictedItems: [MemoryManagerItem] {
        items.filter { $0.status == .contradicted }
    }
}

/// 记忆管理器
class MemoryManager: ObservableObject {
    @Published var memoryPack: MemoryPack
    
    private let compactionThreshold = 500
    
    init() {
        self.memoryPack = MemoryPack(
            workingMemory: WorkingMemory(
                currentChapterOutline: "",
                recentSummaries: [],
                protagonistState: "",
                activePlotThreads: [],
                pendingDisambiguations: []
            ),
            episodicMemory: [],
            semanticMemory: SemanticMemoryStore()
        )
    }
    
    // MARK: - Write Operations
    
    /// 从章节结果更新记忆（写后沉淀）
    func updateFromChapterResult(_ result: ChapterCommitResult) {
        // 1. 更新情景记忆
        let entry = EpisodicMemoryEntry(
            chapterNumber: result.chapterNumber,
            eventType: "chapter_commit",
            description: result.summary
        )
        memoryPack.episodicMemory.append(entry)
        
        // 2. 更新语义记忆
        for fact in result.memoryFacts {
            upsertItem(fact)
        }
        
        // 3. 处理状态变化
        for change in result.stateChanges {
            let item = MemoryManagerItem(
                bucket: .characterState,
                subject: change.character,
                field: change.field,
                value: change.newValue,
                sourceChapter: result.chapterNumber,
                evidence: change.evidence
            )
            upsertItem(item)
        }
        
        // 4. 处理新实体
        for entity in result.newEntities {
            let item = MemoryManagerItem(
                bucket: .storyFacts,
                subject: entity.name,
                field: "introduction",
                value: entity.description,
                sourceChapter: result.chapterNumber
            )
            upsertItem(item)
        }
        
        // 5. 处理新关系
        for relation in result.newRelationships {
            let item = MemoryManagerItem(
                bucket: .relationships,
                subject: relation.from,
                field: relation.type,
                value: relation.to,
                sourceChapter: result.chapterNumber,
                evidence: relation.context
            )
            upsertItem(item)
        }
        
        // 6. 压缩检查
        if memoryPack.semanticMemory.items.count > compactionThreshold {
            compact()
        }
    }
    
    /// 插入或更新记忆项（去重 + 状态管理）
    func upsertItem(_ newItem: MemoryManagerItem) {
        let key = newItem.deduplicationKey
        
        // 查找已有的同 key 活跃项
        if let existingIndex = memoryPack.semanticMemory.items.firstIndex(where: {
            $0.deduplicationKey == key && $0.status == .active
        }) {
            // 旧值降级为 outdated
            memoryPack.semanticMemory.items[existingIndex].status = .outdated
            memoryPack.semanticMemory.items[existingIndex].updatedAt = Date()
        }
        
        // 检查是否与现有值矛盾
        let conflicting = memoryPack.semanticMemory.items.filter {
            $0.deduplicationKey == key && $0.status == .active && $0.value != newItem.value
        }
        if !conflicting.isEmpty {
            var contradictedItem = newItem
            contradictedItem.status = .contradicted
            memoryPack.semanticMemory.items.append(contradictedItem)
        } else {
            memoryPack.semanticMemory.items.append(newItem)
        }
    }
    
    /// 从章节提交结果创建记忆项
    func createMemoryFact(bucket: MemoryBucket, subject: String, field: String,
                          value: String, chapterNumber: Int, evidence: String? = nil) -> MemoryManagerItem {
        MemoryManagerItem(bucket: bucket, subject: subject, field: field, value: value,
                   sourceChapter: chapterNumber, evidence: evidence)
    }
    
    // MARK: - Read Operations
    
    /// 构建记忆包（写前注入）
    func buildMemoryPack(for chapterNumber: Int, outline: String) -> MemoryPack {
        // 更新工作记忆
        memoryPack.workingMemory.currentChapterOutline = outline
        
        return memoryPack
    }
    
    /// 查询角色当前状态
    func queryCharacterState(_ character: String) -> [MemoryManagerItem] {
        memoryPack.semanticMemory.activeItems(in: .characterState)
            .filter { $0.subject.lowercased() == character.lowercased() }
    }
    
    /// 查询世界观规则
    func queryWorldRules() -> [MemoryManagerItem] {
        memoryPack.semanticMemory.activeItems(in: .worldRules)
    }
    
    /// 查询未回收伏笔
    func getOpenLoops() -> [MemoryManagerItem] {
        memoryPack.semanticMemory.activeItems(in: .openLoops)
    }
    
    /// 查询时间线
    func getTimeline() -> [MemoryManagerItem] {
        memoryPack.semanticMemory.activeItems(in: .timeline)
            .sorted { $0.sourceChapter < $1.sourceChapter }
    }
    
    /// 查询角色关系
    func queryRelationships(_ character: String? = nil) -> [MemoryManagerItem] {
        let items = memoryPack.semanticMemory.activeItems(in: .relationships)
        if let character = character {
            return items.filter {
                $0.subject.lowercased() == character.lowercased() ||
                $0.value.lowercased() == character.lowercased()
            }
        }
        return items
    }
    
    // MARK: - Compression
    
    /// 压缩记忆（清理过时项，合并旧时间线）
    func compact() {
        var store = memoryPack.semanticMemory
        
        // 1. 同 key 的 outdated 只保留最新一条
        var seenKeys: [String: Int] = [:]
        var indicesToRemove: [Int] = []
        
        for (index, item) in store.items.enumerated() {
            if item.status == .outdated {
                if let existingIndex = seenKeys[item.deduplicationKey] {
                    indicesToRemove.append(existingIndex)
                }
                seenKeys[item.deduplicationKey] = index
            }
        }
        
        for index in indicesToRemove.sorted().reversed() {
            store.items.remove(at: index)
        }
        
        // 2. 清理已回收的伏笔
        store.items.removeAll { $0.bucket == .openLoops && $0.status == .outdated }
        
        // 3. 更新压缩信息
        store.lastCompactedAt = Date()
        store.totalCompressions += 1
        
        memoryPack.semanticMemory = store
    }
    
    // MARK: - Serialization
    
    /// 导出为可读文本（用于 AI 上下文注入）
    func exportAsText() -> String {
        var sections: [String] = []
        
        for bucket in MemoryBucket.allCases {
            let items = memoryPack.semanticMemory.activeItems(in: bucket)
            if !items.isEmpty {
                var section = "### \(bucket.icon) \(bucket.displayName)\n"
                for item in items {
                    section += "- **\(item.subject)**.**\(item.field)**: \(item.value)"
                    if let evidence = item.evidence {
                        section += " (来源: \(evidence))"
                    }
                    section += " [第\(item.sourceChapter)章]"
                    section += "\n"
                }
                sections.append(section)
            }
        }
        
        // 添加未回收伏笔
        let openLoops = getOpenLoops()
        if !openLoops.isEmpty {
            var section = "### 🔄 未回收伏笔\n"
            for item in openLoops {
                section += "- **\(item.subject)**: \(item.value) [第\(item.sourceChapter)章埋下]\n"
            }
            sections.append(section)
        }
        
        return sections.joined(separator: "\n")
    }
    
    /// 统计信息
    var stats: MemoryStats {
        let active = memoryPack.semanticMemory.allActiveItems.count
        let outdated = memoryPack.semanticMemory.items.filter { $0.status == .outdated }.count
        let contradicted = memoryPack.semanticMemory.contradictedItems.count
        let total = memoryPack.semanticMemory.items.count
        
        return MemoryStats(
            totalItems: total,
            activeItems: active,
            outdatedItems: outdated,
            contradictedItems: contradicted,
            episodicEntries: memoryPack.episodicMemory.count,
            compressionCount: memoryPack.semanticMemory.totalCompressions
        )
    }
}

/// 记忆统计
struct MemoryStats {
    let totalItems: Int
    let activeItems: Int
    let outdatedItems: Int
    let contradictedItems: Int
    let episodicEntries: Int
    let compressionCount: Int
}

// MARK: - Chapter Commit Result (for memory integration)

/// 章节提交结果
struct ChapterCommitResult {
    let chapterNumber: Int
    let summary: String
    let stateChanges: [StateChange]
    let newEntities: [NewEntity]
    let newRelationships: [NewRelationship]
    let memoryFacts: [MemoryManagerItem]
}

struct StateChange {
    let character: String
    let field: String
    let oldValue: String
    let newValue: String
    let evidence: String?
}

struct NewEntity {
    let name: String
    let type: String
    let description: String
}

struct NewRelationship {
    let from: String
    let to: String
    let type: String
    let context: String?
}
