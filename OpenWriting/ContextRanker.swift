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

nonisolated enum RankedContextBudget {
    static let maximumCharacters = 16_000
    private static let truncationMarker = "\n[本节上下文已截断]"
    private static let omissionMarker = "\n\n[其余低优先级上下文因总预算已省略]"

    static func render(
        _ sections: [ContextSection],
        maximumCharacters: Int = maximumCharacters
    ) -> String {
        guard maximumCharacters > 0 else { return "" }
        var rendered = ""

        for (index, section) in sections.enumerated() {
            let header = "\n\n\(section.label)：\n"
            let remainingBeforeHeader = maximumCharacters - rendered.count
            guard remainingBeforeHeader >= header.count else {
                appendMarker(omissionMarker, to: &rendered, limit: maximumCharacters)
                break
            }

            let laterSections = sections.dropFirst(index + 1)
            let currentMinimum = min(
                section.content.count,
                minimumReservedContentCharacters(for: section.category)
            )
            let maximumLaterReservation = max(
                0,
                remainingBeforeHeader - header.count - currentMinimum
            )
            let laterReservation = min(
                reservedCharacters(for: laterSections),
                maximumLaterReservation
            )
            let contentBudget = max(
                0,
                remainingBeforeHeader - header.count - laterReservation
            )
            guard contentBudget > 0 else {
                continue
            }

            rendered += header
            guard section.content.count > contentBudget else {
                rendered += section.content
                continue
            }

            appendTruncated(
                section.content,
                to: &rendered,
                contentBudget: contentBudget
            )
        }

        return rendered
    }

    private static func reservedCharacters(
        for sections: ArraySlice<ContextSection>
    ) -> Int {
        sections.reduce(into: 0) { total, section in
            let minimumContent = min(
                section.content.count,
                minimumReservedContentCharacters(for: section.category)
            )
            guard minimumContent > 0 else { return }
            total += "\n\n\(section.label)：\n".count + minimumContent
        }
    }

    private static func minimumReservedContentCharacters(
        for category: ContextSection.Category
    ) -> Int {
        switch category {
        case .currentDraft:
            return 768
        case .chapterTree, .enhancedMemory:
            return 512
        case .activeThreads, .specialRequirements:
            return 384
        case .strandContext:
            return 256
        case .styleFingerprint,
             .outline,
             .volumePlan,
             .genreTemplate,
             .narrativeStage,
             .manualReference,
             .retrievedReferences,
             .other:
            return 0
        }
    }

    private static func appendTruncated(
        _ content: String,
        to rendered: inout String,
        contentBudget: Int
    ) {
        guard contentBudget > truncationMarker.count else {
            rendered += String(truncationMarker.prefix(contentBudget))
            return
        }

        let availableContent = contentBudget - truncationMarker.count
        let prefixBudget = (availableContent * 2) / 3
        let suffixBudget = availableContent - prefixBudget
        rendered += String(content.prefix(prefixBudget))
        rendered += truncationMarker
        rendered += String(content.suffix(suffixBudget))
    }

    private static func appendMarker(_ marker: String, to text: inout String, limit: Int) {
        let remaining = max(0, limit - text.count)
        text += String(marker.prefix(remaining))
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
    private static let maxExtractedEntities = 256
    private static let maxWindowsPerRun = 48

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

        let scored: [(section: ContextSection, score: Double, originalIndex: Int)] = rankable
            .enumerated()
            .map { entry in
                let (originalIndex, section) = entry
                let recency       = recencyScore(for: section)
                let entityOverlap = entityOverlapScore(for: section, entities: currentEntities)
                let signal        = signalStrengthScore(for: section)

                let total = recency       * recencyWeight
                          + entityOverlap * entityOverlapWeight
                          + signal        * signalStrengthWeight
                return (section, total, originalIndex)
            }

        let ranked = scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.originalIndex < rhs.originalIndex
                }
                return lhs.score > rhs.score
            }
            .map(\.section)

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

        let normalizedCurrentEntities = normalizedEntitySet(currentEntities)
        let normalizedSectionEntities = normalizedEntitySet(sectionEntities)
        let intersection = normalizedCurrentEntities.intersection(normalizedSectionEntities)

        let recall    = Double(intersection.count) / Double(normalizedCurrentEntities.count)
        let precision = Double(intersection.count) / Double(normalizedSectionEntities.count)

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

    /// Extract candidate entity tokens from CJK and mixed-script text.
    /// CJK windows are retained for recall, while Latin/digit runs and identifiers
    /// such as `XJ-9` or `A区7号` are preserved as entity candidates.
    static func extractEntities(from text: String) -> Set<String> {
        var entities = Set<String>()
        var cjkBuffer = [Unicode.Scalar]()
        var mixedBuffer = [Unicode.Scalar]()
        var pendingConnector: Unicode.Scalar?

        for scalar in text.unicodeScalars {
            if entities.count >= maxExtractedEntities {
                break
            }

            if isEntityCore(scalar) {
                if let pendingConnector, !mixedBuffer.isEmpty {
                    mixedBuffer.append(pendingConnector)
                }
                pendingConnector = nil
                mixedBuffer.append(scalar)

                if isCJK(scalar) {
                    cjkBuffer.append(scalar)
                } else {
                    flushEntityBuffer(&cjkBuffer, into: &entities)
                }
            } else if isEntityConnector(scalar), !mixedBuffer.isEmpty {
                flushEntityBuffer(&cjkBuffer, into: &entities)
                pendingConnector = scalar
            } else {
                pendingConnector = nil
                flushEntityBuffer(&cjkBuffer, into: &entities)
                flushMixedEntityBuffer(&mixedBuffer, into: &entities)
            }
        }
        flushEntityBuffer(&cjkBuffer, into: &entities)
        flushMixedEntityBuffer(&mixedBuffer, into: &entities)
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
        let full = buffer.map(String.init).joined()
        if full.count >= 2 && full.count <= 8 {
            entities.insert(full)
        }
        if buffer.count >= 4 {
            let maxStartIndex = buffer.count - 2
            let step = max(1, maxStartIndex / maxWindowsPerRun)
            var emittedWindows = 0
            var i = 0
            while i <= maxStartIndex
                && emittedWindows < maxWindowsPerRun
                && entities.count < maxExtractedEntities {
                let bigram = String(buffer[i]) + String(buffer[i + 1])
                entities.insert(bigram)
                emittedWindows += 1
                i += step
            }
        }
        buffer.removeAll()
    }

    private static func flushMixedEntityBuffer(
        _ buffer: inout [Unicode.Scalar],
        into entities: inout Set<String>
    ) {
        defer { buffer.removeAll() }
        guard entities.count < maxExtractedEntities else { return }

        func insertCandidate(_ candidate: [Unicode.Scalar]) {
            let coreScalars = candidate.filter(isEntityCore)
            guard entities.count < maxExtractedEntities,
                  coreScalars.contains(where: { !isCJK($0) }),
                  (2...64).contains(coreScalars.count) else {
                return
            }
            entities.insert(candidate.map(String.init).joined())
        }

        insertCandidate(buffer)

        var index = 0
        while index < buffer.count {
            guard isNonCJKAlphanumeric(buffer[index]) else {
                index += 1
                continue
            }

            let start = index
            var end = index
            while end + 1 < buffer.count {
                if isNonCJKAlphanumeric(buffer[end + 1]) {
                    end += 1
                } else if isEntityConnector(buffer[end + 1]),
                          end + 2 < buffer.count,
                          isNonCJKAlphanumeric(buffer[end + 2]) {
                    end += 2
                } else {
                    break
                }
            }

            let component = Array(buffer[start...end])
            insertCandidate(component)

            var rightCandidate = component
            var rightIndex = end + 1
            var appendedRightCJK = 0
            while rightIndex < buffer.count, isCJK(buffer[rightIndex]), appendedRightCJK < 2 {
                rightCandidate.append(buffer[rightIndex])
                insertCandidate(rightCandidate)
                appendedRightCJK += 1
                rightIndex += 1
            }

            if start > 0, isCJK(buffer[start - 1]) {
                var surroundingCandidate = [buffer[start - 1]] + component
                insertCandidate(surroundingCandidate)
                if end + 1 < buffer.count, isCJK(buffer[end + 1]) {
                    surroundingCandidate.append(buffer[end + 1])
                    insertCandidate(surroundingCandidate)
                }
            }

            index = end + 1
        }
    }

    private static func normalizedEntitySet(_ entities: Set<String>) -> Set<String> {
        Set(entities.map {
            $0.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ).lowercased()
        })
    }

    private static func isEntityCore(_ scalar: Unicode.Scalar) -> Bool {
        isCJK(scalar) || isNonCJKAlphanumeric(scalar)
    }

    private static func isNonCJKAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        !isCJK(scalar)
            && (CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar))
    }

    private static func isEntityConnector(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "-" || scalar == "_" || scalar == "." || scalar == "·" || scalar == "・"
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (v >= 0x4E00 && v <= 0x9FFF)
            || (v >= 0x3400 && v <= 0x4DBF)
            || (v >= 0xF900 && v <= 0xFAFF)
            || (v >= 0x20000 && v <= 0x2A6DF)
            || (v >= 0x2A700 && v <= 0x2B73F)
            || (v >= 0x2B740 && v <= 0x2B81F)
            || (v >= 0x2B820 && v <= 0x2CEAF)
            || (v >= 0x2CEB0 && v <= 0x2EBEF)
            || (v >= 0x30000 && v <= 0x3134F)
    }
}
