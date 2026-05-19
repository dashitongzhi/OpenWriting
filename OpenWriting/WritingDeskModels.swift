import Observation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - WritingDeskModels
//
// All supporting types for WritingDeskView.
// Extracted to reduce file size.

// MARK: - Scroll Anchor

private enum WritingDeskScrollAnchor: String {
    case draft
    case ai
    case cache
}

// MARK: - Request Contexts

private struct OutlineGenerationRequestContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
    let outlineText: String
    let profile: OutlineGenerationProfile
}

private struct DraftGenerationRequestContext: Equatable {
    let projectID: NovelProject.ID
    let storyLength: NovelLength
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
    let mode: AIWritingMode
    let length: AIWritingLength
    let rewriteDirection: AIRewriteDirection
    let rejectedSuggestion: String
}

// MARK: - Run State

private enum WritingRunState {
    case idle
    case requesting
    case stopping
}

// MARK: - Rewrite Direction

private enum AIRewriteDirection: String, CaseIterable, Identifiable {
    case freshTake
    case fasterPace
    case richerTexture
    case sharperTension
    case moreNaturalDialogue

    var id: Self { self }

    var title: String {
        switch self {
        case .freshTake: return "换一种写法"
        case .fasterPace: return "推进更快"
        case .richerTexture: return "细节更足"
        case .sharperTension: return "张力更强"
        case .moreNaturalDialogue: return "对白更自然"
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

// MARK: - Draft Polish Mode

private enum DraftPolishMode {
    case full
    case selection

    var progressTitle: String {
        switch self {
        case .full: return "正在润色整篇草稿"
        case .selection: return "正在润色选区"
        }
    }

    var reviewTitle: String {
        switch self {
        case .full: return "整篇润色结果已写入正文"
        case .selection: return "选区润色结果已写入正文"
        }
    }
}

// MARK: - Draft Polish Review

private struct DraftPolishReview: Identifiable {
    let id = UUID()
    let projectID: NovelProject.ID
    let mode: DraftPolishMode
    let originalDraft: String
    let polishedDraft: String
    let polishedText: String
    let restoredSelection: WritingDeskDraftSelection

    var changedCharacterCount: Int {
        abs(polishedDraft.count - originalDraft.count)
    }
}

// MARK: - AI Writer Thinking Mode

private enum AIWriterThinkingMode {
    case writing
    case rewriting

    var title: String {
        switch self {
        case .writing: return "创作中"
        case .rewriting: return "润色中"
        }
    }
}

// MARK: - AI Writer Timing Snapshot

struct AIWriterTimingSnapshot: Equatable {
    let startedAt: Date
    let lastChunkAt: Date
    let tokenCount: Int

    var elapsedSeconds: Double {
        Date().timeIntervalSince(startedAt)
    }

    var throughput: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return Double(tokenCount) / elapsedSeconds
    }

    static let idle = AIWriterTimingSnapshot(startedAt: Date(), lastChunkAt: Date(), tokenCount: 0)
}

// MARK: - Toolbar Action

private struct WritingDeskToolbarAction: Identifiable {
    let id = UUID()
    let symbolName: String
    let accessibilityLabel: String
    let action: () -> Void
}