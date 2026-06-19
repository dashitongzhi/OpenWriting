import Foundation

enum WritingSkillOrigin: String, Codable, CaseIterable {
    case imported
    case custom
    case marketplace

    var title: String {
        switch self {
        case .imported:
            return "导入"
        case .custom:
            return "自建"
        case .marketplace:
            return "广场"
        }
    }
}

enum WritingSkillCategory: String, Codable, CaseIterable, Identifiable {
    case voice
    case structure
    case genre
    case revision
    case research
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .voice:
            return "文风"
        case .structure:
            return "结构"
        case .genre:
            return "题材"
        case .revision:
            return "修订"
        case .research:
            return "考据"
        case .custom:
            return "自建"
        }
    }

    var symbolName: String {
        switch self {
        case .voice:
            return "text.quote"
        case .structure:
            return "list.bullet.rectangle.portrait"
        case .genre:
            return "sparkles"
        case .revision:
            return "checkmark.seal"
        case .research:
            return "magnifyingglass"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}

struct WritingSkill: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var summary: String
    var instructions: String
    var category: WritingSkillCategory
    var origin: WritingSkillOrigin
    var sourceName: String
    var isEnabled: Bool
    private var importedAtTimestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case instructions
        case category
        case origin
        case sourceName
        case isEnabled
        case importedAt
    }

    var importedAt: String {
        get { PersistedTimestampCodec.displayLabel(for: importedAtTimestamp, style: .compact) }
        set { importedAtTimestamp = PersistedTimestampCodec.parse(newValue) ?? PersistedTimestampCodec.now() }
    }

    var wordCount: Int {
        instructions
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .count
    }

    var previewText: String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        return String(trimmed.prefix(180)) + "..."
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        instructions: String,
        category: WritingSkillCategory,
        origin: WritingSkillOrigin,
        sourceName: String,
        isEnabled: Bool = true,
        importedAt: String = TimestampLabel.now()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.instructions = instructions
        self.category = category
        self.origin = origin
        self.sourceName = sourceName
        self.isEnabled = isEnabled
        self.importedAtTimestamp = PersistedTimestampCodec.parse(importedAt) ?? PersistedTimestampCodec.now()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        instructions = try container.decode(String.self, forKey: .instructions)
        category = try container.decodeIfPresent(WritingSkillCategory.self, forKey: .category) ?? .custom
        origin = try container.decodeIfPresent(WritingSkillOrigin.self, forKey: .origin) ?? .imported
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? title
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        importedAtTimestamp = try PersistedTimestampCodec.decodeRequired(container, forKey: .importedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(category, forKey: .category)
        try container.encode(origin, forKey: .origin)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try PersistedTimestampCodec.encode(importedAtTimestamp, to: &container, forKey: .importedAt)
    }

    func duplicateForImport(titleSuffix: String = "副本") -> WritingSkill {
        WritingSkill(
            title: "\(title)（\(titleSuffix)）",
            summary: summary,
            instructions: instructions,
            category: category,
            origin: origin,
            sourceName: sourceName,
            isEnabled: isEnabled
        )
    }
}

enum WritingSkillMarketplace {
    static let featured: [WritingSkill] = [
        WritingSkill(
            id: "marketplace-longform-continuity",
            title: "长篇连续性守门",
            summary: "续写前先压住人物状态、伏笔边界和上一章尾声，适合长篇连载。",
            instructions: """
            - 续写必须承接上一章末尾的动作、情绪和信息缺口，不要用总结式开头重讲设定。
            - 新增设定前先检查它是否服务本章目标、长期伏笔或人物关系变化。
            - 不提前揭示长期真相；需要制造信息增量时，优先给出可验证的线索、代价或选择。
            - 每一段场景推进都要让人物状态、局势压力或读者问题至少变化一项。
            """,
            category: .structure,
            origin: .marketplace,
            sourceName: "OpenWriting Skill 广场"
        ),
        WritingSkill(
            id: "marketplace-webnovel-hook",
            title: "网文追读钩子",
            summary: "强化章节内的小悬念、段尾推进和结尾追读，不牺牲连续性。",
            instructions: """
            - 每 600 到 900 字制造一次明确的信息增量、情绪翻面或行动压力。
            - 段尾避免空泛感叹，优先落在未完成动作、意外线索、关系错位或选择代价上。
            - 章节结尾留下一个下一章必须处理的问题，但不要用生硬断章破坏当前场景。
            - 钩子要来自现有设定和人物目标，不凭空添加大反转。
            """,
            category: .genre,
            origin: .marketplace,
            sourceName: "OpenWriting Skill 广场"
        ),
        WritingSkill(
            id: "marketplace-natural-dialogue",
            title: "对白自然化",
            summary: "降低说明腔，让对白承担试探、隐瞒、误解和关系推进。",
            instructions: """
            - 对白不要替作者解释世界观；人物只说自己此刻会说、敢说、想隐藏的话。
            - 长句说明拆成动作、停顿、反问和未说出口的信息。
            - 每段对白至少承担一种功能：推进关系、暴露欲望、制造误解、交换筹码或改变局势。
            - 避免所有角色同一种口吻；用词长度、礼貌程度和关注点区分人物。
            """,
            category: .voice,
            origin: .marketplace,
            sourceName: "OpenWriting Skill 广场"
        ),
        WritingSkill(
            id: "marketplace-revision-pass",
            title: "终稿减 AI 味",
            summary: "返修时优先删解释、压重复、补动作细节，让正文更像人工终稿。",
            instructions: """
            - 删除重复解释、抽象感慨和已经由动作表达过的心理复述。
            - 把泛泛的情绪词替换成可见动作、环境反应、身体感受或具体选择。
            - 保留剧情事实和段落顺序，只做必要的节奏、句式和细节修订。
            - 避免连续使用同构句式、成套转折词和总结性金句。
            """,
            category: .revision,
            origin: .marketplace,
            sourceName: "OpenWriting Skill 广场"
        )
    ]
}

enum WritingSkillImporting {
    private struct Payload: Decodable {
        let title: String?
        let name: String?
        let summary: String?
        let description: String?
        let instructions: String?
        let prompt: String?
        let category: WritingSkillCategory?
        let origin: WritingSkillOrigin?
    }

    static func skills(
        from urls: [URL],
        usingSecurityScopedAccess: Bool = true
    ) throws -> [WritingSkill] {
        try urls.map { try skill(from: $0, usingSecurityScopedAccess: usingSecurityScopedAccess) }
    }

    static func skill(
        from url: URL,
        usingSecurityScopedAccess: Bool = true
    ) throws -> WritingSkill {
        let content = try TextFileDecoding.loadText(from: url, usingSecurityScopedAccess: usingSecurityScopedAccess)
        let sourceName = url.lastPathComponent
        if url.pathExtension.lowercased() == "json",
           let data = content.data(using: .utf8),
           let payload = try? JSONDecoder().decode(Payload.self, from: data),
           let parsed = skill(from: payload, fallbackTitle: url.deletingPathExtension().lastPathComponent, sourceName: sourceName) {
            return parsed
        }

        return skill(fromMarkdown: content, fallbackTitle: url.deletingPathExtension().lastPathComponent, sourceName: sourceName)
    }

    private static func skill(from payload: Payload, fallbackTitle: String, sourceName: String) -> WritingSkill? {
        let title = [payload.title, payload.name, fallbackTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallbackTitle
        let instructions = [payload.instructions, payload.prompt]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let instructions else { return nil }

        let summary = [payload.summary, payload.description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? String(instructions.prefix(90))

        return WritingSkill(
            title: title,
            summary: summary,
            instructions: instructions,
            category: payload.category ?? inferCategory(title: title, content: instructions),
            origin: payload.origin ?? .imported,
            sourceName: sourceName
        )
    }

    private static func skill(fromMarkdown content: String, fallbackTitle: String, sourceName: String) -> WritingSkill {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        let heading = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }?
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = heading?.isEmpty == false ? heading! : fallbackTitle
        let summary = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
            ?? String(trimmed.prefix(90))

        return WritingSkill(
            title: title,
            summary: summary,
            instructions: trimmed,
            category: inferCategory(title: title, content: trimmed),
            origin: .imported,
            sourceName: sourceName
        )
    }

    private static func inferCategory(title: String, content: String) -> WritingSkillCategory {
        let sample = "\(title)\n\(content)".lowercased()
        if sample.contains("对白") || sample.contains("文风") || sample.contains("voice") || sample.contains("style") {
            return .voice
        }
        if sample.contains("结构") || sample.contains("大纲") || sample.contains("伏笔") || sample.contains("outline") {
            return .structure
        }
        if sample.contains("润色") || sample.contains("修订") || sample.contains("rewrite") || sample.contains("revision") {
            return .revision
        }
        if sample.contains("考据") || sample.contains("资料") || sample.contains("research") {
            return .research
        }
        if sample.contains("题材") || sample.contains("genre") || sample.contains("网文") {
            return .genre
        }
        return .custom
    }
}
