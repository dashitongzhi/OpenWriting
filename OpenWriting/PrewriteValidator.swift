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
        checkLongformReadiness(project: project, blockingReasons: &blockingReasons, warnings: &warnings, checklist: &checklist)
        checkUnresolvedPlaceholders(project: project, blockingReasons: &blockingReasons, checklist: &checklist)

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
        let hasFocus = hasSpecificChapterGoal(project)
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
            let chapterLabel = project.currentVolumeNumber > 1
                ? "第\(project.currentVolumeNumber)卷第\(project.currentChapterNumber)章"
                : "第\(project.currentChapterNumber)章"
            warnings.append("当前章节（\(chapterLabel)）已有保存记录，续写将创建新版本。")
        }
    }

    // MARK: - Additional: Continuity

    private static func checkContinuity(
        project: NovelProject,
        warnings: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        // Check if previous chapter exists for continuation
        let hasPreviousChapter = project.previousChapterDraftForContinuation != nil
            || project.draftContinuationCache.count > 50

        if project.writtenChapters > 0 && !hasPreviousChapter {
            warnings.append("未找到上一章的缓存或草稿，续写衔接可能不够紧密。")
        }
    }

    // MARK: - Longform Readiness

    private static func checkLongformReadiness(
        project: NovelProject,
        blockingReasons: inout [String],
        warnings: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        guard project.storyLength.supportsVolumePlanning else { return }

        let hasSpecificVolumePlan = hasStructuredVolumePlan(project)
            || hasProjectSpecificSemanticContent(
                project.volumePlanNotes,
                project: project,
                minimumMeaningfulCharacters: 20
            )
        checklist.append(PrewriteChecklistItem(
            id: "longform_volume_plan",
            label: "长篇分卷计划已具体化",
            passed: hasSpecificVolumePlan,
            isBlocking: true,
            detail: hasSpecificVolumePlan ? "已有具体分卷目标和卷末回收方向" : "长篇不能只依赖默认分卷模板"
        ))
        if !hasSpecificVolumePlan {
            blockingReasons.append("长篇充分性：请先把分卷/阶段规划改成具体内容，至少写清当前卷目标、卷末回收点和下一卷升级方向。")
        }

        let hasChapterDirective = hasSpecificChapterGoal(project)
            || containsCurrentChapterMarker(project.outlineText, project: project)
            || containsCurrentChapterMarker(project.structureNotes, project: project)
        checklist.append(PrewriteChecklistItem(
            id: "longform_chapter_directive",
            label: "本章合同已具体化",
            passed: hasChapterDirective,
            isBlocking: true,
            detail: hasChapterDirective ? "当前章已有明确目标或章纲节点" : "缺少当前章真实目标，AI 容易跳步或泛写"
        ))
        if !hasChapterDirective {
            blockingReasons.append("长篇充分性：请补齐当前章真实目标或章纲节点，不能只使用默认开篇/续写提示。")
        }

        let hasThreadMap = !project.plotThreadList.activeThreads.isEmpty
            || hasProjectSpecificSemanticContent(
                project.activeThreadsNotes,
                project: project,
                minimumMeaningfulCharacters: 12
            )
        checklist.append(PrewriteChecklistItem(
            id: "longform_thread_map",
            label: "在途线索已维护",
            passed: hasThreadMap,
            isBlocking: false,
            detail: hasThreadMap ? "已有主线、支线或伏笔线记录" : "尚未把长篇在途线索具体化"
        ))
        if !hasThreadMap {
            warnings.append("建议补齐在途线索：长篇至少维护主线、支线、伏笔线和近期回收线，避免跨章失联。")
        }

        let hasDetailedChapterTree = project.structureNodeCount >= 3
            && (project.sceneProgressNodeCount >= 2 || project.characterArcNodeCount >= 2)
        checklist.append(PrewriteChecklistItem(
            id: "longform_chapter_tree_detail",
            label: "章节树细节足够",
            passed: hasDetailedChapterTree,
            isBlocking: false,
            detail: hasDetailedChapterTree ? "结构、场景或人物弧线已有拆解" : "章节树仍偏粗，生成质量会依赖模型自由发挥"
        ))
        if !hasDetailedChapterTree {
            warnings.append("建议细化章节树：至少补当前章场景推进、人物状态变化和必须覆盖节点。")
        }

        if project.writtenChapters >= 3 && !project.hasGlobalMemory {
            checklist.append(PrewriteChecklistItem(
                id: "longform_memory_after_three_chapters",
                label: "长篇记忆已建立",
                passed: false,
                isBlocking: true,
                detail: "已写 3 章以上但没有全局记忆"
            ))
            blockingReasons.append("长篇充分性：已写 \(project.writtenChapters) 章但尚无全局记忆，请先刷新或补齐记忆后再继续。")
        }
    }

    // MARK: - Placeholder Scan

    private static func checkUnresolvedPlaceholders(
        project: NovelProject,
        blockingReasons: inout [String],
        checklist: inout [PrewriteChecklistItem]
    ) {
        let fields = [
            ("作品摘要", project.summary),
            ("当前章目标", project.chapterFocus),
            ("作品大纲", project.outlineText),
            ("章节骨架", project.structureNotes),
            ("场景推进", project.sceneProgressNotes),
            ("角色弧线", project.characterArcNotes),
            ("伏笔记录", project.foreshadowNotes),
            ("分卷规划", project.volumePlanNotes),
            ("在途线索", project.activeThreadsNotes),
            ("特殊要求", project.specialRequirements),
            ("全局记忆", project.continuityNotes)
        ]
        let hits = fields.compactMap { label, text -> String? in
            placeholderHit(in: text).map { "\(label)：\($0)" }
        }

        checklist.append(PrewriteChecklistItem(
            id: "placeholder_scan",
            label: "占位符已清理",
            passed: hits.isEmpty,
            isBlocking: true,
            detail: hits.isEmpty ? "未发现明显占位符" : hits.prefix(3).joined(separator: "；")
        ))
        if !hits.isEmpty {
            blockingReasons.append("写前占位符未清理：\(hits.prefix(3).joined(separator: "；"))")
        }
    }

    private static func hasSpecificChapterGoal(_ project: NovelProject) -> Bool {
        let focus = project.chapterFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return hasStructuredChapterDirective(project)
            || hasProjectSpecificSemanticContent(
                focus,
                project: project,
                minimumMeaningfulCharacters: 8
            )
    }

    private static func containsCurrentChapterMarker(_ text: String, project: NovelProject) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return false }
        let chapter = max(project.currentChapterNumber, 1)
        let volume = max(project.currentVolumeNumber, 1)

        var activeVolumeNumber: Int?
        let supportsVolumePlanning = project.storyLength.supportsVolumePlanning
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            if let volumeNumber = explicitVolumeNumber(in: line) {
                activeVolumeNumber = volumeNumber
            }
            if lineReferencesChapter(
                line,
                volume: volume,
                chapter: chapter,
                activeVolumeNumber: activeVolumeNumber,
                supportsVolumePlanning: supportsVolumePlanning
            ) {
                return true
            }
        }

        return false
    }

    private static func lineReferencesChapter(
        _ line: String,
        volume: Int,
        chapter: Int,
        activeVolumeNumber: Int?,
        supportsVolumePlanning: Bool
    ) -> Bool {
        let chapterAlternatives = regexAlternation(for: numberMarkers(for: chapter))
        let chapterPatterns = [
            "第\\s*(?:\(chapterAlternatives))\\s*章",
            "^\\s*\(chapter)\\s*[\\.、）\\)]"
        ]
        let hasChapterMarker = chapterPatterns.contains { pattern in
            line.range(of: pattern, options: .regularExpression) != nil
        }
        guard hasChapterMarker else { return false }

        guard supportsVolumePlanning else { return true }

        if let explicitVolume = explicitVolumeNumber(in: line) {
            return explicitVolume == volume
        }
        if let activeVolumeNumber {
            return activeVolumeNumber == volume
        }

        // In longform mode, a bare chapter marker is reliable only while the
        // project is still in volume 1. Later volumes need an explicit section.
        return volume == 1
    }

    private static func explicitVolumeNumber(in line: String) -> Int? {
        let pattern = "第\\s*([0-9]+|[一二三四五六七八九十百千万零〇两]+)\\s*卷"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 2 else {
            return nil
        }
        let rawValue = nsLine.substring(with: match.range(at: 1))
        return parsedChineseAwareNumber(rawValue)
    }

    private static func parsedChineseAwareNumber(_ value: String) -> Int? {
        if let number = Int(value) {
            return number
        }
        let normalizedValue = value
            .replacingOccurrences(of: "两", with: "二")
            .replacingOccurrences(of: "〇", with: "零")
        for number in 1...999 {
            if numberMarkers(for: number).contains(normalizedValue) {
                return number
            }
        }
        return nil
    }

    private static func numberMarkers(for number: Int) -> [String] {
        let safeNumber = max(number, 1)
        var markers = [String(safeNumber)]
        if let chinese = chineseNumeral(for: safeNumber) {
            markers.append(chinese)
        }
        return markers
    }

    private static func regexAlternation(for values: [String]) -> String {
        values
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }

    private static func chineseNumeral(for number: Int) -> String? {
        guard number > 0, number <= 999 else { return nil }
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if number < 10 {
            return digits[number]
        }
        if number < 100 {
            let tens = number / 10
            let ones = number % 10
            let prefix = tens == 1 ? "十" : "\(digits[tens])十"
            return ones == 0 ? prefix : "\(prefix)\(digits[ones])"
        }

        let hundreds = number / 100
        let remainder = number % 100
        let prefix = "\(digits[hundreds])百"
        guard remainder > 0 else { return prefix }
        if remainder < 10 {
            return "\(prefix)零\(digits[remainder])"
        }
        return "\(prefix)\(chineseNumeral(for: remainder) ?? "")"
    }

    private static func hasStructuredVolumePlan(_ project: NovelProject) -> Bool {
        let runtime = project.longformRuntimeState
        let currentVolume = max(project.currentVolumeNumber, 1)
        guard let contract = runtime.latestContract,
              contract.volume.volumeNumber == currentVolume,
              !contract.prewrite.isBlocked,
              hasSubstantiveSemanticContent(
                  project.volumePlanNotes,
                  minimumMeaningfulCharacters: 20
              ) else {
            return false
        }
        return semanticFingerprint(contract.volume.volumeGoal)
            == semanticFingerprint(project.volumePlanNotes)
    }

    private static func hasStructuredChapterDirective(_ project: NovelProject) -> Bool {
        let runtime = project.longformRuntimeState
        let currentVolume = max(project.currentVolumeNumber, 1)
        let currentChapter = max(project.currentChapterNumber, 1)
        guard let contract = runtime.latestContract,
              contract.volume.volumeNumber == currentVolume,
              contract.chapter.chapterNumber == currentChapter,
              !contract.prewrite.isBlocked,
              hasSubstantiveSemanticContent(
                  project.chapterFocus,
                  minimumMeaningfulCharacters: 8
              ) else {
            return false
        }
        return semanticFingerprint(contract.chapter.chapterGoal)
            == semanticFingerprint(project.chapterFocus)
    }

    private static func hasProjectSpecificSemanticContent(
        _ text: String,
        project: NovelProject,
        minimumMeaningfulCharacters: Int
    ) -> Bool {
        guard hasSubstantiveSemanticContent(
            text,
            minimumMeaningfulCharacters: minimumMeaningfulCharacters
        ) else {
            return false
        }

        let textEntities = semanticEntitySet(in: text)
        guard !textEntities.isEmpty else { return false }
        return !textEntities.isDisjoint(with: projectSpecificEntities(for: project))
    }

    private static func hasSubstantiveSemanticContent(
        _ text: String,
        minimumMeaningfulCharacters: Int
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard placeholderHit(in: trimmed) == nil else { return false }
        let meaningfulScalars = trimmed.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || isCJK($0)
        }
        guard meaningfulScalars.count >= minimumMeaningfulCharacters else { return false }

        let distinctScalars = Set(meaningfulScalars.map {
            String($0).folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        })
        return distinctScalars.count >= 4
    }

    private static func semanticFingerprint(_ text: String) -> String {
        text.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || isCJK($0) }
            .map {
                String($0).folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
            }
            .joined()
    }

    private static func projectSpecificEntities(for project: NovelProject) -> Set<String> {
        let profile = project.outlineGenerationProfile
        var sourceTexts = [
            project.title,
            project.outlineText,
            project.outlineSummary,
            project.currentChapterTitle,
            profile.keyEvents,
            profile.motivations,
            profile.relationshipMap,
            profile.antagonistPortrait,
            profile.foreshadowingNotes
        ]
        sourceTexts.append(contentsOf: project.chapterCatalog.map(\.chapterTitle))
        sourceTexts.append(contentsOf: project.foreshadowList.entries.flatMap {
            [$0.title, $0.description] + $0.threads
        })
        sourceTexts.append(contentsOf: project.plotThreadList.threads.flatMap { thread in
            [thread.title, thread.description]
                + thread.keyEvents.flatMap { [$0.title, $0.description] }
        })
        sourceTexts.append(contentsOf: GlobalMemorySnapshot.Section.allCases.map {
            project.globalMemorySnapshot.value(for: $0)
        })
        if let buckets = project.persistedMemoryBuckets {
            sourceTexts.append(contentsOf: buckets.allActiveItems.flatMap {
                [$0.subject, $0.field, $0.value]
            })
        }

        return semanticEntitySet(in: sourceTexts.joined(separator: "\n"))
    }

    private static func semanticEntitySet(in text: String) -> Set<String> {
        Set(ContextRanker.extractEntities(from: text).compactMap { entity in
            let normalized = normalizedSemanticEntity(entity)
            guard normalized.count >= 2,
                  normalized.rangeOfCharacter(from: .letters) != nil,
                  !genericPlanningEntities.contains(normalized) else {
                return nil
            }
            return normalized
        })
    }

    nonisolated private static func normalizedSemanticEntity(_ entity: String) -> String {
        entity.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
    }

    private static let genericPlanningEntities: Set<String> = {
        let genericPlanningCorpus = """
        主角 女主 男主 角色 人物 目标 当前 本章 章节 分卷 本卷 第一卷 第二卷 第三卷
        阶段 开篇 开场 钩子 冲突 阻力 危机 转折 反转 推进 继续 补齐 场景 节奏 情绪
        关系 支线 主线 伏笔 线索 长期 世界 规则 设定 真相 代价 升级 回收 方向 变化
        计划 规划 结构 内容 逐步 以后 明确 重要 需要 必须 保持
        主角目标 世界规则 开篇钩子 卷末反转 冲突升级 关系变化 伏笔回收 长期线索
        chapter volume scene character goal outline plot story default template placeholder
        """
        return Set(ContextRanker.extractEntities(from: genericPlanningCorpus).map {
            normalizedSemanticEntity($0)
        })
    }()

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value >= 0x4E00 && value <= 0x9FFF)
            || (value >= 0x3400 && value <= 0x4DBF)
            || (value >= 0xF900 && value <= 0xFAFF)
            || (value >= 0x20000 && value <= 0x2A6DF)
            || (value >= 0x2A700 && value <= 0x2B73F)
            || (value >= 0x2B740 && value <= 0x2B81F)
            || (value >= 0x2B820 && value <= 0x2CEAF)
            || (value >= 0x2CEB0 && value <= 0x2EBEF)
            || (value >= 0x30000 && value <= 0x3134F)
    }

    private static func placeholderHit(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let placeholderPatterns = [
            "\\{[^}]{1,40}\\}",
            "<[^>]{1,40}>",
            "\\[[^\\]]*(?:待填|TODO|占位)[^\\]]*\\]",
            "第\\s*N\\s*章",
            "第N章",
            "章纲目标",
            "TODO",
            "占位符",
            "待填"
        ]
        for pattern in placeholderPatterns {
            if let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(trimmed[range])
            }
        }
        return nil
    }
}
