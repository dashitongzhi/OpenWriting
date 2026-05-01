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
            let pid = id
            Self.cacheLock.lock()
            if let cached = Self.memoryBucketsCache[pid] {
                Self.cacheLock.unlock()
                return cached
            }
            Self.cacheLock.unlock()

            let decoded: MemoryBuckets
            if let data = UserDefaults.standard.data(forKey: "memoryBuckets_\(pid)"),
               let buckets = try? JSONDecoder().decode(MemoryBuckets.self, from: data) {
                decoded = buckets
            } else {
                decoded = MemoryBuckets.migrate(from: globalMemorySnapshot, currentChapter: writtenChapters)
            }

            Self.cacheLock.lock()
            Self.memoryBucketsCache[pid] = decoded
            Self.cacheLock.unlock()
            return decoded
        }
        set {
            let pid = id
            Self.cacheLock.lock()
            Self.memoryBucketsCache[pid] = newValue
            Self.cacheLock.unlock()
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "memoryBuckets_\(pid)")
            }
        }
    }

    // MARK: - Strand Weave State

    var strandWeaveState: StrandWeaveState {
        get {
            let pid = id
            Self.cacheLock.lock()
            if let cached = Self.strandWeaveCache[pid] {
                Self.cacheLock.unlock()
                return cached
            }
            Self.cacheLock.unlock()

            let decoded: StrandWeaveState
            if let data = UserDefaults.standard.data(forKey: "strandWeave_\(pid)"),
               let state = try? JSONDecoder().decode(StrandWeaveState.self, from: data) {
                decoded = state
            } else {
                decoded = .empty
            }

            Self.cacheLock.lock()
            Self.strandWeaveCache[pid] = decoded
            Self.cacheLock.unlock()
            return decoded
        }
        set {
            let pid = id
            Self.cacheLock.lock()
            Self.strandWeaveCache[pid] = newValue
            Self.cacheLock.unlock()
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "strandWeave_\(pid)")
            }
        }
    }

    // MARK: - Review History

    var lastReviewResult: ChapterReviewResult? {
        get {
            let pid = id
            Self.cacheLock.lock()
            if Self.lastReviewCacheLoaded.contains(pid) {
                let cached = Self.lastReviewCache[pid]
                Self.cacheLock.unlock()
                return cached ?? nil
            }
            Self.cacheLock.unlock()

            let decoded: ChapterReviewResult?
            if let data = UserDefaults.standard.data(forKey: "lastReview_\(pid)"),
               let result = try? JSONDecoder().decode(ChapterReviewResult.self, from: data) {
                decoded = result
            } else {
                decoded = nil
            }

            Self.cacheLock.lock()
            Self.lastReviewCache[pid] = decoded
            Self.lastReviewCacheLoaded.insert(pid)
            Self.cacheLock.unlock()
            return decoded
        }
        set {
            let pid = id
            Self.cacheLock.lock()
            Self.lastReviewCache[pid] = newValue
            Self.lastReviewCacheLoaded.insert(pid)
            Self.cacheLock.unlock()
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: "lastReview_\(pid)")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastReview_\(pid)")
            }
        }
    }

    // MARK: - Anti-Patterns (accumulated from reviews)

    var accumulatedAntiPatterns: [String] {
        get {
            let pid = id
            Self.cacheLock.lock()
            if let cached = Self.antiPatternsCache[pid] {
                Self.cacheLock.unlock()
                return cached
            }
            Self.cacheLock.unlock()

            let decoded = UserDefaults.standard.stringArray(forKey: "antiPatterns_\(pid)") ?? []

            Self.cacheLock.lock()
            Self.antiPatternsCache[pid] = decoded
            Self.cacheLock.unlock()
            return decoded
        }
        set {
            let pid = id
            Self.cacheLock.lock()
            Self.antiPatternsCache[pid] = newValue
            Self.cacheLock.unlock()
            UserDefaults.standard.set(newValue, forKey: "antiPatterns_\(pid)")
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
