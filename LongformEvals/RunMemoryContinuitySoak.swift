import Foundation

@main
struct MemoryContinuitySoakCLI {
    static func main() {
        do {
            let options = try SoakOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            let scorecard = try MemoryContinuitySoak.run(options: options)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(scorecard)
            try FileManager.default.createDirectory(
                at: options.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: options.outputURL)

            print("Memory continuity soak: \(options.outputURL.path)")
            print("characters=\(scorecard.totalDraftCharacters) contradictions=\(scorecard.memoryContradictions) retrieval_misses=\(scorecard.workingMemoryRetrievalMisses) passed=\(scorecard.passed)")
            guard scorecard.passed else { Foundation.exit(1) }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct SoakOptions {
    var chapters = 2_000
    var charactersPerChapter = 1_100
    var outputURL = URL(fileURLWithPath: "LongformEvals/runs/memory-continuity-soak.json")

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--chapters":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
                    throw SoakError.message("--chapters requires a positive integer")
                }
                chapters = value
                index += 2
            case "--characters-per-chapter":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value >= 200 else {
                    throw SoakError.message("--characters-per-chapter requires an integer of at least 200")
                }
                charactersPerChapter = value
                index += 2
            case "--output":
                guard index + 1 < arguments.count else {
                    throw SoakError.message("--output requires a path")
                }
                outputURL = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            default:
                throw SoakError.message("unknown argument \(arguments[index])")
            }
        }
    }
}

private enum MemoryContinuitySoak {
    static func run(options: SoakOptions) throws -> SoakScorecard {
        var buckets = MemoryBuckets.empty
        var totalDraftCharacters = 0
        var chapterSamplingFailures = 0
        var retrievalChecks = 0
        var retrievalMisses = 0
        var serializationFailures = 0
        var backfillFailures = 0
        var archiveRetrievalFailures = 0

        for chapter in 1...options.chapters {
            let volume = max(1, (chapter - 1) / 100 + 1)
            let chapterText = SyntheticChapter.text(
                chapter: chapter,
                characterCount: options.charactersPerChapter
            )
            totalDraftCharacters += chapterText.count
            let sampledText = MemoryExtractionService.sampledChapterText(
                chapterText,
                limit: min(800, options.charactersPerChapter)
            )
            if !sampledText.contains("章首状态")
                || !sampledText.contains("章中规则")
                || !sampledText.contains("章末伏笔") {
                chapterSamplingFailures += 1
            }

            let extraction = MemoryExtractionService.ExtractionResult(
                characterStates: [
                    .init(
                        subject: "林照",
                        field: "调查阶段",
                        value: "第\(chapter)章已取得新证据并承担代价",
                        evidence: "章首状态"
                    )
                ],
                worldRules: chapter == 1 ? [
                    .init(
                        subject: "月潮法则",
                        field: "限制",
                        value: "银色纹路只能在月潮下显现",
                        evidence: "章中规则"
                    )
                ] : [],
                storyFacts: [
                    .init(
                        subject: "第\(chapter)章证据",
                        field: "调查记录",
                        value: "本章新增可复查证据编号 \(chapter)",
                        evidence: "章中规则"
                    )
                ],
                timeline: [
                    .init(
                        subject: "第\(chapter)日",
                        field: "时间推进",
                        value: "调查进入第\(chapter)个连续节点",
                        evidence: "章中规则"
                    )
                ],
                openLoops: [
                    .init(
                        subject: "银色纹路",
                        field: "血脉真相",
                        value: "银色纹路推进至第\(chapter)章，真正来源仍待回收",
                        evidence: "章末伏笔"
                    )
                ],
                chapterNumber: chapter
            )
            for item in extraction.allItems(
                sourceVolumeNumber: volume,
                sourceChapterNumber: chapter
            ) {
                buckets.upsert(item)
            }

            if chapter > 250, chapter.isMultiple(of: 250) {
                let activeBeforeBackfill = buckets.characterState.first { $0.status == .active }
                buckets.upsert(MemoryItem(
                    id: "backfill-\(chapter)",
                    category: .characterState,
                    subject: "林照",
                    field: "调查阶段",
                    value: "旧章回填：仍在核对最初线索",
                    sourceVolumeNumber: max(1, volume - 1),
                    sourceChapter: max(1, chapter - 150)
                ))
                if buckets.characterState.first(where: { $0.status == .active })?.id != activeBeforeBackfill?.id {
                    backfillFailures += 1
                }
                let archiveContext = buckets.formattedForWorkingContext(
                    buckets.workingContextItems(for: "林照旧章回填最初线索")
                )
                if !archiveContext.contains("旧章回填") || !archiveContext.contains("已过期") {
                    archiveRetrievalFailures += 1
                }
            }

            if chapter.isMultiple(of: 10) || chapter == options.chapters {
                buckets.compact(currentVolumeNumber: volume, currentChapter: chapter)
                retrievalChecks += 1

                let workingItems = buckets.workingContextItems(
                    for: "林照继续调查银色纹路与血脉真相，确认月潮法则",
                    relevantLimit: 16,
                    totalLimit: 26
                )
                let workingContext = buckets.formattedForWorkingContext(workingItems)
                if !workingContext.contains("真正来源仍待回收")
                    || !workingContext.contains("月潮法则") {
                    retrievalMisses += 1
                }
            }

            if chapter.isMultiple(of: 100) || chapter == options.chapters {
                guard let encoded = try? JSONEncoder().encode(buckets),
                      (try? JSONDecoder().decode(MemoryBuckets.self, from: encoded)) != nil
                else {
                    serializationFailures += 1
                    continue
                }
            }
        }

        let activeCharacter = buckets.characterState.first { $0.status == .active }
        let activeForeshadow = buckets.openLoops.first { $0.status == .active }
        let memoryContradictions = buckets.conflicts.count
        let finalCharacterStateIsCurrent = activeCharacter?.sourceChapter == options.chapters
        let finalForeshadowingStateIsCurrent = activeForeshadow?.sourceChapter == options.chapters
        let passed = totalDraftCharacters >= 2_000_000
            && memoryContradictions == 0
            && chapterSamplingFailures == 0
            && retrievalMisses == 0
            && serializationFailures == 0
            && backfillFailures == 0
            && archiveRetrievalFailures == 0
            && finalCharacterStateIsCurrent
            && finalForeshadowingStateIsCurrent
        return SoakScorecard(
            chapters: options.chapters,
            charactersPerChapter: options.charactersPerChapter,
            totalDraftCharacters: totalDraftCharacters,
            finalVolumeNumber: max(1, (options.chapters - 1) / 100 + 1),
            activeMemoryCount: buckets.totalActiveCount,
            memoryContradictions: memoryContradictions,
            chapterSamplingFailures: chapterSamplingFailures,
            workingMemoryRetrievalChecks: retrievalChecks,
            workingMemoryRetrievalMisses: retrievalMisses,
            serializationFailures: serializationFailures,
            backfillFailures: backfillFailures,
            archiveRetrievalFailures: archiveRetrievalFailures,
            finalCharacterStateIsCurrent: finalCharacterStateIsCurrent,
            finalForeshadowingStateIsCurrent: finalForeshadowingStateIsCurrent,
            passed: passed
        )
    }
}

private enum SyntheticChapter {
    static func text(chapter: Int, characterCount: Int) -> String {
        let opening = "章首状态：林照承接第\(chapter)章调查压力。"
        let middle = "章中规则：月潮法则继续限制银色纹路。"
        let ending = "章末伏笔：血脉真正来源仍待回收。"
        let fixedCount = opening.count + middle.count + ending.count
        let padding = max(characterCount - fixedCount, 0)
        let openingPadding = padding / 2
        let endingPadding = padding - openingPadding
        return opening
            + String(repeating: "甲", count: openingPadding)
            + middle
            + String(repeating: "乙", count: endingPadding)
            + ending
    }
}

private struct SoakScorecard: Encodable {
    let chapters: Int
    let charactersPerChapter: Int
    let totalDraftCharacters: Int
    let finalVolumeNumber: Int
    let activeMemoryCount: Int
    let memoryContradictions: Int
    let chapterSamplingFailures: Int
    let workingMemoryRetrievalChecks: Int
    let workingMemoryRetrievalMisses: Int
    let serializationFailures: Int
    let backfillFailures: Int
    let archiveRetrievalFailures: Int
    let finalCharacterStateIsCurrent: Bool
    let finalForeshadowingStateIsCurrent: Bool
    let passed: Bool
}

private enum SoakError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): return message
        }
    }
}
