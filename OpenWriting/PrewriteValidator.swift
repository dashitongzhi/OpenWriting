import Foundation

// MARK: - Pre-Write Validator (Anti-Hallucination Three Laws)

/// Validates that the project is ready for writing before AI generation begins.
/// Implements the "Three Laws" from webnovel-writer:
/// 1. 大纲即法律 — Outline must exist and be loaded
/// 2. 设定即物理 — World rules and character settings must be established
/// 3. 发明需识别 — New entities from prior chapters must be tracked in memory
struct PrewriteValidationResult {
    let isReady: Bool
    let blockingReasons: [String]
    let warnings: [String]
    let checklistItems: [PrewriteChecklistItem]

    var readySummary: String {
        if isReady {
            return warnings.isEmpty
                ? "✅ 写前验证通过，可以开始创作。"
                : "✅ 写前验证通过（有 \(warnings.count) 条建议）"
        }
        return "⛔ 写前验证未通过：\n" + blockingReasons.map { "  · \($0)" }.joined(separator: "\n")
    }
}

struct PrewriteChecklistItem: Identifiable {
    let id: String
    let label: String
    let passed: Bool
    let isBlocking: Bool
    let detail: String
}

enum PrewriteValidator {

    // MARK: - Main Validation

    static func validate(project: NovelProject) -> PrewriteValidationResult {
        var blockingReasons: [String] = []
        var warnings: [String] = []
        var checklist: [PrewriteChecklistItem] = []

        // === Law 1: 大纲即法律 ===
        checkOutline(project: project, blockingReasons: &blockingReasons, warnings: &warnings, checklist: &checklist)

        // === Law 2: 设定即物理 ===
        checkSettings(project: project, blockingReasons: &blockingReasons, warnings: &warnings, checklist: &checklist)

        // === Law 3: 发明需识别 ===
        checkEntityTracking(project: project, blockingReasons: &blockingReasons, warnings: &warnings, checklist: &checklist)

        // === Additional checks ===
        checkChapterFocus(project: project, warnings: &warnings, checklist: &checklist)
        checkContinuity(project: project, warnings: &warnings, checklist: &checklist)

        return PrewriteValidationResult(
            isReady: blockingReasons.isEmpty,
            blockingReasons: blockingReasons,
            warnings: warnings,
            checklistItems: checklist
        )
    }

    // MARK: - Law 1: Outline is Law

    private static func checkOutline(
        project: NovelProject,
        blockingReasons: inout [String],
        warnings: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        let hasOutline = !project.outlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        checklist.append(PrewriteChecklistItem(
            id: "outline_exists",
            label: "大纲已导入",
            passed: hasOutline,
            isBlocking: true,
            detail: hasOutline ? "大纲内容已就绪" : "缺少大纲，AI 将无法遵循故事结构"
        ))

        if !hasOutline {
            blockingReasons.append("大纲即法律：尚未导入大纲，无法约束 AI 的叙事方向。请先在大纲工作区导入或生成大纲。")
        }

        // Check if current chapter has a focus/goal
        let hasFocus = !project.chapterFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && project.chapterFocus != "继续补齐当前章节的目标、冲突和场景节奏。"
        checklist.append(PrewriteChecklistItem(
            id: "chapter_focus",
            label: "本章目标已设定",
            passed: hasFocus,
            isBlocking: false,
            detail: hasFocus ? "目标: \(project.chapterFocus)" : "未设定本章目标，AI 将自行判断推进方向"
        ))

        if !hasFocus {
            warnings.append("建议设定本章目标，帮助 AI 更精准地推进剧情。")
        }
    }

    // MARK: - Law 2: Settings are Physics

    private static func checkSettings(
        project: NovelProject,
        blockingReasons: inout [String],
        warnings: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        // Check if global memory or continuity notes exist
        let hasMemory = project.hasGlobalMemory
        checklist.append(PrewriteChecklistItem(
            id: "global_memory",
            label: "全局记忆已建立",
            passed: hasMemory,
            isBlocking: false,
            detail: hasMemory ? "已有角色状态和设定记录" : "尚无全局记忆，AI 可能不记得已有设定"
        ))

        if !hasMemory && project.writtenChapters > 2 {
            warnings.append("已写 \(project.writtenChapters) 章但尚无全局记忆，建议先刷新全局记忆以防止设定冲突。")
        }

        // Check genre is specified
        let hasGenre = !project.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        checklist.append(PrewriteChecklistItem(
            id: "genre_specified",
            label: "题材已指定",
            passed: hasGenre,
            isBlocking: false,
            detail: hasGenre ? "题材: \(project.genre)" : "未指定题材，AI 将使用通用写作模式"
        ))

        // Check summary
        let hasSummary = !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        checklist.append(PrewriteChecklistItem(
            id: "project_summary",
            label: "项目摘要已填写",
            passed: hasSummary,
            isBlocking: false,
            detail: hasSummary ? "摘要已就绪" : "缺少项目摘要，AI 对整体故事理解可能不足"
        ))
    }

    // MARK: - Law 3: New Inventions Need ID

    private static func checkEntityTracking(
        project: NovelProject,
        blockingReasons: inout [String],
        warnings: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        // Check if chapter tree notes exist (tracks entities, relationships, foreshadowing)
        let hasChapterTree = project.hasStructureNotes
            || project.hasSceneProgressNotes
            || project.hasCharacterArcNotes
            || project.hasForeshadowNotes

        checklist.append(PrewriteChecklistItem(
            id: "chapter_tree",
            label: "章节树已维护",
            passed: hasChapterTree,
            isBlocking: false,
            detail: hasChapterTree ? "已有结构/场景/角色/伏笔记录" : "章节树未维护，新增实体可能无法追踪"
        ))

        // Check for unresolved foreshadowing that needs attention
        let foreshadowCount = project.foreshadowNodeCount
        if foreshadowCount > 0 {
            checklist.append(PrewriteChecklistItem(
                id: "foreshadow_tracking",
                label: "伏笔追踪中",
                passed: true,
                isBlocking: false,
                detail: "当前有 \(foreshadowCount) 条伏笔记录"
            ))
        }
    }

    // MARK: - Additional: Chapter Focus

    private static func checkChapterFocus(
        project: NovelProject,
        warnings: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        // Warn if writing same chapter number as a previously saved chapter
        let hasConflict = project.chapterCatalog.contains(where: {
            $0.volumeNumber == project.currentVolumeNumber
            && $0.chapterNumber == project.currentChapterNumber
        })

        if hasConflict {
            warnings.append("当前章节（第\(project.currentChapterNumber)章）已有保存记录，续写将创建新版本。")
        }
    }

    // MARK: - Additional: Continuity

    private static func checkContinuity(
        project: NovelProject,
        warnings: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        // Check if previous chapter exists for continuation
        let hasPreviousChapter = project.chapterDrafts.contains(where: {
            $0.chapterNumber == project.currentChapterNumber - 1
            || ($0.volumeNumber == project.currentVolumeNumber - 1 && $0.chapterNumber > 0)
        })
            || project.draftContinuationCache.count > 50

        if project.writtenChapters > 0 && !hasPreviousChapter {
            warnings.append("未找到上一章的缓存或草稿，续写衔接可能不够紧密。")
        }
    }
}
