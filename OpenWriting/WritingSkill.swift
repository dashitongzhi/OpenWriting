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
            return "市场"
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

enum WritingSkillListingSource: String, Codable, Hashable {
    case curated
    case localSubmission

    var title: String {
        switch self {
        case .curated:
            return "官方精选"
        case .localSubmission:
            return "本机投稿"
        }
    }
}

struct WritingSkillMarketplaceListing: Codable, Hashable {
    var publisherName: String
    var version: String
    var source: WritingSkillListingSource
    var publishedAt: Date

    var publishedAtLabel: String {
        PersistedTimestampCodec.displayLabel(for: publishedAt, style: .compact)
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
    var marketplaceListing: WritingSkillMarketplaceListing?
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
        case marketplaceListing
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
        marketplaceListing: WritingSkillMarketplaceListing? = nil,
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
        self.marketplaceListing = marketplaceListing
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
        marketplaceListing = try container.decodeIfPresent(
            WritingSkillMarketplaceListing.self,
            forKey: .marketplaceListing
        )
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
        try container.encodeIfPresent(marketplaceListing, forKey: .marketplaceListing)
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
            isEnabled: isEnabled,
            marketplaceListing: nil
        )
    }

    func publishedForLocalMarketplace(
        publisherName: String,
        version: String = "1.0.0",
        publishedAt: Date = Date()
    ) -> WritingSkill {
        var published = self
        published.origin = .marketplace
        published.isEnabled = true
        published.marketplaceListing = WritingSkillMarketplaceListing(
            publisherName: publisherName,
            version: version,
            source: .localSubmission,
            publishedAt: publishedAt
        )
        return published
    }
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
