import Foundation

// MARK: - NovelProject Extensions for Webnovel-Writer Integration

/// Extensions to NovelProject that add the new structured memory, pacing, and review systems.
/// These fields are stored alongside existing project data for backward compatibility.

extension NovelProject {

    // MARK: - In-Memory Cache (avoids repeated JSON decoding on every property access)

    private static let cacheLock = NSLock()
    private static var memoryBucketsCache: [String: MemoryBuckets] = [:]
    private static var strandWeaveCache: [String: StrandWeaveState] = [:]
    private static var antiPatternsCache: [String: [String]] = [:]
    private static var lastReviewCache: [String: ChapterReviewResult?] = [:]
    private static var lastReviewCacheLoaded: Set<String> = []

    /// Clear all cached data for a given project ID (called on project deletion).
    static func clearIntegrationCache(for projectID: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        memoryBucketsCache.removeValue(forKey: projectID)
        strandWeaveCache.removeValue(forKey: projectID)
        antiPatternsCache.removeValue(forKey: projectID)
        lastReviewCache.removeValue(forKey: projectID)
        lastReviewCacheLoaded.remove(projectID)
    }

    // MARK: - Memory Buckets

    /// Structured memory buckets, replacing/supplementing the flat continuityNotes.
    var memoryBuckets: MemoryBuckets {
        get {
            if let persistedMemoryBuckets {
                return persistedMemoryBuckets
            }

            if let data = UserDefaults.standard.data(forKey: "memoryBuckets_\(id)"),
               let buckets = try? JSONDecoder().decode(MemoryBuckets.self, from: data) {
                return buckets
            }

            return MemoryBuckets.migrate(from: globalMemorySnapshot, currentChapter: writtenChapters)
        }
        set {
            persistedMemoryBuckets = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "memoryBuckets_\(id)")
            }
        }
    }

    // MARK: - Strand Weave State

    var strandWeaveState: StrandWeaveState {
        get {
            if let persistedStrandWeaveState {
                return persistedStrandWeaveState
            }

            if let data = UserDefaults.standard.data(forKey: "strandWeave_\(id)"),
               let state = try? JSONDecoder().decode(StrandWeaveState.self, from: data) {
                return state
            }

            return .empty
        }
        set {
            persistedStrandWeaveState = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "strandWeave_\(id)")
            }
        }
    }

    // MARK: - Review History

    var lastReviewResult: ChapterReviewResult? {
        get {
            if let persistedLastReviewResult {
                return persistedLastReviewResult
            }

            if let data = UserDefaults.standard.data(forKey: "lastReview_\(id)"),
               let result = try? JSONDecoder().decode(ChapterReviewResult.self, from: data) {
                return result
            }

            return nil
        }
        set {
            persistedLastReviewResult = newValue
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
            if let persistedAntiPatterns {
                return persistedAntiPatterns
            }

            return UserDefaults.standard.stringArray(forKey: "antiPatterns_\(id)") ?? []
        }
        set {
            persistedAntiPatterns = newValue
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

    /// Build the full memory context for writing, combining structured buckets
    /// with existing notes.
    var enhancedMemoryContext: String {
        var sections: [String] = []

        // Structured memory (high priority)
        let buckets = memoryBuckets
        if buckets.totalActiveCount > 0 {
            sections.append("【结构化记忆】\n\(buckets.formattedForContext)")
        }

        // Global memory snapshot (parsed from continuityNotes) — preferred over raw notes
        if globalMemorySnapshot.hasStructuredContent {
            sections.append("【记忆快照】\n\(globalMemorySnapshot.formattedText)")
        } else if hasContinuityNotes {
            // Fallback to raw continuity notes only when snapshot lacks structured content
            sections.append("【全局记忆】\n\(continuityNotes)")
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
