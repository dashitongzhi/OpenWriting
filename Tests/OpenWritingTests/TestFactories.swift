import Foundation
@testable import OpenWriting

extension NovelProject {
    init(
        title: String,
        genre: String,
        summary: String,
        storyLength: NovelLength = .medium
    ) {
        self.init(
            id: UUID().uuidString,
            title: title,
            genre: genre,
            summary: summary,
            storyLength: storyLength,
            updatedAt: "2026-06-06",
            currentChapterTitle: "开篇设定",
            currentChapterNumber: 1,
            writtenChapters: 0,
            chapterFocus: "继续推进当前章节。",
            draftText: "",
            outlineText: "",
            referenceContextText: "",
            specialRequirements: "",
            wordTargetText: "",
            continuityNotes: "",
            referenceDocuments: []
        )
    }
}

extension ReferenceDocument {
    init(title: String, content: String) {
        self.init(
            title: title,
            content: content,
            importedAt: "2026-06-06"
        )
    }
}

extension ChapterDraft {
    init(
        id: String = UUID().uuidString,
        volumeNumber: Int = 1,
        chapterNumber: Int,
        chapterTitle: String,
        content: String
    ) {
        self.init(
            id: id,
            volumeNumber: volumeNumber,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            content: content,
            savedAt: "2026-06-06"
        )
    }
}

extension ChapterDraftVersion {
    init(
        id: String = UUID().uuidString,
        chapterTitle: String,
        content: String,
        reason: String
    ) {
        self.init(
            id: id,
            chapterTitle: chapterTitle,
            content: content,
            reason: reason,
            savedAt: "2026-06-06"
        )
    }
}

extension OutlineGenerationProfile {
    init(
        storyFlow: String,
        worldDescription: String,
        protagonistTraits: String,
        expectedLength: String,
        endingPreference: String
    ) {
        self.init(
            storyFlow: storyFlow,
            worldDescription: worldDescription,
            protagonistTraits: protagonistTraits,
            expectedLength: expectedLength,
            endingPreference: endingPreference,
            sellingPoints: "",
            keyEvents: "",
            storyPacing: "",
            motivations: "",
            relationshipMap: "",
            antagonistPortrait: "",
            foreshadowingNotes: ""
        )
    }
}
