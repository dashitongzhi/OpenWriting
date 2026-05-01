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

// MARK: - Strand Configuration

struct GenreStrandConfig: Codable, Hashable {
    let genre: String
    let questTarget: Double
    let fireTarget: Double
    let constellationTarget: Double
    let questMaxConsecutive: Int
    let fireMaxGap: Int
    let constellationMaxGap: Int

    static let defaultConfig = GenreStrandConfig(
        genre: "通用",
        questTarget: 0.60,
        fireTarget: 0.20,
        constellationTarget: 0.20,
        questMaxConsecutive: 5,
        fireMaxGap: 10,
        constellationMaxGap: 15
    )
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

            // MARK: Legacy-migrated templates (16 genres)

            // === 高武 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("高武")!),
            // === 西幻 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("西幻")!),
            // === 无限流 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("无限流")!),
            // === 末世 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("末世")!),
            // === 科幻 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("科幻")!),
            // === 都市日常 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("都市日常")!),
            // === 都市脑洞 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("都市脑洞")!),
            // === 电竞 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("电竞")!),
            // === 直播文 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("直播文")!),
            // === 现实题材 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("现实题材")!),
            // === 宫斗宅斗 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("宫斗宅斗")!),
            // === 豪门总裁 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("豪门总裁")!),
            // === 职场婚恋 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("职场婚恋")!),
            // === 幻想言情 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("幻想言情")!),
            // === 悬疑脑洞 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("悬疑脑洞")!),
            // === 悬疑灵异 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("悬疑灵异")!),
            // === 克苏鲁 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("克苏鲁")!),
            // === 狗血言情 ===
            migrateLegacyTemplate(LegacyGenreTemplateLibrary.lookup("狗血言情")!),

            // MARK: Additional romance/mystery genres (no legacy source)

            // === 民国言情 ===
            GenreTemplate(
                id: "republic_romance",
                name: "民国言情",
                category: .romance,
                description: "民国时期背景的言情故事，新旧文化碰撞下的爱情",
                coreSellingPoint: "时代碰撞 + 身份纠葛 + 家国情怀",
                preferredHookTypes: [.emotion, .crisis, .mystery],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.identityReveal, .villainDownfall, .sweetSurprise],
                coolPointDensity: .medium,
                stagnationThreshold: 4,
                setupTolerance: .medium,
                strandConfig: GenreStrandConfig(
                    genre: "民国言情", questTarget: 0.40, fireTarget: 0.35,
                    constellationTarget: 0.25, questMaxConsecutive: 4,
                    fireMaxGap: 5, constellationMaxGap: 12
                ),
                writingDirectives: [
                    "民国背景要考据：服饰、称谓、社会风气要有时代感",
                    "新旧思想冲突是核心张力来源",
                    "战争/革命是推动情节的外部压力",
                    "家族兴衰与个人命运交织",
                ],
                antiPatterns: [
                    "不要用现代网络用语",
                    "不要忽略时代背景对角色行为的约束",
                    "不要让感情线脱离家国大背景",
                ]
            ),

            // === 现言脑洞 ===
            GenreTemplate(
                id: "modern_brainhole",
                name: "现言脑洞",
                category: .romance,
                description: "现代背景、脑洞大开的言情故事，设定新奇有趣",
                coreSellingPoint: "新奇设定 + 甜蜜互动 + 反转解构",
                preferredHookTypes: [.mystery, .emotion, .desire],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.misinterpretation, .sweetSurprise, .identityReveal],
                coolPointDensity: .high,
                stagnationThreshold: 3,
                setupTolerance: .low,
                strandConfig: GenreStrandConfig(
                    genre: "现言脑洞", questTarget: 0.35, fireTarget: 0.40,
                    constellationTarget: 0.25, questMaxConsecutive: 3,
                    fireMaxGap: 3, constellationMaxGap: 12
                ),
                writingDirectives: [
                    "核心脑洞设定要在前三章充分展开",
                    "感情线与脑洞设定要互相服务",
                    "反转要出人意料但逻辑自洽",
                    "节奏轻快，避免沉重",
                ],
                antiPatterns: [
                    "不要让脑洞设定喧宾夺主压过感情线",
                    "不要用过于沉重的冲突破坏轻快基调",
                    "不要让配角智商下线",
                ]
            ),

            // === 女频悬疑 ===
            GenreTemplate(
                id: "female_mystery",
                name: "女频悬疑",
                category: .mystery,
                description: "女性视角的悬疑故事，情感与推理并重",
                coreSellingPoint: "情感推理 + 身份迷局 + 女性成长",
                preferredHookTypes: [.mystery, .emotion, .crisis],
                hookStrengthBaseline: .strong,
                preferredCoolPointPatterns: [.identityReveal, .villainDownfall, .underdogVictory],
                coolPointDensity: .medium,
                stagnationThreshold: 3,
                setupTolerance: .medium,
                strandConfig: GenreStrandConfig(
                    genre: "女频悬疑", questTarget: 0.50, fireTarget: 0.25,
                    constellationTarget: 0.25, questMaxConsecutive: 4,
                    fireMaxGap: 8, constellationMaxGap: 10
                ),
                writingDirectives: [
                    "悬疑线与感情线要双线并进",
                    "女性主角的成长弧线要完整",
                    "线索公平呈现，每章至少推进一个疑点",
                    "情感描写要有细腻层次",
                ],
                antiPatterns: [
                    "不要让女主沦为工具人只推动悬疑线",
                    "不要跳过情感细节直接写推理结论",
                    "不要让反派动机过于单薄",
                ]
            ),

            // === 种田 ===
            GenreTemplate(
                id: "farming_life",
                name: "种田",
                category: .romance,
                description: "古代/穿越背景下经营建设、日常生活的慢节奏故事",
                coreSellingPoint: "经营成长 + 家庭温暖 + 慢热致富",
                preferredHookTypes: [.desire, .emotion, .choice],
                hookStrengthBaseline: .weak,
                preferredCoolPointPatterns: [.sweetSurprise, .underdogVictory, .villainDownfall],
                coolPointDensity: .low,
                stagnationThreshold: 5,
                setupTolerance: .high,
                strandConfig: GenreStrandConfig(
                    genre: "种田", questTarget: 0.50, fireTarget: 0.30,
                    constellationTarget: 0.20, questMaxConsecutive: 5,
                    fireMaxGap: 8, constellationMaxGap: 15
                ),
                writingDirectives: [
                    "经营细节要有真实感和代入感",
                    "日常生活描写要有烟火气",
                    "人物关系缓慢推进，不急于冲突",
                    "致富/成长线要有阶段性里程碑",
                ],
                antiPatterns: [
                    "不要突然引入高强度冲突破坏节奏",
                    "不要跳过经营细节直接写结果",
                    "不要让配角过于脸谱化",
                ]
            ),

            // === 年代 ===
            GenreTemplate(
                id: "period_era",
                name: "年代",
                category: .romance,
                description: "特定年代背景（如六七十年代）的生活与情感故事",
                coreSellingPoint: "时代印记 + 逆袭成长 + 家庭温情",
                preferredHookTypes: [.emotion, .desire, .crisis],
                hookStrengthBaseline: .medium,
                preferredCoolPointPatterns: [.underdogVictory, .villainDownfall, .sweetSurprise],
                coolPointDensity: .medium,
                stagnationThreshold: 4,
                setupTolerance: .high,
                strandConfig: GenreStrandConfig(
                    genre: "年代", questTarget: 0.45, fireTarget: 0.30,
                    constellationTarget: 0.25, questMaxConsecutive: 5,
                    fireMaxGap: 8, constellationMaxGap: 15
                ),
                writingDirectives: [
                    "年代细节要有考据：票证、知青、单位、粮票等",
                    "人物命运要与时代大事件交织",
                    "家庭关系和邻里互动是重要剧情线",
                    "主角要有凭本事改变命运的成长弧线",
                ],
                antiPatterns: [
                    "不要用现代思维直接套用年代背景",
                    "不要忽略时代限制让主角行为过于超前",
                    "不要让背景设定流于表面装饰",
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

// MARK: - Anti-AI Writing Guide (8 LLM Tendencies)

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
    storyLength: StoryLength,
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
    case .shortStory:
        if currentChapter <= 1 { return .openingHook }
        if currentChapter <= 2 { return .risingConflict }
        if currentChapter <= 3 { return .climax }
        return .denouement
    case .novelette:
        if currentChapter <= 2 { return .openingHook }
        if currentChapter <= 4 { return .risingConflict }
        if currentChapter <= 6 { return .climaxBuildup }
        if currentChapter <= 8 { return .climax }
        return .fallingAction
    case .shortNovel:
        if currentChapter <= 3 { return .openingHook }
        if currentChapter <= 8 { return .worldSetup }
        if currentChapter <= 15 { return .risingConflict }
        if currentChapter <= 18 { return .midpointTurn }
        if currentChapter <= 22 { return .climaxBuildup }
        if currentChapter <= 25 { return .climax }
        return .fallingAction
    case .novel:
        if currentChapter <= 5 { return .openingHook }
        if currentChapter <= 15 { return .worldSetup }
        if currentChapter <= 40 { return .risingConflict }
        if currentChapter <= 50 { return .midpointTurn }
        if currentChapter <= 70 { return .climaxBuildup }
        if currentChapter <= 85 { return .climax }
        return .fallingAction
    case .longNovel:
        if currentChapter <= 8 { return .openingHook }
+        if currentChapter <= 25 { return .worldSetup }
+        if currentChapter <= 60 { return .risingConflict }
+        if currentChapter <= 80 { return .midpointTurn }
+        if currentChapter <= 100 { return .climaxBuildup }
+        if currentChapter <= 120 { return .climax }
+        return .fallingAction
+    case .epic:
+        if currentChapter <= 10 { return .openingHook }
+        if currentChapter <= 35 { return .worldSetup }
+        if currentChapter <= 90 { return .risingConflict }
+        if currentChapter <= 120 { return .midpointTurn }
+        if currentChapter <= 160 { return .climaxBuildup }
+        if currentChapter <= 190 { return .climax }
+        return .fallingAction
+    }
+}
+
+// MARK: - Legacy Template Migration Helpers
+
+private func mapLegacyCategory(_ cat: LegacyGenreCategory) -> GenreCategory {
+    switch cat {
+    case .xuanhuan: return .xuanhuan
+    case .urban: return .urban
+    case .romance: return .romance
+    case .suspense: return .mystery
+    }
+}
+
+private func inferHookTypes(from patterns: [String]) -> [HookType] {
+    var result: [HookType] = []
+    let joined = patterns.joined(separator: " ")
+    if joined.contains("危机") || joined.contains("生死") || joined.contains("来袭") || joined.contains("威胁") { result.append(.crisis) }
+    if joined.contains("秘") || joined.contains("疑") || joined.contains("真相") || joined.contains("反转") || joined.contains("揭秘") || joined.contains("隐藏") { result.append(.mystery) }
+    if joined.contains("突破") || joined.contains("升级") || joined.contains("获得") || joined.contains("奖励") || joined.contains("觉醒") || joined.contains("发现") || joined.contains("成功") { result.append(.desire) }
+    if joined.contains("表白") || joined.contains("甜蜜") || joined.contains("互动") || joined.contains("心动") || joined.contains("感情") || joined.contains("虐") { result.append(.emotion) }
+    if joined.contains("抉择") || joined.contains("选择") || joined.contains("背叛") { result.append(.choice) }
+    if result.isEmpty { result = [.crisis, .desire] }
+    return Array(Set(result))
+}
+
+private func inferCoolPointPatterns(from types: [String]) -> [CoolPointPattern] {
+    var result: [CoolPointPattern] = []
+    let joined = types.joined(separator: " ")
+    if joined.contains("打脸") || joined.contains("装逼") || joined.contains("霸气") { result.append(.flexAndCounter) }
+    if joined.contains("扮猪") || joined.contains("低调") || joined.contains("隐藏身份") { result.append(.underdogReveal) }
+    if joined.contains("以弱") || joined.contains("越级") || joined.contains("反杀") || joined.contains("碾压") { result.append(.underdogVictory) }
+    if joined.contains("权威") || joined.contains("家族翻盘") || joined.contains("翻盘") { result.append(.authorityChallenge) }
+    if joined.contains("反派") || joined.contains("真相大白") || joined.contains("因果") { result.append(.villainDownfall) }
+    if joined.contains("甜蜜") || joined.contains("撒糖") || joined.contains("幸福") || joined.contains("心动") { result.append(.sweetSurprise) }
+    if joined.contains("吐槽") || joined.contains("神反转") || joined.contains("笑") || joined.contains("沙雕") || joined.contains("脑洞") { result.append(.misinterpretation) }
+    if joined.contains("身份") || joined.contains("揭秘") || joined.contains("身世") || joined.contains("掉马") { result.append(.identityReveal) }
+    if result.isEmpty { result = [.flexAndCounter, .underdogVictory] }
+    return Array(Set(result))
+}
+
+private func buildStrandConfig(id: String, name: String, ratio: (quest: Double, fire: Double, constellation: Double)) -> GenreStrandConfig {
+    GenreStrandConfig(
+        genre: name,
+        questTarget: ratio.quest,
+        fireTarget: ratio.fire,
+        constellationTarget: ratio.constellation,
+        questMaxConsecutive: 5,
+        fireMaxGap: 10,
+        constellationMaxGap: 15
+    )
+}
+
+private func migrateLegacyTemplate(_ legacy: LegacyGenreTemplate) -> GenreTemplate {
+    let category = mapLegacyCategory(legacy.category)
+    let hookTypes = inferHookTypes(from: legacy.hookPatterns)
+    let coolPatterns = inferCoolPointPatterns(from: legacy.pleasurePointTypes)
+    let strandConfig = buildStrandConfig(id: legacy.id, name: legacy.name, ratio: legacy.strandRatio)
+
+    var directives: [String] = []
+    for rule in legacy.worldRules.prefix(3) { directives.append(rule) }
+    directives.append(legacy.pacingGuide)
+    for hook in legacy.hookPatterns.prefix(2) { directives.append("章末钩子参考：\(hook)") }
+
+    let antiPatterns: [String] = [
+        "不要让配角行为与人设不符（当前角色原型：\(legacy.characterArchetypes.joined(separator: "、"))）",
+        "不要违反世界观核心规则"
+    ]
+
+    return GenreTemplate(
+        id: legacy.id,
+        name: legacy.name,
+        category: category,
+        description: legacy.description,
+        coreSellingPoint: legacy.pleasurePointTypes.prefix(3).joined(separator: " + "),
+        preferredHookTypes: hookTypes,
+        hookStrengthBaseline: .medium,
+        preferredCoolPointPatterns: coolPatterns,
+        coolPointDensity: coolPatterns.count >= 3 ? .high : (coolPatterns.count >= 2 ? .medium : .low),
+        stagnationThreshold: 3,
+        setupTolerance: category == .mystery ? .high : .medium,
+        strandConfig: strandConfig,
+        writingDirectives: directives,
+        antiPatterns: antiPatterns
+    )
+}
+
+// MARK: - Composite Genre Support
+
+extension GenreTemplateLibrary {
+    /// Resolve a composite genre string like "都市异能+规则怪谈" into a merged template
+    static func resolveComposite(_ input: String) -> GenreTemplate {
+        let separators: [Character] = ["+", "/", "、", "与"]
+        let parts = input.split { separators.contains($0) }
+            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
+            .filter { !$0.isEmpty }
+
+        guard parts.count > 1 else { return template(for: input) }
+
+        let templates = parts.map { template(for: $0) }
+        let primary = templates[0]
+
+        var allDirectives = primary.writingDirectives
+        var allAntiPatterns = primary.antiPatterns
+        var allHookTypes = primary.preferredHookTypes
+        var allCoolPatterns = primary.preferredCoolPointPatterns
+
+        for secondary in templates.dropFirst() {
+            for directive in secondary.writingDirectives where !allDirectives.contains(directive) {
+                allDirectives.append(directive)
+            }
+            for pattern in secondary.antiPatterns where !allAntiPatterns.contains(pattern) {
+                allAntiPatterns.append(pattern)
+            }
+            for hook in secondary.preferredHookTypes where !allHookTypes.contains(hook) {
+                allHookTypes.append(hook)
+            }
+            for cool in secondary.preferredCoolPointPatterns where !allCoolPatterns.contains(cool) {
+                allCoolPatterns.append(cool)
+            }
+        }
+
+        return GenreTemplate(
+            id: "composite_\(primary.id)",
+            name: parts.joined(separator: "+"),
+            category: primary.category,
+            description: "复合题材：\(templates.map { $0.name }.joined(separator: " + "))",
+            coreSellingPoint: templates.map { $0.coreSellingPoint }.joined(separator: " | "),
+            preferredHookTypes: allHookTypes,
+            hookStrengthBaseline: primary.hookStrengthBaseline,
+            preferredCoolPointPatterns: allCoolPatterns,
+            coolPointDensity: primary.coolPointDensity,
+            stagnationThreshold: primary.stagnationThreshold,
+            setupTolerance: primary.setupTolerance,
+            strandConfig: primary.strandConfig,
+            writingDirectives: Array(allDirectives.prefix(8)),
+            antiPatterns: Array(allAntiPatterns.prefix(8))
+        )
+    }
+
+    /// Auto-detect genre from project.genre, supporting composite genres
+    static func autoDetect(from projectGenre: String) -> GenreTemplate {
+        let trimmed = projectGenre.trimmingCharacters(in: .whitespacesAndNewlines)
+        guard !trimmed.isEmpty else { return defaultTemplate }
+
+        let hasComposite = trimmed.contains("+") || trimmed.contains("/") || trimmed.contains("与")
+        if hasComposite { return resolveComposite(trimmed) }
+
+        return template(for: trimmed)
+    }
+}
