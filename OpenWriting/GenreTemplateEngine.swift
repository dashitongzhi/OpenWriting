import Foundation

// MARK: - Genre Template Engine

/// Provides parameterized genre configurations that tune the AI writing behavior.
/// Inspired by webnovel-writer's genre profiles and template system.

struct GenreTemplate: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: GenreCategory
    let description: String
    let coreSellingPoint: String

    // Hook configuration
    let preferredHookTypes: [HookType]
    let hookStrengthBaseline: HookStrength

    // Cool-point configuration
    let preferredCoolPointPatterns: [CoolPointPattern]
    let coolPointDensity: CoolPointDensity

    // Pacing configuration
    let stagnationThreshold: Int   // chapters with zero progress before warning
    let setupTolerance: SetupTolerance

    // Strand configuration
    let strandConfig: GenreStrandConfig

    // Writing directives
    let writingDirectives: [String]
    let antiPatterns: [String]

    var displayName: String { name }
}

// MARK: - Genre Category

enum GenreCategory: String, CaseIterable, Codable, Identifiable {
    case xuanhuan = "玄幻修仙"
    case urban = "都市现代"
    case romance = "言情"
    case mystery = "悬疑"

    var id: Self { self }

    var genres: [String] {
        switch self {
        case .xuanhuan:
            return ["修仙", "系统流", "高武", "西幻", "无限流", "末世", "科幻"]
        case .urban:
            return ["都市异能", "都市日常", "都市脑洞", "现实题材", "电竞", "直播文"]
        case .romance:
            return ["古言", "宫斗宅斗", "青春甜宠", "豪门总裁", "职场婚恋", "民国言情",
                    "幻想言情", "现言脑洞", "女频悬疑", "种田", "年代"]
        case .mystery:
            return ["规则怪谈", "悬疑脑洞", "悬疑灵异", "克苏鲁"]
        }
    }
}

// MARK: - Hook Types

enum HookType: String, CaseIterable, Codable {
    case crisis = "crisis"         // 危机钩
    case mystery = "mystery"       // 悬念钩
    case desire = "desire"         // 渴望钩
    case emotion = "emotion"       // 情绪钩
    case choice = "choice"         // 选择钩

    var displayName: String {
        switch self {
        case .crisis: return "危机钩"
        case .mystery: return "悬念钩"
        case .desire: return "渴望钩"
        case .emotion: return "情绪钩"
        case .choice: return "选择钩"
        }
    }

    var description: String {
        switch self {
        case .crisis: return "危险逼近，读者想知道主角如何脱险"
        case .mystery: return "信息缺口，读者想知道答案"
        case .desire: return "奖赏预期，读者想看主角获得成长/复仇/收获"
        case .emotion: return "触发愤怒/心碎/共情/羞耻/心动"
        case .choice: return "两难抉择，高风险决策"
        }
    }
}

enum HookStrength: String, Codable {
    case strong, medium, weak

    var displayName: String {
        switch self {
        case .strong: return "强"
        case .medium: return "中"
        case .weak: return "弱"
        }
    }
}

// MARK: - Cool-Point Patterns

enum CoolPointPattern: String, CaseIterable, Codable {
    case flexAndCounter = "flex_counter"         // 装逼打脸
    case underdogReveal = "underdog_reveal"       // 扮猪吃虎
    case underdogVictory = "underdog_victory"     // 越级反杀
    case authorityChallenge = "authority_challenge" // 打脸权威
    case villainDownfall = "villain_downfall"     // 反派翻车
    case sweetSurprise = "sweet_surprise"         // 甜蜜超预期
    case misinterpretation = "misinterpretation"  // 迪化误解
    case identityReveal = "identity_reveal"       // 身份掉马

    var displayName: String {
        switch self {
        case .flexAndCounter: return "装逼打脸"
        case .underdogReveal: return "扮猪吃虎"
        case .underdogVictory: return "越级反杀"
        case .authorityChallenge: return "打脸权威"
        case .villainDownfall: return "反派翻车"
        case .sweetSurprise: return "甜蜜超预期"
        case .misinterpretation: return "迪化误解"
        case .identityReveal: return "身份掉马"
        }
    }

    var threePhaseStructure: String {
        """
        三段式爽点结构（30/40/30）：
        - 铺垫（30%）：建立信息不对称 + 压力
        - 释放（40%）：执行爽点
        - 余波（30%）：反应、收获、新期待
        """
    }
}

enum CoolPointDensity: String, Codable {
    case high, medium, low

    var displayName: String {
        switch self {
        case .high: return "高密度"
        case .medium: return "中密度"
        case .low: return "低密度"
        }
    }

    var chaptersPerCoolPoint: Int {
        switch self {
        case .high: return 3
        case .medium: return 5
        case .low: return 8
        }
    }
}

enum SetupTolerance: String, Codable {
    case veryLow, low, medium, high

    var displayName: String {
        switch self {
        case .veryLow: return "极低"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var maxSetupChapters: Int {
        switch self {
        case .veryLow: return 1
        case .low: return 2
        case .medium: return 3
        case .high: return 5
        }
    }
}

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
        [
            // === 修仙 ===
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

            // === 系统流 ===
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

            // === 都市异能 ===
            GenreTemplate(
                id: "urban_power",
                name: "都市异能",
                category: .urban,
                description: "现代都市背景 + 超自然能力",
                coreSellingPoint: "低调装逼 + 都市冒险 + 能力升级",
                preferredHookTypes: [.crisis, .mystery, .emotion],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.underdogReveal, .authorityChallenge, .flexAndCounter],
                coolPointDensity: .high,
                stagnationThreshold: 3,
                setupTolerance: .low,
                strandConfig: GenreStrandConfig(
                    genre: "都市异能", questTarget: 0.55, fireTarget: 0.25,
                    constellationTarget: 0.20, questMaxConsecutive: 5,
                    fireMaxGap: 8, constellationMaxGap: 12
                ),
                writingDirectives: [
                    "能力使用要有代价和限制",
                    "日常生活与异能世界的切换要自然",
                    "装逼要有充分铺垫",
                    "都市背景要接地气",
                ],
                antiPatterns: [
                    "不要让主角在公共场合随意使用异能",
                    "不要跳过能力代价",
                    "不要让配角智商下线",
                ]
            ),

            // === 规则怪谈 ===
            GenreTemplate(
                id: "rules_horror",
                name: "规则怪谈",
                category: .mystery,
                description: "规则驱动的恐怖悬疑，强调规则发现、推理、生存",
                coreSellingPoint: "规则发现 + 推理博弈 + 生存压力",
                preferredHookTypes: [.mystery, .crisis, .choice],
                hookStrengthBaseline: .strong,
                preferredCoolPointPatterns: [.misinterpretation, .underdogVictory, .identityReveal],
                coolPointDensity: .medium,
                stagnationThreshold: 2,
                setupTolerance: .high,
                strandConfig: GenreStrandConfig(
                    genre: "规则怪谈", questTarget: 0.55, fireTarget: 0.15,
                    constellationTarget: 0.30, questMaxConsecutive: 4,
                    fireMaxGap: 15, constellationMaxGap: 10
                ),
                writingDirectives: [
                    "规则要清晰、可推理、有漏洞",
                    "恐怖氛围靠细节堆砌而非直接描述",
                    "每章至少发现或验证一条规则",
                    "信息不对称是核心驱动力",
                ],
                antiPatterns: [
                    "不要让角色无条件相信规则",
                    "不要跳过推理过程直接给结论",
                    "不要用突然惊吓替代氛围恐怖",
                ]
            ),

            // === 青春甜宠 ===
            GenreTemplate(
                id: "sweet_romance",
                name: "青春甜宠",
                category: .romance,
                description: "甜蜜恋爱，强调心动瞬间、误会化解、双向奔赴",
                coreSellingPoint: "甜蜜互动 + 心动瞬间 + 误会升级",
                preferredHookTypes: [.emotion, .desire, .mystery],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.sweetSurprise, .identityReveal, .misinterpretation],
                coolPointDensity: .medium,
                stagnationThreshold: 4,
                setupTolerance: .medium,
                strandConfig: GenreStrandConfig(
                    genre: "青春甜宠", questTarget: 0.40, fireTarget: 0.40,
                    constellationTarget: 0.20, questMaxConsecutive: 3,
                    fireMaxGap: 3, constellationMaxGap: 15
                ),
                writingDirectives: [
                    "甜度要循序渐进",
                    "误会要合理，化解要有仪式感",
                    "配角要服务于主线感情",
                    "心动瞬间要有具体细节支撑",
                ],
                antiPatterns: [
                    "不要让误会太低级",
                    "不要跳过暧昧直接在一起",
                    "不要让配角抢戏",
                ]
            ),

            // === 古言 ===
            GenreTemplate(
                id: "period_drama",
                name: "古言",
                category: .romance,
                description: "古代背景言情，强调权谋、家族、身份",
                coreSellingPoint: "权谋博弈 + 身份秘密 + 家国情怀",
                preferredHookTypes: [.mystery, .crisis, .emotion],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.identityReveal, .authorityChallenge, .villainDownfall],
                coolPointDensity: .medium,
                stagnationThreshold: 4,
                setupTolerance: .medium,
                strandConfig: GenreStrandConfig(
                    genre: "古言", questTarget: 0.45, fireTarget: 0.35,
                    constellationTarget: 0.20, questMaxConsecutive: 4,
                    fireMaxGap: 5, constellationMaxGap: 15
                ),
                writingDirectives: [
                    "对白要符合古代语境但不过度文言",
                    "权谋要有逻辑链条",
                    "身份秘密要有伏笔铺垫",
                    "场景描写要有古韵",
                ],
                antiPatterns: [
                    "不要用现代网络用语",
                    "不要让角色行为不符合时代背景",
                    "不要跳过礼仪细节",
                ]
            ),
        ]
    }
}

// MARK: - Genre Template Formatting

extension GenreTemplate {
    /// Format template for injection into AI writing prompt
    var formattedForPrompt: String {
        var sections: [String] = []

        sections.append("题材配置: \(name)")
        sections.append("核心卖点: \(coreSellingPoint)")

        sections.append("偏好钩子类型: \(preferredHookTypes.map { $0.displayName }.joined(separator: "、"))")
        sections.append("钩子强度基线: \(hookStrengthBaseline.displayName)")

        sections.append("偏好爽点模式: \(preferredCoolPointPatterns.map { $0.displayName }.joined(separator: "、"))")
        sections.append("爽点密度: \(coolPointDensity.displayName)（每\(coolPointDensity.chaptersPerCoolPoint)章至少1个）")

        sections.append("节奏红线:")
        sections.append("  · 停滞阈值: \(stagnationThreshold) 章无进展则告警")
        sections.append("  · 铺垫容忍: 最多 \(setupTolerance.maxSetupChapters) 章铺垫")

        if !writingDirectives.isEmpty {
            sections.append("写作指引:")
            for directive in writingDirectives {
                sections.append("  · \(directive)")
            }
        }

        if !antiPatterns.isEmpty {
            sections.append("避让模式:")
            for pattern in antiPatterns {
                sections.append("  · \(pattern)")
            }
        }

        return sections.joined(separator: "\n")
    }
}
