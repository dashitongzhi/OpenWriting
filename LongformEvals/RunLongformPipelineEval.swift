import Foundation

private let supportedChapterCounts: Set<Int> = [10, 30, 80]

@main
struct LongformPipelineEvalCLI {
    static func main() async {
        do {
            let options = try EvalOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            guard options.mode == "local" || options.mode == "real" else {
                throw EvalError.message("RunLongformPipelineEval only supports --mode local or --mode real.")
            }
            guard supportedChapterCounts.contains(options.chapters) else {
                throw EvalError.message("--chapters must be one of 10, 30, or 80")
            }

            let seeds = try JSONDecoder().decode([EvalSeed].self, from: Data(contentsOf: options.seedsURL))
            guard !seeds.isEmpty else {
                throw EvalError.message("No eval seeds found at \(options.seedsURL.path)")
            }

            let runner = try LongformPipelineRunner(seeds: seeds, options: options)
            try await runner.run()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            fputs("error: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct EvalOptions {
    var chapters: Int = 30
    var mode: String = "local"
    var seedsURL = URL(fileURLWithPath: "LongformEvals/seeds.json")
    var outputURL = URL(fileURLWithPath: "LongformEvals/runs")

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--chapters":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]) else {
                    throw EvalError.message("--chapters requires an integer value")
                }
                chapters = value
                index += 2
            case "--mode":
                guard index + 1 < arguments.count else {
                    throw EvalError.message("--mode requires a value")
                }
                mode = arguments[index + 1]
                index += 2
            case "--seeds":
                guard index + 1 < arguments.count else {
                    throw EvalError.message("--seeds requires a path")
                }
                seedsURL = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--output":
                guard index + 1 < arguments.count else {
                    throw EvalError.message("--output requires a path")
                }
                outputURL = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            default:
                throw EvalError.message("unknown argument \(arguments[index])")
            }
        }
    }
}

private struct EvalSeed: Decodable {
    let id: String
    let genre: String
    let world: String
    let protagonist: String
    let coreConflict: String
    let longForeshadowing: String
    let chapterGoal: String

    enum CodingKeys: String, CodingKey {
        case id
        case genre
        case world
        case protagonist
        case coreConflict = "core_conflict"
        case longForeshadowing = "long_foreshadowing"
        case chapterGoal = "chapter_goal"
    }
}

private struct ProjectEvalState {
    var savedChapters: [ChapterDraft] = []
    var memoryBuckets: MemoryBuckets = .empty
    var strandState: StrandWeaveState = .empty
    var runtime: LongformStoryRuntimeState = .empty
    var foreshadowList = ForeshadowList()
    var plotThreadList = PlotThreadList()
    var lastReview: ChapterReviewResult?

    var nextChapterNumber: Int {
        savedChapters.count + 1
    }
}

private final class LongformPipelineRunner {
    private let seeds: [EvalSeed]
    private let options: EvalOptions
    private let encoder: JSONEncoder
    private let realModel: RealLongformModel?
    private var states: [String: ProjectEvalState] = [:]
    private var generatedProjectIDs = Set<String>()

    init(seeds: [EvalSeed], options: EvalOptions) throws {
        self.seeds = seeds
        self.options = options
        realModel = try options.mode == "real" ? RealLongformModel() : nil
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func run() async throws {
        let runURL = try makeRunDirectory()
        let chaptersURL = runURL.appendingPathComponent("chapters", isDirectory: true)
        try FileManager.default.createDirectory(at: chaptersURL, withIntermediateDirectories: true)
        defer { cleanupGeneratedDefaults() }

        do {
            var chapterArtifacts: [ChapterArtifact] = []
            for globalChapter in 1...options.chapters {
                let seed = seeds[(globalChapter - 1) % seeds.count]
                let artifact = try await runChapter(globalChapter: globalChapter, seed: seed)
                chapterArtifacts.append(artifact)
                let outputURL = chaptersURL.appendingPathComponent(String(format: "chapter-%03d.json", globalChapter))
                try encoder.encode(artifact).write(to: outputURL)
            }

            let scorecard = Scorecard(mode: options.mode, chapters: options.chapters, seedCount: seeds.count, artifacts: chapterArtifacts)
            try encoder.encode(scorecard).write(to: runURL.appendingPathComponent("scorecard.json"))

            print("Longform eval run: \(runURL.path)")
            print("average_score=\(scorecard.averageScore) lowest_score=\(scorecard.lowestScore) passed=\(scorecard.passed)")
            guard scorecard.passed else {
                throw EvalError.message("\(options.mode) longform pipeline eval did not meet scorecard thresholds")
            }
        } catch {
            let failure = FailureArtifact(mode: options.mode, chapters: options.chapters, error: error)
            try? encoder.encode(failure).write(to: runURL.appendingPathComponent("failure.json"))
            throw error
        }
    }

    private func runChapter(globalChapter: Int, seed: EvalSeed) async throws -> ChapterArtifact {
        cleanupDefaults(for: seed.projectID)
        generatedProjectIDs.insert(seed.projectID)

        var state = states[seed.id] ?? ProjectEvalState()
        var project = seed.makeProject(state: state)
        let validation = PrewriteValidator.validate(project: project)
        guard validation.isReady else {
            throw EvalError.message("prewrite validation failed for \(seed.id) chapter \(state.nextChapterNumber): \(validation.blockingReasons.joined(separator: "；"))")
        }

        let support = AIWritingService.WritingSupportContext(project: project)
        let planPrompt = AIWritingService.writingPlanUserPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: LocalModel.additionalInstruction(seed: seed),
            length: .short,
            support: support
        )
        try PromptAssertions.require(planPrompt, contains: "长篇后台执行合同", label: "plan prompt longform contract")
        let plan = try await planText(seed: seed, project: project, prompt: planPrompt)

        let draftPrompt = AIWritingService.userPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: LocalModel.additionalInstruction(seed: seed),
            length: .short,
            support: support,
            writingPlan: plan
        )
        try PromptAssertions.require(draftPrompt, contains: "下一章 brief", label: "draft prompt next-chapter brief")
        try PromptAssertions.require(draftPrompt, contains: "近期质量趋势", label: "draft prompt quality trend")
        let draft = try await draftText(seed: seed, project: project, writingPlan: plan, prompt: draftPrompt)

        let revisionPrompt = AIWritingService.writingRevisionUserPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: LocalModel.additionalInstruction(seed: seed),
            length: .short,
            support: support,
            writingPlan: plan,
            draft: draft
        )
        try PromptAssertions.require(revisionPrompt, contains: "本章执行验收", label: "revision prompt execution contract")
        let revisedDraft = try await revisedDraftText(draft: draft, prompt: revisionPrompt)
        let contract = LongformStorySystem.buildRuntimeContract(for: project)
        let missingNodes = LongformStorySystem.missingMandatoryNodes(
            for: project,
            additionalText: revisedDraft,
            contract: contract
        )

        let reviewPrompt = ChapterQualityReviewer.reviewUserPrompt(
            project: project,
            chapterDraft: revisedDraft,
            memoryContext: project.enhancedMemoryContext
        )
        try PromptAssertions.require(reviewPrompt, contains: "输出格式（严格 JSON）", label: "review prompt JSON schema")
        try PromptAssertions.require(reviewPrompt, contains: "后台长篇合同", label: "review prompt longform contract")

        var review = try await reviewResult(
            seed: seed,
            project: project,
            draft: revisedDraft,
            contract: contract,
            missingNodes: missingNodes,
            prompt: reviewPrompt
        )
        review = ChapterQualityReviewer.mergeLocalAntiPatterns(
            into: review,
            localPatterns: ChapterQualityReviewer.quickAIFlavorCheck(text: revisedDraft)
        )
        review = ChapterQualityReviewer.mergeLocalHeuristicIssues(
            into: review,
            localIssues: ChapterQualityReviewer.localHeuristicIssues(text: revisedDraft, project: project)
        )

        let repairProbePrompt = AIWritingService.writingReviewRepairUserPrompt(
            project: project,
            mode: .advanceChapter,
            additionalInstruction: LocalModel.additionalInstruction(seed: seed),
            length: .short,
            support: support,
            writingPlan: plan,
            draft: revisedDraft,
            review: LocalModel.repairProbeReview()
        )
        try PromptAssertions.require(repairProbePrompt, contains: "质量审查反馈", label: "repair prompt review feedback")

        let chapterDraft = ChapterDraft(
            volumeNumber: project.currentVolumeNumber,
            chapterNumber: project.currentChapterNumber,
            chapterTitle: project.currentChapterTitle,
            content: revisedDraft,
            savedAt: EvalClock.timestamp(globalChapter)
        )
        let commit = LongformStorySystem.buildCommit(
            project: project,
            chapterDraft: chapterDraft,
            review: review,
            extractedMemoryItems: LocalModel.memoryItems(seed: seed, chapter: project.currentChapterNumber),
            contract: contract
        )
        LongformStorySystem.apply(commit: commit, contract: contract, to: &project)
        project.chapterDrafts.append(chapterDraft)
        project.chapterCatalog = project.chapterDrafts.map(ChapterDraftMetadata.init)

        let roundtripOK = ProjectRoundtrip.check(project: project)
        state.savedChapters = project.chapterDrafts
        state.memoryBuckets = project.memoryBuckets
        state.strandState = project.strandWeaveState
        state.runtime = project.longformRuntimeState
        state.foreshadowList = project.foreshadowList
        state.plotThreadList = project.plotThreadList
        state.lastReview = review
        states[seed.id] = state

        let promptMetrics = PromptMetrics(
            plan: planPrompt,
            draft: draftPrompt,
            revision: revisionPrompt,
            review: reviewPrompt,
            repair: repairProbePrompt
        )

        return ChapterArtifact(
            globalChapter: globalChapter,
            seedID: seed.id,
            projectChapter: project.currentChapterNumber,
            prewriteReady: validation.isReady,
            promptMetrics: promptMetrics,
            contract: ContractArtifact(contract: contract),
            prewriteBrief: PrewriteBrief(project: project),
            chapterDraft: revisedDraft,
            reviewJSON: ReviewJSON(review: review),
            memorySnapshot: MemorySnapshot(project: project),
            foreshadowingState: ForeshadowingState(project: project),
            qualityTrend: QualityTrendArtifact(project: project),
            repairTasks: project.longformNextChapterBrief.repairTasks,
            runtimeHealth: RuntimeHealthArtifact(project: project, saveRoundtripOK: roundtripOK),
            commit: CommitArtifact(commit: project.longformRuntimeState.latestCommit ?? commit, missingNodes: missingNodes)
        )
    }

    private func planText(seed: EvalSeed, project: NovelProject, prompt: String) async throws -> String {
        guard let realModel else {
            return LocalModel.plan(seed: seed, project: project)
        }
        return try await realModel.complete(
            systemPrompt: AIWritingService.writingPlanSystemPrompt,
            userPrompt: prompt,
            temperature: 0.42,
            maxTokens: 760
        )
    }

    private func draftText(seed: EvalSeed, project: NovelProject, writingPlan: String, prompt: String) async throws -> String {
        guard let realModel else {
            return LocalModel.draft(seed: seed, project: project, writingPlan: writingPlan)
        }
        return try await realModel.complete(
            systemPrompt: AIWritingService.systemPrompt,
            userPrompt: prompt,
            temperature: 0.82,
            maxTokens: AIWritingLength.short.maxTokens
        )
    }

    private func revisedDraftText(draft: String, prompt: String) async throws -> String {
        guard let realModel else {
            return LocalModel.revision(of: draft)
        }
        return try await realModel.complete(
            systemPrompt: AIWritingService.writingRevisionSystemPrompt,
            userPrompt: prompt,
            temperature: 0.34,
            maxTokens: AIWritingLength.short.maxTokens + 500
        )
    }

    private func reviewResult(
        seed: EvalSeed,
        project: NovelProject,
        draft: String,
        contract: LongformStoryContractBundle,
        missingNodes: [String],
        prompt: String
    ) async throws -> ChapterReviewResult {
        guard let realModel else {
            return ChapterQualityReviewer.parseReviewResult(
                from: try LocalLongformJudge.reviewJSON(
                    seed: seed,
                    project: project,
                    draft: draft,
                    contract: contract,
                    missingNodes: missingNodes
                )
            )
        }

        let reviewResponse = try await realModel.complete(
            systemPrompt: ChapterQualityReviewer.reviewSystemPrompt,
            userPrompt: prompt,
            temperature: 0.3,
            maxTokens: 3_000
        )
        return ChapterQualityReviewer.parseReviewResult(from: reviewResponse)
    }

    private func makeRunDirectory() throws -> URL {
        let timestamp = EvalClock.runTimestamp()
        let runURL = options.outputURL.appendingPathComponent("\(timestamp)-\(options.mode)-\(options.chapters)", isDirectory: true)
        try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)
        return runURL
    }

    private func cleanupGeneratedDefaults() {
        for projectID in generatedProjectIDs {
            cleanupDefaults(for: projectID)
        }
    }

    private func cleanupDefaults(for projectID: String) {
        let keys = [
            "memoryBuckets_\(projectID)",
            "strandWeave_\(projectID)",
            "antiPatterns_\(projectID)",
            "lastReview_\(projectID)",
            "longformRuntime_\(projectID)",
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private final class RealLongformModel {
    private let configuration: AIConnectionConfiguration

    init() throws {
        configuration = try ModelConnectionConfigurationStore.loadConnectionConfiguration()
        let provider = ModelConnectionConfigurationStore.loadSelectedProvider()
        fputs("Using OpenWriting \(provider.title) model configuration: \(configuration.modelName) @ \(configuration.baseURL.absoluteString)\n", stderr)
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        try await AIWritingService.generateText(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

private enum LocalModel {
    static func additionalInstruction(seed: EvalSeed) -> String {
        "本次 eval 必须推进「\(seed.chapterGoal)」，并显式维护「\(seed.longForeshadowing)」。"
    }

    static func plan(seed: EvalSeed, project: NovelProject) -> String {
        """
        - 承接第 \(max(project.currentChapterNumber - 1, 1)) 章末尾压力，让\(seed.protagonist)先处理眼前阻力。
        - 推进本章目标：\(seed.chapterGoal)
        - 让长期伏笔「\(seed.longForeshadowing)」获得新状态，但不提前揭示最终答案。
        - 章末留下下一章入口，让读者知道冲突还在升级。
        """
    }

    static func draft(seed: EvalSeed, project: NovelProject, writingPlan: String) -> String {
        let priorPressure = project.previousChapterDraftForContinuation?.chapterTitle ?? "上一章留下的压力"
        let paragraphSeeds = [
            "第一段，\(seed.protagonist)没有立刻解释\(priorPressure)，而是把注意力放回\(seed.world)。这条规则像一根压在纸面下的线，逼他确认眼前危机不是偶然，而是\(seed.coreConflict)露出的新裂口。",
            "第二段，他先让身边人按旧约撤到安全处，自己留下核对痕迹。现场的证据指向本章目标：\(seed.chapterGoal) 他没有绕回旧争执，而是用一次明确选择把危机向前推。",
            "第三段，冲突很快有了代价。对手试图用一份伪造记录掩盖真正来源，\(seed.protagonist)却从细节里发现一处前后不合的空白，并把它和长期伏笔「\(seed.longForeshadowing)」连在一起。",
            "第四段，角色状态也随之变化。他不再只追着结果奔跑，而是主动设下反证，让旁观者必须表态。这个动作兑现了上一个压力点，也让人物关系出现新的裂缝。",
            "第五段，世界规则给出反馈：\(seed.world)没有被改写，限制仍然有效。正因为限制有效，本章的解决不能靠临时开挂，只能靠主角对规则的理解和一次有风险的交换。",
            "第六段，他把交换放到众人面前，逼迫隐藏的一方承认漏洞。场面没有直接结束，反而把\(seed.coreConflict)推到更清楚的位置，让读者看见下一步必须面对谁。",
            "第七段，\(seed.longForeshadowing)在这一章获得新的可追踪状态：它不再只是传闻，而是留下了可以复查的编号、地点和见证人。这个状态足够推进，却没有提前揭开最终真相。",
            "第八段，\(seed.protagonist)为此失去一项短期优势。这个损失让胜利不显得轻飘，也让后续章节有了回收压力：他必须证明这次选择不是把更大的风险推给别人。",
            "第九段，场景收束时，他把证据交给最不愿相信他的人。对方没有立刻站队，只问了一个更尖锐的问题：如果线索是真的，为什么现在才出现？",
            "第十段，问题落下后，远处传来新的动静。\(seed.protagonist)抬头看见下一处入口已经被打开，而\(seed.longForeshadowing)留下的标记正指向那里：这一次，他还来得及阻止吗？"
        ]
        return paragraphSeeds.joined(separator: "\n\n")
    }

    static func revision(of draft: String) -> String {
        draft + "\n\n他把最后一枚证据收进掌心，没有解释胜负，只确认下一步行动：先追上标记，再回头清算这场误导。"
    }

    static func repairProbeReview() -> ChapterReviewResult {
        let scores = Dictionary(uniqueKeysWithValues: ReviewDimension.allUnifiedDimensions.map { ($0, 7) })
        return ChapterReviewResult(
            overallScore: 70,
            dimensionScores: scores,
            issues: [
                ReviewIssue(
                    dimension: .readerPull,
                    severity: .high,
                    description: "章末期待不足。",
                    evidence: "结尾直接收束。",
                    fixHint: "补出下一章入口和未完成压力。",
                    location: "末段"
                )
            ],
            hasBlockingIssues: false,
            antiPatterns: ["章末安全着陆"],
            overallSummary: "用于本地 eval 触发返修提示词。"
        )
    }

    static func memoryItems(seed: EvalSeed, chapter: Int) -> [MemoryItem] {
        [
            MemoryItem(
                id: "\(seed.id)-story-\(chapter)",
                category: .storyFact,
                subject: "\(seed.id)-chapter-\(chapter)",
                field: "chapter_progress",
                value: "第 \(chapter) 章完成：\(seed.chapterGoal)",
                sourceChapter: chapter
            ),
            MemoryItem(
                id: "\(seed.id)-character-\(chapter)",
                category: .characterState,
                subject: seed.protagonist,
                field: "current_state",
                value: "完成一次有代价的选择，并继续追查核心冲突。",
                sourceChapter: chapter
            ),
            MemoryItem(
                id: "\(seed.id)-foreshadow-\(chapter)",
                category: .openLoop,
                subject: seed.longForeshadowing,
                field: "tracking_state",
                value: "\(seed.longForeshadowing) 已在第 \(chapter) 章推进，仍需后续回收。",
                sourceChapter: chapter
            )
        ]
    }
}

private enum LocalLongformJudge {
    static func reviewJSON(
        seed: EvalSeed,
        project: NovelProject,
        draft: String,
        contract: LongformStoryContractBundle,
        missingNodes: [String]
    ) throws -> String {
        let issues = reviewIssues(
            seed: seed,
            project: project,
            draft: draft,
            contract: contract,
            missingNodes: missingNodes
        )
        let response = LocalReviewResponse(
            overallScore: overallScore(for: issues),
            dimensionScores: dimensionScores(for: issues),
            issues: issues,
            antiPatterns: ChapterQualityReviewer.quickAIFlavorCheck(text: draft),
            overallSummary: issues.isEmpty
                ? "local judge passed: draft covers the chapter contract, seed continuity, foreshadowing state, and reader-pull handoff."
                : "local judge found \(issues.count) contract or quality issue(s); inspect issues before trusting this run."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(response)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EvalError.message("local judge could not encode review JSON")
        }
        return json
    }

    private static func reviewIssues(
        seed: EvalSeed,
        project: NovelProject,
        draft: String,
        contract: LongformStoryContractBundle,
        missingNodes: [String]
    ) -> [LocalReviewIssue] {
        let normalizedDraft = normalized(draft)
        let paragraphs = draft.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var issues: [LocalReviewIssue] = []

        if !missingNodes.isEmpty {
            issues.append(LocalReviewIssue(
                dimension: .narrativeContinuity,
                severity: .critical,
                description: "本章没有覆盖后台合同要求的必走节点。",
                evidence: missingNodes.prefix(3).joined(separator: "；"),
                fixHint: "补写缺失节点对应的行动、证据或状态变化后再提交。",
                location: "长篇合同节点",
                blocking: true
            ))
        }
        if !covers(seed.chapterGoal, in: normalizedDraft) {
            issues.append(LocalReviewIssue(
                dimension: .logicIntegrity,
                severity: .high,
                description: "正文没有可验证地推进 seed 的本章目标。",
                evidence: seed.chapterGoal,
                fixHint: "让正文出现本章目标中的关键行动或信息增量。",
                location: "本章目标"
            ))
        }
        if !covers(seed.longForeshadowing, in: normalizedDraft) {
            issues.append(LocalReviewIssue(
                dimension: .readerPull,
                severity: .high,
                description: "长期伏笔没有获得可追踪的新状态。",
                evidence: seed.longForeshadowing,
                fixHint: "补出伏笔的新编号、地点、证人、代价或下一步入口。",
                location: "伏笔线"
            ))
        }
        if !covers(seed.protagonist, in: normalizedDraft) {
            issues.append(LocalReviewIssue(
                dimension: .characterConsistency,
                severity: .high,
                description: "主角状态没有在正文中明确承接。",
                evidence: seed.protagonist,
                fixHint: "让主角以符合 seed 设定的行动推进本章，而不是只描述局势。",
                location: "人物线"
            ))
        }
        if !covers(seed.world, in: normalizedDraft) {
            issues.append(LocalReviewIssue(
                dimension: .settingConsistency,
                severity: .medium,
                description: "世界规则没有在本章行动中形成约束。",
                evidence: seed.world,
                fixHint: "补出世界规则如何限制选择或制造代价。",
                location: "世界规则"
            ))
        }
        if !containsAny(["代价", "失去", "风险", "交换", "逼迫"], in: normalizedDraft) {
            issues.append(LocalReviewIssue(
                dimension: .highPointDensity,
                severity: .medium,
                description: "章节推进缺少代价或压力，微兑现可能偏轻。",
                evidence: String(draft.prefix(140)),
                fixHint: "给本章胜利附带损失、交换或下一章压力。",
                location: "冲突推进"
            ))
        }
        if paragraphs.count < 6 {
            issues.append(LocalReviewIssue(
                dimension: .pacing,
                severity: .medium,
                description: "正文段落过少，难以覆盖长篇章节的承接、推进、兑现和钩子。",
                evidence: "段落数 \(paragraphs.count)",
                fixHint: "至少拆出承接、调查、对抗、代价、伏笔状态和章末入口。",
                location: "篇幅结构"
            ))
        }
        if !hasReaderPullEnding(draft) {
            issues.append(LocalReviewIssue(
                dimension: .readerPull,
                severity: .medium,
                description: "章末缺少下一章入口或未完成压力。",
                evidence: String(draft.suffix(120)),
                fixHint: "以新发现、未完成行动、尖锐问题或更高压力收束。",
                location: "末段"
            ))
        }
        if contract.review.requiresPostwriteReview == true,
           contract.review.minimumAcceptedScore <= 0 {
            issues.append(LocalReviewIssue(
                dimension: .logicIntegrity,
                severity: .critical,
                description: "长篇合同要求写后审查，但最低通过线无效。",
                evidence: "\(contract.review.minimumAcceptedScore)",
                fixHint: "修复 LongformStorySystem 的审查合同生成逻辑。",
                location: "审查合同",
                blocking: true
            ))
        }

        return issues
    }

    private static func overallScore(for issues: [LocalReviewIssue]) -> Int {
        max(0, min(96, 100 - issues.map { $0.severity.penalty }.reduce(0, +)))
    }

    private static func dimensionScores(for issues: [LocalReviewIssue]) -> [String: Int] {
        var scores = Dictionary(uniqueKeysWithValues: ReviewDimension.allUnifiedDimensions.map { ($0.rawValue, 10) })
        for issue in issues {
            let penalty: Int
            switch issue.severity {
            case .critical:
                penalty = 4
            case .high:
                penalty = 3
            case .medium:
                penalty = 1
            case .low:
                penalty = 1
            }
            scores[issue.dimension.rawValue] = max(1, (scores[issue.dimension.rawValue] ?? 10) - penalty)
        }
        return scores
    }

    private static func covers(_ expected: String, in normalizedDraft: String) -> Bool {
        anchorTokens(from: expected).contains { normalizedDraft.contains($0) }
    }

    private static func anchorTokens(from value: String) -> [String] {
        normalized(value)
            .components(separatedBy: CharacterSet(charactersIn: "，。；：、,. ;:「」“”\"()（）\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }
            .prefix(4)
            .map(normalized)
    }

    private static func containsAny(_ candidates: [String], in normalizedDraft: String) -> Bool {
        candidates.contains { normalizedDraft.contains(normalized($0)) }
    }

    private static func hasReaderPullEnding(_ draft: String) -> Bool {
        let tail = String(draft.suffix(180))
        return containsAny(["？", "?", "下一", "入口", "追上", "阻止", "为什么", "标记", "还来得及"], in: normalized(tail))
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LocalReviewResponse: Encodable {
    let overallScore: Int
    let dimensionScores: [String: Int]
    let issues: [LocalReviewIssue]
    let antiPatterns: [String]
    let overallSummary: String

    enum CodingKeys: String, CodingKey {
        case overallScore = "overall_score"
        case dimensionScores = "dimension_scores"
        case issues
        case antiPatterns = "anti_patterns"
        case overallSummary = "overall_summary"
    }
}

private struct LocalReviewIssue: Encodable {
    let dimension: ReviewDimension
    let severity: ReviewSeverity
    let description: String
    let evidence: String
    let fixHint: String
    let location: String
    var blocking = false

    enum CodingKeys: String, CodingKey {
        case dimension
        case severity
        case description
        case evidence
        case fixHint = "fix_hint"
        case location
        case blocking
    }
}

private extension EvalSeed {
    var projectID: String { "longform-eval-\(id)" }

    func makeProject(state: ProjectEvalState) -> NovelProject {
        let chapter = state.nextChapterNumber
        var project = NovelProject(
            id: projectID,
            title: "Eval \(id)",
            genre: genre,
            summary: "\(world)\n\(protagonist)\n\(coreConflict)",
            storyLength: .long,
            updatedAt: EvalClock.timestamp(chapter),
            currentChapterTitle: "局部危机与新线索",
            currentVolumeNumber: 1,
            currentChapterNumber: chapter,
            writtenChapters: max(0, chapter - 1),
            chapterFocus: chapterGoal,
            draftText: draftOpening(chapter: chapter),
            outlineText: outlineText,
            structureNotes: structureNotes,
            sceneProgressNotes: sceneProgressNotes,
            characterArcNotes: characterArcNotes,
            foreshadowNotes: foreshadowNotes,
            volumePlanNotes: volumePlanNotes,
            activeThreadsNotes: activeThreadsNotes,
            outlineSummary: "当前卷围绕\(coreConflict)持续升级，\(longForeshadowing)必须保持可追踪状态。",
            referenceContextText: "评测素材：\(world) \(protagonist) \(longForeshadowing)",
            specialRequirements: "每章必须有微兑现、代价和下一章入口。",
            wordTargetText: "单章 900 到 1400 字，本地 eval 以结构覆盖为主。",
            continuityNotes: globalMemory.formattedText,
            globalMemorySnapshot: globalMemory,
            referenceDocuments: referenceDocuments,
            chapterDrafts: state.savedChapters,
            chapterCatalog: state.savedChapters.map(ChapterDraftMetadata.init),
            persistedMemoryBuckets: state.memoryBuckets,
            persistedStrandWeaveState: state.strandState,
            persistedLastReviewResult: state.lastReview,
            persistedLongformRuntimeState: state.runtime
        )
        project.foreshadowList = state.foreshadowList.entries.isEmpty ? initialForeshadowList : state.foreshadowList
        project.plotThreadList = state.plotThreadList.threads.isEmpty ? initialPlotThreadList : state.plotThreadList
        return project
    }

    private func draftOpening(chapter: Int) -> String {
        guard chapter > 1 else {
            return "\(protagonist)抵达第一处现场，先确认\(world)的限制仍然有效。"
        }
        return "\(protagonist)承接上一章留下的证据，准备继续处理\(chapterGoal)。"
    }

    private var globalMemory: GlobalMemorySnapshot {
        GlobalMemorySnapshot(
            recentDevelopments: "- \(protagonist)正在处理：\(coreConflict)",
            characterRelations: "- \(protagonist)与关键见证者保持临时合作，信任仍需证明。",
            identityChanges: "- \(protagonist)的公开身份稳定，但调查者身份逐步暴露。",
            injuries: "- 暂无重伤，体力和资源都受上一章行动影响。",
            factions: "- 主要对抗方仍隐藏在\(coreConflict)背后。",
            locations: "- \(world)",
            items: "- 关键证据与\(longForeshadowing)存在关联。",
            worldState: "- \(world)的核心规则不能被随意改写。",
            unresolvedForeshadowing: "- \(longForeshadowing)"
        )
    }

    private var outlineText: String {
        """
        第一卷：围绕\(coreConflict)建立连续压力，卷末确认幕后结构。
        主线：\(chapterGoal)
        长线伏笔：\(longForeshadowing)需要逐章留下可验证状态。
        """
    }

    private var structureNotes: String {
        """
        开场承接上一章压力，不重写已发生事实。
        中段用一次证据交换推进\(coreConflict)。
        末段留下下一处入口，并保持\(longForeshadowing)未完全揭示。
        """
    }

    private var sceneProgressNotes: String {
        """
        现场核验：主角确认规则限制仍然有效。
        冲突推进：对手试图掩盖线索，主角用反证逼出新状态。
        章末入口：标记指向下一处地点。
        """
    }

    private var characterArcNotes: String {
        """
        \(protagonist)从被动追查转向主动设局。
        见证者从怀疑转向有限合作。
        对抗方被迫暴露一个新的行动痕迹。
        """
    }

    private var foreshadowNotes: String {
        """
        \(longForeshadowing)：保持活跃，每章只能推进状态，不能一次性揭示答案。
        """
    }

    private var volumePlanNotes: String {
        "第一卷目标：用十个连续案件拆出\(coreConflict)的真实结构，卷末回收\(longForeshadowing)的一半信息并打开下一卷升级方向。"
    }

    private var activeThreadsNotes: String {
        """
        主线：\(coreConflict)
        伏笔线：\(longForeshadowing)
        人物线：\(protagonist)逐步从被追索者变成主动设局者。
        """
    }

    private var referenceDocuments: [ReferenceDocument] {
        [
            ReferenceDocument(
                title: "Eval Seed \(id)",
                content: "\(world)\n\(protagonist)\n\(coreConflict)\n\(longForeshadowing)",
                importedAt: "2026-06-15 00:00",
                category: .worldbuilding
            )
        ]
    }

    private var initialForeshadowList: ForeshadowList {
        ForeshadowList(entries: [
            ForeshadowEntry(
                id: "\(id)-initial-foreshadow",
                title: longForeshadowing,
                description: "eval seed long foreshadowing promise",
                firstChapter: 1,
                volumeNumber: 1,
                status: .active,
                importance: .major,
                threads: ["quest"],
                lastAdvancedChapter: 1,
                plantedChapter: 1,
                expectedResolutionChapter: 20
            )
        ])
    }

    private var initialPlotThreadList: PlotThreadList {
        PlotThreadList(threads: [
            PlotThread(
                id: "\(id)-main-thread",
                title: coreConflict,
                description: "eval seed main conflict",
                threadType: .quest,
                status: .active,
                startChapter: 1,
                lastActiveChapter: max(1, 1),
                volumeRange: 1...1
            )
        ])
    }
}

private enum PromptAssertions {
    static func require(_ prompt: String, contains expected: String, label: String) throws {
        guard prompt.contains(expected) else {
            throw EvalError.message("prompt assertion failed: \(label)")
        }
    }
}

private enum ProjectRoundtrip {
    static func check(project: NovelProject) -> Bool {
        guard let data = try? JSONEncoder().encode(project) else { return false }
        return (try? JSONDecoder().decode(NovelProject.self, from: data)) != nil
    }
}

private enum EvalClock {
    static func runTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }

    static func timestamp(_ chapter: Int) -> String {
        "2026-06-15 \(String(format: "%02d", min(chapter, 23))):00"
    }
}

private struct PromptMetrics: Encodable {
    let planPromptHash: String
    let draftPromptHash: String
    let revisionPromptHash: String
    let reviewPromptHash: String
    let repairPromptHash: String
    let planPromptLength: Int
    let draftPromptLength: Int
    let revisionPromptLength: Int
    let reviewPromptLength: Int
    let repairPromptLength: Int

    init(plan: String, draft: String, revision: String, review: String, repair: String) {
        planPromptHash = StableHash.hash(plan)
        draftPromptHash = StableHash.hash(draft)
        revisionPromptHash = StableHash.hash(revision)
        reviewPromptHash = StableHash.hash(review)
        repairPromptHash = StableHash.hash(repair)
        planPromptLength = plan.count
        draftPromptLength = draft.count
        revisionPromptLength = revision.count
        reviewPromptLength = review.count
        repairPromptLength = repair.count
    }
}

private struct PrewriteBrief: Encodable {
    let chapterGoal: String
    let mandatoryContinuities: [String]
    let foreshadowingPromises: [String]
    let forbiddenContradictions: [String]
    let qualityDebts: [String]
    let risks: [String]

    init(project: NovelProject) {
        let brief = project.longformNextChapterBrief
        chapterGoal = brief.chapterGoal
        mandatoryContinuities = brief.mandatoryContinuities
        foreshadowingPromises = brief.foreshadowingPromises
        forbiddenContradictions = brief.forbiddenContradictions
        qualityDebts = brief.qualityDebts
        risks = brief.risks
    }
}

private struct ContractArtifact: Encodable {
    let minimumAcceptedScore: Int
    let requiresPostwriteReview: Bool
    let mandatoryNodes: [String]
    let activeForeshadowing: [String]
    let prewriteBlocked: Bool
    let prewriteWarnings: [String]

    enum CodingKeys: String, CodingKey {
        case minimumAcceptedScore = "minimum_accepted_score"
        case requiresPostwriteReview = "requires_postwrite_review"
        case mandatoryNodes = "mandatory_nodes"
        case activeForeshadowing = "active_foreshadowing"
        case prewriteBlocked = "prewrite_blocked"
        case prewriteWarnings = "prewrite_warnings"
    }

    init(contract: LongformStoryContractBundle) {
        minimumAcceptedScore = contract.review.minimumAcceptedScore
        requiresPostwriteReview = contract.review.requiresPostwriteReview ?? false
        mandatoryNodes = contract.chapter.mandatoryNodes
        activeForeshadowing = contract.chapter.activeForeshadowing
        prewriteBlocked = contract.prewrite.isBlocked
        prewriteWarnings = contract.prewrite.warnings
    }
}

private struct ReviewJSON: Encodable {
    let overallScore: Int
    let dimensionScores: [String: Int]
    let issues: [IssueJSON]
    let antiPatterns: [String]
    let overallSummary: String

    enum CodingKeys: String, CodingKey {
        case overallScore = "overall_score"
        case dimensionScores = "dimension_scores"
        case issues
        case antiPatterns = "anti_patterns"
        case overallSummary = "overall_summary"
    }

    init(review: ChapterReviewResult) {
        overallScore = review.overallScore
        dimensionScores = Dictionary(uniqueKeysWithValues: review.dimensionScores.map { ($0.key.rawValue, $0.value) })
        issues = review.issues.map(IssueJSON.init)
        antiPatterns = review.antiPatterns
        overallSummary = review.overallSummary
    }
}

private struct IssueJSON: Encodable {
    let dimension: String
    let severity: String
    let description: String
    let evidence: String
    let fixHint: String
    let location: String

    init(issue: ReviewIssue) {
        dimension = issue.dimension.rawValue
        severity = issue.severity.rawValue
        description = issue.description
        evidence = issue.evidence
        fixHint = issue.fixHint
        location = issue.location
    }
}

private struct MemorySnapshot: Encodable {
    let activeMemoryCount: Int
    let recentDevelopments: String
    let characterState: String
    let worldState: String

    init(project: NovelProject) {
        activeMemoryCount = project.memoryBuckets.totalActiveCount
        recentDevelopments = project.globalMemorySnapshot.recentDevelopments
        characterState = project.globalMemorySnapshot.identityChanges
        worldState = project.globalMemorySnapshot.worldState
    }
}

private struct ForeshadowingState: Encodable {
    let active: [String]
    let forgotten: Bool

    init(project: NovelProject) {
        active = project.foreshadowList.activeEntries.map(\.title)
        forgotten = active.isEmpty && !project.foreshadowNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct QualityTrendArtifact: Encodable {
    let recentScores: [Int]
    let minimumAcceptedScore: Int
    let lowScoreCount: Int

    init(project: NovelProject) {
        let trend = project.longformQualityTrend
        recentScores = trend.recentScores
        minimumAcceptedScore = trend.minimumAcceptedScore
        lowScoreCount = trend.lowScoreCount
    }
}

private struct RuntimeHealthArtifact: Encodable {
    let continuityFailures: Int
    let characterDrift: Int
    let foreshadowingForgotten: Int
    let blockingGateChecks: [String]
    let warningGateChecks: [String]
    let healthStatus: String
    let saveRoundtripOK: Bool

    enum CodingKeys: String, CodingKey {
        case continuityFailures = "continuity_failures"
        case characterDrift = "character_drift"
        case foreshadowingForgotten = "foreshadowing_forgotten"
        case blockingGateChecks = "blocking_gate_checks"
        case warningGateChecks = "warning_gate_checks"
        case healthStatus = "health_status"
        case saveRoundtripOK = "save_roundtrip_ok"
    }

    init(project: NovelProject, saveRoundtripOK: Bool) {
        let health = project.longformRuntimeHealth
        continuityFailures = health.issues.filter { $0.title.contains("断章") || $0.title.contains("落后") }.count
        characterDrift = health.issues.filter { $0.title.contains("角色") || $0.detail.contains("角色") }.count
        foreshadowingForgotten = health.issues.filter { $0.title.contains("伏笔") || $0.detail.contains("伏笔") }.count
        blockingGateChecks = project.longformRuntimeState.latestWriteGate?.blockingChecks.map(Self.formatGateCheck) ?? []
        warningGateChecks = project.longformRuntimeState.latestWriteGate?.warningChecks.map(Self.formatGateCheck) ?? []
        healthStatus = health.status.rawValue
        self.saveRoundtripOK = saveRoundtripOK
    }

    private static func formatGateCheck(_ check: LongformWriteGateCheck) -> String {
        [check.stage.displayName, check.message, check.detail]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "：")
    }
}

private struct CommitArtifact: Encodable {
    let status: String
    let rejectionReasons: [String]
    let missedNodes: [String]
    let missingNodesBeforeCommit: [String]
    let writeGateSummary: String

    init(commit: LongformChapterCommit, missingNodes: [String]) {
        status = commit.status.rawValue
        rejectionReasons = commit.rejectionReasons ?? []
        missedNodes = commit.missedNodes
        missingNodesBeforeCommit = missingNodes
        writeGateSummary = commit.projectionStatus["quality_gate"] ?? "unknown"
    }
}

private struct ChapterArtifact: Encodable {
    let globalChapter: Int
    let seedID: String
    let projectChapter: Int
    let prewriteReady: Bool
    let promptMetrics: PromptMetrics
    let contract: ContractArtifact
    let prewriteBrief: PrewriteBrief
    let chapterDraft: String
    let reviewJSON: ReviewJSON
    let memorySnapshot: MemorySnapshot
    let foreshadowingState: ForeshadowingState
    let qualityTrend: QualityTrendArtifact
    let repairTasks: [String]
    let runtimeHealth: RuntimeHealthArtifact
    let commit: CommitArtifact

    enum CodingKeys: String, CodingKey {
        case globalChapter = "global_chapter"
        case seedID = "seed_id"
        case projectChapter = "project_chapter"
        case prewriteReady = "prewrite_ready"
        case promptMetrics = "prompt_metrics"
        case contract
        case prewriteBrief = "prewrite_brief"
        case chapterDraft = "chapter_draft"
        case reviewJSON = "review_json"
        case memorySnapshot = "memory_snapshot"
        case foreshadowingState = "foreshadowing_state"
        case qualityTrend = "quality_trend"
        case repairTasks = "repair_tasks"
        case runtimeHealth = "runtime_health"
        case commit
    }
}

private struct Scorecard: Encodable {
    let mode: String
    let chapters: Int
    let seedCount: Int
    let averageScore: Double
    let lowestScore: Int
    let dimensionAverages: [String: Double]
    let continuityFailures: Int
    let characterDrift: Int
    let foreshadowingForgotten: Int
    let foreshadowingMissRate: Double
    let aiFlavorDensity: Double
    let lowScoreRepairRate: Double
    let retryRejectionRate: Double
    let saveRoundtripFailures: Int
    let acceptedCommits: Int
    let rejectedCommits: Int
    let passThresholds: PassThresholds
    let passed: Bool
    private let writeGateBlockingFailures: Int

    enum CodingKeys: String, CodingKey {
        case mode
        case chapters
        case seedCount = "seed_count"
        case averageScore = "average_score"
        case lowestScore = "lowest_score"
        case dimensionAverages = "dimension_averages"
        case continuityFailures = "continuity_failures"
        case characterDrift = "character_drift"
        case foreshadowingForgotten = "foreshadowing_forgotten"
        case foreshadowingMissRate = "foreshadowing_miss_rate"
        case aiFlavorDensity = "ai_flavor_density"
        case lowScoreRepairRate = "low_score_repair_rate"
        case retryRejectionRate = "retry_rejection_rate"
        case saveRoundtripFailures = "save_roundtrip_failures"
        case acceptedCommits = "accepted_commits"
        case rejectedCommits = "rejected_commits"
        case passThresholds = "pass_thresholds"
        case passed
    }

    init(mode: String, chapters: Int, seedCount: Int, artifacts: [ChapterArtifact]) {
        self.mode = mode
        self.chapters = chapters
        self.seedCount = seedCount

        let scores = artifacts.map(\.reviewJSON.overallScore)
        averageScore = Scorecard.round(scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count))
        lowestScore = scores.min() ?? 0

        var dimensions: [String: [Int]] = [:]
        for artifact in artifacts {
            for (dimension, score) in artifact.reviewJSON.dimensionScores {
                dimensions[dimension, default: []].append(score)
            }
        }
        dimensionAverages = dimensions.mapValues { values in
            Scorecard.round(Double(values.reduce(0, +)) / Double(values.count))
        }

        continuityFailures = artifacts.map(\.runtimeHealth.continuityFailures).reduce(0, +)
        characterDrift = artifacts.map(\.runtimeHealth.characterDrift).reduce(0, +)
        foreshadowingForgotten = artifacts.map(\.runtimeHealth.foreshadowingForgotten).reduce(0, +)
        foreshadowingMissRate = Scorecard.round(Double(foreshadowingForgotten) / Double(max(chapters, 1)), places: 4)
        let aiFlavorIssues = artifacts.flatMap(\.reviewJSON.issues).filter { $0.dimension == ReviewDimension.aiFlavor.rawValue }.count
        aiFlavorDensity = Scorecard.round(Double(aiFlavorIssues) / Double(max(chapters, 1)), places: 4)
        let lowScores = scores.filter { $0 < 90 }.count
        lowScoreRepairRate = lowScores == 0 ? 1.0 : 0.0
        rejectedCommits = artifacts.filter { $0.commit.status == LongformCommitStatus.rejected.rawValue }.count
        acceptedCommits = artifacts.count - rejectedCommits
        retryRejectionRate = Scorecard.round(Double(rejectedCommits) / Double(max(chapters, 1)), places: 4)
        saveRoundtripFailures = artifacts.filter { !$0.runtimeHealth.saveRoundtripOK }.count
        writeGateBlockingFailures = artifacts.map(\.runtimeHealth.blockingGateChecks.count).reduce(0, +)
        passThresholds = PassThresholds()
        passed = averageScore >= Double(passThresholds.averageScoreAtLeast)
            && lowestScore >= passThresholds.lowestScoreAtLeast
            && continuityFailures == passThresholds.continuityFailures
            && foreshadowingMissRate < passThresholds.foreshadowingMissRateBelow
            && saveRoundtripFailures == 0
            && writeGateBlockingFailures == 0
            && rejectedCommits == 0
    }

    private static func round(_ value: Double, places: Int = 2) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }
}

private struct FailureArtifact: Encodable {
    let mode: String
    let chapters: Int
    let failedAt: String
    let error: String

    enum CodingKeys: String, CodingKey {
        case mode
        case chapters
        case failedAt = "failed_at"
        case error
    }

    init(mode: String, chapters: Int, error: Error) {
        self.mode = mode
        self.chapters = chapters
        failedAt = EvalClock.runTimestamp()
        self.error = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

private struct PassThresholds: Encodable {
    let averageScoreAtLeast = 90
    let lowestScoreAtLeast = 82
    let continuityFailures = 0
    let foreshadowingMissRateBelow = 0.05

    enum CodingKeys: String, CodingKey {
        case averageScoreAtLeast = "average_score_at_least"
        case lowestScoreAtLeast = "lowest_score_at_least"
        case continuityFailures = "continuity_failures"
        case foreshadowingMissRateBelow = "foreshadowing_miss_rate_below"
    }
}

private enum StableHash {
    static func hash(_ value: String) -> String {
        let hash = value.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { result, scalar in
            (result ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

private enum EvalError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}
