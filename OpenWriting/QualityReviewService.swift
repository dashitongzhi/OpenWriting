import Foundation

// MARK: - Quality Review Service (Backward-Compatible Wrapper)
//
// This file provides backward compatibility for code that uses
// QualityReviewService.reviewChapter() and QualityReviewReport.
//
// The actual review logic now lives in UnifiedQualityReviewer (ChapterQualityReviewer.swift).
// This wrapper translates between the legacy QualityReviewReport format and the
// unified ChapterReviewResult format.

// MARK: - Legacy Types (kept for Codable backward compatibility)

/// Legacy review dimension (pre-unification). Kept for Codable compatibility.
enum LegacyQualityReviewDimension: String, Codable, CaseIterable, Identifiable {
    case highPoint = "爽点密度"
    case consistency = "设定一致性"
    case characterOOC = "角色OOC"
    case pacing = "节奏比例"
    case continuity = "叙事连贯"
    case readerPull = "追读力"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .highPoint: return "🎯"
        case .consistency: return "🔒"
        case .characterOOC: return "🎭"
        case .pacing: return "📐"
        case .continuity: return "🔗"
        case .readerPull: return "🪝"
        }
    }

    var description: String {
        switch self {
        case .highPoint: return "检查章节中爽点的密度与质量，是否能持续吸引读者"
        case .consistency: return "检查战力、地点、时间线等设定是否前后矛盾"
        case .characterOOC: return "检查人物行为是否偏离既定人设（Out of Character）"
        case .pacing: return "检查主线、感情线、世界观扩展的比例是否合理"
        case .continuity: return "检查场景切换与叙事逻辑是否通顺"
        case .readerPull: return "检查钩子强度、期待管理、微兑现是否到位"
        }
    }

    /// Map to unified ReviewDimension
    var unifiedDimension: ReviewDimension {
        switch self {
        case .highPoint:   return .highPointDensity
        case .consistency: return .settingConsistency
        case .characterOOC: return .characterConsistency
        case .pacing:      return .pacing
        case .continuity:  return .narrativeContinuity
        case .readerPull:  return .readerPull
        }
    }
}

/// Legacy dimension result (pre-unification). Kept for Codable compatibility.
struct ReviewDimensionResult: Codable, Identifiable {
    let dimension: LegacyQualityReviewDimension
    let score: Int // 1-10
    let issues: [LegacyQualityReviewIssue]
    let summary: String

    var id: String { dimension.rawValue }

    var grade: ReviewGrade {
        switch score {
        case 8...10: return .excellent
        case 6...7:  return .good
        case 4...5:  return .fair
        default:     return .poor
        }
    }
}

/// Legacy issue severity (pre-unification). Kept for Codable compatibility.
enum LegacyIssueSeverity: String, Codable {
    case critical = "严重"
    case major = "重要"
    case minor = "轻微"

    /// Map to unified ReviewSeverity
    var unified: ReviewSeverity {
        switch self {
        case .critical: return .critical
        case .major:    return .high
        case .minor:    return .low
        }
    }
}

/// Legacy issue (pre-unification). Kept for Codable compatibility.
struct LegacyQualityReviewIssue: Codable, Identifiable {
    let id: UUID
    let severity: LegacyIssueSeverity
    let description: String
    let suggestion: String

    init(severity: LegacyIssueSeverity, description: String, suggestion: String) {
        self.id = UUID()
        self.severity = severity
        self.description = description
        self.suggestion = suggestion
    }
}

// MARK: - QualityReviewReport (Backward-Compatible, now wraps ChapterReviewResult)

/// Legacy report format, stored in NovelProject.qualityReviewReports.
/// Now constructed from the unified ChapterReviewResult.
struct QualityReviewReport: Codable, Identifiable {
    let id: UUID
    let chapterNumber: Int
    let chapterTitle: String
    let reviewedAt: Date
    let dimensionResults: [ReviewDimensionResult]
    let overallScore: Int
    let overallSummary: String

    /// The unified review result this report was built from.
    /// Transient — not persisted, reconstructed from dimensionResults.
    var unifiedResult: ChapterReviewResult? {
        // Build dimension scores from legacy results
        var dimensionScores: [ReviewDimension: Int] = [:]
        var issues: [ReviewIssue] = []
        for result in dimensionResults {
            let unifiedDim = result.dimension.unifiedDimension
            dimensionScores[unifiedDim] = result.score
            for issue in result.issues {
                issues.append(ReviewIssue(
                    dimension: unifiedDim,
                    severity: issue.severity.unified,
                    description: issue.description,
                    fixHint: issue.suggestion
                ))
            }
        }
        let hasBlocking = issues.contains { $0.isBlocking }
        return ChapterReviewResult(
            overallScore: overallScore,
            dimensionScores: dimensionScores,
            issues: issues,
            hasBlockingIssues: hasBlocking,
            antiPatterns: [],
            overallSummary: overallSummary
        )
    }

    init(chapterNumber: Int, chapterTitle: String, dimensionResults: [ReviewDimensionResult], overallSummary: String) {
        self.id = UUID()
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.reviewedAt = Date()
        self.dimensionResults = dimensionResults
        let scores = dimensionResults.map { $0.score }
        self.overallScore = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        self.overallSummary = overallSummary
    }

    /// Build from unified ChapterReviewResult (preferred constructor).
    init(chapterNumber: Int, chapterTitle: String, unifiedResult: ChapterReviewResult) {
        self.id = UUID()
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.reviewedAt = Date()
        self.overallScore = unifiedResult.overallScore
        self.overallSummary = unifiedResult.overallSummary

        // Convert unified results to legacy dimension results
        var results: [ReviewDimensionResult] = []
        for legacyDim in LegacyQualityReviewDimension.allCases {
            let unifiedDim = legacyDim.unifiedDimension
            let score = unifiedResult.dimensionScores[unifiedDim] ?? 80
            let dimIssues = unifiedResult.issues
                .filter { $0.dimension == unifiedDim }
                .map { issue -> LegacyQualityReviewIssue in
                    let legacySev: LegacyIssueSeverity
                    switch issue.severity {
                    case .critical: legacySev = .critical
                    case .high:     legacySev = .major
                    case .medium, .low: legacySev = .minor
                    }
                    return LegacyQualityReviewIssue(
                        severity: legacySev,
                        description: issue.description,
                        suggestion: issue.fixHint
                    )
                }
            results.append(ReviewDimensionResult(
                dimension: legacyDim,
                score: score,
                issues: dimIssues,
                summary: ""
            ))
        }
        self.dimensionResults = results
    }

    /// Whether the chapter passes (no critical issues, score >= 6).
    var isPassed: Bool {
        let hasCritical = dimensionResults.contains { result in
            result.issues.contains { $0.severity == .critical }
        }
        return !hasCritical && overallScore >= 6
    }

    /// All issues sorted by severity.
    var allIssues: [LegacyQualityReviewIssue] {
        dimensionResults.flatMap { $0.issues }
            .sorted { a, b in
                let order: [LegacyIssueSeverity] = [.critical, .major, .minor]
                return (order.firstIndex(of: a.severity) ?? 99) < (order.firstIndex(of: b.severity) ?? 99)
            }
    }
}

// MARK: - QualityReviewService (Delegates to UnifiedQualityReviewer)

/// Legacy entry point for quality review.
/// Delegates to the unified system and wraps results in QualityReviewReport.
enum QualityReviewService {

    /// Review a chapter using the unified 9-dimension system.
    /// Returns a QualityReviewReport for backward compatibility with NovelProject.qualityReviewReports.
    static func reviewChapter(
        chapterTitle: String,
        chapterContent: String,
        chapterNumber: Int,
        project: NovelProject,
        configuration: AIConnectionConfiguration
    ) async throws -> QualityReviewReport {

        let unifiedResult = try await UnifiedQualityReviewer.reviewChapter(
            project: project,
            chapterDraft: chapterContent,
            memoryContext: project.globalMemorySnapshot.formattedText,
            configuration: configuration
        )

        return QualityReviewReport(
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            unifiedResult: unifiedResult
        )
    }
}
