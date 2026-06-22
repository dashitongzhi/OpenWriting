import Foundation

enum LongformCommitStatus: String, Codable, Hashable {
    case accepted
    case rejected
}

enum LongformWriteGateStage: String, Codable, Hashable {
    case prewrite
    case review
    case fulfillment
    case projection

    var displayName: String {
        switch self {
        case .prewrite:
            return "写前"
        case .review:
            return "审查"
        case .fulfillment:
            return "节点"
        case .projection:
            return "投影"
        }
    }
}

enum LongformWriteGateStatus: String, Codable, Hashable {
    case passed
    case warning
    case blocked

    var displayName: String {
        switch self {
        case .passed:
            return "通过"
        case .warning:
            return "提醒"
        case .blocked:
            return "阻断"
        }
    }
}

struct LongformWriteGateCheck: Codable, Hashable, Identifiable {
    var id: String
    var stage: LongformWriteGateStage
    var status: LongformWriteGateStatus
    var message: String
    var detail: String?
}

struct LongformWriteGateReport: Codable, Hashable, Identifiable {
    var id: String
    var volumeNumber: Int
    var chapterNumber: Int
    var generatedAt: Date
    var overallStatus: LongformWriteGateStatus
    var checks: [LongformWriteGateCheck]

    var isPassed: Bool {
        overallStatus == .passed
    }

    var blockingChecks: [LongformWriteGateCheck] {
        checks.filter { $0.status == .blocked }
    }

    var warningChecks: [LongformWriteGateCheck] {
        checks.filter { $0.status == .warning }
    }

    var summary: String {
        if !blockingChecks.isEmpty {
            return "阻断 \(blockingChecks.count) 项"
        }
        if !warningChecks.isEmpty {
            return "警告 \(warningChecks.count) 项"
        }
        return "门禁通过"
    }
}

struct LongformRuntimeHealthIssue: Codable, Hashable, Identifiable {
    var id: String
    var status: LongformWriteGateStatus
    var title: String
    var detail: String
    var repairHint: String
}

struct LongformRuntimeHealthReport: Codable, Hashable, Identifiable {
    var id: String
    var volumeNumber: Int
    var chapterNumber: Int
    var generatedAt: Date
    var status: LongformWriteGateStatus
    var issues: [LongformRuntimeHealthIssue]
    var metrics: [String: String]

    var blockingIssues: [LongformRuntimeHealthIssue] {
        issues.filter { $0.status == .blocked }
    }

    var warningIssues: [LongformRuntimeHealthIssue] {
        issues.filter { $0.status == .warning }
    }

    var summary: String {
        if !blockingIssues.isEmpty {
            return "阻断 \(blockingIssues.count) 项"
        }
        if !warningIssues.isEmpty {
            return "提醒 \(warningIssues.count) 项"
        }
        return "健康"
    }

    var nextAction: String {
        if let issue = blockingIssues.first {
            return issue.repairHint
        }
        if let issue = warningIssues.first {
            return issue.repairHint
        }
        return "可以继续推进当前章节，但仍要保持写后审查和后台提交。"
    }
}

struct LongformQualityTrend {
    var recentScores: [Int]
    var minimumAcceptedScore: Int
    var recurringDimensions: [(dimension: ReviewDimension, count: Int)]
    var qualityDebtTargets: [String]
    var priorityIssues: [String]
    var antiPatterns: [String]
    var revisionHints: [String]

    var hasSignals: Bool {
        !recentScores.isEmpty
            || !recurringDimensions.isEmpty
            || !qualityDebtTargets.isEmpty
            || !priorityIssues.isEmpty
            || !antiPatterns.isEmpty
            || !revisionHints.isEmpty
    }

    var averageScore: Int? {
        guard !recentScores.isEmpty else { return nil }
        let total = recentScores.reduce(0, +)
        return Int((Double(total) / Double(recentScores.count)).rounded())
    }

    var lowScoreCount: Int {
        recentScores.filter { $0 < minimumAcceptedScore }.count
    }

    var formattedForPrompt: String {
        guard hasSignals else {
            return "暂无跨章节质量趋势。"
        }

        var lines: [String] = []
        if let averageScore {
            let scoreText = recentScores.prefix(6).map(String.init).joined(separator: " / ")
            let riskText = lowScoreCount > 0 ? "，其中 \(lowScoreCount) 次低于当前最低线 \(minimumAcceptedScore)" : ""
            lines.append("- 最近审查均分：\(averageScore)/100（\(scoreText)\(riskText)）。")
        }

        if !recurringDimensions.isEmpty {
            let dimensions = recurringDimensions
                .prefix(4)
                .map { "\($0.dimension.displayName)×\($0.count)" }
                .joined(separator: "；")
            lines.append("- 反复失分维度：\(dimensions)。")
        }

        if !qualityDebtTargets.isEmpty {
            lines.append("- 低分章节续写约束：\(qualityDebtTargets.prefix(4).joined(separator: "；"))")
        }

        if !priorityIssues.isEmpty {
            lines.append("- 下章必须主动修复：\(priorityIssues.prefix(4).joined(separator: "；"))")
        }

        if !antiPatterns.isEmpty {
            lines.append("- 避免重复 AI 味：\(antiPatterns.prefix(5).joined(separator: "；"))")
        }

        if !revisionHints.isEmpty {
            lines.append("- 未通过章节遗留修订债：\(revisionHints.prefix(4).joined(separator: "；"))")
        }

        return lines.joined(separator: "\n")
    }
}

struct LongformNextChapterBrief: Codable, Hashable {
    var chapterGoal: String
    var mandatoryContinuities: [String]
    var foreshadowingPromises: [String]
    var forbiddenContradictions: [String]
    var qualityDebts: [String]
    var repairTasks: [String]
    var risks: [String]

    var hasActionableSignals: Bool {
        !mandatoryContinuities.isEmpty
            || !foreshadowingPromises.isEmpty
            || !forbiddenContradictions.isEmpty
            || !qualityDebts.isEmpty
            || !repairTasks.isEmpty
            || !risks.isEmpty
    }

    var formattedForPrompt: String {
        var lines: [String] = []
        lines.append("本章目标：\(chapterGoal.isEmpty ? "推进当前章节一个实质变化。" : chapterGoal)")
        lines.append("必须延续的记忆：\(Self.formatList(mandatoryContinuities, fallback: "暂无命中的结构化记忆，请承接草稿箱最后状态。"))")
        lines.append("必须兑现或推进的伏笔：\(Self.formatList(foreshadowingPromises, fallback: "暂无明确活跃伏笔。"))")
        lines.append("禁止违反的设定：\(Self.formatList(forbiddenContradictions, fallback: "不得违背已有设定、时间线、人物状态和章节目标。"))")
        lines.append("当前质量债：\(Self.formatList(qualityDebts, fallback: "暂无未解决质量债。"))")
        lines.append("本章修复任务：\(Self.formatList(repairTasks, fallback: "暂无额外修复任务。"))")
        lines.append("风险提醒：\(Self.formatList(risks, fallback: "保持章末期待、人物动机和信息密度。"))")
        return lines.joined(separator: "\n")
    }

    private static func formatList(_ values: [String], fallback: String) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return fallback }
        return cleaned.prefix(6).joined(separator: "；")
    }
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
        var requiresPostwriteReview: Bool?
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
    var revisionHints: [String]? = nil
    var acceptedEvents: [LongformStoryEvent]
    var extractedMemoryItems: [MemoryItem]
    var dominantThreadType: ThreadType
    var reviewSummary: String
    var projectionStatus: [String: String]

    var isAccepted: Bool {
        status == .accepted
    }

    func matchesPosition(of other: LongformChapterCommit) -> Bool {
        volumeNumber == other.volumeNumber && chapterNumber == other.chapterNumber
    }
}

struct LongformStoryEvent: Codable, Hashable, Identifiable {
    var id: String
    var volumeNumber: Int? = nil
    var chapter: Int
    var eventType: String
    var subject: String
    var field: String
    var value: String
}

struct LongformStoryRuntimeState: Codable, Hashable {
    private static let rejectedCommitHistoryLimit = 200

    var latestContract: LongformStoryContractBundle?
    var latestCommit: LongformChapterCommit?
    var latestWriteGate: LongformWriteGateReport?
    var acceptedCommits: [LongformChapterCommit]
    var rejectedCommits: [LongformChapterCommit]

    static let empty = LongformStoryRuntimeState(
        latestContract: nil,
        latestCommit: nil,
        latestWriteGate: nil,
        acceptedCommits: [],
        rejectedCommits: []
    )

    mutating func record(contract: LongformStoryContractBundle) {
        latestContract = contract
    }

    mutating func record(writeGate: LongformWriteGateReport) {
        latestWriteGate = writeGate
    }

    mutating func record(commit: LongformChapterCommit) {
        latestCommit = commit
        if commit.isAccepted {
            acceptedCommits.removeAll { $0.matchesPosition(of: commit) }
            rejectedCommits.removeAll { $0.matchesPosition(of: commit) }
            acceptedCommits.insert(commit, at: 0)
        } else {
            acceptedCommits.removeAll { $0.matchesPosition(of: commit) }
            rejectedCommits.removeAll { $0.matchesPosition(of: commit) }
            rejectedCommits.insert(commit, at: 0)
            rejectedCommits = Array(rejectedCommits.prefix(Self.rejectedCommitHistoryLimit))
        }
    }
}

enum LongformStorySystem {
    private struct SavedChapterRuntimeProbe {
        var volumeNumber: Int
        var chapterNumber: Int
        var chapterSummary: String
        var savedAtDate: Date
        var draft: ChapterDraft?

        init(metadata: ChapterDraftMetadata, draft: ChapterDraft?) {
            if let draft {
                volumeNumber = max(draft.volumeNumber, 1)
                chapterNumber = max(draft.chapterNumber, 1)
                chapterSummary = draft.chapterSummary
                savedAtDate = draft.savedAtDate
                self.draft = draft
            } else {
                volumeNumber = max(metadata.volumeNumber, 1)
                chapterNumber = max(metadata.chapterNumber, 1)
                chapterSummary = metadata.chapterSummary
                savedAtDate = metadata.savedAtDate
                self.draft = nil
            }
        }

        init(draft: ChapterDraft) {
            volumeNumber = max(draft.volumeNumber, 1)
            chapterNumber = max(draft.chapterNumber, 1)
            chapterSummary = draft.chapterSummary
            savedAtDate = draft.savedAtDate
            self.draft = draft
        }

        nonisolated static func sortDescending(_ lhs: SavedChapterRuntimeProbe, _ rhs: SavedChapterRuntimeProbe) -> Bool {
            if lhs.volumeNumber != rhs.volumeNumber {
                return lhs.volumeNumber > rhs.volumeNumber
            }
            if lhs.chapterNumber != rhs.chapterNumber {
                return lhs.chapterNumber > rhs.chapterNumber
            }
            return lhs.savedAtDate > rhs.savedAtDate
        }
    }

    static func minimumAcceptedScore(for storyLength: NovelLength) -> Int {
        switch storyLength {
        case .short:
            return 60
        case .medium:
            return 68
        case .long:
            return 75
        }
    }

    static func buildRuntimeContract(for project: NovelProject) -> LongformStoryContractBundle {
        let validation = PrewriteValidator.validate(project: project)
        let memoryConflicts = project.memoryBuckets.conflicts.map {
            "\($0.category.displayName)：\($0.key) 存在 \($0.count) 条生效记录"
        }
        let strand = project.strandWeaveState
        let activeThreadLines = activeThreadSummaries(for: project)
        let chapterNodePlan = chapterRelevantLines(
            from: [project.outlineText, project.structureNotes],
            volume: project.currentVolumeNumber,
            chapter: project.currentChapterNumber,
            fallback: project.chapterFocus
        )
        let sceneNodePlan = chapterRelevantLines(
            from: [project.sceneProgressNotes],
            volume: project.currentVolumeNumber,
            chapter: project.currentChapterNumber,
            fallback: ""
        )
        let characterNodePlan = chapterRelevantLines(
            from: [project.characterArcNotes],
            volume: project.currentVolumeNumber,
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
            minimumAcceptedScore: minimumAcceptedScore(for: project.storyLength),
            requiresPostwriteReview: project.storyLength.supportsVolumePlanning
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
        let requiresReview = contract.review.requiresPostwriteReview ?? false
        var rejectionReasons: [String] = []
        if contract.prewrite.isBlocked {
            let reasons = (contract.prewrite.blockingReasons + contract.prewrite.memoryConflicts)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if reasons.isEmpty {
                rejectionReasons.append("写前合同未通过")
            } else {
                rejectionReasons.append("写前合同未通过：\(reasons.prefix(2).joined(separator: "；"))")
            }
        }
        if hasBlockingReview {
            rejectionReasons.append("写后审查存在阻断问题")
        }
        if belowMinimumScore {
            rejectionReasons.append("审查分数低于最低通过线 \(contract.review.minimumAcceptedScore)")
        }
        if requiresReview && review == nil && reviewFailureReason == nil {
            rejectionReasons.append("长篇提交缺少写后审查结果")
        }
        if let reviewFailureReason {
            rejectionReasons.append("当前章审查失败：\(reviewFailureReason)")
        }
        if contract.chapter.requiresMandatoryNodeCoverage == true && !missedNodes.isEmpty {
            rejectionReasons.append("未覆盖本章明确节点：\(missedNodes.prefix(3).joined(separator: "；"))")
        }
        let status: LongformCommitStatus = rejectionReasons.isEmpty ? .accepted : .rejected
        let revisionHints = buildRevisionHints(
            review: review,
            reviewFailureReason: reviewFailureReason,
            missedNodes: missedNodes,
            contract: contract
        )
        let events = extractedMemoryItems.map {
            LongformStoryEvent(
                id: stableID(parts: [
                    "event",
                    String(chapterDraft.volumeNumber),
                    String(chapterDraft.chapterNumber),
                    $0.category.rawValue,
                    $0.subject,
                    $0.field,
                    $0.value
                ]),
                volumeNumber: chapterDraft.volumeNumber,
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
            revisionHints: revisionHints,
            acceptedEvents: status == .accepted ? events : [],
            extractedMemoryItems: status == .accepted ? extractedMemoryItems : [],
            dominantThreadType: dominantThread,
            reviewSummary: review?.summary ?? "暂无写后审查结果。",
            projectionStatus: [
                "memory": status == .accepted ? "pending" : "skipped",
                "foreshadowing": status == .accepted ? "pending" : "skipped",
                "threads": status == .accepted ? "pending" : "skipped",
                "strands": status == .accepted ? "pending" : "skipped",
                "runtime": "pending"
            ]
        )
    }

    static func missingMandatoryNodes(
        for project: NovelProject,
        additionalText: String,
        contract: LongformStoryContractBundle? = nil
    ) -> [String] {
        let contract = contract ?? buildRuntimeContract(for: project)
        guard contract.chapter.requiresMandatoryNodeCoverage == true else {
            return []
        }

        let combinedContent = [project.draftText, additionalText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !combinedContent.isEmpty else {
            return contract.chapter.mandatoryNodes
        }

        return contract.chapter.mandatoryNodes.filter { node in
            !nodeIsCovered(node, by: combinedContent)
        }
    }

    static func buildWriteGateReport(
        commit: LongformChapterCommit,
        contract: LongformStoryContractBundle
    ) -> LongformWriteGateReport {
        let rejectionReasons = commit.rejectionReasons ?? []
        let prewriteStatus: LongformWriteGateStatus
        let prewriteMessage: String
        let prewriteDetail: String?
        if contract.prewrite.isBlocked {
            prewriteStatus = .blocked
            let reasons = contract.prewrite.blockingReasons + contract.prewrite.memoryConflicts
            prewriteMessage = "写前合同未通过"
            prewriteDetail = reasons.prefix(4).joined(separator: "；")
        } else if !contract.prewrite.warnings.isEmpty {
            prewriteStatus = .warning
            prewriteMessage = "写前可继续，但有建议项"
            prewriteDetail = contract.prewrite.warnings.prefix(4).joined(separator: "；")
        } else {
            prewriteStatus = .passed
            prewriteMessage = "写前合同通过"
            prewriteDetail = nil
        }

        let reviewReasons = rejectionReasons.filter {
            $0.contains("审查") || $0.contains("写后")
        }
        let requiresReview = contract.review.requiresPostwriteReview ?? false
        let reviewStatus: LongformWriteGateStatus
        let reviewMessage: String
        let reviewDetail: String?
        if !reviewReasons.isEmpty {
            reviewStatus = .blocked
            reviewMessage = "写后审查未通过"
            reviewDetail = reviewReasons.prefix(4).joined(separator: "；")
        } else if requiresReview && commit.reviewSummary == "暂无写后审查结果。" {
            reviewStatus = .blocked
            reviewMessage = "缺少写后审查"
            reviewDetail = "长篇章节必须有可解析的写后审查结果。"
        } else if commit.reviewSummary == "暂无写后审查结果。" {
            reviewStatus = .warning
            reviewMessage = "未记录写后审查"
            reviewDetail = "当前规模允许继续，但建议完成审查后再沉淀记忆。"
        } else {
            reviewStatus = .passed
            reviewMessage = "写后审查通过"
            reviewDetail = commit.reviewSummary
        }

        let fulfillmentStatus: LongformWriteGateStatus
        let fulfillmentMessage: String
        let fulfillmentDetail: String?
        if contract.chapter.requiresMandatoryNodeCoverage == true && !commit.missedNodes.isEmpty {
            fulfillmentStatus = .blocked
            fulfillmentMessage = "本章节点未覆盖"
            fulfillmentDetail = commit.missedNodes.prefix(4).joined(separator: "；")
        } else if !commit.missedNodes.isEmpty {
            fulfillmentStatus = .warning
            fulfillmentMessage = "存在未覆盖节点"
            fulfillmentDetail = commit.missedNodes.prefix(4).joined(separator: "；")
        } else {
            fulfillmentStatus = .passed
            fulfillmentMessage = "本章节点覆盖完成"
            fulfillmentDetail = commit.plannedNodes.isEmpty ? "本章没有明确节点要求。" : "\(commit.coveredNodes.count)/\(commit.plannedNodes.count)"
        }

        let unsettledProjectionItems = commit.projectionStatus
            .filter { _, value in
                !Self.isSettledProjectionStatus(value)
            }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        let projectionStatus: LongformWriteGateStatus
        let projectionMessage: String
        let projectionDetail: String?
        if !unsettledProjectionItems.isEmpty {
            projectionStatus = .blocked
            projectionMessage = "后台投影未完成"
            projectionDetail = unsettledProjectionItems.joined(separator: "；")
        } else {
            projectionStatus = .passed
            projectionMessage = commit.isAccepted ? "后台投影完成" : "拒稿已隔离，投影跳过"
            projectionDetail = commit.projectionStatus
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "；")
        }

        let checks = [
            LongformWriteGateCheck(
                id: stableID(parts: ["gate", commit.id, "prewrite"]),
                stage: .prewrite,
                status: prewriteStatus,
                message: prewriteMessage,
                detail: prewriteDetail
            ),
            LongformWriteGateCheck(
                id: stableID(parts: ["gate", commit.id, "review"]),
                stage: .review,
                status: reviewStatus,
                message: reviewMessage,
                detail: reviewDetail
            ),
            LongformWriteGateCheck(
                id: stableID(parts: ["gate", commit.id, "fulfillment"]),
                stage: .fulfillment,
                status: fulfillmentStatus,
                message: fulfillmentMessage,
                detail: fulfillmentDetail
            ),
            LongformWriteGateCheck(
                id: stableID(parts: ["gate", commit.id, "projection"]),
                stage: .projection,
                status: projectionStatus,
                message: projectionMessage,
                detail: projectionDetail
            )
        ]
        let overallStatus: LongformWriteGateStatus
        if checks.contains(where: { $0.status == .blocked }) {
            overallStatus = .blocked
        } else if checks.contains(where: { $0.status == .warning }) {
            overallStatus = .warning
        } else {
            overallStatus = .passed
        }

        return LongformWriteGateReport(
            id: stableID(parts: ["write_gate", commit.id, overallStatus.rawValue]),
            volumeNumber: commit.volumeNumber,
            chapterNumber: commit.chapterNumber,
            generatedAt: Date(),
            overallStatus: overallStatus,
            checks: checks
        )
    }

    private static func isSettledProjectionStatus(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done", "skipped", "passed", "rejected", "invalidated":
            return true
        default:
            return false
        }
    }

    static func buildRuntimeHealth(for project: NovelProject) -> LongformRuntimeHealthReport {
        let runtime = project.longformRuntimeState
        let prewrite = PrewriteValidator.validate(project: project)
        let memoryBuckets = project.memoryBuckets
        let memoryConflicts = memoryBuckets.conflicts
        let strandWarnings = project.strandWeaveState.checkRedLines(currentChapter: project.currentChapterNumber)
        let qualityTrend = buildQualityTrend(for: project)
        let minimumAcceptedScore = minimumAcceptedScore(for: project.storyLength)
        var issues: [LongformRuntimeHealthIssue] = []

        func appendIssue(
            status: LongformWriteGateStatus,
            title: String,
            detail: String,
            repairHint: String
        ) {
            issues.append(LongformRuntimeHealthIssue(
                id: stableID(parts: ["health", project.id, title, detail]),
                status: status,
                title: title,
                detail: detail,
                repairHint: repairHint
            ))
        }

        if !prewrite.isReady {
            appendIssue(
                status: .blocked,
                title: "写前门禁未通过",
                detail: prewrite.blockingReasons.prefix(3).joined(separator: "；"),
                repairHint: "先补齐大纲、分卷计划、本章目标、记忆或占位符，再生成正文。"
            )
        } else if !prewrite.warnings.isEmpty {
            appendIssue(
                status: .warning,
                title: "写前有提醒",
                detail: prewrite.warnings.prefix(3).joined(separator: "；"),
                repairHint: "生成前尽量处理提醒项，长篇会更稳。"
            )
        }

        if project.storyLength.supportsVolumePlanning && runtime.latestContract == nil {
            appendIssue(
                status: .warning,
                title: "长篇合同尚未落盘",
                detail: "当前项目还没有持久化的后台合同。",
                repairHint: "保存章节或完成一次后台提交后，合同会写入运行态。"
            )
        }

        if let writeGate = runtime.latestWriteGate {
            for check in writeGate.blockingChecks.prefix(3) {
                appendIssue(
                    status: .blocked,
                    title: "\(check.stage.displayName)门禁阻断",
                    detail: [check.message, check.detail].compactMap { $0 }.joined(separator: "："),
                    repairHint: "按门禁提示修复后再推进下一章。"
                )
            }
            for check in writeGate.warningChecks.prefix(2) {
                appendIssue(
                    status: .warning,
                    title: "\(check.stage.displayName)门禁提醒",
                    detail: [check.message, check.detail].compactMap { $0 }.joined(separator: "："),
                    repairHint: "建议处理提醒，避免后续跨章累积问题。"
                )
            }
        } else if project.writtenChapters > 0 {
            appendIssue(
                status: .warning,
                title: "缺少后台门禁记录",
                detail: "已有保存章节，但还没有 write-gate 报告。",
                repairHint: "重新保存当前章或运行一次写后刷新，让后台补齐提交和门禁。"
            )
        }

        if let latestCommit = runtime.latestCommit {
            if latestCommit.status == .rejected {
                let reasons = latestCommit.rejectionReasons ?? []
                appendIssue(
                    status: .blocked,
                    title: "最新章节提交被拒",
                    detail: reasons.prefix(3).joined(separator: "；"),
                    repairHint: "先按修订建议改当前章，不要绕开失败章节继续推进。"
                )
            }
            if latestCommit.volumeNumber > project.currentVolumeNumber
                || (latestCommit.volumeNumber == project.currentVolumeNumber && latestCommit.chapterNumber > project.currentChapterNumber) {
                appendIssue(
                    status: .warning,
                    title: "后台提交领先当前编辑位置",
                    detail: "最新提交是第 \(latestCommit.volumeNumber) 卷第 \(latestCommit.chapterNumber) 章，当前编辑是第 \(project.currentVolumeNumber) 卷第 \(project.currentChapterNumber) 章。",
                    repairHint: "确认是否正在回修旧章节，避免把旧章当成新章继续写。"
                )
            }
        } else if project.writtenChapters > 0 {
            appendIssue(
                status: .warning,
                title: "缺少章节提交链",
                detail: "已有保存章节，但后台没有 latest commit。",
                repairHint: "重新保存最近章节，让后台生成 accepted/rejected commit。"
            )
        }

        if project.storyLength.supportsVolumePlanning {
            let allSavedChapters = savedChapterRuntimeProbes(
                for: project,
                limit: max(project.savedChapterCount, project.chapterDrafts.count, 1)
            )
            let recentSavedChapters = Array(allSavedChapters.prefix(40))
            let acceptedCommitsByPosition = runtime.acceptedCommits.reduce(into: [String: LongformChapterCommit]()) { partial, commit in
                let key = chapterPositionKey(volumeNumber: commit.volumeNumber, chapterNumber: commit.chapterNumber)
                partial[key] = partial[key] ?? commit
            }
            let savedPositions = Set(allSavedChapters.map {
                chapterPositionKey(volumeNumber: $0.volumeNumber, chapterNumber: $0.chapterNumber)
            })
            let missingSavedVolumeLabels = missingSavedVolumeLabels(in: allSavedChapters)
            let missingSavedChapterLabels = missingSavedChapterLabels(in: allSavedChapters)
            let duplicateSavedChapterLabels = duplicateSavedChapterLabels(for: project)
            let uncommittedSavedChapters = allSavedChapters.filter {
                acceptedCommitsByPosition[chapterPositionKey(volumeNumber: $0.volumeNumber, chapterNumber: $0.chapterNumber)] == nil
            }
            let staleCommitChapters = recentSavedChapters.filter { draft in
                guard let loadedDraft = draft.draft else {
                    return false
                }
                guard let commit = acceptedCommitsByPosition[
                    chapterPositionKey(volumeNumber: draft.volumeNumber, chapterNumber: draft.chapterNumber)
                ] else {
                    return false
                }
                return commit.id != expectedCommitID(projectID: project.id, draft: loadedDraft)
            }
            let orphanAcceptedCommits = runtime.acceptedCommits.filter {
                !savedPositions.contains(chapterPositionKey(volumeNumber: $0.volumeNumber, chapterNumber: $0.chapterNumber))
            }
            if !missingSavedVolumeLabels.isEmpty {
                appendIssue(
                    status: .blocked,
                    title: "分卷目录存在断卷",
                    detail: missingSavedVolumeLabels
                        .prefix(4)
                        .joined(separator: "；"),
                    repairHint: "先回到缺失分卷的第 1 章补齐分卷起点，再继续后续卷章。"
                )
            }

            if !missingSavedChapterLabels.isEmpty {
                appendIssue(
                    status: .blocked,
                    title: "章节目录存在断章",
                    detail: missingSavedChapterLabels
                        .prefix(6)
                        .joined(separator: "；"),
                    repairHint: "先补齐或恢复缺失章节，再继续生成后续正文，避免长篇时间线和记忆链跳章。"
                )
            }

            if !duplicateSavedChapterLabels.isEmpty {
                appendIssue(
                    status: .blocked,
                    title: "章节目录存在重复位置",
                    detail: duplicateSavedChapterLabels
                        .prefix(6)
                        .joined(separator: "；"),
                    repairHint: "先合并或删除重复位置的保存章，保证每个卷章只有一个权威正文。"
                )
            }

            if let latestSavedChapter = allSavedChapters.first,
               chapterPositionIsEarlier(
                   volumeNumber: project.currentVolumeNumber,
                   chapterNumber: project.currentChapterNumber,
                   than: latestSavedChapter
               ) {
                appendIssue(
                    status: .warning,
                    title: "当前编辑位置落后于已保存最新章",
                    detail: "已保存最新位置是第 \(latestSavedChapter.volumeNumber) 卷第 \(latestSavedChapter.chapterNumber) 章，当前编辑是第 \(project.currentVolumeNumber) 卷第 \(project.currentChapterNumber) 章。",
                    repairHint: "确认这是回修旧章；若要继续连载，请载入最新章后再进入下一章。"
                )
            }

            if !uncommittedSavedChapters.isEmpty {
                appendIssue(
                    status: .blocked,
                    title: "保存章节未进入提交链",
                    detail: uncommittedSavedChapters
                        .prefix(3)
                        .map(\.chapterSummary)
                        .joined(separator: "；"),
                    repairHint: "回到对应章节重新保存，通过审查后再继续推进后续章节。"
                )
            }

            if !staleCommitChapters.isEmpty {
                appendIssue(
                    status: .blocked,
                    title: "章节内容与提交链不一致",
                    detail: staleCommitChapters
                        .prefix(3)
                        .map(\.chapterSummary)
                        .joined(separator: "；"),
                    repairHint: "这些章节保存后被改动过，请重新保存并通过长篇门禁，让记忆和伏笔按新正文重建。"
                )
            }

            if !orphanAcceptedCommits.isEmpty {
                appendIssue(
                    status: .warning,
                    title: "后台提交缺少对应保存章",
                    detail: orphanAcceptedCommits
                        .prefix(3)
                        .map { "第 \($0.volumeNumber) 卷第 \($0.chapterNumber) 章" }
                        .joined(separator: "；"),
                    repairHint: "确认是否删除或迁移过章节；必要时重新保存最新章节以刷新后台提交链。"
                )
            }
        }

        if !memoryConflicts.isEmpty {
            appendIssue(
                status: .blocked,
                title: "结构化记忆存在冲突",
                detail: memoryConflicts.prefix(3).map { "\($0.category.displayName)：\($0.key)" }.joined(separator: "；"),
                repairHint: "先整理冲突记忆，避免模型同时拿到多个互斥状态。"
            )
        }

        if project.storyLength.supportsVolumePlanning && project.writtenChapters >= 3 && memoryBuckets.allActiveItems.isEmpty {
            appendIssue(
                status: .blocked,
                title: "长篇记忆为空",
                detail: "已写 3 章以上，但结构化长期记忆仍为空。",
                repairHint: "刷新全局记忆或重新保存章节，让角色状态、伏笔和时间线进入记忆桶。"
            )
        }

        if project.storyLength.supportsThreadTracking
            && project.plotThreadList.activeThreads.isEmpty
            && !project.hasActiveThreadsNotes {
            appendIssue(
                status: .warning,
                title: "在途线索不足",
                detail: "尚未维护结构化叙事线或在途线索文本。",
                repairHint: "补齐主线、支线、伏笔线和近期回收线。"
            )
        }

        for warning in strandWarnings.prefix(3) {
            appendIssue(
                status: warning.isCritical ? .blocked : .warning,
                title: "Strand 节奏告警",
                detail: warning.message,
                repairHint: "下一章按提示补充对应线索，避免长篇节奏单调或断档。"
            )
        }

        if project.storyLength.supportsVolumePlanning, qualityTrend.hasSignals {
            if let averageScore = qualityTrend.averageScore,
               averageScore < minimumAcceptedScore || qualityTrend.lowScoreCount >= 2 {
                let scoreText = qualityTrend.recentScores
                    .prefix(5)
                    .map(String.init)
                    .joined(separator: " / ")
                appendIssue(
                    status: .warning,
                    title: "近期质量趋势偏低",
                    detail: "最近均分 \(averageScore)/100，最低通过线 \(minimumAcceptedScore)/100；近期分数：\(scoreText)",
                    repairHint: "下一次生成前先处理趋势里的高优先级问题，避免低分模式继续滚到后续章节。"
                )
            }

            let recurringDimensions = qualityTrend.recurringDimensions
                .filter { $0.count >= 2 }
                .prefix(4)
            if !recurringDimensions.isEmpty {
                let dimensionText = recurringDimensions
                    .map { "\($0.dimension.displayName)×\($0.count)" }
                    .joined(separator: "；")
                let issueText = qualityTrend.priorityIssues
                    .prefix(2)
                    .joined(separator: "；")
                let detail = issueText.isEmpty
                    ? dimensionText
                    : "\(dimensionText)：\(issueText)"
                appendIssue(
                    status: .warning,
                    title: "审查维度反复失分",
                    detail: detail,
                    repairHint: "本章生成时主动补足这些维度，不要等保存审查后再返修。"
                )
            }
        }

        let overallStatus: LongformWriteGateStatus
        if issues.contains(where: { $0.status == .blocked }) {
            overallStatus = .blocked
        } else if issues.contains(where: { $0.status == .warning }) {
            overallStatus = .warning
        } else {
            overallStatus = .passed
        }

        var metrics = [
            "accepted": "\(runtime.acceptedCommits.count)",
            "rejected": "\(runtime.rejectedCommits.count)",
            "memory": "\(memoryBuckets.allActiveItems.count)",
            "saved": "\(project.savedChapterCount)",
            "threads": "\(project.plotThreadList.activeCount)",
            "strand": "\(project.strandWeaveState.entries.count)"
        ]
        if project.storyLength.supportsVolumePlanning {
            let allSavedChapters = savedChapterRuntimeProbes(
                for: project,
                limit: max(project.savedChapterCount, project.chapterDrafts.count, 1)
            )
            let missingSavedVolumes = missingSavedVolumeLabels(in: allSavedChapters)
            if !missingSavedVolumes.isEmpty {
                metrics["missingVolumes"] = "\(missingSavedVolumes.count)"
            }
            if !project.missingChapterNumbers.isEmpty {
                metrics["missingChapters"] = "\(project.missingChapterNumbers.count)"
            }
            if !project.duplicateChapterNumbers.isEmpty {
                metrics["duplicateChapters"] = "\(project.duplicateChapterNumbers.count)"
            }
        }
        if let averageScore = qualityTrend.averageScore {
            metrics["quality"] = "\(averageScore)/\(minimumAcceptedScore)"
        }
        if qualityTrend.lowScoreCount > 0 {
            metrics["lowScore"] = "\(qualityTrend.lowScoreCount)"
        }

        return LongformRuntimeHealthReport(
            id: stableID(parts: ["runtime_health", project.id, String(project.currentVolumeNumber), String(project.currentChapterNumber), overallStatus.rawValue]),
            volumeNumber: max(project.currentVolumeNumber, 1),
            chapterNumber: max(project.currentChapterNumber, 1),
            generatedAt: Date(),
            status: overallStatus,
            issues: issues,
            metrics: metrics
        )
    }

    static func buildQualityTrend(for project: NovelProject) -> LongformQualityTrend {
        var reviewResults: [ChapterReviewResult] = []
        var seenReviewKeys = Set<String>()
        let minimumAcceptedScore = minimumAcceptedScore(for: project.storyLength)

        func appendReview(_ review: ChapterReviewResult?) {
            guard let review else { return }
            let key = [
                String(review.overallScore),
                review.overallSummary,
                review.issues.map(\.description).joined(separator: "|")
            ].joined(separator: "::")
            guard !seenReviewKeys.contains(key) else { return }
            seenReviewKeys.insert(key)
            reviewResults.append(review)
        }

        appendReview(project.lastReviewResult)
        for report in project.qualityReviewReports
            .sorted(by: { $0.reviewedAt > $1.reviewedAt })
            .prefix(8) {
            appendReview(report.unifiedResult)
        }

        let runtime = project.longformRuntimeState
        let commitScores = (runtime.acceptedCommits + runtime.rejectedCommits)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .compactMap { score(fromReviewSummary: $0.reviewSummary) }

        let reviewScores = reviewResults.map(\.overallScore)
        let recentScores = Array((reviewScores + commitScores).prefix(8))

        var dimensionCounts: [ReviewDimension: Int] = [:]
        var qualityDebtTargets: [String] = []
        var priorityIssues: [String] = []
        for review in reviewResults.prefix(8) {
            for issue in review.issues where issue.isBlocking || issue.severity == .high {
                dimensionCounts[issue.dimension, default: 0] += 1
                let fixHint = issue.fixHint.trimmingCharacters(in: .whitespacesAndNewlines)
                let description = issue.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = fixHint.isEmpty ? description : fixHint
                if !detail.isEmpty {
                    priorityIssues.append("[\(issue.dimension.displayName)] \(detail)")
                }
            }

            if review.overallScore < minimumAcceptedScore || review.dimensionScores.values.contains(where: { $0 <= 6 }) {
                let weakDimensions = review.dimensionScores
                    .filter { $0.value <= 7 }
                    .sorted {
                        if $0.value == $1.value {
                            return $0.key.displayName < $1.key.displayName
                        }
                        return $0.value < $1.value
                    }
                    .prefix(3)
                    .map { "\($0.key.displayName)\($0.value)/10" }
                    .joined(separator: "、")
                let issueHints = review.issues
                    .filter { $0.severity == .critical || $0.severity == .high || $0.severity == .medium }
                    .prefix(3)
                    .compactMap { issue -> String? in
                        let fixHint = issue.fixHint.trimmingCharacters(in: .whitespacesAndNewlines)
                        let description = issue.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        let detail = fixHint.isEmpty ? description : fixHint
                        guard !detail.isEmpty else { return nil }
                        return "[\(issue.dimension.displayName)] \(detail)"
                    }
                    .joined(separator: "；")
                let summary = review.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                let debtParts = [
                    review.overallScore < minimumAcceptedScore ? "审查 \(review.overallScore)/100 低于最低线 \(minimumAcceptedScore)" : nil,
                    weakDimensions.isEmpty ? nil : "薄弱维度 \(weakDimensions)",
                    issueHints.isEmpty ? nil : issueHints,
                    summary.isEmpty ? nil : summary
                ].compactMap { $0 }
                if !debtParts.isEmpty {
                    qualityDebtTargets.append(debtParts.prefix(3).joined(separator: "，"))
                }
            }
        }

        let recurringDimensions = dimensionCounts
            .map { (dimension: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.dimension.displayName < $1.dimension.displayName
                }
                return $0.count > $1.count
            }

        let revisionHints = (runtime.rejectedCommits + (runtime.latestCommit.map { [$0] } ?? []))
            .filter { !$0.isAccepted }
            .sorted { $0.createdAt > $1.createdAt }
            .flatMap { commit in
                (commit.revisionHints ?? commit.rejectionReasons ?? [])
                    .map { hint in
                        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedHint.isEmpty else { return "" }
                        return "第 \(commit.volumeNumber) 卷第 \(commit.chapterNumber) 章：\(trimmedHint)"
                    }
            }

        let reviewAntiPatterns = reviewResults.flatMap(\.antiPatterns)
        let antiPatterns = uniqueOrderedStrings(project.accumulatedAntiPatterns + reviewAntiPatterns, limit: 12)

        return LongformQualityTrend(
            recentScores: recentScores,
            minimumAcceptedScore: minimumAcceptedScore,
            recurringDimensions: Array(recurringDimensions.prefix(6)),
            qualityDebtTargets: uniqueOrderedStrings(qualityDebtTargets, limit: 6),
            priorityIssues: uniqueOrderedStrings(priorityIssues, limit: 8),
            antiPatterns: antiPatterns,
            revisionHints: uniqueOrderedStrings(revisionHints, limit: 8)
        )
    }

    static func buildNextChapterBrief(for project: NovelProject) -> LongformNextChapterBrief {
        let chapterGoal = firstUsefulText([project.chapterFocus, project.currentChapterSummary])
        let chapterNodePlan = chapterRelevantLines(
            from: [project.outlineText, project.structureNotes],
            volume: project.currentVolumeNumber,
            chapter: project.currentChapterNumber,
            fallback: chapterGoal
        )
        let memoryItems = project.memoryBuckets.relevantActiveItems(
            for: [chapterGoal, project.draftText, project.outlineText, project.structureNotes].joined(separator: " "),
            limit: 12
        )
        let memoryContinuities = memoryItems.map {
            "[\($0.category.displayName)] \($0.subject) / \($0.field)：\($0.value)"
        }
        let qualityTrend = buildQualityTrend(for: project)
        let health = buildRuntimeHealth(for: project)
        let healthRepairTasks = health.issues
            .filter { $0.title != "长篇合同尚未落盘" }
            .map { "\($0.title)：\($0.repairHint)" }
        let healthRisks = health.issues
            .filter { $0.status != .passed && $0.title != "长篇合同尚未落盘" }
            .map { "\($0.title)：\($0.detail)" }

        return LongformNextChapterBrief(
            chapterGoal: chapterGoal,
            mandatoryContinuities: uniqueOrderedStrings(chapterNodePlan.lines + memoryContinuities, limit: 8),
            foreshadowingPromises: uniqueOrderedStrings(activeForeshadowingLines(for: project), limit: 8),
            forbiddenContradictions: uniqueOrderedStrings(forbiddenZones(for: project), limit: 8),
            qualityDebts: uniqueOrderedStrings(
                qualityTrend.qualityDebtTargets + qualityTrend.priorityIssues,
                limit: 8
            ),
            repairTasks: uniqueOrderedStrings(
                qualityTrend.revisionHints + healthRepairTasks,
                limit: 8
            ),
            risks: uniqueOrderedStrings(
                genreRisks(for: project) + qualityTrend.antiPatterns + healthRisks,
                limit: 10
            )
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
            var buckets = project.memoryBuckets
            buckets.removeItems(
                sourceVolumeNumber: commit.volumeNumber,
                sourceChapter: commit.chapterNumber
            )
            project.memoryBuckets = buckets
            removeChapterProjections(
                volumeNumber: commit.volumeNumber,
                chapterNumber: commit.chapterNumber,
                from: &project
            )
            updatedCommit.projectionStatus["memory"] = "invalidated"
            updatedCommit.projectionStatus["foreshadowing"] = "invalidated"
            updatedCommit.projectionStatus["threads"] = "invalidated"
            updatedCommit.projectionStatus["strands"] = "invalidated"
            updatedCommit.projectionStatus["runtime"] = "done"
            updatedCommit.projectionStatus["quality_gate"] = "rejected"
            runtime.record(commit: updatedCommit)
            runtime.record(writeGate: buildWriteGateReport(commit: updatedCommit, contract: contract))
            project.longformRuntimeState = runtime
            return
        }

        var buckets = project.memoryBuckets
        buckets.removeItems(
            sourceVolumeNumber: commit.volumeNumber,
            sourceChapter: commit.chapterNumber
        )
        removeChapterProjections(
            volumeNumber: commit.volumeNumber,
            chapterNumber: commit.chapterNumber,
            from: &project
        )
        for item in commit.extractedMemoryItems {
            buckets.upsert(item)
        }
        buckets.compact(currentVolumeNumber: commit.volumeNumber, currentChapter: commit.chapterNumber)
        project.memoryBuckets = buckets
        updatedCommit.projectionStatus["memory"] = "done"

        applyForeshadowing(from: commit, to: &project)
        updatedCommit.projectionStatus["foreshadowing"] = "done"

        applyThreadProgress(from: commit, to: &project)
        updatedCommit.projectionStatus["threads"] = "done"

        var strandState = project.strandWeaveState
        strandState.recordChapter(
            commit.chapterNumber,
            volumeNumber: commit.volumeNumber,
            dominant: strandType(for: commit.dominantThreadType)
        )
        project.strandWeaveState = strandState
        updatedCommit.projectionStatus["strands"] = "done"

        updatedCommit.projectionStatus["runtime"] = "done"
        updatedCommit.projectionStatus["quality_gate"] = "passed"
        runtime.record(commit: updatedCommit)
        runtime.record(writeGate: buildWriteGateReport(commit: updatedCommit, contract: contract))
        project.longformRuntimeState = runtime
    }

    private static func removeChapterProjections(
        volumeNumber: Int,
        chapterNumber: Int,
        from project: inout NovelProject
    ) {
        let normalizedVolume = max(volumeNumber, 1)
        let normalizedChapter = max(chapterNumber, 1)
        project.foreshadowList.removeLongformProjection(
            volumeNumber: normalizedVolume,
            chapterNumber: normalizedChapter
        )
        project.plotThreadList.removeLongformProjection(
            volumeNumber: normalizedVolume,
            chapterNumber: normalizedChapter
        )
        var strandState = project.strandWeaveState
        strandState.removeChapter(normalizedChapter, volumeNumber: normalizedVolume)
        project.strandWeaveState = strandState
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

        写后门禁：
        - 当前规模最低审查通过线：\(contract.review.minimumAcceptedScore)/100。
        \(contract.review.requiresPostwriteReview == true ? "- 长篇章节必须通过写后质量审查后才会写入长期记忆、伏笔和叙事线。" : "- 当前规模允许轻量本地提交，但仍应尽量完成写后审查。")
        """)

        let qualityTrend = buildQualityTrend(for: project)
        if qualityTrend.hasSignals {
            sections.append("""
            【近期质量趋势】
            \(qualityTrend.formattedForPrompt)

            写作要求：
            - 本次正文必须主动避开最近反复失分的问题，不能只在审查后再补救。
            - 若趋势里出现修订债，优先在当前章可修复范围内补齐，不要把问题推给下一章。
            """)
        }

        if prewrite.isBlocked || !prewrite.warnings.isEmpty || !prewrite.memoryConflicts.isEmpty {
            let reasons = prewrite.blockingReasons + prewrite.memoryConflicts + prewrite.warnings
            sections.append("""
            【写前预警】
            \(formatList(reasons, fallback: "无。"))
            """)
        }

        let health = buildRuntimeHealth(for: project)
        let healthIssues = health.issues
            .filter { $0.title != "长篇合同尚未落盘" }
            .prefix(4)
        if !healthIssues.isEmpty {
            let healthLines = healthIssues.map { issue in
                "- [\(issue.status.displayName)] \(issue.title)：\(issue.detail)\n  修复方向：\(issue.repairHint)"
            }
            sections.append("""
            【后台健康诊断】
            当前状态：\(health.summary)
            下一步：\(healthIssues.first?.repairHint ?? health.nextAction)

            \(healthLines.isEmpty ? "- 暂无额外诊断项。" : healthLines.joined(separator: "\n"))
            """)
        }

        if let rejectedCommit = rejectedCommitForCurrentChapter(project: project, contract: contract) {
            let reasons = formatList(
                rejectedCommit.rejectionReasons ?? [],
                fallback: "上一版未通过长篇后台，请先修订后再推进。"
            )
            let hints = formatList(
                rejectedCommit.revisionHints ?? [],
                fallback: "优先补齐漏写节点、修复审查阻断问题，并保持当前章节目标不变。"
            )
            sections.append("""
            【本章修订反馈】
            上一版第 \(rejectedCommit.volumeNumber) 卷 · 第 \(rejectedCommit.chapterNumber) 章未通过，重写时必须先解决这些问题，不要绕开当前章节继续推进。

            未通过原因：
            \(reasons)

            修订重点：
            \(hints)
            """)
        }

        sections.append("""
        【写作输出】
        直接续写正文。不要解释合同，不要列提纲，不要替读者总结设定。每次至少推进一个情节拍点、关系变化、信息增量或伏笔状态。
        """)

        return sections.joined(separator: "\n\n")
    }

    private static func rejectedCommitForCurrentChapter(
        project: NovelProject,
        contract: LongformStoryContractBundle
    ) -> LongformChapterCommit? {
        let chapter = contract.chapter
        let runtime = project.longformRuntimeState
        if let latest = runtime.latestCommit,
           latest.status == .rejected,
           latest.volumeNumber == contract.volume.volumeNumber,
           latest.chapterNumber == chapter.chapterNumber {
            return latest
        }
        return runtime.rejectedCommits.first { commit in
            commit.status == .rejected
                && commit.volumeNumber == contract.volume.volumeNumber
                && commit.chapterNumber == chapter.chapterNumber
        }
    }

    private static func applyForeshadowing(from commit: LongformChapterCommit, to project: inout NovelProject) {
        let projectionMarker = "longform:auto:v\(max(commit.volumeNumber, 1)):c\(max(commit.chapterNumber, 1))"
        for item in commit.extractedMemoryItems where item.category == .openLoop || item.category == .readerPromise {
            let title = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let isResolved = title.contains("已回收")
                || title.contains("已解决")
                || title.contains("已完成")
                || title.contains("已兑现")
                || title.contains("兑现")
                || title.localizedCaseInsensitiveContains("resolved")
                || title.localizedCaseInsensitiveContains("paid_off")

            if isResolved {
                let resolutionKeys = [title, item.subject, item.field]
                    .map { normalizedForeshadowKey($0, removingResolutionMarkers: true) }
                    .filter { !$0.isEmpty }
                if let existingIndex = project.foreshadowList.entries.firstIndex(where: {
                    resolutionKeys.contains(normalizedForeshadowKey($0.title))
                }) {
                    let existing = project.foreshadowList.entries[existingIndex]
                    project.foreshadowList.resolveForeshadow(id: existing.id, at: commit.chapterNumber)
                    if let resolvedIndex = project.foreshadowList.entries.firstIndex(where: { $0.id == existing.id }) {
                        let existingNotes = project.foreshadowList.entries[resolvedIndex].notes
                        project.foreshadowList.entries[resolvedIndex].notes = [existingNotes, projectionMarker]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                    }
                }
                continue
            }

            let normalizedTitle = normalizedForeshadowKey(title)
            if project.foreshadowList.entries.contains(where: { normalizedForeshadowKey($0.title) == normalizedTitle }) {
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
                    notes: "由后台章节提交自动识别\n\(projectionMarker)"
                )
            )
        }
        project.foreshadowList.pruneResolved()
    }

    private static func normalizedForeshadowKey(
        _ value: String,
        removingResolutionMarkers: Bool = false
    ) -> String {
        var normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if removingResolutionMarkers {
            for marker in ["已回收", "已解决", "已完成", "已兑现", "兑现", "resolved", "paid_off", "closed", "done"] {
                normalized = normalized.replacingOccurrences(of: marker, with: "")
            }
        }
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return normalized
            .unicodeScalars
            .filter { !separators.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func applyThreadProgress(from commit: LongformChapterCommit, to project: inout NovelProject) {
        let threadType = commit.dominantThreadType
        let event = ThreadEvent(
            volumeNumber: commit.volumeNumber,
            chapter: commit.chapterNumber,
            title: commit.chapterTitle,
            description: commit.extractedMemoryItems
                .filter { $0.category == .storyFact || $0.category == .timeline }
                .prefix(3)
                .map(\.value)
                .joined(separator: "；"),
            eventType: .development,
            source: "longform"
        )

        if let existing = project.plotThreadList.threads.first(where: { $0.threadType == threadType && $0.isActive }) {
            project.plotThreadList.addEventToThread(
                threadID: existing.id,
                event: event,
                volumeNumber: commit.volumeNumber
            )
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
        volume: Int,
        chapter: Int,
        fallback: String
    ) -> (lines: [String], requiresCoverage: Bool) {
        let lines = texts
            .flatMap { $0.nonEmptyLines(limit: 240) }
            .filter { line in
                lineReferencesChapter(line, volume: max(volume, 1), chapter: max(chapter, 1))
            }
            .map { $0.cleanedListLine }
            .deduplicatedPreservingOrder()
        if !lines.isEmpty {
            return (Array(lines.prefix(10)), true)
        }
        let fallbackLine = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackLine.isEmpty else {
            return ([], false)
        }
        return ([fallbackLine], fallbackLine != "继续补齐当前章节的目标、冲突和场景节奏。")
    }

    private static func lineReferencesChapter(_ line: String, volume: Int, chapter: Int) -> Bool {
        let normalizedLine = line.cleanedListLine
        guard !normalizedLine.isEmpty else { return false }

        let volumeAlternatives = regexAlternation(for: numberMarkers(for: volume))
        let chapterAlternatives = regexAlternation(for: numberMarkers(for: chapter))
        let anyVolumePattern = "第\\s*(?:[0-9]+|[一二三四五六七八九十百千万零〇两]+)\\s*卷"
        let lineHasVolumeMarker = normalizedLine.range(of: anyVolumePattern, options: .regularExpression) != nil
        let explicitChapterPatterns = lineHasVolumeMarker
            ? ["第\\s*(?:\(volumeAlternatives))\\s*卷.*第\\s*(?:\(chapterAlternatives))\\s*章"]
            : [
                "第\\s*(?:\(chapterAlternatives))\\s*章",
                "^\\s*\(chapter)\\s*[\\.、）\\)]"
            ]
        return explicitChapterPatterns.contains { pattern in
            normalizedLine.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func numberMarkers(for number: Int) -> [String] {
        let safeNumber = max(number, 1)
        var markers = [String(safeNumber)]
        if let chinese = chineseNumeral(for: safeNumber) {
            markers.append(chinese)
        }
        return markers
    }

    private static func regexAlternation(for values: [String]) -> String {
        values
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }

    private static func chineseNumeral(for number: Int) -> String? {
        guard number > 0, number <= 999 else { return nil }
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if number < 10 {
            return digits[number]
        }
        if number < 100 {
            let tens = number / 10
            let ones = number % 10
            let prefix = tens == 1 ? "十" : "\(digits[tens])十"
            return ones == 0 ? prefix : "\(prefix)\(digits[ones])"
        }

        let hundreds = number / 100
        let remainder = number % 100
        let prefix = "\(digits[hundreds])百"
        guard remainder > 0 else { return prefix }
        if remainder < 10 {
            return "\(prefix)零\(digits[remainder])"
        }
        return "\(prefix)\(chineseNumeral(for: remainder) ?? "")"
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
        let subject = node.coverageSubject
        guard subject.count >= 2 else { return false }

        let keyPhrase = node.keyPhraseForMatching
        let actionCues = node.coverageActionCues
        let hasRequiredActionCue = actionCues.isEmpty || actionCues.contains {
            content.localizedCaseInsensitiveContains($0)
        }

        if keyPhrase.count >= 4,
           content.localizedCaseInsensitiveContains(keyPhrase),
           hasRequiredActionCue {
            return true
        }

        let tokens = node.coverageTokens
        guard !tokens.isEmpty else { return false }
        let hitCount = tokens.filter { content.localizedCaseInsensitiveContains($0) }.count
        let requiredHits: Int
        switch tokens.count {
        case 0:
            requiredHits = 0
        case 1:
            requiredHits = 1
        case 2:
            requiredHits = 2
        default:
            requiredHits = min(3, tokens.count)
        }
        return hitCount >= requiredHits && hasRequiredActionCue
    }

    private static func formatList(_ items: [String], fallback: String) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "- \(fallback)" }
        return cleaned.prefix(16).map { "- \($0)" }.joined(separator: "\n")
    }

    private static func uniqueOrderedStrings(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var results: [String] = []
        for value in values {
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedValue.isEmpty, !seen.contains(normalizedValue) else {
                continue
            }
            seen.insert(normalizedValue)
            results.append(normalizedValue)
            if results.count >= limit {
                break
            }
        }
        return results
    }

    private static func score(fromReviewSummary summary: String) -> Int? {
        let pattern = #"(\d{1,3})\s*/\s*100"#
        let nsSummary = summary as NSString
        let fullRange = NSRange(location: 0, length: nsSummary.length)
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: summary, range: fullRange),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let value = nsSummary.substring(with: match.range(at: 1))
        guard let score = Int(value) else { return nil }
        return min(max(score, 0), 100)
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
        switch StrandKeywordClassifier.dominantStrand(in: text, fallback: fallback) {
        case .fire:
            return .fire
        case .constellation:
            return .constellation
        case .quest:
            return .quest
        }
    }

    private static func buildRevisionHints(
        review: ChapterReviewResult?,
        reviewFailureReason: String?,
        missedNodes: [String],
        contract: LongformStoryContractBundle
    ) -> [String] {
        var hints: [String] = []

        if contract.prewrite.isBlocked {
            let prewriteHints = (contract.prewrite.blockingReasons + contract.prewrite.memoryConflicts)
                .prefix(3)
                .map { "先补齐写前合同：\($0)" }
            hints.append(contentsOf: prewriteHints)
        }

        if let reviewFailureReason {
            hints.append("重新运行当前章审查，确认模型返回可解析结果：\(reviewFailureReason)")
        } else if contract.review.requiresPostwriteReview == true && review == nil {
            hints.append("先完成当前章写后质量审查；审查通过后再写入长期记忆、伏笔和叙事线。")
        }

        if !missedNodes.isEmpty {
            hints.append("补写本章明确节点：\(missedNodes.prefix(3).joined(separator: "；"))")
        }

        if let review {
            let priorityIssues = (review.blockingIssues + review.nonBlockingIssues.filter { $0.severity == .high })
                .prefix(4)
            for issue in priorityIssues {
                let fixText = issue.fixHint.trimmingCharacters(in: .whitespacesAndNewlines)
                let description = issue.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fixText.isEmpty {
                    hints.append("[\(issue.dimension.displayName)] \(fixText)")
                } else if !description.isEmpty {
                    hints.append("[\(issue.dimension.displayName)] 修正：\(description)")
                }
            }

            if review.overallScore < contract.review.minimumAcceptedScore {
                hints.append("先处理严重和高优先级问题，把审查分数提高到 \(contract.review.minimumAcceptedScore) 分以上。")
            }
        }

        var seen = Set<String>()
        return hints.filter { hint in
            let normalizedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedHint.isEmpty, !seen.contains(normalizedHint) else {
                return false
            }
            seen.insert(normalizedHint)
            return true
        }
    }

    private static func strandType(for threadType: ThreadType) -> StrandType {
        switch threadType {
        case .fire:
            return .fire
        case .constellation:
            return .constellation
        case .quest, .subplot, .character:
            return .quest
        }
    }

    private static func chapterPositionKey(volumeNumber: Int, chapterNumber: Int) -> String {
        "v\(max(volumeNumber, 1)):c\(max(chapterNumber, 1))"
    }

    private static func missingSavedVolumeLabels(in probes: [SavedChapterRuntimeProbe]) -> [String] {
        let volumeNumbers = Set(probes.map(\.volumeNumber))
        guard let highestVolume = volumeNumbers.max(), highestVolume > 1 else { return [] }
        return (1...highestVolume)
            .filter { !volumeNumbers.contains($0) }
            .map { "第 \($0) 卷" }
    }

    private static func missingSavedChapterLabels(in probes: [SavedChapterRuntimeProbe]) -> [String] {
        let chaptersByVolume = Dictionary(grouping: probes, by: \.volumeNumber)
        return chaptersByVolume.keys.sorted().flatMap { volumeNumber -> [String] in
            let chapterNumbers = Set(chaptersByVolume[volumeNumber, default: []].map(\.chapterNumber))
            guard let highestChapter = chapterNumbers.max(), highestChapter > 1 else { return [] }
            return (1...highestChapter)
                .filter { !chapterNumbers.contains($0) }
                .map { "第 \(volumeNumber) 卷第 \($0) 章" }
        }
    }

    private static func duplicateSavedChapterLabels(for project: NovelProject) -> [String] {
        let grouped = Dictionary(grouping: project.sortedChapterCatalog) { metadata in
            chapterPositionKey(volumeNumber: metadata.volumeNumber, chapterNumber: metadata.chapterNumber)
        }
        return grouped.values
            .filter { $0.count > 1 }
            .compactMap { metadataGroup in
                guard let metadata = metadataGroup.first else { return nil }
                return "第 \(metadata.volumeNumber) 卷第 \(metadata.chapterNumber) 章×\(metadataGroup.count)"
            }
            .sorted()
    }

    private static func chapterPositionIsEarlier(
        volumeNumber: Int,
        chapterNumber: Int,
        than savedChapter: SavedChapterRuntimeProbe
    ) -> Bool {
        let currentVolume = max(volumeNumber, 1)
        let currentChapter = max(chapterNumber, 1)
        if currentVolume != savedChapter.volumeNumber {
            return currentVolume < savedChapter.volumeNumber
        }
        return currentChapter < savedChapter.chapterNumber
    }

    private static func savedChapterRuntimeProbes(
        for project: NovelProject,
        limit: Int
    ) -> [SavedChapterRuntimeProbe] {
        let loadedDraftsByID = project.chapterDrafts.reduce(into: [ChapterDraft.ID: ChapterDraft]()) { partial, draft in
            partial[draft.id] = draft
        }
        var probesByPosition: [String: SavedChapterRuntimeProbe] = [:]

        func upsert(_ probe: SavedChapterRuntimeProbe) {
            let key = chapterPositionKey(volumeNumber: probe.volumeNumber, chapterNumber: probe.chapterNumber)
            guard let existing = probesByPosition[key] else {
                probesByPosition[key] = probe
                return
            }

            if existing.draft == nil && probe.draft != nil {
                probesByPosition[key] = probe
                return
            }
            if existing.draft != nil && probe.draft == nil {
                return
            }
            if probe.savedAtDate > existing.savedAtDate {
                probesByPosition[key] = probe
            }
        }

        for metadata in project.sortedChapterCatalog {
            upsert(SavedChapterRuntimeProbe(
                metadata: metadata,
                draft: loadedDraftsByID[metadata.id]
            ))
        }

        for draft in project.sortedChapterDrafts {
            upsert(SavedChapterRuntimeProbe(draft: draft))
        }

        return Array(probesByPosition.values)
            .sorted(by: SavedChapterRuntimeProbe.sortDescending)
            .prefix(limit)
            .map { $0 }
    }

    private static func expectedCommitID(projectID: String, draft: ChapterDraft) -> String {
        stableID(parts: [
            "commit",
            projectID,
            String(max(draft.volumeNumber, 1)),
            String(draft.chapterNumber),
            draft.content
        ])
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

    var longformRuntimeHealth: LongformRuntimeHealthReport {
        LongformStorySystem.buildRuntimeHealth(for: self)
    }

    var longformQualityTrend: LongformQualityTrend {
        LongformStorySystem.buildQualityTrend(for: self)
    }

    var longformNextChapterBrief: LongformNextChapterBrief {
        LongformStorySystem.buildNextChapterBrief(for: self)
    }
}

private extension String {
    var cleanedListLine: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t"))
    }

    var keyPhraseForMatching: String {
        let cleaned = coverageSubject
        let separators = CharacterSet(charactersIn: "：:，,。.;；、-")
        return cleaned
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 2 }
            ?? cleaned
    }

    var coverageTokens: [String] {
        let separators = CharacterSet(charactersIn: "：:，,。.;；、-—（）()[]【】《》\"“”‘’ \t")
        let rawTokens = coverageSubject.components(separatedBy: separators)
        let trimmedTokens = rawTokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let ignoredTokens = Set(["第", "卷", "章", "本章", "章节", "目标", "推进", "节点", "必须", "场景", "角色", "伏笔"])
        let meaningfulTokens = trimmedTokens.filter { token in
            token.count >= 2 && !ignoredTokens.contains(token)
        }
        return meaningfulTokens.prefix(8).map { String($0) }
    }

    var coverageActionCues: [String] {
        let subject = coverageSubject
        let cues = [
            "发现", "确认", "揭示", "暴露", "决定", "选择", "进入", "到达", "离开", "追查",
            "追", "查", "询问", "回答", "承认", "拒绝", "接受", "交出", "获得", "失去",
            "打开", "关闭", "救", "杀", "击败", "打败", "受伤", "死亡", "背叛", "结盟",
            "冲突", "对峙", "回收", "兑现", "种下", "埋下", "推进", "转变", "变化", "意识到",
            "记起", "恢复", "升级", "突破", "失败", "成功"
        ]
        return cues.filter { subject.contains($0) }
    }

    var coverageSubject: String {
        var value = cleanedListLine
        let numberPattern = "(?:[0-9]+|[一二三四五六七八九十百千万零〇两]+)"
        let leadingPatterns = [
            "^第\\s*\(numberPattern)\\s*卷\\s*[·•\\-—:：、\\s]*第\\s*\(numberPattern)\\s*章\\s*[：:、\\-—\\.）\\)]*",
            "^第\\s*\(numberPattern)\\s*章\\s*[：:、\\-—\\.）\\)]*",
            "^[0-9]+\\s*[\\.、）\\)]\\s*"
        ]
        for pattern in leadingPatterns {
            if let range = value.range(of: pattern, options: .regularExpression) {
                value.removeSubrange(range)
                break
            }
        }
        let labelPatterns = [
            "^(?:章节节点|场景推进|角色弧线|伏笔回收|本章必须执行|本章目标)\\s*[：:、\\-—]*"
        ]
        for pattern in labelPatterns {
            if let range = value.range(of: pattern, options: .regularExpression) {
                value.removeSubrange(range)
                break
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func nonEmptyLines(limit: Int) -> [String] {
        components(separatedBy: .newlines)
            .map { $0.cleanedListLine }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { String($0) }
    }
}

private extension Array where Element == String {
    func deduplicatedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { value in
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedValue.isEmpty, !seen.contains(normalizedValue) else {
                return false
            }
            seen.insert(normalizedValue)
            return true
        }
    }
}
