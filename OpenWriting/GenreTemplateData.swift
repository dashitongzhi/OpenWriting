import Foundation

// MARK: - Genre Template Data
//
// All data types for the genre template system.
// Extracted from GenreTemplateEngine.swift to reduce file size.

// MARK: - Genre Template

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