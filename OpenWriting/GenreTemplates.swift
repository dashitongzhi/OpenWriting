import Foundation

// MARK: - Genre Template System
// Inspired by webnovel-writer's 37 built-in genre templates

/// 题材分类
enum LegacyGenreCategory: String, Codable, CaseIterable, Identifiable {
    case xuanhuan = "玄幻修仙"
    case urban = "都市现代"
    case romance = "言情"
    case suspense = "悬疑"
    
    var id: String { rawValue }
    
    var genres: [LegacyGenreTemplate] {
        LegacyGenreTemplateLibrary.allTemplates.filter { $0.category == self }
    }
}

/// 题材模板
struct LegacyGenreTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let aliases: [String]
    let category: LegacyGenreCategory
    let description: String
    
    /// 世界观核心规则
    let worldRules: [String]
    /// 典型角色原型
    let characterArchetypes: [String]
    /// 节奏指导
    let pacingGuide: String
    /// 常见 Hook 模式
    let hookPatterns: [String]
    /// 爽点类型
    let pleasurePointTypes: [String]
    /// 推荐的 Strand Weave 比例 (Quest, Fire, Constellation)
    let strandRatio: (quest: Double, fire: Double, constellation: Double)
    
    enum CodingKeys: String, CodingKey {
        case id, name, aliases, category, description
        case worldRules, characterArchetypes, pacingGuide
        case hookPatterns, pleasurePointTypes
        case questRatio, fireRatio, constellationRatio
    }
    
    init(id: String, name: String, aliases: [String] = [], category: LegacyGenreCategory,
         description: String, worldRules: [String], characterArchetypes: [String],
         pacingGuide: String, hookPatterns: [String], pleasurePointTypes: [String],
         strandRatio: (quest: Double, fire: Double, constellation: Double) = (0.6, 0.2, 0.2)) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.description = description
        self.worldRules = worldRules
        self.characterArchetypes = characterArchetypes
        self.pacingGuide = pacingGuide
        self.hookPatterns = hookPatterns
        self.pleasurePointTypes = pleasurePointTypes
        self.strandRatio = strandRatio
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        category = try c.decode(LegacyGenreCategory.self, forKey: .category)
        description = try c.decode(String.self, forKey: .description)
        worldRules = try c.decode([String].self, forKey: .worldRules)
        characterArchetypes = try c.decode([String].self, forKey: .characterArchetypes)
        pacingGuide = try c.decode(String.self, forKey: .pacingGuide)
        hookPatterns = try c.decode([String].self, forKey: .hookPatterns)
        pleasurePointTypes = try c.decode([String].self, forKey: .pleasurePointTypes)
        let q = try c.decodeIfPresent(Double.self, forKey: .questRatio) ?? 0.6
        let f = try c.decodeIfPresent(Double.self, forKey: .fireRatio) ?? 0.2
        let con = try c.decodeIfPresent(Double.self, forKey: .constellationRatio) ?? 0.2
        strandRatio = (q, f, con)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(category, forKey: .category)
        try c.encode(description, forKey: .description)
        try c.encode(worldRules, forKey: .worldRules)
        try c.encode(characterArchetypes, forKey: .characterArchetypes)
        try c.encode(pacingGuide, forKey: .pacingGuide)
        try c.encode(hookPatterns, forKey: .hookPatterns)
        try c.encode(pleasurePointTypes, forKey: .pleasurePointTypes)
        try c.encode(strandRatio.quest, forKey: .questRatio)
        try c.encode(strandRatio.fire, forKey: .fireRatio)
        try c.encode(strandRatio.constellation, forKey: .constellationRatio)
    }
}

/// 题材模板库
enum LegacyGenreTemplateLibrary {
    
    static let allTemplates: [LegacyGenreTemplate] = xuanhuanGenres + urbanGenres + romanceGenres + suspenseGenres
    
    /// 通过名称或别名查找题材
    static func lookup(_ input: String) -> LegacyGenreTemplate? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allTemplates.first { template in
            template.name.lowercased() == normalized ||
            template.aliases.contains(where: { $0.lowercased() == normalized })
        }
    }
    
    /// 支持复合题材查找（如 "都市脑洞+规则怪谈"）
    static func lookupComposite(_ input: String) -> [LegacyGenreTemplate] {
        let separators: [Character] = ["+", "/", "、", "与"]
        let parts = input.split { separators.contains($0) }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.compactMap { lookup($0) }
    }
    
    // MARK: - 玄幻修仙类
    
    static let xuanhuanGenres: [LegacyGenreTemplate] = [
        LegacyGenreTemplate(
            id: "xianxia", name: "修仙", aliases: ["玄幻", "修真", "玄幻修仙"],
            category: .xuanhuan,
            description: "修炼升级、飞升渡劫、宗门争霸的仙侠世界",
            worldRules: [
                "修炼境界体系明确（如炼气→筑基→金丹→元婴→化神→渡劫→大乘）",
                "灵气/仙气是修炼基础资源",
                "天劫/雷劫是突破瓶颈的考验",
                "法宝、丹药、阵法是重要辅助系统",
                "宗门/门派是基本社会单位"
            ],
            characterArchetypes: ["废柴逆袭主角", "隐世高人师父", "天才对手", "红颜知己", "宗门长老"],
            pacingGuide: "前期快速升级建立爽感，中期宗门争霸扩展世界观，后期飞升渡劫收束主线",
            hookPatterns: ["境界突破", "秘境探宝", "宗门大比", "渡劫危机", "远古传承"],
            pleasurePointTypes: ["打脸装逼", "突破升级", "获得传承", "炼丹成功", "法宝认主"]
        ),
        LegacyGenreTemplate(
            id: "system-flow", name: "系统流", aliases: ["系统文", "面板流"],
            category: .xuanhuan,
            description: "主角获得系统面板，通过完成任务获得奖励和升级",
            worldRules: [
                "系统是独立于世界观的外挂存在",
                "任务完成可获得经验、道具、技能等奖励",
                "系统商城/抽奖是核心资源获取途径",
                "系统可能有自己的隐藏目的",
                "系统等级与主角实力挂钩"
            ],
            characterArchetypes: ["普通主角", "系统精灵", "任务目标人物", "竞争者", "幕后黑手"],
            pacingGuide: "每个任务周期形成一个小高潮，连续任务构成卷级剧情",
            hookPatterns: ["新任务发布", "限时挑战", "隐藏任务", "系统升级", "商城刷新"],
            pleasurePointTypes: ["完成任务获得奖励", "系统商城买到神装", "隐藏成就解锁", "系统升级", "抽奖出金"]
        ),
        LegacyGenreTemplate(
            id: "high-wu", name: "高武", aliases: ["武道", "高武世界"],
            category: .xuanhuan,
            description: "武道修炼极致，肉身成圣、拳碎星辰的高武世界",
            worldRules: [
                "武道境界分明（如明劲→暗劲→化劲→宗师→大宗师→武圣）",
                "肉身力量可以碾压一切",
                "武技/功法是核心战斗手段",
                "武道意志/心境是突破关键",
                "天地元气/星辰之力是修炼能量"
            ],
            characterArchetypes: ["武痴主角", "武道前辈", "武馆对手", "军方人物", "异族强者"],
            pacingGuide: "以武道大会/比武为节奏节点，穿插生死搏杀和武道感悟",
            hookPatterns: ["武道突破", "比武大会", "生死搏杀", "秘境历练", "武道传承"],
            pleasurePointTypes: ["以弱胜强", "武道顿悟", "碾压对手", "获得功法", "肉身蜕变"]
        ),
        LegacyGenreTemplate(
            id: "western-fantasy", name: "西幻", aliases: ["西方奇幻", "剑与魔法"],
            category: .xuanhuan,
            description: "骑士、魔法、龙族、王国争霸的西方奇幻世界",
            worldRules: [
                "魔法体系分明（元素魔法、召唤、炼金等）",
                "骑士/战士/法师等职业划分",
                "教会、王国、公会是主要势力",
                "魔物/魔兽是常见威胁",
                "神祇可能真实存在并干预凡间"
            ],
            characterArchetypes: ["落魄贵族主角", "精灵伙伴", "矮人工匠", "龙族盟友", "黑暗势力首领"],
            pacingGuide: "冒险→任务→BOSS→升级→新区域，经典RPG节奏",
            hookPatterns: ["新区域探索", "地下城冒险", "王国战争", "神器发现", "龙族觉醒"],
            pleasurePointTypes: ["获得神器", "击败BOSS", "等级提升", "公会升级", "领地建设"]
        ),
        LegacyGenreTemplate(
            id: "infinite-flow", name: "无限流", aliases: ["副本流", "无限恐怖"],
            category: .xuanhuan,
            description: "进入不同副本/世界完成任务的生存冒险",
            worldRules: [
                "主神空间/系统是进入副本的媒介",
                "每个副本有独立的规则和BOSS",
                "积分/奖励用于强化和兑换",
                "团队合作与背叛是核心戏剧冲突",
                "副本难度递增，最终面对终极副本"
            ],
            characterArchetypes: ["智谋主角", "战斗型队友", "辅助型队友", "反派队伍", "主神意志"],
            pacingGuide: "每个副本是一个完整故事弧，副本间休整和团队互动是过渡",
            hookPatterns: ["新副本开启", "副本内隐藏剧情", "队友背叛", "积分商城", "终极副本"],
            pleasurePointTypes: ["通关副本获得SSS评价", "兑换神级道具", "智谋碾压", "团队配合", "隐藏副本解锁"]
        ),
        LegacyGenreTemplate(
            id: "post-apocalypse", name: "末世", aliases: ["末日", "末世生存"],
            category: .xuanhuan,
            description: "文明崩塌后的生存与重建",
            worldRules: [
                "丧尸/异变/灾难是文明崩塌的原因",
                "资源稀缺是核心矛盾",
                "异能/进化是人类适应新世界的方式",
                "幸存者聚落是基本社会单位",
                "旧文明遗迹是重要资源来源"
            ],
            characterArchetypes: ["生存专家主角", "军人领袖", "科学家", "异能者", "聚落首领"],
            pacingGuide: "生存→建设→扩张→冲突→重建文明",
            hookPatterns: ["尸潮来袭", "新资源发现", "聚落冲突", "异能觉醒", "旧文明遗迹"],
            pleasurePointTypes: ["异能升级", "基地扩建", "击败尸潮", "找到稀缺资源", "收服强者"]
        ),
        LegacyGenreTemplate(
            id: "sci-fi", name: "科幻", aliases: ["星际", "太空歌剧"],
            category: .xuanhuan,
            description: "星际航行、外星文明、科技爆发的未来世界",
            worldRules: [
                "星际航行是基本交通方式",
                "AI/人工智能高度发达",
                "外星种族可能友好或敌对",
                "科技等级决定文明实力",
                "宇宙资源争夺是核心矛盾"
            ],
            characterArchetypes: ["舰长主角", "AI伙伴", "外星盟友", "科学天才", "星际海盗"],
            pacingGuide: "探索→发现→冲突→科技突破→星际争霸",
            hookPatterns: ["新星球探索", "外星接触", "科技突破", "星际战争", "宇宙奥秘"],
            pleasurePointTypes: ["科技升级", "舰队壮大", "击败外星势力", "发现新文明", "AI觉醒"]
        )
    ]
    
    // MARK: - 都市现代类
    
    static let urbanGenres: [LegacyGenreTemplate] = [
        LegacyGenreTemplate(
            id: "urban-powers", name: "都市异能", aliases: ["都市修真", "都市超能力"],
            category: .urban,
            description: "现代都市背景下隐藏的异能者世界",
            worldRules: [
                "异能者隐藏在普通人之中",
                "有专门的组织管理异能者",
                "异能觉醒有特定触发条件",
                "普通人不知道异能者的存在",
                "异能等级划分明确"
            ],
            characterArchetypes: ["觉醒者主角", "异能组织成员", "普通人恋人", "异能反派", "政府特工"],
            pacingGuide: "觉醒→适应→任务→升级→对抗大BOSS",
            hookPatterns: ["异能觉醒", "组织任务", "身份暴露危机", "异能对决", "城市危机"],
            pleasurePointTypes: ["异能升级", "碾压对手", "隐藏身份反转", "拯救城市", "获得组织认可"]
        ),
        LegacyGenreTemplate(
            id: "urban-daily", name: "都市日常", aliases: ["日常流", "生活流"],
            category: .urban,
            description: "贴近现实的都市生活故事，侧重人情世故和情感",
            worldRules: [
                "贴近现实社会规则",
                "职场/校园是主要场景",
                "人际关系是核心驱动力",
                "没有超自然元素",
                "经济/社会压力是常见矛盾"
            ],
            characterArchetypes: ["普通人主角", "上司/老板", "同事/同学", "恋人", "竞争对手"],
            pacingGuide: "以日常事件推动，情感线和事业线交替推进",
            hookPatterns: ["职场危机", "感情转折", "家庭矛盾", "事业机会", "旧友重逢"],
            pleasurePointTypes: ["事业成功", "感情进展", "化解危机", "获得认可", "逆袭打脸"]
        ),
        LegacyGenreTemplate(
            id: "urban-brainhole", name: "都市脑洞", aliases: ["脑洞文", "沙雕文"],
            category: .urban,
            description: "设定新奇、脑洞大开的都市故事",
            worldRules: [
                "核心设定必须新奇有趣",
                "逻辑自洽比合理性更重要",
                "反转和意外是常态",
                "幽默感是必要元素",
                "可以打破常规叙事"
            ],
            characterArchetypes: ["脑洞主角", "吐槽役", "正常人对照组", "奇葩配角", "反套路角色"],
            pacingGuide: "快节奏，每章一个反转或笑点，避免拖沓",
            hookPatterns: ["设定反转", "身份揭秘", "规则打破", "意外展开", "黑色幽默"],
            pleasurePointTypes: ["神反转", "全网吐槽", "设定炸裂", "笑到喷饭", "细思恐极"]
        ),
        LegacyGenreTemplate(
            id: "esports", name: "电竞", aliases: ["游戏电竞", "电竞文"],
            category: .urban,
            description: "电子竞技职业选手的热血竞技故事",
            worldRules: [
                "电竞比赛是核心舞台",
                "团队配合大于个人实力",
                "版本更新影响战术体系",
                "选手状态和心态是关键变量",
                "俱乐部运营和商业元素是背景"
            ],
            characterArchetypes: ["天才选手主角", "老将队长", "新人培养对象", "对手战队王牌", "教练/分析师"],
            pacingGuide: "训练→小组赛→淘汰赛→决赛，赛季节奏",
            hookPatterns: ["关键团战", "战术创新", "选手对决", "团队危机", "逆风翻盘"],
            pleasurePointTypes: ["逆风翻盘", "战术碾压", "个人秀操作", "团队配合", "夺冠时刻"]
        ),
        LegacyGenreTemplate(
            id: "livestream", name: "直播文", aliases: ["直播", "主播", "直播带货"],
            category: .urban,
            description: "以直播/短视频为载体的都市故事",
            worldRules: [
                "直播平台是核心舞台",
                "流量/粉丝是核心资源",
                "内容创意决定上限",
                "打赏/带货是变现方式",
                "网络舆论是重要变量"
            ],
            characterArchetypes: ["新人主播", "平台大佬", "MCN运营", "忠实粉丝", "黑粉/喷子"],
            pacingGuide: "开播→涨粉→危机→转型→爆红",
            hookPatterns: ["直播翻车", "意外走红", "平台打压", "带货奇迹", "网红互撕"],
            pleasurePointTypes: ["粉丝暴涨", "带货破纪录", "打脸黑粉", "平台认可", "出圈爆红"]
        ),
        LegacyGenreTemplate(
            id: "realistic", name: "现实题材", aliases: ["现实主义", "纪实"],
            category: .urban,
            description: "关注社会现实问题的严肃题材",
            worldRules: [
                "贴近真实社会规则",
                "不做过度美化",
                "关注社会问题和人性",
                "结局可以不完美",
                "细节真实是核心"
            ],
            characterArchetypes: ["普通劳动者", "社会底层", "理想主义者", "现实妥协者", "时代见证者"],
            pacingGuide: "慢节奏，以人物命运折射时代变迁",
            hookPatterns: ["命运转折", "社会事件冲击", "人性考验", "道德困境", "时代洪流"],
            pleasurePointTypes: ["人物成长", "命运抗争", "人性光辉", "社会反思", "情感共鸣"]
        )
    ]
    
    // MARK: - 言情类
    
    static let romanceGenres: [LegacyGenreTemplate] = [
        LegacyGenreTemplate(
            id: "ancient-romance", name: "古言", aliases: ["古代言情", "古风言情"],
            category: .romance,
            description: "古代背景的言情故事，宫廷/江湖/宅院",
            worldRules: [
                "古代社会等级分明",
                "男女大防/礼教约束",
                "家族/门第观念重",
                "嫡庶之争是常见矛盾",
                "诗词歌赋是社交手段"
            ],
            characterArchetypes: ["世家小姐", "王侯将相", "丫鬟/侍女", "嫡母/庶母", "皇帝/太后"],
            pacingGuide: "初遇→误会→相知→阻碍→结合，穿插宅斗/宫斗",
            hookPatterns: ["身份揭秘", "赐婚/退婚", "家族危机", "宫廷政变", "生死相随"],
            pleasurePointTypes: ["甜蜜互动", "打脸恶毒配角", "男主霸气护妻", "身份反转", "终成眷属"]
        ),
        LegacyGenreTemplate(
            id: "palace-intrigue", name: "宫斗宅斗", aliases: ["宫斗", "宅斗"],
            category: .romance,
            description: "宫廷/后宅女性之间的权谋争斗",
            worldRules: [
                "等级制度森严",
                "子嗣是核心筹码",
                "家族势力是后盾",
                "表面和谐暗流涌动",
                "皇帝/家主是最终裁判"
            ],
            characterArchetypes: ["隐忍女主", "嚣张宠妃", "腹黑皇后", "忠心侍女", "皇帝/家主"],
            pacingGuide: "入局→受辱→布局→反击→上位",
            hookPatterns: ["陷害与反杀", "宠爱争夺", "子嗣之争", "家族兴衰", "最终上位"],
            pleasurePointTypes: ["反杀对手", "获得宠爱", "子嗣降生", "家族翻盘", "登上高位"]
        ),
        LegacyGenreTemplate(
            id: "sweet-love", name: "青春甜宠", aliases: ["甜宠", "校园恋爱"],
            category: .romance,
            description: "甜蜜轻松的恋爱故事，高甜无虐",
            worldRules: [
                "双向暗恋或一见钟情",
                "误会都是甜蜜的",
                "配角都是助攻",
                "HE是必须的",
                "日常互动是核心"
            ],
            characterArchetypes: ["可爱女主", "高冷/温柔男主", "闺蜜助攻", "情敌（很快出局）", "开明家长"],
            pacingGuide: "相遇→暧昧→表白→热恋→小波折→大团圆",
            hookPatterns: ["甜蜜互动", "意外同居", "假装情侣", "表白名场面", "求婚惊喜"],
            pleasurePointTypes: ["甜蜜暴击", "男主吃醋", "当众表白", "撒狗粮", "幸福结局"]
        ),
        LegacyGenreTemplate(
            id: "ceo-romance", name: "豪门总裁", aliases: ["总裁文", "豪门"],
            category: .romance,
            description: "霸道总裁与灰姑娘的爱情故事",
            worldRules: [
                "财富差距是核心矛盾",
                "总裁有隐藏的温柔面",
                "商业斗争是背景",
                "身世揭秘是常见反转",
                "门当户对观念要被打破"
            ],
            characterArchetypes: ["霸道总裁", "坚强女主", "总裁助理", "恶毒女配", "开明长辈"],
            pacingGuide: "契约/误会→相处→心动→阻碍→真相→HE",
            hookPatterns: ["契约关系", "身份暴露", "商业危机", "情敌挑衅", "身世揭秘"],
            pleasurePointTypes: ["总裁霸气护妻", "甜蜜撒糖", "打脸恶毒配角", "身世反转", "盛大婚礼"]
        ),
        LegacyGenreTemplate(
            id: "workplace-romance", name: "职场婚恋", aliases: ["职场言情", "婚恋"],
            category: .romance,
            description: "职场背景的成熟爱情故事",
            worldRules: [
                "职场规则是核心约束",
                "事业与爱情的平衡是主题",
                "年龄/阅历带来成熟感情观",
                "家庭压力是常见外部矛盾",
                "经济独立是女主底线"
            ],
            characterArchetypes: ["职场精英女主", "同行/对手男主", "职场新人", "上司/老板", "前任"],
            pacingGuide: "职场相遇→合作→误解→理解→相爱→共同成长",
            hookPatterns: ["职场危机", "项目合作", "误会澄清", "事业选择", "感情表白"],
            pleasurePointTypes: ["事业成功", "感情进展", "化解危机", "互相成就", "携手同行"]
        ),
        LegacyGenreTemplate(
            id: "fantasy-romance", name: "幻想言情", aliases: ["仙侠言情", "玄幻言情"],
            category: .romance,
            description: "仙侠/玄幻背景的言情故事",
            worldRules: [
                "修炼体系支撑世界观",
                "寿命差异是情感障碍",
                "天道/命运是终极考验",
                "前世今生是常见设定",
                "双修/道侣是关系形态"
            ],
            characterArchetypes: ["仙子/女修", "魔尊/仙君", "凡人前世", "天道使者", "反派情敌"],
            pacingGuide: "初遇→结缘→误会→分离→重逢→共渡天劫",
            hookPatterns: ["前世记忆", "天劫考验", "仙魔对立", "生死相随", "天道阻挠"],
            pleasurePointTypes: ["甜蜜互动", "突破境界", "前世真相", "共渡天劫", "终成眷属"]
        )
    ]
    
    // MARK: - 悬疑类
    
    static let suspenseGenres: [LegacyGenreTemplate] = [
        LegacyGenreTemplate(
            id: "rules-mystery", name: "规则怪谈", aliases: ["怪谈", "规则类怪谈"],
            category: .suspense,
            description: "遵循特定规则才能存活的恐怖故事",
            worldRules: [
                "每条规则都有深层含义",
                "违反规则的后果是致命的",
                "规则之间可能存在矛盾",
                "真正的规则可能隐藏在假规则中",
                "理解规则背后的逻辑是存活关键"
            ],
            characterArchetypes: ["推理型主角", "第一个出局的配角", "隐藏的知情者", "规则制定者", "怪物/诡异"],
            pacingGuide: "进入→发现规则→试探→推理→破解→逃脱",
            hookPatterns: ["新规则发现", "规则矛盾", "同伴出局", "真相揭露", "规则反转"],
            pleasurePointTypes: ["推理正确", "规则破解", "智取存活", "真相大白", "反杀怪物"]
        ),
        LegacyGenreTemplate(
            id: "suspense-brainhole", name: "悬疑脑洞", aliases: ["悬疑推理", "烧脑"],
            category: .suspense,
            description: "充满反转和推理的悬疑故事",
            worldRules: [
                "线索必须公平呈现",
                "每个反转都要有伏笔",
                "真相出人意料但合情合理",
                "多线叙事最终交汇",
                "叙述性诡计可以使用"
            ],
            characterArchetypes: ["侦探型主角", "嫌疑人A/B/C", "隐藏的真凶", "关键证人", "误导性角色"],
            pacingGuide: "案件→调查→误导→反转→真相→终极反转",
            hookPatterns: ["新线索发现", "嫌疑人排除", "关键反转", "真相揭露", "终极反转"],
            pleasurePointTypes: ["推理正确", "真相大白", "伏笔回收", "反转震撼", "逻辑自洽"]
        ),
        LegacyGenreTemplate(
            id: "supernatural-suspense", name: "悬疑灵异", aliases: ["灵异", "鬼故事"],
            category: .suspense,
            description: "灵异元素与悬疑推理结合的故事",
            worldRules: [
                "灵异现象是真实存在的",
                "每个灵异事件背后有因果",
                "驱邪/化解有特定方法",
                "阴阳眼/灵媒是特殊能力",
                "因果报应是核心法则"
            ],
            characterArchetypes: ["灵媒/道士", "被缠上的普通人", "鬼魂/怨灵", "民间高人", "知情者"],
            pacingGuide: "遭遇灵异→调查真相→化解怨念→揭示因果",
            hookPatterns: ["灵异事件", "真相调查", "驱邪过程", "因果揭示", "善后化解"],
            pleasurePointTypes: ["驱邪成功", "真相大白", "怨灵化解", "因果圆满", "能力提升"]
        ),
        LegacyGenreTemplate(
            id: "cthulhu", name: "克苏鲁", aliases: ["克系", "克系悬疑"],
            category: .suspense,
            description: "面对不可名状的宇宙恐怖",
            worldRules: [
                "宇宙中有不可理解的存在",
                "知识本身就是危险",
                "理智值(SAN)是核心属性",
                "人类在宇宙中微不足道",
                "恐惧来自未知而非暴力"
            ],
            characterArchetypes: ["调查员", "邪教徒", "古老存在", "疯狂学者", "幸存者"],
            pacingGuide: "日常→异常→调查→深入→疯狂边缘→直面恐怖",
            hookPatterns: ["异常发现", "理智下降", "邪教仪式", "古神苏醒", "禁忌知识"],
            pleasurePointTypes: ["理智保全", "逃脱恐怖", "知识获取", "邪教挫败", "生存"]
        ),
        LegacyGenreTemplate(
            id: "dog-blood-romance", name: "狗血言情", aliases: ["狗血"],
            category: .suspense,
            description: "极致冲突、极致反转的言情故事",
            worldRules: [
                "冲突要足够极端",
                "反转要足够震撼",
                "虐要虐到极致",
                "甜要甜到齁",
                "配角要足够讨厌"
            ],
            characterArchetypes: ["虐心女主", "渣男/深情男主", "恶毒女配", "忠犬男二", "极品亲戚"],
            pacingGuide: "甜蜜→背叛→虐心→真相→追妻火葬场→大团圆",
            hookPatterns: ["背叛揭秘", "虐心名场面", "身份反转", "追妻火葬场", "终极真相"],
            pleasurePointTypes: ["打脸渣男", "虐心反转", "追妻火葬场", "真相大白", "大团圆"]
        )
    ]
}
