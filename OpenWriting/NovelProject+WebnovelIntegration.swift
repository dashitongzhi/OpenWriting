import Foundation

// MARK: - NovelProject Extensions for Webnovel-Writer Integration

/// Extensions to NovelProject that add the new structured memory, pacing, and review systems.
/// These fields are stored alongside existing project data for backward compatibility.

extension NovelProject {

    // MARK: - Memory Buckets

    /// Structured memory buckets, replacing/supplementing the flat continuityNotes.
    var memoryBuckets: MemoryBuckets {
        get {
            if let persistedMemoryBuckets {
                return persistedMemoryBuckets
            }

            return MemoryBuckets.migrate(from: globalMemorySnapshot, currentChapter: writtenChapters)
        }
        set {
            persistedMemoryBuckets = newValue
        }
    }

    // MARK: - Strand Weave State

    var strandWeaveState: StrandWeaveState {
        get {
            if let persistedStrandWeaveState {
                return persistedStrandWeaveState
            }

            return .empty
        }
        set {
            persistedStrandWeaveState = newValue
        }
    }

    // MARK: - Review History

    var lastReviewResult: ChapterReviewResult? {
        get {
            if let persistedLastReviewResult {
                return persistedLastReviewResult
            }

            return nil
        }
        set {
            persistedLastReviewResult = newValue
        }
    }

    // MARK: - Anti-Patterns (accumulated from reviews)

    var accumulatedAntiPatterns: [String] {
        get {
            if let persistedAntiPatterns {
                return persistedAntiPatterns
            }
            return []
        }
        set {
            persistedAntiPatterns = newValue
        }
    }

    /// Append new anti-patterns from a review result, deduplicating.
    mutating func appendAntiPatterns(from review: ChapterReviewResult) {
        var existing = Set(accumulatedAntiPatterns)
        for pattern in review.antiPatterns {
            existing.insert(pattern)
        }
        // Keep max 50 anti-patterns
        accumulatedAntiPatterns = Array(existing.prefix(50))
    }

    /// Append anti-patterns from a raw string array (e.g., local quick-check results).
    mutating func appendAntiPatterns(from patterns: [String]) {
        var existing = Set(accumulatedAntiPatterns)
        for pattern in patterns {
            existing.insert(pattern)
        }
        accumulatedAntiPatterns = Array(existing.prefix(50))
    }

    // MARK: - Genre Template

    var genreTemplate: GenreTemplate {
        if let genreTemplateId,
           let selected = GenreTemplateLibrary.allTemplates.first(where: { $0.id == genreTemplateId }) {
            return selected
        }
        return GenreTemplateLibrary.autoDetect(from: genre)
    }

    // MARK: - Narrative Stage Detection

    var narrativeStage: NarrativeStage {
        detectNarrativeStage(
            currentChapter: currentChapterNumber,
            totalChapters: nil,
            storyLength: storyLength
        )
    }

    // MARK: - Enhanced Memory Context

    /// Hard cap on the assembled memory context string. Without this, a project
    /// with thousands of memory items can push the prompt past the LLM's
    /// context window.
    static let enhancedMemoryContextCharacterLimit = 4000

    /// Build the full memory context for writing, combining structured buckets
    /// with existing notes.
    var enhancedMemoryContext: String {
        var sections: [String] = []

        // Structured memory (high priority)
        let buckets = memoryBuckets
        if buckets.totalActiveCount > 0 {
            let query = [
                currentChapterSummary,
                chapterFocus,
                draftText,
                outlineSummary,
                sceneProgressNotes,
                characterArcNotes,
                foreshadowNotes,
                activeThreadsNotes
            ].joined(separator: "\n")
            let workingItems = buckets.workingContextItems(for: query)
            sections.append("【结构化记忆】\n\(buckets.formattedForWorkingContext(workingItems))")
        } else if globalMemorySnapshot.hasStructuredContent {
            // Legacy fallback when the project has not migrated into structured buckets.
            sections.append("【记忆快照】\n\(globalMemorySnapshot.formattedText)")
        } else if hasContinuityNotes {
            // Fallback to raw continuity notes only when snapshot lacks structured content
            sections.append("【全局记忆】\n\(continuityNotes)")
        }

        let joined = sections.isEmpty ? "暂无记忆上下文。" : sections.joined(separator: "\n\n")
        return truncate(joined, to: Self.enhancedMemoryContextCharacterLimit)
    }

    private func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        return head + "\n…(已截断，完整记忆存储在结构化存储中)"
    }

    // MARK: - Strand Context

    var strandContext: String {
        strandWeaveState.formattedForContext
    }

    // MARK: - Genre Template Context

    var genreTemplateContext: String {
        genreTemplate.formattedForPrompt
    }

    // MARK: - Anti-Pattern Context

    var antiPatternContext: String {
        let patterns = accumulatedAntiPatterns
        guard !patterns.isEmpty else { return "暂无积累的反模式。" }
        return "已识别的 AI 味反模式（写作时务必避免）：\n" + patterns.map { "· \($0)" }.joined(separator: "\n")
    }
}
