import Foundation

// MARK: - NovelProject Extensions for Webnovel-Writer Integration

/// Extensions to NovelProject that add the new structured memory, pacing, and review systems.
/// These fields are stored alongside existing project data for backward compatibility.

extension NovelProject {

    // MARK: - Memory Buckets

    /// Structured memory buckets, replacing/supplementing the flat continuityNotes.
    var memoryBuckets: MemoryBuckets {
        get {
            // Try to load from UserDefaults keyed by project ID
            if let data = UserDefaults.standard.data(forKey: "memoryBuckets_\(id)"),
               let buckets = try? JSONDecoder().decode(MemoryBuckets.self, from: data) {
                return buckets
            }
            // Migrate from existing GlobalMemorySnapshot
            return MemoryBuckets.migrate(from: globalMemorySnapshot, currentChapter: writtenChapters)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "memoryBuckets_\(id)")
            }
        }
    }

    // MARK: - Strand Weave State

    var strandWeaveState: StrandWeaveState {
        get {
            if let data = UserDefaults.standard.data(forKey: "strandWeave_\(id)"),
               let state = try? JSONDecoder().decode(StrandWeaveState.self, from: data) {
                return state
            }
            return .empty
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "strandWeave_\(id)")
            }
        }
    }

    // MARK: - Review History

    var lastReviewResult: ChapterReviewResult? {
        get {
            if let data = UserDefaults.standard.data(forKey: "lastReview_\(id)"),
               let result = try? JSONDecoder().decode(ChapterReviewResult.self, from: data) {
                return result
            }
            return nil
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: "lastReview_\(id)")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastReview_\(id)")
            }
        }
    }

    // MARK: - Anti-Patterns (accumulated from reviews)

    var accumulatedAntiPatterns: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: "antiPatterns_\(id)") ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "antiPatterns_\(id)")
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
        GenreTemplateLibrary.autoDetect(from: genre)
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

    /// Build the full memory context for writing, combining structured buckets
    /// with existing notes.
    var enhancedMemoryContext: String {
        var sections: [String] = []

        // Structured memory (high priority)
        let buckets = memoryBuckets
        if buckets.totalActiveCount > 0 {
            sections.append("【结构化记忆】\n\(buckets.formattedForContext)")
        }

        // Legacy continuity notes (backward compat)
        if hasContinuityNotes {
            sections.append("【全局记忆】\n\(continuityNotes)")
        }

        // Global memory snapshot
        if globalMemorySnapshot.hasStructuredContent {
            sections.append("【记忆快照】\n\(globalMemorySnapshot.formattedText)")
        }

        return sections.isEmpty ? "暂无记忆上下文。" : sections.joined(separator: "\n\n")
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
