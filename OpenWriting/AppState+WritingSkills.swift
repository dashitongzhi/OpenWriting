import Foundation

extension AppState {
    var enabledWritingSkills: [WritingSkill] {
        writingSkills.filter(\.isEnabled)
    }

    var installedWritingSkillIDs: Set<WritingSkill.ID> {
        Set(writingSkills.map(\.id))
    }

    var marketplaceWritingSkills: [WritingSkill] {
        writingSkillCatalog.catalog(
            publishedSkills: publishedWritingSkills,
            installedSkills: writingSkills
        )
    }

    static func loadWritingSkills(from userDefaults: UserDefaults) -> [WritingSkill]? {
        guard let data = userDefaults.data(forKey: StorageKey.writingSkills) else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode([WritingSkill].self, from: data) else {
            return nil
        }
        return normalizedWritingSkills(decoded)
    }

    static func loadPublishedWritingSkills(from userDefaults: UserDefaults) -> [WritingSkill]? {
        guard let data = userDefaults.data(forKey: StorageKey.publishedWritingSkills) else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode([WritingSkill].self, from: data) else {
            return nil
        }
        return normalizedWritingSkills(decoded)
    }

    static func normalizedWritingSkills(_ skills: [WritingSkill]) -> [WritingSkill] {
        var seenIDs = Set<WritingSkill.ID>()
        return skills.filter { seenIDs.insert($0.id).inserted }
    }

    func persistWritingSkills(_ skills: [WritingSkill]) {
        guard let data = try? JSONEncoder().encode(skills) else { return }
        userDefaults.set(data, forKey: StorageKey.writingSkills)
    }

    func persistPublishedWritingSkills(_ skills: [WritingSkill]) {
        guard let data = try? JSONEncoder().encode(skills) else { return }
        userDefaults.set(data, forKey: StorageKey.publishedWritingSkills)
    }

    func importWritingSkills(_ skills: [WritingSkill]) {
        guard !skills.isEmpty else { return }

        var nextSkills = writingSkills
        var existingIDs = Set(nextSkills.map(\.id))
        for skill in skills {
            let resolvedSkill: WritingSkill
            if existingIDs.contains(skill.id) {
                resolvedSkill = skill.duplicateForImport()
            } else {
                resolvedSkill = skill
            }
            nextSkills.insert(resolvedSkill, at: 0)
            existingIDs.insert(resolvedSkill.id)
        }

        writingSkills = nextSkills
    }

    @discardableResult
    func publishWritingSkills(
        _ skills: [WritingSkill],
        publisherName: String,
        version: String = "1.0.0"
    ) -> [WritingSkill] {
        guard !skills.isEmpty else { return [] }

        let resolvedPublisher = publisherName.trimmingCharacters(in: .whitespacesAndNewlines)
        let publishedAt = Date()
        let publishedSkills = skills.map { skill in
            skill.publishedForLocalMarketplace(
                publisherName: resolvedPublisher.isEmpty ? "本机创作者" : resolvedPublisher,
                version: version,
                publishedAt: publishedAt
            )
        }

        var nextSkills = writingSkills
        var nextPublishedSkills = publishedWritingSkills
        for published in publishedSkills.reversed() {
            if let index = nextSkills.firstIndex(where: { $0.id == published.id }) {
                nextSkills[index] = published
            } else {
                nextSkills.insert(published, at: 0)
            }

            if let index = nextPublishedSkills.firstIndex(where: { $0.id == published.id }) {
                nextPublishedSkills[index] = published
            } else {
                nextPublishedSkills.insert(published, at: 0)
            }
        }
        publishedWritingSkills = nextPublishedSkills
        writingSkills = nextSkills
        return publishedSkills
    }

    func installMarketplaceSkill(_ skill: WritingSkill) {
        if let index = writingSkills.firstIndex(where: { $0.id == skill.id }) {
            var refreshed = skill
            refreshed.isEnabled = true
            writingSkills[index] = refreshed
            return
        }

        var installed = skill
        installed.isEnabled = true
        writingSkills.insert(installed, at: 0)
    }

    func toggleWritingSkill(_ skillID: WritingSkill.ID) {
        guard let index = writingSkills.firstIndex(where: { $0.id == skillID }) else { return }
        writingSkills[index].isEnabled.toggle()
    }

    func deleteWritingSkill(_ skillID: WritingSkill.ID) {
        writingSkills.removeAll { $0.id == skillID }
    }

    func projectWithActiveWritingSkills(_ project: NovelProject) -> NovelProject {
        let prompt = activeWritingSkillPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return project }

        var project = project
        let existing = project.specialRequirements.trimmingCharacters(in: .whitespacesAndNewlines)
        project.specialRequirements = existing.isEmpty
            ? prompt
            : "\(existing)\n\n\(prompt)"
        return project
    }

    private var activeWritingSkillPrompt: String {
        let enabledSkills = enabledWritingSkills
        guard !enabledSkills.isEmpty else { return "" }

        let skillBlocks = enabledSkills.prefix(8).map { skill in
            """
            【\(skill.title)】
            \(skill.instructions.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        }
        .joined(separator: "\n\n")

        return """
        ===== 已启用写作 Skill =====
        以下 Skill 是用户在 Skill 市场/本地库中启用的写作策略。它们约束本次生成、修订、大纲规划和质量审查；若与项目事实冲突，以项目事实和已保存正文为准。

        \(skillBlocks)
        """
    }
}
