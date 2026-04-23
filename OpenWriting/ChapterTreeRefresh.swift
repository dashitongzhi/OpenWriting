import Foundation

struct ChapterTreeRefresh {
    static let empty = ChapterTreeRefresh()

    var outlineSummary: String = ""
    var structureNotes: String = ""
    var sceneProgressNotes: String = ""
    var characterArcNotes: String = ""
    var foreshadowNotes: String = ""

    static let sectionCount = 5

    var hasStructuredContent: Bool {
        [
            outlineSummary,
            structureNotes,
            sceneProgressNotes,
            characterArcNotes,
            foreshadowNotes
        ]
        .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func parse(from text: String) -> ChapterTreeRefresh {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return .empty }

        let lines = trimmedText.components(separatedBy: .newlines)
        var sections: [Section: [String]] = [:]
        var currentSection: Section?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                if let currentSection {
                    sections[currentSection, default: []].append("")
                }
                continue
            }

            if let matchedSection = Section.matching(line) {
                currentSection = matchedSection
                let remainder = matchedSection.inlineRemainder(in: line)
                if !remainder.isEmpty {
                    sections[matchedSection, default: []].append(remainder)
                }
                continue
            }

            guard let currentSection else { continue }
            sections[currentSection, default: []].append(line)
        }

        return ChapterTreeRefresh(
            outlineSummary: Section.outlineSummary.content(from: sections),
            structureNotes: Section.structureNotes.content(from: sections),
            sceneProgressNotes: Section.sceneProgressNotes.content(from: sections),
            characterArcNotes: Section.characterArcNotes.content(from: sections),
            foreshadowNotes: Section.foreshadowNotes.content(from: sections)
        )
    }
}

struct ChapterTreeRefreshBaseline {
    let continuityNotes: String
    let outlineSummary: String
    let structureNotes: String
    let sceneProgressNotes: String
    let characterArcNotes: String
    let foreshadowNotes: String

    init(project: NovelProject) {
        continuityNotes = project.continuityNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        outlineSummary = project.outlineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        structureNotes = project.structureNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        sceneProgressNotes = project.sceneProgressNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        characterArcNotes = project.characterArcNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        foreshadowNotes = project.foreshadowNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChapterTreeRefreshApplyOutcome {
    var acceptedSections = 0
    var protectedSections = 0

    var hasAcceptedChanges: Bool {
        acceptedSections > 0
    }

    var preservedLocalChanges: Bool {
        protectedSections > 0
    }
}

private enum Section: CaseIterable {
    case outlineSummary
    case structureNotes
    case sceneProgressNotes
    case characterArcNotes
    case foreshadowNotes

    var title: String {
        switch self {
        case .outlineSummary:
            return "章节树总结"
        case .structureNotes:
            return "章节骨架拆解"
        case .sceneProgressNotes:
            return "场景推进记录"
        case .characterArcNotes:
            return "角色弧线记录"
        case .foreshadowNotes:
            return "伏笔与回收记录"
        }
    }

    static func matching(_ line: String) -> Section? {
        allCases.first { section in
            line == section.title
                || line == "\(section.title)："
                || line == "\(section.title):"
                || line.hasPrefix("\(section.title)：")
                || line.hasPrefix("\(section.title):")
        }
    }

    func inlineRemainder(in line: String) -> String {
        guard line.hasPrefix(title) else { return "" }
        let remainder = line.dropFirst(title.count)
        return remainder
            .trimmingCharacters(in: CharacterSet(charactersIn: "：: ").union(.whitespacesAndNewlines))
    }

    func content(from sections: [Section: [String]]) -> String {
        sections[self, default: []]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
