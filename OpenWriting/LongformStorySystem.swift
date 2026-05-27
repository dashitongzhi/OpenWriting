import Foundation

enum LongformCommitStatus: String, Codable, Hashable {
    case accepted
    case rejected
}

struct LongformStoryContractBundle: Codable, Hashable {
    var master: MasterContract
    var volume: VolumeContract
    var chapter: ChapterContract
    var review: ReviewContract
    var prewrite: PrewriteContract
    var writingBrief: String
    var updatedAt: Date

    struct MasterContract: Codable, Hashable {
        var title: String
        var genre: String
        var storyLength: NovelLength
        var summary: String
        var coreLaws: [String]
        var genreRules: [String]
        var antiPatterns: [String]
    }

    struct VolumeContract: Codable, Hashable {
        var volumeNumber: Int
        var volumeGoal: String
        var pacingStrategy: String
        var activeThreads: [String]
        var strandTargets: StrandTargets
    }

    struct StrandTargets: Codable, Hashable {
        var quest: Double
        var fire: Double
        var constellation: Double
        var questMaxConsecutive: Int
        var fireMaxGap: Int
        var constellationMaxGap: Int
    }

    struct ChapterContract: Codable, Hashable {
        var chapterNumber: Int
        var chapterTitle: String
        var chapterGoal: String
        var mandatoryNodes: [String]
        var requiresMandatoryNodeCoverage: Bool?
        var sceneDirectives: [String]
        var characterDirectives: [String]
        var activeForeshadowing: [String]
        var forbiddenZones: [String]
    }

    struct ReviewContract: Codable, Hashable {
        var mustCheck: [String]
        var blockingRules: [String]
        var genreSpecificRisks: [String]
        var minimumAcceptedScore: Int
    }

    struct PrewriteContract: Codable, Hashable {
        var isBlocked: Bool
        var blockingReasons: [String]
        var warnings: [String]
        var memoryConflicts: [String]
    }
}

struct LongformChapterCommit: Codable, Hashable, Identifiable {
    var id: String
    var chapterNumber: Int
    var volumeNumber: Int
    var chapterTitle: String
    var status: LongformCommitStatus
    var createdAt: Date
    var plannedNodes: [String]
    var coveredNodes: [String]
    var missedNodes: [String]
    var rejectionReasons: [String]?
    var acceptedEvents: [LongformStoryEvent]
    var extractedMemoryItems: [MemoryItem]
    var dominantThreadType: ThreadType
    var reviewSummary: String
    var projectionStatus: [String: String]

    var isAccepted: Bool {
        status == .accepted
    }
}

struct LongformStoryEvent: Codable, Hashable, Identifiable {
    var id: String
    var chapter: Int
    var eventType: String
    var subject: String
    var field: String
    var value: String
}

struct LongformStoryRuntimeState: Codable, Hashable {
    var latestContract: LongformStoryContractBundle?
    var latestCommit: LongformChapterCommit?
    var acceptedCommits: [LongformChapterCommit]
    var rejectedCommits: [LongformChapterCommit]

    static let empty = LongformStoryRuntimeState(
        latestContract: nil,
        latestCommit: nil,
        acceptedCommits: [],
        rejectedCommits: []
    )

    mutating func record(contract: LongformStoryContractBundle) {
        latestContract = contract
    }

    mutating func record(commit: LongformChapterCommit) {
        latestCommit = commit
        if commit.isAccepted {
            acceptedCommits.removeAll { $0.chapterNumber == commit.chapterNumber }
            acceptedCommits.insert(commit, at: 0)
            acceptedCommits = Array(acceptedCommits.prefix(40))
        } else {
            rejectedCommits.removeAll { $0.chapterNumber == commit.chapterNumber }
            rejectedCommits.insert(commit, at: 0)
            rejectedCommits = Array(rejectedCommits.prefix(20))
        }
    }
}

enum LongformStorySystem {
    static func buildRuntimeContract(for project: NovelProject) -> LongformStoryContractBundle {
        let validation = PrewriteValidator.validate(project: project)
        let memoryConflicts = project.memoryBuckets.conflicts.map {
            "\($0.category.displayName)：\($0.key) 存在 \($0.count) 条生效记录"
        }
        let strand = project.strandWeaveState
        let activeThreadLines = activeThreadSummaries(for: project)
        let chapterNodePlan = chapterRelevantLines(
            from: [project.outlineText, project.structureNotes],
            chapter: project.currentChapterNumber,
            fallback: project.chapterFocus
        )
        let sceneNodePlan = chapterRelevantLines(
            from: [project.sceneProgressNotes],
            chapter: project.currentChapterNumber,
            fallback: ""
        )
        let characterNodePlan = chapterRelevantLines(
            from: [project.characterArcNotes],
            chapter: project.currentChapterNumber,
            fallback: ""
        )
        let foreshadowLines = activeForeshadowingLines(for: project)
        let forbiddenZones = forbiddenZones(for: project)
        let reviewContract = LongformStoryContractBundle.ReviewContract(
            mustCheck: ReviewDimension.allUnifiedDimensions.map(\.checkDescription),
            blockingRules: [
                "不得违背已记录的角色状态、世界规则、时间线和章节目标。",
                "不得跳过本章目标中的必要推进节点。",
                "不得让已有未回收伏笔失去状态记录。",
                "不得把草稿箱已有正文改写成另一条时间线。"
            ],
            genreSpecificRisks: genreRisks(for: project),
            minimumAcceptedScore: 60
        )
        let contract = LongformStoryContractBundle(
            master: .init(
                title: project.title,
                genre: project.genre,
                storyLength: project.storyLength,
                summary: project.summary,
                coreLaws: [
                    "大纲即法律：章节目标和结构节点优先于模型自由发挥。",
                    "设定即物理：人物能力、世界规则、地点和道具状态必须承接现有记录。",
                    "发明需识别：新增角色、关系、伏笔和规则必须进入写后提交。"
                ],
                genreRules: project.genreTemplate.formattedForPrompt.nonEmptyLines(limit: 8),
                antiPatterns: Array(project.accumulatedAntiPatterns.prefix(12))
            ),
            volume: .init(
                volumeNumber: max(project.currentVolumeNumber, 1),
                volumeGoal: firstUsefulText([project.volumePlanNotes, project.outlineSummary, project.summary]),
                pacingStrategy: project.storyLength.outlineDirective,
                activeThreads: activeThreadLines,
                strandTargets: .init(
                    quest: strand.questTarget,
                    fire: strand.fireTarget,
                    constellation: strand.constellationTarget,
                    questMaxConsecutive: strand.questMaxConsecutive,
                    fireMaxGap: strand.fireMaxGap,
                    constellationMaxGap: strand.constellationMaxGap
                )
            ),
            chapter: .init(
                chapterNumber: max(project.currentChapterNumber, 1),
                chapterTitle: project.currentChapterTitle,
                chapterGoal: firstUsefulText([project.chapterFocus, project.currentChapterSummary]),
                mandatoryNodes: chapterNodePlan.lines,
                requiresMandatoryNodeCoverage: chapterNodePlan.requiresCoverage,
                sceneDirectives: sceneNodePlan.lines,
                characterDirectives: characterNodePlan.lines,
                activeForeshadowing: foreshadowLines,
                forbiddenZones: forbiddenZones
            ),
            review: reviewContract,
            prewrite: .init(
                isBlocked: !validation.isReady || !memoryConflicts.isEmpty,
                blockingReasons: validation.blockingReasons,
                warnings: validation.warnings,
                memoryConflicts: memoryConflicts
            ),
            writingBrief: "",
            updatedAt: Date()
        )

        var completed = contract
        completed.writingBrief = writingBrief(for: project, contract: completed)
        return completed
    }

    static func buildCommit(
        project: NovelProject,
        chapterDraft: ChapterDraft,
        review: ChapterReviewResult?,
        reviewFailureReason: String? = nil,
        extractedMemoryItems: [MemoryItem],
        contract: LongformStoryContractBundle
    ) -> LongformChapterCommit {
        let plannedNodes = contract.chapter.mandatoryNodes
        let coveredNodes = plannedNodes.filter { nodeIsCovered($0, by: chapterDraft.content) }
        let missedNodes = plannedNodes.filter { !coveredNodes.contains($0) }
        let hasBlockingReview = review?.hasBlockingIssues ?? false
        let belowMinimumScore = review.map { $0.overallScore < contract.review.minimumAcceptedScore } ?? false
        var rejectionReasons: [String] = []
        if hasBlockingReview {
            rejectionReasons.append("写后审查存在阻断问题")
        }
        if belowMinimumScore {
            rejectionReasons.append("审查分数低于最低通过线 \(contract.review.minimumAcceptedScore)")
        }
        if let reviewFailureReason {
            rejectionReasons.append("当前章审查失败：\(reviewFailureReason)")
        }
        if contract.chapter.requiresMandatoryNodeCoverage == true && !missedNodes.isEmpty {
            rejectionReasons.append("未覆盖本章明确节点：\(missedNodes.prefix(3).joined(separator: "；"))")
        }
        let status: LongformCommitStatus = rejectionReasons.isEmpty ? .accepted : .rejected
        let events = extractedMemoryItems.map {
            LongformStoryEvent(
                id: stableID(parts: ["event", String(chapterDraft.chapterNumber), $0.category.rawValue, $0.subject, $0.field, $0.value]),
                chapter: chapterDraft.chapterNumber,
                eventType: eventType(for: $0.category),
                subject: $0.subject,
                field: $0.field,
                value: $0.value
            )
        }
        let dominantThread = dominantThreadType(from: chapterDraft.content, fallback: project.strandWeaveState.entries.last?.dominant ?? .quest)
        return LongformChapterCommit(
            id: stableID(parts: ["commit", project.id, String(chapterDraft.volumeNumber), String(chapterDraft.chapterNumber), chapterDraft.content]),
            chapterNumber: chapterDraft.chapterNumber,
            volumeNumber: chapterDraft.volumeNumber,
            chapterTitle: chapterDraft.chapterTitle,
            status: status,
            createdAt: Date(),
            plannedNodes: plannedNodes,
            coveredNodes: coveredNodes,
            missedNodes: missedNodes,
            rejectionReasons: rejectionReasons,
            acceptedEvents: status == .accepted ? events : [],
            extractedMemoryItems: status == .accepted ? extractedMemoryItems : [],
            dominantThreadType: dominantThread,
            reviewSummary: review?.summary ?? "暂无写后审查结果。",
            projectionStatus: [
                "memory": status == .accepted ? "pending" : "skipped",
                "foreshadowing": status == .accepted ? "pending" : "skipped",
                "threads": status == .accepted ? "pending" : "skipped",
                "runtime": "pending"
            ]
        )
    }

    static func apply(
        commit: LongformChapterCommit,
        contract: LongformStoryContractBundle,
        to project: inout NovelProject
    ) {
        var runtime = project.longformRuntimeState
        runtime.record(contract: contract)

        var updatedCommit = commit
        guard commit.isAccepted else {
            updatedCommit.projectionStatus["runtime"] = "done"
            updatedCommit.projectionStatus["quality_gate"] = "rejected"
            runtime.record(commit: updatedCommit)
            project.longformRuntimeState = runtime
            return
        }

        var buckets = project.memoryBuckets
        for item in commit.extractedMemoryItems {
            buckets.upsert(item)
        }
        buckets.compact(currentChapter: commit.chapterNumber)
        project.memoryBuckets = buckets
        updatedCommit.projectionStatus["memory"] = "done"

        applyForeshadowing(from: commit, to: &project)
        updatedCommit.projectionStatus["foreshadowing"] = "done"

        applyThreadProgress(from: commit, to: &project)
        updatedCommit.projectionStatus["threads"] = "done"

        updatedCommit.projectionStatus["runtime"] = "done"
        updatedCommit.projectionStatus["quality_gate"] = "passed"
        runtime.record(commit: updatedCommit)
        project.longformRuntimeState = runtime
    }

    static func contextBlock(for project: NovelProject) -> String {
        let contract = buildRuntimeContract(for: project)
        return contract.writingBrief
    }

    private static func writingBrief(
        for project: NovelProject,
        contract: LongformStoryContractBundle
    ) -> String {
        let chapter = contract.chapter
        let master = contract.master
        let volume = contract.volume
        let prewrite = contract.prewrite

        var sections: [String] = []
        sections.append("""
        【后台写作合同】
        作品：\(master.title)
        题材：\(master.genre)
        规模：\(master.storyLength.title)，目标是支撑长篇连载、分卷推进和跨章记忆一致。
        当前：第 \(volume.volumeNumber) 卷 · 第 \(chapter.chapterNumber) 章《\(chapter.chapterTitle)》
        本章目标：\(chapter.chapterGoal)
        """)

        let nodeText = formatList(chapter.mandatoryNodes, fallback: "暂无明确章节节点，按本章目标推进一个实质变化。")
        let sceneText = formatList(chapter.sceneDirectives, fallback: "暂无单独场景约束，优先承接草稿箱最后状态。")
        sections.append("""
        【本章必须执行】
        章节节点：
        \(nodeText)

        场景推进：
        \(sceneText)
        """)

        let memoryItems = project.memoryBuckets.relevantActiveItems(
            for: [chapter.chapterGoal, chapter.mandatoryNodes.joined(separator: " "), project.draftText].joined(separator: " "),
            limit: 24
        )
        let memoryText = memoryItems.isEmpty
            ? "暂无命中的结构化记忆。"
            : memoryItems.map { "- [\($0.category.displayName)] \($0.subject) / \($0.field)：\($0.value)" }.joined(separator: "\n")
        sections.append("""
        【后台记忆约束】
        \(memoryText)
        """)

        let foreshadowText = formatList(chapter.activeForeshadowing, fallback: "暂无活跃伏笔命中。")
        let threadText = formatList(volume.activeThreads, fallback: "暂无结构化叙事线，按主线推进。")
        sections.append("""
        【长篇连续性】
        分卷目标：\(volume.volumeGoal)
        在途线索：
        \(threadText)

        未回收伏笔：
        \(foreshadowText)
        """)

        let forbiddenText = formatList(chapter.forbiddenZones + contract.review.blockingRules, fallback: "不得违背已有设定、时间线和草稿箱状态。")
        let riskText = formatList(contract.review.genreSpecificRisks + master.antiPatterns, fallback: "避免安全着陆、重复解释和人物突然失忆。")
        sections.append("""
        【禁区与风险】
        \(forbiddenText)

        题材/风格风险：
        \(riskText)
        """)

        if prewrite.isBlocked || !prewrite.warnings.isEmpty || !prewrite.memoryConflicts.isEmpty {
            let reasons = prewrite.blockingReasons + prewrite.memoryConflicts + prewrite.warnings
            sections.append("""
            【写前预警】
            \(formatList(reasons, fallback: "无。"))
            """)
        }

        sections.append("""
        【写作输出】
        直接续写正文。不要解释合同，不要列提纲，不要替读者总结设定。每次至少推进一个情节拍点、关系变化、信息增量或伏笔状态。
        """)

        return sections.joined(separator: "\n\n")
    }

    private static func applyForeshadowing(from commit: LongformChapterCommit, to project: inout NovelProject) {
        for item in commit.extractedMemoryItems where item.category == .openLoop || item.category == .readerPromise {
            let title = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let isResolved = title.contains("已回收")
                || title.contains("已解决")
                || title.contains("兑现")
                || title.localizedCaseInsensitiveContains("resolved")
                || title.localizedCaseInsensitiveContains("paid_off")

            if isResolved,
               let existing = project.foreshadowList.entries.first(where: { title.contains($0.title) || $0.title.contains(title) }) {
                project.foreshadowList.resolveForeshadow(id: existing.id, at: commit.chapterNumber)
                continue
            }

            if project.foreshadowList.entries.contains(where: { $0.title == title }) {
                continue
            }

            project.foreshadowList.add(
                ForeshadowEntry(
                    title: title,
                    description: item.field,
                    firstChapter: commit.chapterNumber,
                    volumeNumber: commit.volumeNumber,
                    status: .active,
                    importance: item.category == .readerPromise ? .major : .minor,
                    threads: [commit.dominantThreadType.rawValue],
                    lastAdvancedChapter: commit.chapterNumber,
                    plantedChapter: commit.chapterNumber,
                    expectedResolutionChapter: commit.chapterNumber + 20,
                    notes: "由后台章节提交自动识别"
                )
            )
        }
        project.foreshadowList.pruneResolved()
    }

    private static func applyThreadProgress(from commit: LongformChapterCommit, to project: inout NovelProject) {
        let threadType = commit.dominantThreadType
        let event = ThreadEvent(
            chapter: commit.chapterNumber,
            title: commit.chapterTitle,
            description: commit.extractedMemoryItems
                .filter { $0.category == .storyFact || $0.category == .timeline }
                .prefix(3)
                .map(\.value)
                .joined(separator: "；"),
            eventType: .development
        )

        if let existing = project.plotThreadList.threads.first(where: { $0.threadType == threadType && $0.isActive }) {
            project.plotThreadList.addEventToThread(threadID: existing.id, event: event)
        } else {
            var thread = PlotThread(
                title: threadType.displayName,
                description: "后台根据章节提交自动维护的\(threadType.displayName)",
                threadType: threadType,
                status: .advancing,
                startChapter: commit.chapterNumber,
                lastActiveChapter: commit.chapterNumber,
                volumeRange: commit.volumeNumber...commit.volumeNumber
            )
            thread.addEvent(event)
            project.plotThreadList.add(thread)
        }
        project.plotThreadList.pruneCompleted()
    }

    private static func activeForeshadowingLines(for project: NovelProject) -> [String] {
        let structured = project.foreshadowList.activeEntries
            .sorted { $0.importance.rawValue < $1.importance.rawValue }
            .prefix(12)
            .map { "\($0.title)：\($0.description)" }
        if !structured.isEmpty {
            return Array(structured)
        }
        return project.foreshadowNotes.nonEmptyLines(limit: 12)
    }

    private static func activeThreadSummaries(for project: NovelProject) -> [String] {
        let structured = project.plotThreadList.activeThreads
            .prefix(12)
            .map { "\($0.threadType.displayName)：\($0.title)，最后活跃第 \($0.lastActiveChapter) 章" }
        if !structured.isEmpty {
            return Array(structured)
        }
        return project.activeThreadsNotes.nonEmptyLines(limit: 12)
    }

    private static func chapterRelevantLines(
        from texts: [String],
        chapter: Int,
        fallback: String
    ) -> (lines: [String], requiresCoverage: Bool) {
        let markers = [
            "第\(chapter)章",
            "第 \(chapter) 章",
            "\(chapter).",
            "\(chapter)、",
            "\(chapter)）",
            "\(chapter)"
        ]
        let lines = texts
            .flatMap { $0.nonEmptyLines(limit: 240) }
            .filter { line in markers.contains { line.contains($0) } }
            .map { $0.cleanedListLine }
        if !lines.isEmpty {
            return (Array(lines.prefix(10)), true)
        }
        let fallbackLine = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackLine.isEmpty else {
            return ([], false)
        }
        return ([fallbackLine], fallbackLine != "继续补齐当前章节的目标、冲突和场景节奏。")
    }

    private static func forbiddenZones(for project: NovelProject) -> [String] {
        var zones = [
            "不要重写用户已经放进草稿箱的正文。",
            "不要绕回上一章重新起笔。",
            "不要提前揭示长期真相或一次性回收所有伏笔。"
        ]
        if project.storyLength == .long {
            zones.append("长篇模式下不要单章透支底牌，关键信息应分阶段释放。")
        }
        if project.hasGlobalMemory {
            zones.append("不得违背全局记忆中的人物关系、身份、伤势、阵营、地点和道具状态。")
        }
        return zones
    }

    private static func genreRisks(for project: NovelProject) -> [String] {
        let genre = project.genre + " " + project.genreTemplate.name
        if genre.contains("悬疑") || genre.contains("规则") {
            return ["线索必须可回溯，不得靠临时补设定破案。", "真相推进要有证据链，不要突然宣布答案。"]
        }
        if genre.contains("修仙") || genre.contains("玄幻") || genre.contains("高武") {
            return ["战力、境界、代价和冷却必须承接已有记录。", "升级需要代价或条件，避免无来源变强。"]
        }
        if genre.contains("言情") || genre.contains("甜宠") || genre.contains("婚恋") {
            return ["关系变化必须有互动证据，不要突然改变情感立场。", "误会和和解都要保留人物动机。"]
        }
        return ["保持题材承诺，不要让章节偏离既定读者期待。"]
    }

    private static func firstUsefulText(_ candidates: [String]) -> String {
        candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "暂无明确记录。"
    }

    private static func nodeIsCovered(_ node: String, by content: String) -> Bool {
        let keyPhrase = node.keyPhraseForMatching
        if keyPhrase.count >= 2, content.localizedCaseInsensitiveContains(keyPhrase) {
            return true
        }

        let tokens = node.coverageTokens
        guard !tokens.isEmpty else { return false }
        let hitCount = tokens.filter { content.localizedCaseInsensitiveContains($0) }.count
        return hitCount >= min(2, tokens.count)
    }

    private static func formatList(_ items: [String], fallback: String) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "- \(fallback)" }
        return cleaned.prefix(16).map { "- \($0)" }.joined(separator: "\n")
    }

    private static func eventType(for category: MemoryCategory) -> String {
        switch category {
        case .characterState:
            return "character_state_changed"
        case .relationship:
            return "relationship_changed"
        case .worldRule:
            return "world_rule_revealed"
        case .storyFact:
            return "story_fact"
        case .timeline:
            return "timeline_event"
        case .openLoop:
            return "open_loop_created"
        case .readerPromise:
            return "promise_created"
        }
    }

    private static func dominantThreadType(from text: String, fallback: StrandType) -> ThreadType {
        let fireKeywords = ["心动", "喜欢", "爱", "拥抱", "亲吻", "脸红", "心跳", "思念", "吃醋", "告白", "暧昧"]
        let constellationKeywords = ["势力", "家族", "宗门", "王国", "帝国", "规则", "体系", "境界", "历史", "大陆", "世界"]
        let fireCount = fireKeywords.filter { text.contains($0) }.count
        let constellationCount = constellationKeywords.filter { text.contains($0) }.count
        if fireCount >= 3 && fireCount > constellationCount {
            return .fire
        }
        if constellationCount >= 3 && constellationCount > fireCount {
            return .constellation
        }
        switch fallback {
        case .fire:
            return .fire
        case .constellation:
            return .constellation
        case .quest:
            return .quest
        }
    }

    private static func stableID(parts: [String]) -> String {
        let raw = parts.joined(separator: "|")
        let hash = raw.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { result, scalar in
            (result ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

extension NovelProject {
    private static let longformRuntimeLock = NSLock()
    private static var longformRuntimeCache: [String: LongformStoryRuntimeState] = [:]

    var longformRuntimeState: LongformStoryRuntimeState {
        get {
            if let persistedLongformRuntimeState {
                return persistedLongformRuntimeState
            }

            if let data = UserDefaults.standard.data(forKey: "longformRuntime_\(id)"),
               let state = try? JSONDecoder().decode(LongformStoryRuntimeState.self, from: data) {
                return state
            }

            return .empty
        }
        set {
            persistedLongformRuntimeState = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "longformRuntime_\(id)")
            }
        }
    }

    var longformStorySystemContext: String {
        LongformStorySystem.contextBlock(for: self)
    }
}

private extension String {
    var cleanedListLine: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t"))
    }

    var keyPhraseForMatching: String {
        let cleaned = cleanedListLine
        let separators = CharacterSet(charactersIn: "：:，,。.;；、-")
        return cleaned
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 2 }
            ?? cleaned
    }

    var coverageTokens: [String] {
        let separators = CharacterSet(charactersIn: "：:，,。.;；、-—（）()[]【】《》\"“”‘’ \t")
        let rawTokens = cleanedListLine.components(separatedBy: separators)
        let trimmedTokens = rawTokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let ignoredTokens = Set(["第", "本章", "章节", "目标", "推进"])
        let meaningfulTokens = trimmedTokens.filter { token in
            token.count >= 2 && !ignoredTokens.contains(token)
        }
        return meaningfulTokens.prefix(8).map { String($0) }
    }

    func nonEmptyLines(limit: Int) -> [String] {
        components(separatedBy: .newlines)
            .map { $0.cleanedListLine }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { String($0) }
    }
}
