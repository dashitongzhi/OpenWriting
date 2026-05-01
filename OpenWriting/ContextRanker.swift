import Foundation

// MARK: - Context Section for Ranking

/// Represents a single context section that can be scored and reordered
/// before being assembled into the LLM prompt.
struct ContextSection {
    let label: String       // Section header (e.g. "章节树关键约束")
    let content: String     // The rendered text block
    let category: Category  // Used for scoring heuristics

    enum Category: String {
        case currentDraft         // Always pinned at top
        case chapterTree          // Chapter tree constraints
        case styleFingerprint     // Style guide
        case enhancedMemory       // Long-term memory
        case outline              // Story outline
        case volumePlan           // Volume/arc planning
        case activeThreads        // Active narrative threads
        case strandContext        // Strand weave monitoring
        case genreTemplate        // Genre configuration
        case narrativeStage       // Narrative stage directives
        case manualReference      // Manual reference text
        case retrievedReferences  // BM25-retrieved references
        case specialRequirements  // Special requirements
        case other                // Catch-all
    }
}

// MARK: - Context Ranker

/// Scores and reorders context sections by relevance before they are
/// assembled into the system/user prompt.
///
/// Three scoring dimensions are combined:
///  - **Recency**: sections that update per-save (chapter tree, memory) rank higher
///  - **Entity overlap**: sections sharing character/place tokens with the current chapter rank higher
///  **Signal strength**: sections containing warnings, open loops, or foreshadowing rank higher
///
/// The ranker is applied only in the enhanced pipeline (`continueChapterEnhanced`);
/// the standard pipeline remains unchanged for backward compatibility.
struct ContextRanker {

    // MARK: - Weights

    private static let recencyWeight: Double       = 0.30
    private static let entityOverlapWeight: Double  = 0.40
    private static let signalStrengthWeight: Double = 0.30

    // MARK: - Public API

    /// Score and reorder context sections by relevance.
    ///
    /// Sections whose `category` is `.currentDraft` are pinned at the front
    /// and never reordered. All other sections are scored on three dimensions
    /// and returned in descending score order.
    ///
    /// - Parameters:
    ///   - sections: The context sections to rank.
    ///   - project:  The current novel project (for entity extraction & chapter number).
    /// - Returns: Sections reordered by descending relevance score.
    static func rank(_ sections: [ContextSection], project: NovelProject) -> [ContextSection] {
        let pinnedCategories: Set<ContextSection.Category> = [.currentDraft]

        var pinned  = [ContextSection]()
        var rankable = [ContextSection]()
        for section in sections {
            if pinnedCategories.contains(section.category) {
                pinned.append(section)
            } else {
                rankable.append(section)
            }
        }

        guard rankable.count > 1 else { return sections }

        // Build entity set from current chapter context
        let currentEntities = extractEntities(from: [
            project.currentChapterSummary,
            project.chapterFocus,
            project.draftText
        ].joined(separator: "\n"))

        let scored: [(ContextSection, Double)] = rankable.map { section in
            let recency       = recencyScore(for: section)
            let entityOverlap = entityOverlapScore(for: section, entities: currentEntities)
            let signal        = signalStrengthScore(for: section)

            let total = recency       * recencyWeight
                      + entityOverlap * entityOverlapWeight
                      + signal        * signalStrengthWeight
            return (section, total)
        }

        let ranked = scored
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }

        return pinned + ranked
    }

    // MARK: - Recency Score

    /// Heuristic recency: how recently is this type of section typically updated?
    /// Per-save sections score highest; static project config scores lowest.
    private static func recencyScore(for section: ContextSection) -> Double {
        switch section.category {
        case .currentDraft:         return 1.00
        case .chapterTree:          return 0.95   // refreshed every save
        case .enhancedMemory:       return 0.90   // refreshed every save
        case .activeThreads:        return 0.85   // updated periodically
        case .strandContext:        return 0.80   // per-write analysis
        case .retrievedReferences:  return 0.72   // BM25-rank already relevant
        case .narrativeStage:       return 0.65   // semi-static
        case .styleFingerprint:     return 0.60   // changes slowly
        case .volumePlan:           return 0.55   // per-arc updates
        case .genreTemplate:        return 0.50   // static per project
        case .outline:              return 0.45   // relatively static
        case .manualReference:      return 0.40   // user-set, may be stale
        case .specialRequirements:  return 0.35   // user-set, may be stale
        case .other:                return 0.30
        }
    }

    // MARK: - Entity Overlap Score

    /// Measures how many character / place / concept tokens overlap between
    /// the section and the current chapter context.
    private static func entityOverlapScore(
        for section: ContextSection,
        entities currentEntities: Set<String>
    ) -> Double {
        guard !currentEntities.isEmpty else { return 0.5 }  // neutral

        let sectionEntities = extractEntities(from: section.content)
        guard !sectionEntities.isEmpty else { return 0.0 }

        let intersection = currentEntities.intersection(sectionEntities)

        let recall    = Double(intersection.count) / Double(currentEntities.count)
        let precision = Double(intersection.count) / Double(sectionEntities.count)

        guard recall + precision > 0 else { return 0.0 }
        // F1-like score
        return 2.0 * recall * precision / (recall + precision)
    }

    // MARK: - Signal Strength Score

    /// Sections containing warnings, open loops, or active foreshadowing
    /// score higher because the LLM needs to be aware of unresolved threads.
    private static func signalStrengthScore(for section: ContextSection) -> Double {
        let content = section.content
        var score: Double = 0.0

        // Warning / danger indicators
        let warningKeywords = ["警告", "注意", "隐患", "矛盾", "⚠", "待回收", "待解决", "未完成", "红线"]
        for kw in warningKeywords where content.contains(kw) {
            score += 0.08
        }

        // Open-loop / foreshadowing indicators
        let loopKeywords = ["伏笔", "悬念", "埋下", "待揭晓", "线索", "暗示", "伏线", "暗线", "未回收"]
        for kw in loopKeywords where content.contains(kw) {
            score += 0.10
        }

        // Active conflict / tension indicators
        let tensionKeywords = ["对峙", "危机", "冲突", "转折", "变化", "升级", "突破", "真相", "反转"]
        for kw in tensionKeywords where content.contains(kw) {
            score += 0.06
        }

        // Penalty for placeholder / empty content
        if content.contains("暂无") || content.contains("暂无明确变化") {
            score -= 0.15
        }

        return min(1.0, max(0.0, score))
    }

    // MARK: - Entity Extraction

    /// Extract candidate entity tokens from CJK text.
    /// Sequences of 2–6 contiguous CJK characters are treated as entity candidates.
    static func extractEntities(from text: String) -> Set<String> {
        var entities = Set<String>()
        var buffer = [Unicode.Scalar]()

        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                buffer.append(scalar)
            } else {
                flushEntityBuffer(&buffer, into: &entities)
            }
        }
        flushEntityBuffer(&buffer, into: &entities)
        return entities
    }

    private static func flushEntityBuffer(
        _ buffer: inout [Unicode.Scalar],
        into entities: inout Set<String>
    ) {
        guard buffer.count >= 2 else {
            buffer.removeAll()
            return
        }
        // Emit the full run and all 2-char sub-windows for better recall
        let full = String(Unicode.ScalarView(buffer))
        if full.count >= 2 && full.count <= 8 {
            entities.insert(full)
        }
        if buffer.count >= 4 {
            for i in 0...(buffer.count - 2) {
                let bigram = String(Unicode.ScalarView([buffer[i], buffer[i + 1]]))
                entities.insert(bigram)
            }
        }
        buffer.removeAll()
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (v >= 0x4E00 && v <= 0x9FFF)
            || (v >= 0x3400 && v <= 0x4DBF)
            || (v >= 0xF900 && v <= 0xFAFF)
            || (v >= 0x20000 && v <= 0x2A6DF)
    }
}
