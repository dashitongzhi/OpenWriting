import Foundation

// MARK: - Genre Template Engine
//
// Core logic and library for genre templates.
// Data types are in GenreTemplateData.swift.

/// Provides parameterized genre configurations that tune the AI writing behavior.
/// Inspired by webnovel-writer's genre profiles and template system.

// MARK: - Genre Template Library

enum GenreTemplateLibrary {

    static let allTemplates: [GenreTemplate] = buildTemplates()

    /// Find the best matching template for a genre string
    static func template(for genre: String) -> GenreTemplate {
        let genreLower = genre.lowercased()

        // Try exact match first
        if let exact = allTemplates.first(where: { $0.name.lowercased() == genreLower }) {
            return exact
        }

        // Try fuzzy match
        for template in allTemplates {
            if genreLower.contains(template.name.lowercased())
                || template.name.lowercased().contains(genreLower) {
                return template
            }
        }

        // Category-level match
        if genreLower.contains("修仙") || genreLower.contains("玄幻") {
            return allTemplates.first(where: { $0.name == "修仙" }) ?? defaultTemplate
        }
        if genreLower.contains("都市") {
            return allTemplates.first(where: { $0.name == "都市异能" }) ?? defaultTemplate
        }
        if genreLower.contains("言情") || genreLower.contains("甜宠") {
            return allTemplates.first(where: { $0.name == "青春甜宠" }) ?? defaultTemplate
        }
        if genreLower.contains("悬疑") || genreLower.contains("怪谈") {
            return allTemplates.first(where: { $0.name == "规则怪谈" }) ?? defaultTemplate
        }

        return defaultTemplate
    }

    static let defaultTemplate = GenreTemplate(
        id: "default",
        name: "通用",
        category: .xuanhuan,
        description: "适用于未指定题材的通用写作配置",
        coreSellingPoint: "角色成长 + 冲突推进 + 阶段性胜利",
        preferredHookTypes: [.crisis, .desire, .mystery],
        hookStrengthBaseline: .medium,
        preferredCoolPointPatterns: [.flexAndCounter, .underdogVictory],
        coolPointDensity: .medium,
        stagnationThreshold: 3,
        setupTolerance: .medium,
        strandConfig: .defaultConfig,
        writingDirectives: [
            "章首300字内给出目标与阻力",
            "章末保留未闭合问题",
            "每600-900字给一次微兑现",
            "避免连续3段以上相同句式",
        ],
        antiPatterns: [
            "不要用缓缓/淡淡/微微开头的万能描写",
            "不要每段结尾都写总结句",
            "不要直接标注情绪（他感到愤怒）",
            "不要用他不知道的是作为旁白开头",
        ]
    )

    // MARK: - Build Templates

    private static func buildTemplates() -> [GenreTemplate] {
        let combined = buildCoreTemplates() + migrateLegacyTemplates() + buildAdditionalTemplates()
        // Deduplicate by id (legacy migration can collide with core entries like
        // "高武" and "都市日常"), preserving first occurrence order.
        var seen = Set<String>()
        var unique: [GenreTemplate] = []
        for template in combined where seen.insert(template.id).inserted {
            unique.append(template)
        }
        return unique
    }

    /// Core templates defined in the new system (hand-authored, not migrated from legacy).
    private static func buildCoreTemplates() -> [GenreTemplate] {
        buildXuanhuanCoreTemplates()
        + buildUrbanCoreTemplates()
        + buildRomanceCoreTemplates()
        + buildMysteryCoreTemplates()
    }

    // MARK: Xuanhuan (玄幻) — Core

    private static func buildXuanhuanCoreTemplates() -> [GenreTemplate] {
        [
            GenreTemplate(
                id: "xianxia",
                name: "修仙",
                category: .xuanhuan,
                description: "修仙题材，强调升级体系、宗门争斗、机缘争夺",
                coreSellingPoint: "境界突破 + 机缘争夺 + 以弱胜强",
                preferredHookTypes: [.crisis, .desire, .mystery],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.underdogVictory, .flexAndCounter, .underdogReveal],
                coolPointDensity: .high,
                stagnationThreshold: 4,
                setupTolerance: .medium,
                strandConfig: GenreStrandConfig(
                    genre: "修仙", questTarget: 0.60, fireTarget: 0.20,
                    constellationTarget: 0.20, questMaxConsecutive: 6,
                    fireMaxGap: 12, constellationMaxGap: 15
                ),
                writingDirectives: [
                    "境界体系要清晰，突破要有可见反馈",
                    "机缘四步法：传闻→探索→冲突→收获",
                    "宗门/势力关系要服务于主线冲突",
                    "章末留钩：下一境界、下一个对手、下一个机缘",
                ],
                antiPatterns: [
                    "不要平白无故突破境界",
                    "不要让配角无条件帮忙",
                    "不要跳过战斗直接写结果",
                ]
            ),

            GenreTemplate(
                id: "system",
                name: "系统流",
                category: .xuanhuan,
                description: "系统面板驱动，强调任务完成、属性成长、奖励获取",
                coreSellingPoint: "系统任务 + 属性成长 + 奖励机制",
                preferredHookTypes: [.desire, .crisis, .choice],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.underdogVictory, .flexAndCounter, .misinterpretation],
                coolPointDensity: .high,
                stagnationThreshold: 3,
                setupTolerance: .low,
                strandConfig: .defaultConfig,
                writingDirectives: [
                    "系统提示要有仪式感",
                    "任务难度要递进",
                    "属性成长要有可视化体现",
                    "奖励要与当前困境形成呼应",
                ],
                antiPatterns: [
                    "不要让系统提示过于冗长",
                    "不要无条件给奖励",
                    "不要跳过任务直接给结果",
                ]
            ),
        ]
    }

    // MARK: Urban (都市) — Core

    private static func buildUrbanCoreTemplates() -> [GenreTemplate] {
        [
            GenreTemplate(
                id: "urban异能",
                name: "都市异能",
                category: .urban,
                description: "都市背景下的异能/超能力题材，强调都市风云和身份冲突",
                coreSellingPoint: "异能展示 + 都市风云 + 身份张力",
                preferredHookTypes: [.crisis, .desire, .mystery],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.flexAndCounter, .identityReveal, .underdogVictory],
                coolPointDensity: .high,
                stagnationThreshold: 3,
                setupTolerance: .low,
                strandConfig: GenreStrandConfig(
                    genre: "都市异能", questTarget: 0.55, fireTarget: 0.25,
                    constellationTarget: 0.20, questMaxConsecutive: 5,
                    fireMaxGap: 8, constellationMaxGap: 12
                ),
                writingDirectives: [
                    "异能不能随意扩展，必须有代价或限制",
                    "都市背景要有真实细节",
                    "身份冲突要贯穿主线",
                    "每次异能使用要有代价反馈",
                ],
                antiPatterns: [
                    "不要让异能无代价使用",
                    "不要跳过代价直接写结果",
                ]
            ),

            GenreTemplate(
                id: "都市日常",
                name: "都市日常",
                category: .urban,
                description: "轻松都市题材，节奏舒缓，强调人际和温情",
                coreSellingPoint: "人际温馨 + 日常感 + 角色成长",
                preferredHookTypes: [.emotion, .desire],
                hookStrengthBaseline: .weak,
                preferredCoolPointPatterns: [.sweetSurprise, .misinterpretation],
                coolPointDensity: .low,
                stagnationThreshold: 5,
                setupTolerance: .high,
                strandConfig: GenreStrandConfig(
                    genre: "都市日常", questTarget: 0.30, fireTarget: 0.40,
                    constellationTarget: 0.30, questMaxConsecutive: 4,
                    fireMaxGap: 15, constellationMaxGap: 20
                ),
                writingDirectives: [
                    "节奏舒缓，但每章至少一个小高潮或温馨点",
                    "角色互动要有细节和个性",
                    "避免大段背景介绍，用对话和行为带出",
                ],
                antiPatterns: [
                    "不要节奏拖沓无推进",
                    "不要全是流水账日常",
                ]
            ),
        ]
    }

    // MARK: Romance (言情) — Core

    private static func buildRomanceCoreTemplates() -> [GenreTemplate] {
        [
            GenreTemplate(
                id: "青春甜宠",
                name: "青春甜宠",
                category: .romance,
                description: "轻松甜蜜的言情题材，感情线甜宠为主",
                coreSellingPoint: "甜蜜互动 + 心动瞬间 + 关系升温",
                preferredHookTypes: [.emotion, .desire, .choice],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.sweetSurprise, .misinterpretation],
                coolPointDensity: .high,
                stagnationThreshold: 3,
                setupTolerance: .low,
                strandConfig: GenreStrandConfig(
                    genre: "青春甜宠", questTarget: 0.40, fireTarget: 0.35,
                    constellationTarget: 0.25, questMaxConsecutive: 4,
                    fireMaxGap: 10, constellationMaxGap: 12
                ),
                writingDirectives: [
                    "每章至少一个甜蜜或心动瞬间",
                    "互动要有拉扯感，不要一步到位",
                    "误会和吃醋是推进感情的好工具",
                    "章末留钩引导读者期待下一章",
                ],
                antiPatterns: [
                    "不要一上来就互表心意",
                    "不要缺少拉扯和误会",
                    "不要感情线推进过慢或过快",
                ]
            ),

            GenreTemplate(
                id: "古言",
                name: "古言",
                category: .romance,
                description: "古代背景言情，强调古风氛围和情感纠葛",
                coreSellingPoint: "古风美感 + 情感纠葛 + 身份冲突",
                preferredHookTypes: [.emotion, .crisis, .mystery],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.sweetSurprise, .identityReveal, .villainDownfall],
                coolPointDensity: .medium,
                stagnationThreshold: 4,
                setupTolerance: .medium,
                strandConfig: GenreStrandConfig(
                    genre: "古言", questTarget: 0.50, fireTarget: 0.25,
                    constellationTarget: 0.25, questMaxConsecutive: 5,
                    fireMaxGap: 12, constellationMaxGap: 15
                ),
                writingDirectives: [
                    "语言风格要统一在古风氛围内",
                    "情感纠葛要有层次",
                    "章末留悬念引导期待",
                ],
                antiPatterns: [
                    "不要语言风格混杂古今",
                    "不要情感推进过于平淡",
                ]
            ),
        ]
    }

    // MARK: Mystery (悬疑) — Core

    private static func buildMysteryCoreTemplates() -> [GenreTemplate] {
        [
            GenreTemplate(
                id: "规则怪谈",
                name: "规则怪谈",
                category: .mystery,
                description: "规则类怪谈，强调悬疑氛围和规则逻辑",
                coreSellingPoint: "悬疑氛围 + 规则逻辑 + 生存压力",
                preferredHookTypes: [.mystery, .crisis],
                hookStrengthBaseline: .strong,
                preferredCoolPointPatterns: [.misinterpretation, .villainDownfall],
                coolPointDensity: .medium,
                stagnationThreshold: 2,
                setupTolerance: .veryLow,
                strandConfig: GenreStrandConfig(
                    genre: "规则怪谈", questTarget: 0.70, fireTarget: 0.15,
                    constellationTarget: 0.15, questMaxConsecutive: 4,
                    fireMaxGap: 8, constellationMaxGap: 10
                ),
                writingDirectives: [
                    "规则必须前后一致，不得随意更改",
                    "悬疑氛围要贯穿始终",
                    "每章至少一个悬念或反转",
                    "章末必须留有未解之谜",
                ],
                antiPatterns: [
                    "不要规则自相矛盾",
                    "不要悬疑解决过于轻易",
                    "不要缺少生存压力",
                ]
            ),
        ]
    }

    // MARK: - Additional Templates

    private static func buildAdditionalTemplates() -> [GenreTemplate] {
        [
            GenreTemplate(
                id: "高武",
                name: "高武",
                category: .xuanhuan,
                description: "高端武力体系，强调战斗力和越级挑战",
                coreSellingPoint: "武力压制 + 越级战斗 + 尊严对决",
                preferredHookTypes: [.crisis, .desire],
                hookStrengthBaseline: .strong,
                preferredCoolPointPatterns: [.underdogVictory, .flexAndCounter, .authorityChallenge],
                coolPointDensity: .high,
                stagnationThreshold: 3,
                setupTolerance: .veryLow,
                strandConfig: GenreStrandConfig(
                    genre: "高武", questTarget: 0.65, fireTarget: 0.20,
                    constellationTarget: 0.15, questMaxConsecutive: 5,
                    fireMaxGap: 10, constellationMaxGap: 12
                ),
                writingDirectives: [
                    "战斗场面要精彩，不能跳过过程",
                    "越级挑战要有策略和智慧",
                    "每次战斗后要有收获和成长",
                ],
                antiPatterns: [
                    "不要让越级挑战过于简单",
                    "不要跳过战斗细节",
                ]
            ),
        ]
    }

    // MARK: - Legacy Template Migration

    /// Look up a legacy genre template by name
    private static func lookupLegacy(_ name: String) -> LegacyGenreTemplate? {
        LegacyGenreTemplateLibrary.lookup(name)
    }

    private static func migrateLegacyTemplates() -> [GenreTemplate] {
        let legacyNames = [
            "高武", "西幻", "无限流", "末世", "科幻",
            "都市日常", "都市脑洞", "电竞", "直播文", "现实题材",
            "宫斗宅斗", "豪门总裁", "职场婚恋", "幻想言情",
            "悬疑脑洞", "悬疑灵异", "克苏鲁", "狗血言情",
        ]
        return legacyNames.compactMap { name -> GenreTemplate? in
            guard let legacy = lookupLegacy(name) else {
                #if DEBUG
                print("[GenreTemplateEngine] Warning: legacy template '\(name)' not found, skipping")
                #endif
                return nil
            }
            return migrateLegacyTemplate(legacy)
        }
    }

    private static func migrateLegacyTemplate(_ legacy: LegacyGenreTemplate) -> GenreTemplate {
        let category = mapLegacyCategory(legacy.category)
        let hookTypes = inferHookTypes(from: legacy.hookPatterns)
        let coolPatterns = inferCoolPointPatterns(from: legacy.pleasurePointTypes)
        let strandConfig = buildStrandConfig(id: legacy.id, name: legacy.name, ratio: legacy.strandRatio)

        var directives: [String] = []
        for rule in legacy.worldRules.prefix(3) { directives.append(rule) }
        directives.append(legacy.pacingGuide)
        for hook in legacy.hookPatterns.prefix(2) { directives.append("章末钩子参考：\(hook)") }

        let antiPatterns: [String] = [
            "不要让配角行为与人设不符（当前角色原型：\(legacy.characterArchetypes.joined(separator: "、"))）",
            "不要违反世界观核心规则"
        ]

        return GenreTemplate(
            id: legacy.id,
            name: legacy.name,
            category: category,
            description: legacy.description,
            coreSellingPoint: legacy.pleasurePointTypes.prefix(3).joined(separator: " + "),
            preferredHookTypes: hookTypes,
            hookStrengthBaseline: .medium,
            preferredCoolPointPatterns: coolPatterns,
            coolPointDensity: coolPatterns.count >= 3 ? .high : (coolPatterns.count >= 2 ? .medium : .low),
            stagnationThreshold: 3,
            setupTolerance: category == .mystery ? .high : .medium,
            strandConfig: strandConfig,
            writingDirectives: directives,
            antiPatterns: antiPatterns
        )
    }

    // MARK: - Composite Genre Support

    /// Check if "与" is used as a genre separator (short strings on each side, max 6 chars).
    /// Avoids splitting natural text like "奇幻与冒险的旅程".
    private static func hasYuSeparator(_ text: String) -> Bool {
        guard let range = text.range(of: "与") else { return false }
        let leftPart = String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        var rightPart = ""
        var i = range.upperBound
        while i < text.endIndex {
            let char = text[i]
            if char == "+" || char == "/" || char == "、" || char == "与" { break }
            rightPart.append(char)
            i = text.index(after: i)
        }
        let rightTrimmed = rightPart.trimmingCharacters(in: .whitespacesAndNewlines)
        return leftPart.count <= 6 && rightTrimmed.count <= 6
    }

    /// Split composite genre string, treating "与" as separator only when both sides are short (≤6 chars).
    private static func splitCompositeGenre(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var i = input.startIndex
        while i < input.endIndex {
            let char = input[i]
            if char == "+" || char == "/" || char == "、" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                current = ""
            } else if char == "与" {
                let leftTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                var rightPart = ""
                var j = input.index(after: i)
                while j < input.endIndex {
                    let rChar = input[j]
                    if rChar == "+" || rChar == "/" || rChar == "、" || rChar == "与" { break }
                    rightPart.append(rChar)
                    j = input.index(after: j)
                }
                let rightTrimmed = rightPart.trimmingCharacters(in: .whitespacesAndNewlines)
                if leftTrimmed.count <= 6 && rightTrimmed.count <= 6 {
                    if !leftTrimmed.isEmpty { parts.append(leftTrimmed) }
                    current = ""
                } else {
                    current.append(char)
                }
            } else {
                current.append(char)
            }
            i = input.index(after: i)
        }
        let lastTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastTrimmed.isEmpty { parts.append(lastTrimmed) }
        return parts
    }

    /// Resolve a composite genre string like "都市异能+规则怪谈" into a merged template
    static func resolveComposite(_ input: String) -> GenreTemplate {
        let parts = splitCompositeGenre(input)

        guard parts.count > 1 else { return template(for: input) }

        let templates = parts.map { template(for: $0) }
        let primary = templates[0]

        var allDirectives = primary.writingDirectives
        var allAntiPatterns = primary.antiPatterns
        var allHookTypes = primary.preferredHookTypes
        var allCoolPatterns = primary.preferredCoolPointPatterns

        for secondary in templates.dropFirst() {
            for directive in secondary.writingDirectives where !allDirectives.contains(directive) {
                allDirectives.append(directive)
            }
            for pattern in secondary.antiPatterns where !allAntiPatterns.contains(pattern) {
                allAntiPatterns.append(pattern)
            }
            for hook in secondary.preferredHookTypes where !allHookTypes.contains(hook) {
                allHookTypes.append(hook)
            }
            for cool in secondary.preferredCoolPointPatterns where !allCoolPatterns.contains(cool) {
                allCoolPatterns.append(cool)
            }
        }

        return GenreTemplate(
            id: "composite_\(primary.id)",
            name: parts.joined(separator: "+"),
            category: primary.category,
            description: "复合题材：\(templates.map { $0.name }.joined(separator: " + "))",
            coreSellingPoint: templates.map { $0.coreSellingPoint }.joined(separator: " | "),
            preferredHookTypes: allHookTypes,
            hookStrengthBaseline: primary.hookStrengthBaseline,
            preferredCoolPointPatterns: allCoolPatterns,
            coolPointDensity: primary.coolPointDensity,
            stagnationThreshold: primary.stagnationThreshold,
            setupTolerance: primary.setupTolerance,
            strandConfig: primary.strandConfig,
            writingDirectives: Array(allDirectives.prefix(8)),
            antiPatterns: Array(allAntiPatterns.prefix(8))
        )
    }

    /// Auto-detect genre from project.genre, supporting composite genres
    static func autoDetect(from projectGenre: String) -> GenreTemplate {
        let trimmed = projectGenre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultTemplate }

        let hasComposite = trimmed.contains("+") || trimmed.contains("/")
            || trimmed.contains("、") || hasYuSeparator(trimmed)
        if hasComposite { return resolveComposite(trimmed) }

        return template(for: trimmed)
    }
}

// MARK: - Anti-AI Writing Guide

enum AntiAIWritingGuide {
    /// The 8 most common LLM writing tendencies that break immersion
    static let eightTendencies: [(name: String, description: String, avoidance: String)] = [
        (
            name: "每段结尾闭环",
            description: "每段结尾都写反思、总结或升华句，形成机械闭合节奏，读起来像AI在'总结陈词'",
            avoidance: "删掉反思/总结句。段落可以戛然而止于动作、对白、悬念或画面，允许断裂感"
        ),
        (
            name: "滥用副词",
            description: "频繁使用'缓缓'、'轻轻'、'淡淡'、'微微'、'不禁'等副词修饰动作，形成AI特征句式",
            avoidance: "用具体动作替代副词。例：不说'他缓缓站起身'，写'膝盖撑了两下才直起腰，扶着桌沿喘了口气'"
        ),
        (
            name: "所有角色相同反应",
            description: "不同角色面对同一事件时反应模式相同，缺乏个性化微动作和差异化情绪表达",
            avoidance: "为每个角色设计个性化微动作：紧张的人咬指甲、暴躁的人砸东西、隐忍的人攥拳指节发白"
        ),
        (
            name: "对话即辩论",
            description: "每段对话都像辩论赛，你来我往、逻辑完整、无人打断，缺乏真实对话的混乱感",
            avoidance: "增加潜台词、打断、跳跃、答非所问、沉默。真实对话充满中断和未说完的话"
        ),
        (
            name: "情绪标签化",
            description: "直接写'他感到愤怒'、'她心中一紧'、'一股悲伤涌上心头'等情绪标签，而非通过行为展示",
            avoidance: "用生理反应替代情绪标签。例：不说'他很紧张'，写'手心攥出一层汗，喉结上下滚了两轮'"
        ),
        (
            name: "均匀信息密度",
            description: "每段信息量几乎相同，节奏匀速推进，像流水线产品，缺乏张弛",
            avoidance: "制造稀疏/密集对比：有的段落只写一个眼神，有的段落压缩多个动作。让读者有喘息也有紧张"
        ),
        (
            name: "安全着陆",
            description: "每章结尾都给出完美收束，所有悬念都被回应，所有情绪都被安抚，读者没有继续看的动力",
            avoidance: "留至少一个未解决问题、一个新悬念或一个不安定的情绪尾巴，驱动读者翻下一章"
        ),
        (
            name: "先解释再展示",
            description: "在写动作/场景之前先用一段解释性叙述说明'为什么会这样'，破坏悬念和沉浸感",
            avoidance: "先展示再解释，或干脆不解释。让读者通过行为和结果自行推理，删除所有解释性前置句"
        )
    ]

    /// Formatted anti-AI guide for injection into system prompts
    static var formattedGuide: String {
        """
        ## 反AI写作检查（8大常见LLM写作倾向，务必规避）

        \(eightTendencies.enumerated().map { idx, item in
            "\(idx+1).【\(item.name)】\(item.description)\n   规避：\(item.avoidance)"
        }.joined(separator: "\n\n"))
        """
    }
}

// MARK: - CBN/CPNs/CEN Plot Structure Guide

enum CBNStructureGuide {
    /// CBN = Chapter Beginning Node, CPNs = Chapter Progression Nodes, CEN = Chapter Ending Node
    static var formattedGuide: String {
        """
        ## 章节节点结构（CBN / CPNs / CEN）

        每一章必须包含三个结构层：

        1. **CBN（章节起始节点）**—— 章节的第一段必须建立明确的叙事锚点：新的动作、新的冲突、新的观察或承接上一章 CEN 的具体状态。禁止用总结式开头。

        2. **CPNs（章节推进节点）**—— 每章至少 2 到 4 个推进节点，每个节点必须包含以下至少一项：信息增量、关系变化、冲突升级、角色决策。节点之间要有递进或转折，不能平行堆砌。

        3. **CEN（章节结束节点）**—— 章节最后一段必须留下叙事钩子：未解决的矛盾、新出现的威胁、角色的未完成决定或一个不安定的情绪尾巴。CBN of Chapter N+1 必须承接 CEN of Chapter N 的状态，形成连续叙事链。

        **节点连接铁律**：第 N 章的 CEN 必须在第 N+1 章的 CBN 中被直接承接，不能跳过、不能重新起头、不能忽略上一章结尾的状态。
        """
    }
}

// MARK: - Narrative Stage Guide (Early/Mid/Late)

enum NarrativeStageGuide {
    static var formattedGuide: String {
        """
        ## 叙事阶段检测（Early / Mid / Late）

        根据当前章节编号判断叙事阶段，调整上下文权重和节奏策略：

        **早期（第 1–30 章）**—— 建设阶段
        - 重点：世界观铺设、角色立人设、建立核心冲突
        - 上下文权重：世界观规则 > 角色背景 > 卖点展示 > 伏笔铺设
        - 节奏：快开慢铺，每章必须有新信息注入，避免重复
        - 字数建议：每段信息密度要高，用动作和对白带出设定，不要整段讲解

        **中期（第 31–120 章）**—— 推进阶段
        - 重点：冲突升级、关系深化、伏笔推进与部分回收
        - 上下文权重：冲突升级 > 角色成长 > 伏笔回收 > 世界观补全
        - 节奏：稳中有变，每 3-5 章要有一次小高潮或转折
        - 字数建议：可以适当放慢节奏，但每章必须有至少一个情节推进点

        **后期（第 121+ 章）**—— 收束阶段
        - 重点：线索汇聚、高潮爆发、伏笔全部回收、角色弧线闭合
        - 上下文权重：线索汇聚 > 角色终态 > 伏笔收束 > 情感满足
        - 节奏：逐步加快到高潮，然后减速收尾
        - 字数建议：高密度推进，减少新设定引入，专注解决已有矛盾
        """
    }
}

// MARK: - Narrative Stage Detection

enum NarrativeStage: String, CaseIterable, Codable {
    case openingHook = "开篇钩子"
    case worldSetup = "世界观铺设"
    case risingConflict = "冲突升级"
    case midpointTurn = "中点转折"
    case climaxBuildup = "高潮蓄力"
    case climax = "高潮爆发"
    case fallingAction = "收束化解"
    case denouement = "余韵收尾"

    var pacingDirective: String {
        switch self {
        case .openingHook:
            return "开篇阶段：用悬念或危机快速抓住读者，3段内必须建立核心冲突。节奏要快，避免大段设定说明。"
        case .worldSetup:
            return "铺设阶段：通过角色行动和对话自然带出世界观，不要整段讲解设定。保持每章至少一个微冲突。"
        case .risingConflict:
            return "升级阶段：每个新场景都要提升赌注或增加复杂度。保持'赢了一步又来一个新问题'的节奏。"
        case .midpointTurn:
            return "中点转折：让主角面对一个改变认知或处境的重大反转，打破原有计划。"
        case .climaxBuildup:
            return "蓄力阶段：收束分散的线索，所有角色和力量向最终冲突汇聚。节奏逐步加快。"
        case .climax:
            return "高潮阶段：全力释放冲突，用短句、快节奏、密集动作推进。不要插入设定说明或回忆。"
        case .fallingAction:
            return "收束阶段：解决主线冲突的直接后果，处理角色的情感落点。不要急着收尾，留足呼吸空间。"
        case .denouement:
            return "余韵阶段：给出角色最终状态、伏笔全部回收、给读者情感满足感。不要开新线。"
        }
    }

    var contextWeightHint: String {
        switch self {
        case .openingHook: return "上下文权重：章节目标 > 卖点 > 世界观 > 角色弧线"
        case .worldSetup: return "上下文权重：世界观规则 > 角色背景 > 情节推进 > 伏笔"
        case .risingConflict: return "上下文权重：冲突升级 > 角色成长 > 伏笔回收 > 世界观补全"
        case .midpointTurn: return "上下文权重：反转信息 > 角色反应 > 旧计划推翻 > 新方向确立"
        case .climaxBuildup: return "上下文权重：线索汇聚 > 角色到位 > 情绪蓄力 > 节奏加快"
        case .climax: return "上下文权重：动作节奏 > 冲突释放 > 角色决断 > 简洁有力"
        case .fallingAction: return "上下文权重：情感落点 > 关系解决 > 伏笔回收 > 世界观确认"
        case .denouement: return "上下文权重：角色终态 > 伏笔收束 > 情感满足 > 不开新线"
        }
    }
}

/// Detect narrative stage based on chapter position in the project
func detectNarrativeStage(
    currentChapter: Int,
    totalChapters: Int?,
    storyLength: NovelLength,
    outlineText: String = ""
) -> NarrativeStage {
    if let total = totalChapters, total > 0 {
        let ratio = Double(currentChapter) / Double(total)
        if currentChapter <= 3 { return .openingHook }
        if ratio < 0.15 { return .worldSetup }
        if ratio < 0.45 { return .risingConflict }
        if ratio < 0.55 { return .midpointTurn }
        if ratio < 0.75 { return .climaxBuildup }
        if ratio < 0.85 { return .climax }
        if ratio < 0.95 { return .fallingAction }
        return .denouement
    }

    switch storyLength {
    case .short:
        if currentChapter <= 3 { return .openingHook }
        if currentChapter <= 5 { return .worldSetup }
        if currentChapter <= 8 { return .risingConflict }
        if currentChapter <= 10 { return .midpointTurn }
        if currentChapter <= 12 { return .climaxBuildup }
        if currentChapter <= 15 { return .climax }
        return .fallingAction
    case .medium:
        if currentChapter <= 5 { return .openingHook }
        if currentChapter <= 15 { return .worldSetup }
        if currentChapter <= 30 { return .risingConflict }
        if currentChapter <= 40 { return .midpointTurn }
        if currentChapter <= 50 { return .climaxBuildup }
        if currentChapter <= 60 { return .climax }
        return .fallingAction
    case .long:
        if currentChapter <= 8 { return .openingHook }
        if currentChapter <= 25 { return .worldSetup }
        if currentChapter <= 60 { return .risingConflict }
        if currentChapter <= 80 { return .midpointTurn }
        if currentChapter <= 100 { return .climaxBuildup }
        if currentChapter <= 120 { return .climax }
        return .fallingAction
    }
}

// MARK: - Legacy Template Migration Helpers

private func mapLegacyCategory(_ cat: LegacyGenreCategory) -> GenreCategory {
    switch cat {
    case .xuanhuan: return .xuanhuan
    case .urban: return .urban
    case .romance: return .romance
    case .suspense: return .mystery
    }
}

private func inferHookTypes(from patterns: [String]) -> [HookType] {
    var result: [HookType] = []
    let joined = patterns.joined(separator: " ")
    if joined.contains("危机") || joined.contains("生死") || joined.contains("来袭") || joined.contains("威胁") { result.append(.crisis) }
    if joined.contains("秘") || joined.contains("疑") || joined.contains("真相") || joined.contains("反转") || joined.contains("揭秘") || joined.contains("隐藏") { result.append(.mystery) }
    if joined.contains("突破") || joined.contains("升级") || joined.contains("获得") || joined.contains("奖励") || joined.contains("觉醒") || joined.contains("发现") || joined.contains("成功") { result.append(.desire) }
    if joined.contains("表白") || joined.contains("甜蜜") || joined.contains("互动") || joined.contains("心动") || joined.contains("感情") || joined.contains("虐") { result.append(.emotion) }
    if joined.contains("抉择") || joined.contains("选择") || joined.contains("背叛") { result.append(.choice) }
    if result.isEmpty { result = [.crisis, .desire] }
    // Dedupe while preserving insertion order (Array(Set(...)) was non-deterministic).
    var seen = Set<HookType>()
    return result.filter { seen.insert($0).inserted }
}

private func inferCoolPointPatterns(from types: [String]) -> [CoolPointPattern] {
    var result: [CoolPointPattern] = []
    let joined = types.joined(separator: " ")
    if joined.contains("打脸") || joined.contains("装逼") || joined.contains("霸气") { result.append(.flexAndCounter) }
    if joined.contains("扮猪") || joined.contains("低调") || joined.contains("隐藏身份") { result.append(.underdogReveal) }
    if joined.contains("以弱") || joined.contains("越级") || joined.contains("反杀") || joined.contains("碾压") { result.append(.underdogVictory) }
    if joined.contains("权威") || joined.contains("家族翻盘") || joined.contains("翻盘") { result.append(.authorityChallenge) }
    if joined.contains("反派") || joined.contains("真相大白") || joined.contains("因果") { result.append(.villainDownfall) }
    if joined.contains("甜蜜") || joined.contains("撒糖") || joined.contains("幸福") || joined.contains("心动") { result.append(.sweetSurprise) }
    if joined.contains("吐槽") || joined.contains("神反转") || joined.contains("笑") || joined.contains("沙雕") || joined.contains("脑洞") { result.append(.misinterpretation) }
    if joined.contains("身份") || joined.contains("揭秘") || joined.contains("身世") || joined.contains("掉马") { result.append(.identityReveal) }
    if result.isEmpty { result = [.flexAndCounter, .underdogVictory] }
    // Dedupe while preserving insertion order (Array(Set(...)) was non-deterministic).
    var seen = Set<CoolPointPattern>()
    return result.filter { seen.insert($0).inserted }
}

private func buildStrandConfig(id: String, name: String, ratio: (quest: Double, fire: Double, constellation: Double)) -> GenreStrandConfig {
    GenreStrandConfig(
        genre: name,
        questTarget: ratio.quest,
        fireTarget: ratio.fire,
        constellationTarget: ratio.constellation,
        questMaxConsecutive: 5,
        fireMaxGap: 10,
        constellationMaxGap: 15
    )
}
