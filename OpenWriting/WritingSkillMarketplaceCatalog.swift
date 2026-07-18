import Foundation

protocol WritingSkillCatalogProviding {
    func catalog(
        publishedSkills: [WritingSkill],
        installedSkills: [WritingSkill]
    ) -> [WritingSkill]
}

struct BundledWritingSkillCatalog: WritingSkillCatalogProviding {
    let curatedSkills: [WritingSkill]

    init(curatedSkills: [WritingSkill] = WritingSkillMarketplace.featured) {
        self.curatedSkills = curatedSkills
    }

    func catalog(
        publishedSkills: [WritingSkill],
        installedSkills: [WritingSkill]
    ) -> [WritingSkill] {
        let installedByID = installedSkills.reduce(into: [WritingSkill.ID: WritingSkill]()) { result, skill in
            if result[skill.id] == nil {
                result[skill.id] = skill
            }
        }
        let curatedIDs = Set(curatedSkills.map(\.id))
        var seenPublishedIDs = Set<WritingSkill.ID>()
        let uniquePublishedSkills = publishedSkills.filter { seenPublishedIDs.insert($0.id).inserted }
        let localSubmissions = uniquePublishedSkills
            .filter { skill in
                skill.marketplaceListing?.source == .localSubmission
                    && !curatedIDs.contains(skill.id)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.marketplaceListing?.publishedAt ?? .distantPast
                let rhsDate = rhs.marketplaceListing?.publishedAt ?? .distantPast
                return lhsDate > rhsDate
            }

        return (localSubmissions + curatedSkills).map { listedSkill in
            var resolved = listedSkill
            resolved.isEnabled = installedByID[listedSkill.id]?.isEnabled ?? false
            return resolved
        }
    }
}

enum WritingSkillMarketplace {
    static let featured: [WritingSkill] = [
        curatedSkill(
            id: "marketplace-longform-continuity",
            title: "长篇连续性守门",
            summary: "续写前先压住人物状态、伏笔边界和上一章尾声，适合长篇连载。",
            instructions: """
            - 续写必须承接上一章末尾的动作、情绪和信息缺口，不要用总结式开头重讲设定。
            - 新增设定前先检查它是否服务本章目标、长期伏笔或人物关系变化。
            - 不提前揭示长期真相；需要制造信息增量时，优先给出可验证的线索、代价或选择。
            - 每一段场景推进都要让人物状态、局势压力或读者问题至少变化一项。
            """,
            category: .structure
        ),
        curatedSkill(
            id: "marketplace-webnovel-hook",
            title: "网文追读钩子",
            summary: "强化章节内的小悬念、段尾推进和结尾追读，不牺牲连续性。",
            instructions: """
            - 每 600 到 900 字制造一次明确的信息增量、情绪翻面或行动压力。
            - 段尾避免空泛感叹，优先落在未完成动作、意外线索、关系错位或选择代价上。
            - 章节结尾留下一个下一章必须处理的问题，但不要用生硬断章破坏当前场景。
            - 钩子要来自现有设定和人物目标，不凭空添加大反转。
            """,
            category: .genre
        ),
        curatedSkill(
            id: "marketplace-natural-dialogue",
            title: "对白自然化",
            summary: "降低说明腔，让对白承担试探、隐瞒、误解和关系推进。",
            instructions: """
            - 对白不要替作者解释世界观；人物只说自己此刻会说、敢说、想隐藏的话。
            - 长句说明拆成动作、停顿、反问和未说出口的信息。
            - 每段对白至少承担一种功能：推进关系、暴露欲望、制造误解、交换筹码或改变局势。
            - 避免所有角色同一种口吻；用词长度、礼貌程度和关注点区分人物。
            """,
            category: .voice
        ),
        curatedSkill(
            id: "marketplace-revision-pass",
            title: "终稿减 AI 味",
            summary: "返修时优先删解释、压重复、补动作细节，让正文更像人工终稿。",
            instructions: """
            - 删除重复解释、抽象感慨和已经由动作表达过的心理复述。
            - 把泛泛的情绪词替换成可见动作、环境反应、身体感受或具体选择。
            - 保留剧情事实和段落顺序，只做必要的节奏、句式和细节修订。
            - 避免连续使用同构句式、成套转折词和总结性金句。
            """,
            category: .revision
        )
    ]

    private static func curatedSkill(
        id: String,
        title: String,
        summary: String,
        instructions: String,
        category: WritingSkillCategory
    ) -> WritingSkill {
        WritingSkill(
            id: id,
            title: title,
            summary: summary,
            instructions: instructions,
            category: category,
            origin: .marketplace,
            sourceName: "OpenWriting Skill 市场",
            isEnabled: false,
            marketplaceListing: WritingSkillMarketplaceListing(
                publisherName: "OpenWriting",
                version: "1.0.0",
                source: .curated,
                publishedAt: Date(timeIntervalSince1970: 1_773_734_400)
            )
        )
    }
}
