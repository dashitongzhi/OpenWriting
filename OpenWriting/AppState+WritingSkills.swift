import Foundation

extension AppState {
    var enabledWritingSkills: [WritingSkill] {
        writingSkills.filter(\.isEnabled)
    }

    var installedWritingSkillIDs: Set<WritingSkill.ID> {
        Set(writingSkills.map(\.id))
    }

    static func loadWritingSkills(for scope: String?, from userDefaults: UserDefaults) -> [WritingSkill]? {
        guard let data = userDefaults.data(forKey: writingSkillsStorageKey(for: scope)) else {
            return nil
        }

        return try? JSONDecoder().decode([WritingSkill].self, from: data)
    }

    func persistWritingSkills(_ skills: [WritingSkill]) {
        guard let data = try? JSONEncoder().encode(skills) else { return }
        userDefaults.set(data, forKey: Self.writingSkillsStorageKey(for: currentStorageScope))
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

    func installMarketplaceSkill(_ skill: WritingSkill) {
        if let index = writingSkills.firstIndex(where: { $0.id == skill.id }) {
            writingSkills[index].isEnabled = true
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
        以下 Skill 是用户在 Skill 广场/本地库中启用的写作策略。它们约束本次生成、修订和大纲规划；若与项目事实冲突，以项目事实和已保存正文为准。

        \(skillBlocks)
        """
    }
}
