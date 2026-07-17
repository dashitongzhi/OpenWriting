import Foundation

nonisolated enum StorageHealthStatus: String, Codable, Hashable {
    case passed
    case warning
    case blocked

    var displayName: String {
        switch self {
        case .passed: return "健康"
        case .warning: return "需关注"
        case .blocked: return "需恢复"
        }
    }
}

nonisolated enum ProjectStorageIssueKind: String, Codable, Hashable {
    case projectIndexMissing
    case projectIndexCorrupt
    case projectMetadataMissing
    case projectMetadataCorrupt
    case chapterIndexMissing
    case chapterIndexCorrupt
    case chapterFileMissing
    case chapterFileCorrupt
    case orphanChapterFile
    case catalogFileMismatch
    case legacyProjectFile
    case cloudSelectionConflict
}

nonisolated enum StorageRecoveryAction: String, Codable, Hashable, CaseIterable, Identifiable {
    case exportDiagnostics
    case rebuildChapterCatalog
    case preserveMissingChapterPlaceholder
    case recoverMetadataShell
    case markCloudConflict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exportDiagnostics: return "导出诊断"
        case .rebuildChapterCatalog: return "重建目录"
        case .preserveMissingChapterPlaceholder: return "保留占位"
        case .recoverMetadataShell: return "恢复项目壳"
        case .markCloudConflict: return "标记冲突"
        }
    }
}

nonisolated struct ProjectStorageIssue: Identifiable, Codable, Hashable {
    var id: String
    var kind: ProjectStorageIssueKind
    var status: StorageHealthStatus
    var projectID: NovelProject.ID
    var chapterID: ChapterDraft.ID?
    var title: String
    var detail: String
    var recoveryActions: [StorageRecoveryAction]
}

nonisolated struct StorageHealthReport: Identifiable, Codable, Hashable {
    var id: String
    var projectID: NovelProject.ID
    var scopeName: String
    var checkedAt: Date
    var status: StorageHealthStatus
    var summary: String
    var nextAction: String
    var issues: [ProjectStorageIssue]
    var metrics: [String: String]

    var blockingIssues: [ProjectStorageIssue] {
        issues.filter { $0.status == .blocked }
    }

    var warningIssues: [ProjectStorageIssue] {
        issues.filter { $0.status == .warning }
    }

    var hasIssues: Bool {
        !issues.isEmpty
    }
}

nonisolated struct StorageRecoveryResult: Codable, Hashable {
    var action: StorageRecoveryAction
    var issueID: ProjectStorageIssue.ID
    var didChangeStore: Bool
    var message: String
    var outputURL: URL?
}
