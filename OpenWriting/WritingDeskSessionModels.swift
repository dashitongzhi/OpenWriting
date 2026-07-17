import Foundation

enum WritingDeskScrollAnchor: String {
    case draft
    case ai
    case cache
}

struct WritingDeskSessionKey: Hashable {
    let projectID: NovelProject.ID
    let volumeNumber: Int
    let chapterNumber: Int
}

struct OutlineGenerationRequestContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
    let outlineText: String
    let profile: OutlineGenerationProfile
}

struct DraftGenerationRequestContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
    let currentVolumeNumber: Int
    let currentChapterTitle: String
    let currentChapterNumber: Int
    let chapterFocus: String
    let draftText: String
    let outlineText: String
    let referenceContextText: String
    let specialRequirements: String
    let wordTargetText: String
    let continuityNotes: String
    let referenceDocuments: [ReferenceDocument]
    let chapterDrafts: [ChapterDraft]
    let enhancedMemoryContext: String
    let longformStorySystemContext: String
    let mode: AIWritingMode
    let length: AIWritingLength
    let rewriteDirection: AIRewriteDirection
    let rejectedSuggestion: String
}

struct AISuggestionAcceptanceContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
    let currentVolumeNumber: Int
    let currentChapterTitle: String
    let currentChapterNumber: Int
    let chapterFocus: String
    let draftText: String
    let outlineText: String
    let referenceContextText: String
    let specialRequirements: String
    let wordTargetText: String
    let continuityNotes: String
    let referenceDocuments: [ReferenceDocument]
    let chapterDrafts: [ChapterDraft]
    let enhancedMemoryContext: String
    let longformStorySystemContext: String
    let mode: AIWritingMode
    let length: AIWritingLength
}

struct ChapterSaveValidationContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
    let currentVolumeNumber: Int
    let currentChapterNumber: Int
    let currentChapterTitle: String
    let chapterFocus: String
    let draftText: String
    let outlineText: String
    let structureNotes: String
    let sceneProgressNotes: String
    let characterArcNotes: String
    let foreshadowNotes: String
    let volumePlanNotes: String
    let activeThreadsNotes: String
    let continuityNotes: String
    let referenceContextText: String
    let specialRequirements: String
    let wordTargetText: String
    let enhancedMemoryContext: String
    let longformStorySystemContext: String
}

enum WritingRunState {
    case idle
    case requesting
    case stopping
}

enum AIRewriteDirection: String, CaseIterable, Identifiable {
    case freshTake
    case fasterPace
    case richerTexture
    case sharperTension
    case moreNaturalDialogue

    var id: Self { self }

    var title: String {
        switch self {
        case .freshTake:
            return "换一种写法"
        case .fasterPace:
            return "推进更快"
        case .richerTexture:
            return "细节更足"
        case .sharperTension:
            return "张力更强"
        case .moreNaturalDialogue:
            return "对白更自然"
        }
    }

    var instruction: String {
        switch self {
        case .freshTake:
            return "明显更换起笔、节奏和措辞，避免重复上一版的句子结构或段落组织。"
        case .fasterPace:
            return "减少铺垫和解释，优先推进动作、选择、冲突结果和信息增量。"
        case .richerTexture:
            return "保留推进方向，同时补强动作细节、场景感、心理层次和段落质感。"
        case .sharperTension:
            return "提高冲突压迫感和人物选择压力，让场景更紧、更有悬念。"
        case .moreNaturalDialogue:
            return "优化对白的口语节奏、潜台词和人物差异，减少说明式台词。"
        }
    }
}

enum DraftPolishMode {
    case full
    case selection

    var progressTitle: String {
        switch self {
        case .full:
            return "正在润色整篇草稿"
        case .selection:
            return "正在润色选区"
        }
    }

    var reviewTitle: String {
        switch self {
        case .full:
            return "整篇润色结果已写入正文"
        case .selection:
            return "选区润色结果已写入正文"
        }
    }
}

struct DraftPolishReview: Identifiable {
    let id = UUID()
    let projectID: NovelProject.ID
    let mode: DraftPolishMode
    let originalDraft: String
    let polishedDraft: String
    let polishedText: String
    let restoredSelection: WritingDeskDraftSelection
    let isApplied: Bool
    let blockingMessage: String?

    var changedCharacterCount: Int {
        abs(polishedDraft.count - originalDraft.count)
    }
}

enum AIWriterThinkingMode {
    case writing
    case rewriting

    var title: String {
        switch self {
        case .writing:
            return "AI 作家正在组织这一章"
        case .rewriting:
            return "AI 作家正在重写这一版"
        }
    }

    var subtitle: String {
        switch self {
        case .writing:
            return "会先梳理当前目标、人物状态和场景推进，再落到正文。"
        case .rewriting:
            return "会保留当前约束，但重新组织起笔、节奏和措辞。"
        }
    }

    var messages: [String] {
        switch self {
        case .writing:
            return [
                "回看当前章节目标、上一章缓存与正在进行的冲突。",
                "对齐大纲、参考文本、特殊要求和字数约束。",
                "先定这一段的切入点、情绪坡度和信息释放顺序。",
                "把人物动作、对白张力与场景质感压进可直接续写的正文。"
            ]
        case .rewriting:
            return [
                "回收上一版里不满意的句式和段落组织，避免重复。",
                "保留章节目标与既有约束，但重排起笔和推进节奏。",
                "换一组更贴合当前情绪的动作细节、对白与叙述重心。",
                "整理成另一种可直接进入草稿箱的候选稿。"
            ]
        }
    }
}

struct AIWriterTimingSnapshot {
    var queue: Double
    var generate: Double
    var finish: Double
    var complete: Double
    var activeStage: AIWriterTimelineStage?
    var isStopping: Bool

    static let idle = AIWriterTimingSnapshot(
        queue: 0,
        generate: 0,
        finish: 0,
        complete: 0,
        activeStage: nil,
        isStopping: false
    )

    static let queued = AIWriterTimingSnapshot(
        queue: 0.1,
        generate: 0,
        finish: 0,
        complete: 0.1,
        activeStage: .queue,
        isStopping: false
    )

    static func live(elapsed: TimeInterval) -> AIWriterTimingSnapshot {
        let queueDuration = min(elapsed, 0.6)
        let generateDuration = elapsed > 0.6 ? min(elapsed - 0.6, 2.4) : 0
        let finishDuration = elapsed > 3.0 ? elapsed - 3.0 : 0
        let activeStage: AIWriterTimelineStage =
            elapsed < 0.6 ? .queue :
            elapsed < 3.0 ? .generate :
            .finish

        return AIWriterTimingSnapshot(
            queue: queueDuration,
            generate: generateDuration,
            finish: finishDuration,
            complete: elapsed,
            activeStage: activeStage,
            isStopping: false
        )
    }

    static func completed(total: TimeInterval) -> AIWriterTimingSnapshot {
        AIWriterTimingSnapshot(
            queue: max(min(total * 0.12, 0.8), 0.1),
            generate: max(total * 0.70, 0.1),
            finish: max(total * 0.18, 0.1),
            complete: max(total, 0.2),
            activeStage: .complete,
            isStopping: false
        )
    }

    func stopping() -> AIWriterTimingSnapshot {
        AIWriterTimingSnapshot(
            queue: queue,
            generate: generate,
            finish: finish,
            complete: complete,
            activeStage: activeStage,
            isStopping: true
        )
    }
}

enum ChapterWritingSessionPolicy {
    static func isCurrent(_ context: OutlineGenerationRequestContext, for project: NovelProject) -> Bool {
        context == outlineGenerationContext(for: project, profile: context.profile)
    }

    static func isCurrent(_ context: DraftGenerationRequestContext, for project: NovelProject) -> Bool {
        context == draftGenerationContext(
            for: project,
            rewriteDirection: context.rewriteDirection,
            rejectedSuggestion: context.rejectedSuggestion
        )
    }

    static func isCurrent(_ context: AISuggestionAcceptanceContext, for project: NovelProject) -> Bool {
        context == acceptanceContext(for: project)
    }

    static func isCurrent(_ context: ChapterSaveValidationContext, for project: NovelProject) -> Bool {
        context == chapterSaveValidationContext(for: project)
    }

    static func shouldConfirmChapterLoad(in project: NovelProject) -> Bool {
        let currentDraft = project.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentDraft.isEmpty else { return false }

        let currentSavedDraft = project.chapterDrafts.first {
            $0.volumeNumber == max(project.currentVolumeNumber, 1)
                && $0.chapterNumber == max(project.currentChapterNumber, 1)
        }
        let savedText = currentSavedDraft?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return savedText != currentDraft
    }

    static func preferredLength(for project: NovelProject) -> AIWritingLength {
        let number = inferredTargetWordCount(from: project.wordTargetText)

        if number == 0 {
            switch project.storyLength {
            case .short:
                return .short
            case .medium:
                return .medium
            case .long:
                return .long
            }
        }

        switch number {
        case 0 ..< 850:
            return .short
        case 1_700...:
            return .long
        default:
            return .medium
        }
    }

    static func generationInstruction(
        rewriteDirection: AIRewriteDirection,
        rejectedSuggestion: String?,
        reviewFeedback: String
    ) -> String {
        let baseInstruction = "请同时遵守项目中的特殊要求和字数设定，直接创作可进入草稿箱的正文候选稿。"
        let trimmedRejectedSuggestion = rejectedSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedRejectedSuggestion.isEmpty else {
            return baseInstruction
        }

        let trimmedReviewFeedback = reviewFeedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewFeedbackBlock = trimmedReviewFeedback.isEmpty
            ? ""
            : """

            上一版质量审查反馈（这次必须优先修复，不要只换措辞）：
            \(trimmedReviewFeedback)
            """

        return """
        \(baseInstruction)
        用户对上一版候选稿不满意，这次重写方向是：\(rewriteDirection.title)。\(rewriteDirection.instruction)
        \(reviewFeedbackBlock)
        不要重复下面这版的句子结构或段落组织：
        \(excerpt(from: trimmedRejectedSuggestion, limit: 1_200))
        """
    }

    static func outlineGenerationContext(
        for project: NovelProject,
        profile: OutlineGenerationProfile
    ) -> OutlineGenerationRequestContext {
        OutlineGenerationRequestContext(
            projectID: project.id,
            storyLength: project.storyLength,
            outlineText: project.outlineText,
            profile: profile
        )
    }

    static func draftGenerationContext(
        for project: NovelProject,
        rewriteDirection: AIRewriteDirection,
        rejectedSuggestion: String?
    ) -> DraftGenerationRequestContext {
        DraftGenerationRequestContext(
            projectID: project.id,
            storyLength: project.storyLength,
            currentVolumeNumber: project.currentVolumeNumber,
            currentChapterTitle: project.currentChapterTitle,
            currentChapterNumber: project.currentChapterNumber,
            chapterFocus: project.chapterFocus,
            draftText: project.draftText,
            outlineText: project.outlineText,
            referenceContextText: project.referenceContextText,
            specialRequirements: project.specialRequirements,
            wordTargetText: project.wordTargetText,
            continuityNotes: project.continuityNotes,
            referenceDocuments: project.referenceDocuments,
            chapterDrafts: project.chapterDrafts,
            enhancedMemoryContext: project.enhancedMemoryContext,
            longformStorySystemContext: project.longformStorySystemContext,
            mode: project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .advanceChapter : .continueScene,
            length: preferredLength(for: project),
            rewriteDirection: rewriteDirection,
            rejectedSuggestion: rejectedSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    static func acceptanceContext(for project: NovelProject) -> AISuggestionAcceptanceContext {
        AISuggestionAcceptanceContext(
            projectID: project.id,
            storyLength: project.storyLength,
            currentVolumeNumber: max(project.currentVolumeNumber, 1),
            currentChapterTitle: project.currentChapterTitle,
            currentChapterNumber: max(project.currentChapterNumber, 1),
            chapterFocus: project.chapterFocus,
            draftText: project.draftText,
            outlineText: project.outlineText,
            referenceContextText: project.referenceContextText,
            specialRequirements: project.specialRequirements,
            wordTargetText: project.wordTargetText,
            continuityNotes: project.continuityNotes,
            referenceDocuments: project.referenceDocuments,
            chapterDrafts: project.chapterDrafts,
            enhancedMemoryContext: project.enhancedMemoryContext,
            longformStorySystemContext: project.longformStorySystemContext,
            mode: project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .advanceChapter : .continueScene,
            length: preferredLength(for: project)
        )
    }

    static func chapterSaveValidationContext(for project: NovelProject) -> ChapterSaveValidationContext {
        ChapterSaveValidationContext(
            projectID: project.id,
            storyLength: project.storyLength,
            currentVolumeNumber: max(project.currentVolumeNumber, 1),
            currentChapterNumber: max(project.currentChapterNumber, 1),
            currentChapterTitle: project.currentChapterTitle,
            chapterFocus: project.chapterFocus,
            draftText: project.draftText,
            outlineText: project.outlineText,
            structureNotes: project.structureNotes,
            sceneProgressNotes: project.sceneProgressNotes,
            characterArcNotes: project.characterArcNotes,
            foreshadowNotes: project.foreshadowNotes,
            volumePlanNotes: project.volumePlanNotes,
            activeThreadsNotes: project.activeThreadsNotes,
            continuityNotes: project.continuityNotes,
            referenceContextText: project.referenceContextText,
            specialRequirements: project.specialRequirements,
            wordTargetText: project.wordTargetText,
            enhancedMemoryContext: project.enhancedMemoryContext,
            longformStorySystemContext: project.longformStorySystemContext
        )
    }

    private static func inferredTargetWordCount(from text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let rangePattern = #"(\d+(?:\.\d+)?)\s*(万|千)?\s*[-~—–至到]\s*(\d+(?:\.\d+)?)\s*(万|千)?\s*字?"#
        let singlePattern = #"(\d+(?:\.\d+)?)\s*(万|千)?\s*字"#
        let chapterKeywords = ["本章", "本次", "当前章节", "单章", "章节", "章均", "每章"]
        let projectKeywords = ["全书", "全文", "总字数", "总计", "预计", "完本", "全稿"]
        let adjustmentKeywords = ["上浮", "下浮", "浮动", "%", "百分"]

        struct Candidate {
            let value: Int
            let score: Int
        }

        func normalizedValue(_ numberText: String, unit: String?) -> Int? {
            guard let base = Double(numberText) else { return nil }
            let multiplier: Double

            switch unit {
            case "万":
                multiplier = 10_000
            case "千":
                multiplier = 1_000
            default:
                multiplier = 1
            }

            return Int(base * multiplier)
        }

        func context(for range: NSRange) -> String {
            let lowerBound = max(0, range.location - 12)
            let upperBound = min(nsText.length, range.location + range.length + 12)
            return nsText.substring(with: NSRange(location: lowerBound, length: upperBound - lowerBound))
        }

        func score(for context: String, value: Int, prefersRange: Bool) -> Int {
            var score = prefersRange ? 8 : 4

            if chapterKeywords.contains(where: context.contains) {
                score += 8
            }
            if projectKeywords.contains(where: context.contains) {
                score -= 8
            }
            if adjustmentKeywords.contains(where: context.contains) {
                score -= 5
            }
            if value > 10_000 {
                score -= 10
            } else if value >= 800, value <= 4_500 {
                score += 5
            }

            return score
        }

        var candidates: [Candidate] = []

        if let rangeExpression = try? NSRegularExpression(pattern: rangePattern) {
            for match in rangeExpression.matches(in: trimmed, range: fullRange) {
                guard match.numberOfRanges >= 5 else { continue }
                let lowerText = nsText.substring(with: match.range(at: 1))
                let lowerUnit = match.range(at: 2).location == NSNotFound ? nil : nsText.substring(with: match.range(at: 2))
                let upperText = nsText.substring(with: match.range(at: 3))
                let upperUnit = match.range(at: 4).location == NSNotFound ? lowerUnit : nsText.substring(with: match.range(at: 4))
                guard
                    let lower = normalizedValue(lowerText, unit: lowerUnit),
                    let upper = normalizedValue(upperText, unit: upperUnit)
                else { continue }

                let midpoint = (lower + upper) / 2
                let candidateContext = context(for: match.range)
                candidates.append(.init(value: midpoint, score: score(for: candidateContext, value: midpoint, prefersRange: true)))
            }
        }

        if let singleExpression = try? NSRegularExpression(pattern: singlePattern) {
            for match in singleExpression.matches(in: trimmed, range: fullRange) {
                guard match.numberOfRanges >= 3 else { continue }
                let numberText = nsText.substring(with: match.range(at: 1))
                let unit = match.range(at: 2).location == NSNotFound ? nil : nsText.substring(with: match.range(at: 2))
                guard let value = normalizedValue(numberText, unit: unit) else { continue }
                let candidateContext = context(for: match.range)
                candidates.append(.init(value: value, score: score(for: candidateContext, value: value, prefersRange: false)))
            }
        }

        if let bestCandidate = candidates.max(by: {
            if $0.score == $1.score {
                return abs($0.value - 2_000) > abs($1.value - 2_000)
            }
            return $0.score < $1.score
        }) {
            return bestCandidate.value
        }

        let fallbackNumbers = trimmed
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { (500 ... 5_000).contains($0) }

        if let fallback = fallbackNumbers.min(by: { abs($0 - 2_000) < abs($1 - 2_000) }) {
            return fallback
        }

        return 0
    }

    private static func excerpt(from text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
