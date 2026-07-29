import Foundation

/// Deterministic, transport-independent merge policy for account-scoped projects.
nonisolated enum CloudProjectMergePolicy {
    static func mergeCloudProjects(local: [NovelProject], remote: [NovelProject]) -> [NovelProject] {
        let normalizedLocal = coalescedCloudProjects(local)
        let normalizedRemote = coalescedCloudProjects(remote)
        var localByID = Dictionary(
            uniqueKeysWithValues: normalizedLocal.map { ($0.id, $0) }
        )
        var merged: [NovelProject] = []
        var visitedIDs = Set<NovelProject.ID>()

        for remoteProject in normalizedRemote {
            if let localProject = localByID.removeValue(forKey: remoteProject.id) {
                merged.append(mergeCloudProject(local: localProject, remote: remoteProject))
            } else {
                merged.append(remoteProject)
            }
            visitedIDs.insert(remoteProject.id)
        }

        let remainingLocal = normalizedLocal
            .filter { !visitedIDs.contains($0.id) }
            .sorted(by: cloudProjectSortsBefore)
        merged.append(contentsOf: remainingLocal)
        return merged.sorted(by: cloudProjectSortsBefore)
    }

    /// A fresh write treats the newest whole project as authoritative.
    ///
    /// Pull reconciliation can safely preserve independent fields from both
    /// sides, but using that union for every save revives locally deleted
    /// nested values that have no tombstone of their own. A fresh writer has
    /// an explicit current project snapshot, so it wins equal timestamps;
    /// a strictly newer remote project still wins a race.
    static func mergeCloudProjectStateForFreshWrite(
        local: [NovelProject],
        localDeletedProjects: [ProjectDeletionTombstone],
        remote: [NovelProject],
        remoteDeletedProjects: [ProjectDeletionTombstone]
    ) -> (
        projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone]
    ) {
        let normalizedLocal = coalescedAuthoritativeCloudProjects(local)
        let normalizedRemote = coalescedAuthoritativeCloudProjects(remote)
        var remoteByID = Dictionary(
            uniqueKeysWithValues: normalizedRemote.map { ($0.id, $0) }
        )
        var mergedProjects: [NovelProject] = []

        for localProject in normalizedLocal {
            guard let remoteProject = remoteByID.removeValue(
                forKey: localProject.id
            ) else {
                mergedProjects.append(localProject)
                continue
            }
            mergedProjects.append(
                localProject.updatedAtDate >= remoteProject.updatedAtDate
                    ? localProject
                    : remoteProject
            )
        }
        mergedProjects.append(contentsOf: remoteByID.values)

        return resolvedCloudProjectState(
            projects: mergedProjects.sorted(by: cloudProjectSortsBefore),
            localDeletedProjects: localDeletedProjects,
            remoteDeletedProjects: remoteDeletedProjects
        )
    }

    private static func coalescedCloudProjects(
        _ projects: [NovelProject]
    ) -> [NovelProject] {
        var projectsByID: [NovelProject.ID: NovelProject] = [:]
        for project in projects {
            if let existing = projectsByID[project.id] {
                projectsByID[project.id] = mergeCloudProject(
                    local: existing,
                    remote: project
                )
            } else {
                projectsByID[project.id] = project
            }
        }
        return projectsByID.values.sorted(by: cloudProjectSortsBefore)
    }

    private static func coalescedAuthoritativeCloudProjects(
        _ projects: [NovelProject]
    ) -> [NovelProject] {
        var projectsByID: [NovelProject.ID: NovelProject] = [:]
        for project in projects {
            guard let existing = projectsByID[project.id] else {
                projectsByID[project.id] = project
                continue
            }
            if project.updatedAtDate != existing.updatedAtDate {
                projectsByID[project.id] =
                    project.updatedAtDate > existing.updatedAtDate
                    ? project
                    : existing
            } else {
                projectsByID[project.id] = canonicalCloudValue(
                    existing,
                    project
                )
            }
        }
        return projectsByID.values.sorted(by: cloudProjectSortsBefore)
    }

    static func mergeCloudProjectState(
        local: [NovelProject],
        localDeletedProjects: [ProjectDeletionTombstone],
        remote: [NovelProject],
        remoteDeletedProjects: [ProjectDeletionTombstone]
    ) -> (
        projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone]
    ) {
        let mergedProjects = mergeCloudProjects(local: local, remote: remote)
        return resolvedCloudProjectState(
            projects: mergedProjects,
            localDeletedProjects: localDeletedProjects,
            remoteDeletedProjects: remoteDeletedProjects
        )
    }

    private static func resolvedCloudProjectState(
        projects: [NovelProject],
        localDeletedProjects: [ProjectDeletionTombstone],
        remoteDeletedProjects: [ProjectDeletionTombstone]
    ) -> (
        projects: [NovelProject],
        deletedProjects: [ProjectDeletionTombstone]
    ) {
        let tombstones = ProjectDeletionTombstone.normalized(
            localDeletedProjects + remoteDeletedProjects
        )
        let projectByID = projects.reduce(into: [NovelProject.ID: NovelProject]()) {
            $0[$1.id] = $1
        }
        let activeTombstones = tombstones.filter { tombstone in
            guard let project = projectByID[tombstone.projectID] else { return true }
            return tombstone.deletedAt >= project.updatedAtDate
        }
        let activeTombstoneIDs = Set(activeTombstones.map(\.projectID))
        let survivingProjects = projects.filter {
            !activeTombstoneIDs.contains($0.id)
        }
        return (
            projects: survivingProjects,
            deletedProjects: activeTombstones
        )
    }

    private static func mergeCloudProject(local: NovelProject, remote: NovelProject) -> NovelProject {
        if local.updatedAtDate != remote.updatedAtDate {
            // Nested values do not yet carry deletion tombstones. Once one
            // whole-project snapshot is strictly newer, merging arrays from
            // the older snapshot would revive chapters, references, memory,
            // review history, or planning items that the newer writer
            // intentionally removed.
            return local.updatedAtDate > remote.updatedAtDate ? local : remote
        }

        var merged = canonicalCloudValue(local, remote)
        merged.chapterDrafts = mergeCloudChapterDrafts(local: local.chapterDrafts, remote: remote.chapterDrafts)
        merged.chapterCatalog = merged.chapterDrafts.map(ChapterDraftMetadata.init)

        mergeIndependentCloudFields(
            into: &merged,
            local: local,
            remote: remote
        )

        if let newestChapterDate = merged.chapterDrafts.map(\.savedAtDate).max(),
           newestChapterDate > merged.updatedAtDate {
            merged.updatedAtDate = newestChapterDate
        }

        return merged
    }

    private static func cloudProjectSortsBefore(
        _ lhs: NovelProject,
        _ rhs: NovelProject
    ) -> Bool {
        if lhs.updatedAtDate != rhs.updatedAtDate {
            return lhs.updatedAtDate > rhs.updatedAtDate
        }
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        return lhs.id < rhs.id
    }

    private static func cloudChapterPositionIsLater(
        volumeNumber: Int,
        chapterNumber: Int,
        thanVolumeNumber: Int,
        chapterNumber otherChapterNumber: Int
    ) -> Bool {
        let normalizedVolume = max(volumeNumber, 1)
        let normalizedOtherVolume = max(thanVolumeNumber, 1)
        if normalizedVolume != normalizedOtherVolume {
            return normalizedVolume > normalizedOtherVolume
        }
        return max(chapterNumber, 1) > max(otherChapterNumber, 1)
    }

    private static func mergeIndependentCloudFields(
        into merged: inout NovelProject,
        local: NovelProject,
        remote: NovelProject
    ) {
        merged.storyLength = mergeDefaultAwareCloudValue(
            local.storyLength,
            remote.storyLength,
            isDefault: { $0 == .long }
        )
        merged.outlineGenerationProfile = mergeDefaultAwareCloudValue(
            local.outlineGenerationProfile,
            remote.outlineGenerationProfile,
            isDefault: { $0 == .empty }
        )
        merged.genreTemplateId = mergeCloudGenreTemplateID(
            local.genreTemplateId,
            remote.genreTemplateId
        )
        merged.draftText = mergeConflictPreservingText(
            local.draftText,
            remote.draftText
        )
        merged.currentChapterTitle = mergeConflictPreservingText(
            local.currentChapterTitle,
            remote.currentChapterTitle
        )
        merged.chapterFocus = mergeConflictPreservingText(
            local.chapterFocus,
            remote.chapterFocus
        )
        if (local.currentVolumeNumber, local.currentChapterNumber)
            != (remote.currentVolumeNumber, remote.currentChapterNumber) {
            let furthest = cloudChapterPositionIsLater(
                volumeNumber: local.currentVolumeNumber,
                chapterNumber: local.currentChapterNumber,
                thanVolumeNumber: remote.currentVolumeNumber,
                chapterNumber: remote.currentChapterNumber
            ) ? local : remote
            merged.currentVolumeNumber = furthest.currentVolumeNumber
            merged.currentChapterNumber = furthest.currentChapterNumber
        }
        merged.writtenChapters = max(
            local.writtenChapters,
            remote.writtenChapters
        )
        merged.outlineText = mergeConflictPreservingText(
            local.outlineText,
            remote.outlineText
        )
        merged.structureNotes = mergeConflictPreservingText(
            local.structureNotes,
            remote.structureNotes
        )
        merged.sceneProgressNotes = mergeConflictPreservingText(
            local.sceneProgressNotes,
            remote.sceneProgressNotes
        )
        merged.characterArcNotes = mergeConflictPreservingText(
            local.characterArcNotes,
            remote.characterArcNotes
        )
        merged.foreshadowNotes = mergeConflictPreservingText(
            local.foreshadowNotes,
            remote.foreshadowNotes
        )
        merged.volumePlanNotes = mergeConflictPreservingText(
            local.volumePlanNotes,
            remote.volumePlanNotes
        )
        merged.activeThreadsNotes = mergeConflictPreservingText(
            local.activeThreadsNotes,
            remote.activeThreadsNotes
        )
        merged.outlineSummary = mergeConflictPreservingText(
            local.outlineSummary,
            remote.outlineSummary
        )
        merged.outlineSummaryUpdatedAtDate = [
            local.outlineSummaryUpdatedAtDate,
            remote.outlineSummaryUpdatedAtDate
        ]
        .compactMap { $0 }
        .max()

        var globalMemory = GlobalMemorySnapshot.empty
        for section in GlobalMemorySnapshot.Section.allCases {
            globalMemory.setValue(
                mergeConflictPreservingText(
                    local.globalMemorySnapshot.value(for: section),
                    remote.globalMemorySnapshot.value(for: section)
                ),
                for: section
            )
        }
        merged.globalMemorySnapshot = globalMemory
        merged.continuityNotes = mergeConflictPreservingText(
            local.continuityNotes,
            remote.continuityNotes
        )
        merged.referenceContextText = mergeConflictPreservingText(
            local.referenceContextText,
            remote.referenceContextText
        )
        merged.specialRequirements = mergeConflictPreservingText(
            local.specialRequirements,
            remote.specialRequirements
        )
        merged.wordTargetText = mergeConflictPreservingText(
            local.wordTargetText,
            remote.wordTargetText
        )
        merged.globalMemoryUpdatedAtDate = [
            local.globalMemoryUpdatedAtDate,
            remote.globalMemoryUpdatedAtDate
        ]
        .compactMap { $0 }
        .max()

        merged.referenceDocuments = mergeCloudReferenceDocuments(
            local.referenceDocuments,
            remote.referenceDocuments
        )
        merged.foreshadowList = mergeCloudForeshadowLists(
            local.foreshadowList,
            remote.foreshadowList
        )
        merged.plotThreadList = mergeCloudPlotThreadLists(
            local.plotThreadList,
            remote.plotThreadList
        )
        merged.persistedMemoryBuckets = mergeCloudMemoryBuckets(
            local.persistedMemoryBuckets,
            remote.persistedMemoryBuckets
        )
        var mergedStrandState = mergeCloudStrandWeaveStates(
            local.persistedStrandWeaveState,
            remote.persistedStrandWeaveState
        )
        let strandConfiguration = [
            CloudStrandConfiguration(local.strandWeaveTracker),
            CloudStrandConfiguration(remote.strandWeaveTracker)
        ]
        .reduce(
            mergedStrandState.map(CloudStrandConfiguration.init)
                ?? .defaultConfiguration
        ) {
            mergeDefaultAwareCloudValue(
                $0,
                $1,
                isDefault: \.isDefault
            )
        }
        if var state = mergedStrandState {
            strandConfiguration.apply(to: &state)
            mergedStrandState = state
        }
        merged.persistedStrandWeaveState = mergedStrandState
        merged.strandWeaveTracker = mergeCloudLegacyStrandTrackers(
            local.strandWeaveTracker,
            remote.strandWeaveTracker,
            configuration: strandConfiguration,
            persistedState: mergedStrandState
        )
        merged.persistedLastReviewResult = mergeCanonicalOptionalCloudValue(
            local.persistedLastReviewResult,
            remote.persistedLastReviewResult
        )
        merged.persistedLongformRuntimeState = mergeCloudLongformRuntimeStates(
            local.persistedLongformRuntimeState,
            remote.persistedLongformRuntimeState
        )
        merged.qualityReviewReports = mergeCloudQualityReviewReports(
            local.qualityReviewReports,
            remote.qualityReviewReports
        )
        if local.persistedAntiPatterns == nil,
           remote.persistedAntiPatterns == nil {
            merged.persistedAntiPatterns = nil
        } else {
            merged.persistedAntiPatterns = Array(
                Set(
                    (local.persistedAntiPatterns ?? [])
                        + (remote.persistedAntiPatterns ?? [])
                )
            )
            .sorted()
        }
    }

    private static func canonicalCloudValue<Value: Encodable>(
        _ first: Value,
        _ second: Value
    ) -> Value {
        let firstData = canonicalCloudData(first)
        let secondData = canonicalCloudData(second)
        guard firstData != secondData else { return first }
        return firstData.lexicographicallyPrecedes(secondData) ? second : first
    }

    private static func canonicalCloudData<Value: Encodable>(
        _ value: Value
    ) -> Data {
        if let encoded = try? CloudProjectJSONCoding.makeEncoder().encode(value) {
            return encoded
        }
        return Data(String(reflecting: value).utf8)
    }

    private static func mergeDefaultAwareCloudValue<Value: Encodable>(
        _ first: Value,
        _ second: Value,
        isDefault: (Value) -> Bool
    ) -> Value {
        switch (isDefault(first), isDefault(second)) {
        case (true, false):
            return second
        case (false, true):
            return first
        default:
            return canonicalCloudValue(first, second)
        }
    }

    private static func mergeCloudGenreTemplateID(
        _ first: String?,
        _ second: String?
    ) -> String? {
        let first = normalizedCloudGenreTemplateID(first)
        let second = normalizedCloudGenreTemplateID(second)
        guard let first else { return second }
        guard let second else { return first }
        return canonicalCloudValue(first, second)
    }

    private static func normalizedCloudGenreTemplateID(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func mergeCanonicalOptionalCloudValue<Value: Encodable>(
        _ first: Value?,
        _ second: Value?
    ) -> Value? {
        guard let first else { return second }
        guard let second else { return first }
        return canonicalCloudValue(first, second)
    }

    private static func mergeCloudLongformRuntimeStates(
        _ first: LongformStoryRuntimeState?,
        _ second: LongformStoryRuntimeState?
    ) -> LongformStoryRuntimeState? {
        guard first != nil || second != nil else { return nil }
        guard let first else { return second }
        guard let second else { return first }

        let allCommits = mergeCloudLongformCommits(
            first.acceptedCommits
                + first.rejectedCommits
                + [first.latestCommit].compactMap { $0 },
            second.acceptedCommits
                + second.rejectedCommits
                + [second.latestCommit].compactMap { $0 }
        )
        let acceptedCommits = allCommits.filter(\.isAccepted)
        let rejectedCommits = allCommits.filter { !$0.isAccepted }
        let latestCommit = allCommits.first

        return LongformStoryRuntimeState(
            latestContract: newestCanonicalCloudValue(
                first.latestContract,
                second.latestContract,
                date: \.updatedAt
            ),
            latestCommit: latestCommit,
            latestWriteGate: newestCanonicalCloudValue(
                first.latestWriteGate,
                second.latestWriteGate,
                date: \.generatedAt
            ),
            acceptedCommits: acceptedCommits,
            rejectedCommits: Array(rejectedCommits.prefix(200))
        )
    }

    private static func mergeCloudLongformCommits(
        _ first: [LongformChapterCommit],
        _ second: [LongformChapterCommit]
    ) -> [LongformChapterCommit] {
        var commitsByPosition: [String: LongformChapterCommit] = [:]
        for commit in first + second {
            let position = "\(max(commit.volumeNumber, 1)):\(max(commit.chapterNumber, 1))"
            guard let existing = commitsByPosition[position] else {
                commitsByPosition[position] = commit
                continue
            }
            if existing.createdAt != commit.createdAt {
                commitsByPosition[position] = existing.createdAt > commit.createdAt
                    ? existing
                    : commit
            } else {
                commitsByPosition[position] = canonicalCloudValue(existing, commit)
            }
        }
        return commitsByPosition.values.sorted(by: cloudLongformCommitSortsBefore)
    }

    private static func cloudLongformCommitSortsBefore(
        _ lhs: LongformChapterCommit,
        _ rhs: LongformChapterCommit
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id < rhs.id
    }

    private static func newestCanonicalCloudValue<Value: Encodable>(
        _ first: Value?,
        _ second: Value?,
        date: KeyPath<Value, Date>
    ) -> Value? {
        guard let first else { return second }
        guard let second else { return first }
        let firstDate = first[keyPath: date]
        let secondDate = second[keyPath: date]
        if firstDate != secondDate {
            return firstDate > secondDate ? first : second
        }
        return canonicalCloudValue(first, second)
    }

    private static func mergeCloudReferenceDocuments(
        _ first: [ReferenceDocument],
        _ second: [ReferenceDocument]
    ) -> [ReferenceDocument] {
        var documentsByID: [String: ReferenceDocument] = [:]
        for document in first + second {
            guard let existing = documentsByID[document.id] else {
                documentsByID[document.id] = document
                continue
            }
            let preferred: ReferenceDocument
            if existing.importedAtDate != document.importedAtDate {
                preferred = existing.importedAtDate > document.importedAtDate
                    ? existing
                    : document
            } else {
                preferred = canonicalCloudValue(existing, document)
            }
            var merged = ReferenceDocument(
                id: preferred.id,
                title: mergeConflictPreservingText(existing.title, document.title),
                content: mergeConflictPreservingText(existing.content, document.content),
                importedAt: CloudProjectJSONCoding.string(
                    from: max(existing.importedAtDate, document.importedAtDate)
                ),
                category: preferred.category
            )
            merged.importedAtDate = max(existing.importedAtDate, document.importedAtDate)
            documentsByID[document.id] = merged
        }
        return documentsByID.values.sorted {
            if $0.importedAtDate != $1.importedAtDate {
                return $0.importedAtDate < $1.importedAtDate
            }
            return $0.id < $1.id
        }
    }

    private static func mergeCloudForeshadowLists(
        _ first: ForeshadowList,
        _ second: ForeshadowList
    ) -> ForeshadowList {
        var entriesByID: [String: ForeshadowEntry] = [:]
        for entry in first.entries + second.entries {
            guard let existing = entriesByID[entry.id] else {
                entriesByID[entry.id] = entry
                continue
            }
            var merged: ForeshadowEntry
            if existing.updatedAt != entry.updatedAt {
                merged = existing.updatedAt > entry.updatedAt ? existing : entry
            } else {
                merged = canonicalCloudValue(existing, entry)
            }
            merged.title = mergeConflictPreservingText(existing.title, entry.title)
            merged.description = mergeConflictPreservingText(
                existing.description,
                entry.description
            )
            merged.notes = mergeConflictPreservingText(existing.notes, entry.notes)
            merged.threads = Array(Set(existing.threads + entry.threads)).sorted()
            merged.createdAt = min(existing.createdAt, entry.createdAt)
            merged.updatedAt = max(existing.updatedAt, entry.updatedAt)
            entriesByID[entry.id] = merged
        }
        return ForeshadowList(entries: entriesByID.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id < $1.id
        })
    }

    private static func mergeCloudPlotThreadLists(
        _ first: PlotThreadList,
        _ second: PlotThreadList
    ) -> PlotThreadList {
        var threadsByID: [String: PlotThread] = [:]
        for thread in first.threads + second.threads {
            guard let existing = threadsByID[thread.id] else {
                threadsByID[thread.id] = thread
                continue
            }
            var merged: PlotThread
            if existing.updatedAt != thread.updatedAt {
                merged = existing.updatedAt > thread.updatedAt ? existing : thread
            } else {
                merged = canonicalCloudValue(existing, thread)
            }
            merged.title = mergeConflictPreservingText(existing.title, thread.title)
            merged.description = mergeConflictPreservingText(
                existing.description,
                thread.description
            )
            merged.relatedForeshadowIDs = Array(
                Set(existing.relatedForeshadowIDs + thread.relatedForeshadowIDs)
            ).sorted()
            merged.keyEvents = mergeCloudThreadEvents(
                existing.keyEvents,
                thread.keyEvents
            )
            merged.startChapter = min(existing.startChapter, thread.startChapter)
            merged.lastActiveChapter = max(
                existing.lastActiveChapter,
                thread.lastActiveChapter
            )
            let volumeBounds = [
                existing.volumeRange?.lowerBound,
                existing.volumeRange?.upperBound,
                thread.volumeRange?.lowerBound,
                thread.volumeRange?.upperBound
            ]
            .compactMap { $0 }
            if let minimumVolume = volumeBounds.min(),
               let maximumVolume = volumeBounds.max() {
                merged.volumeRange = minimumVolume...maximumVolume
            }
            merged.createdAt = min(existing.createdAt, thread.createdAt)
            merged.updatedAt = max(existing.updatedAt, thread.updatedAt)
            threadsByID[thread.id] = merged
        }
        return PlotThreadList(threads: threadsByID.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id < $1.id
        })
    }

    private static func mergeCloudThreadEvents(
        _ first: [ThreadEvent],
        _ second: [ThreadEvent]
    ) -> [ThreadEvent] {
        var eventsByID: [String: ThreadEvent] = [:]
        for event in first + second {
            if let existing = eventsByID[event.id] {
                eventsByID[event.id] = canonicalCloudValue(existing, event)
            } else {
                eventsByID[event.id] = event
            }
        }
        return eventsByID.values.sorted {
            let firstVolume = $0.volumeNumber ?? 1
            let secondVolume = $1.volumeNumber ?? 1
            if firstVolume != secondVolume {
                return firstVolume < secondVolume
            }
            if $0.chapter != $1.chapter {
                return $0.chapter < $1.chapter
            }
            return $0.id < $1.id
        }
    }

    private static func mergeCloudMemoryBuckets(
        _ first: MemoryBuckets?,
        _ second: MemoryBuckets?
    ) -> MemoryBuckets? {
        guard first != nil || second != nil else { return nil }
        guard let first else { return second }
        guard let second else { return first }

        let allItems = MemoryCategory.allCases.flatMap { category in
            first.bucket(for: category) + second.bucket(for: category)
        }
        var itemsByID: [String: MemoryItem] = [:]
        for item in allItems {
            guard let existing = itemsByID[item.id] else {
                itemsByID[item.id] = item
                continue
            }
            if existing.updatedAt != item.updatedAt {
                itemsByID[item.id] = existing.updatedAt > item.updatedAt
                    ? existing
                    : item
            } else {
                itemsByID[item.id] = canonicalCloudValue(existing, item)
            }
        }

        var merged = MemoryBuckets.empty
        for category in MemoryCategory.allCases {
            let items = itemsByID.values
                .filter { $0.category == category }
                .sorted {
                    if $0.sourceVolumeNumber != $1.sourceVolumeNumber {
                        return $0.sourceVolumeNumber < $1.sourceVolumeNumber
                    }
                    if $0.sourceChapter != $1.sourceChapter {
                        return $0.sourceChapter < $1.sourceChapter
                    }
                    return $0.id < $1.id
                }
            merged.setBucket(items, for: category)
        }
        merged.lastCompactedAtChapter = max(
            first.lastCompactedAtChapter,
            second.lastCompactedAtChapter
        )
        return merged
    }

    private static func mergeCloudStrandWeaveStates(
        _ first: StrandWeaveState?,
        _ second: StrandWeaveState?
    ) -> StrandWeaveState? {
        guard first != nil || second != nil else { return nil }
        guard let first else { return second }
        guard let second else { return first }

        let firstConfiguration = CloudStrandConfiguration(first)
        let secondConfiguration = CloudStrandConfiguration(second)
        let configuration = mergeDefaultAwareCloudValue(
            firstConfiguration,
            secondConfiguration,
            isDefault: \.isDefault
        )
        var merged = first
        configuration.apply(to: &merged)
        var entriesByPosition: [String: StrandWeaveState.Entry] = [:]
        for entry in first.entries + second.entries {
            let position = "\(entry.volumeNumber):\(entry.chapterNumber)"
            guard let existing = entriesByPosition[position] else {
                entriesByPosition[position] = entry
                continue
            }
            if existing.recordedAt != entry.recordedAt {
                entriesByPosition[position] = existing.recordedAt > entry.recordedAt
                    ? existing
                    : entry
            } else {
                entriesByPosition[position] = canonicalCloudValue(existing, entry)
            }
        }
        merged.entries = entriesByPosition.values.sorted {
            if $0.volumeNumber != $1.volumeNumber {
                return $0.volumeNumber < $1.volumeNumber
            }
            if $0.chapterNumber != $1.chapterNumber {
                return $0.chapterNumber < $1.chapterNumber
            }
            return $0.id < $1.id
        }
        return merged
    }

    private static func mergeCloudLegacyStrandTrackers(
        _ first: StrandWeaveTracker,
        _ second: StrandWeaveTracker,
        configuration: CloudStrandConfiguration,
        persistedState: StrandWeaveState?
    ) -> StrandWeaveTracker {
        var recordsByChapter: [Int: ChapterStrandRecord] = [:]
        for record in first.records + second.records {
            guard let existing = recordsByChapter[record.chapterNumber] else {
                recordsByChapter[record.chapterNumber] = record
                continue
            }
            if existing.recordedAt != record.recordedAt {
                recordsByChapter[record.chapterNumber] =
                    existing.recordedAt > record.recordedAt ? existing : record
            } else {
                recordsByChapter[record.chapterNumber] =
                    canonicalCloudValue(existing, record)
            }
        }

        if let persistedState {
            let persistedDominants = Dictionary(
                grouping: persistedState.entries,
                by: \.chapterNumber
            )
            .mapValues { Set($0.map(\.dominant)) }
            recordsByChapter = recordsByChapter.filter { chapterNumber, record in
                guard let dominants = persistedDominants[chapterNumber] else {
                    return true
                }
                return dominants.count == 1 && dominants.contains(record.primaryStrand)
            }
        }

        let tracker = configuration.makeTracker()
        recordsByChapter.values
            .sorted {
                if $0.chapterNumber != $1.chapterNumber {
                    return $0.chapterNumber < $1.chapterNumber
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .forEach(tracker.recordChapter)
        return tracker
    }

    private struct CloudStrandConfiguration: Codable {
        static let defaultConfiguration = CloudStrandConfiguration(
            questTarget: 0.60,
            fireTarget: 0.20,
            constellationTarget: 0.20,
            questMaxConsecutive: 5,
            fireMaxGap: 10,
            constellationMaxGap: 15
        )

        var questTarget: Double
        var fireTarget: Double
        var constellationTarget: Double
        var questMaxConsecutive: Int
        var fireMaxGap: Int
        var constellationMaxGap: Int

        init(_ state: StrandWeaveState) {
            questTarget = state.questTarget
            fireTarget = state.fireTarget
            constellationTarget = state.constellationTarget
            questMaxConsecutive = state.questMaxConsecutive
            fireMaxGap = state.fireMaxGap
            constellationMaxGap = state.constellationMaxGap
        }

        init(_ tracker: StrandWeaveTracker) {
            questTarget = tracker.idealRatio[.quest] ?? 0.60
            fireTarget = tracker.idealRatio[.fire] ?? 0.20
            constellationTarget = tracker.idealRatio[.constellation] ?? 0.20
            questMaxConsecutive = tracker.redLineConfig.maxConsecutiveQuest
            fireMaxGap = tracker.redLineConfig.maxGapFire
            constellationMaxGap = tracker.redLineConfig.maxGapConstellation
        }

        private init(
            questTarget: Double,
            fireTarget: Double,
            constellationTarget: Double,
            questMaxConsecutive: Int,
            fireMaxGap: Int,
            constellationMaxGap: Int
        ) {
            self.questTarget = questTarget
            self.fireTarget = fireTarget
            self.constellationTarget = constellationTarget
            self.questMaxConsecutive = questMaxConsecutive
            self.fireMaxGap = fireMaxGap
            self.constellationMaxGap = constellationMaxGap
        }

        var isDefault: Bool {
            questTarget == Self.defaultConfiguration.questTarget
                && fireTarget == Self.defaultConfiguration.fireTarget
                && constellationTarget == Self.defaultConfiguration.constellationTarget
                && questMaxConsecutive == Self.defaultConfiguration.questMaxConsecutive
                && fireMaxGap == Self.defaultConfiguration.fireMaxGap
                && constellationMaxGap == Self.defaultConfiguration.constellationMaxGap
        }

        func apply(to state: inout StrandWeaveState) {
            state.questTarget = questTarget
            state.fireTarget = fireTarget
            state.constellationTarget = constellationTarget
            state.questMaxConsecutive = questMaxConsecutive
            state.fireMaxGap = fireMaxGap
            state.constellationMaxGap = constellationMaxGap
        }

        func makeTracker() -> StrandWeaveTracker {
            StrandWeaveTracker(
                idealRatio: [
                    .quest: questTarget,
                    .fire: fireTarget,
                    .constellation: constellationTarget
                ],
                redLineConfig: RhythmRedLineConfig(
                    maxConsecutiveQuest: questMaxConsecutive,
                    maxGapFire: fireMaxGap,
                    maxGapConstellation: constellationMaxGap
                )
            )
        }
    }

    private static func mergeCloudQualityReviewReports(
        _ first: [QualityReviewReport],
        _ second: [QualityReviewReport]
    ) -> [QualityReviewReport] {
        var reportsByID: [UUID: QualityReviewReport] = [:]
        for report in first + second {
            guard let existing = reportsByID[report.id] else {
                reportsByID[report.id] = report
                continue
            }
            if existing.reviewedAt != report.reviewedAt {
                reportsByID[report.id] = existing.reviewedAt > report.reviewedAt
                    ? existing
                    : report
            } else {
                reportsByID[report.id] = canonicalCloudValue(existing, report)
            }
        }
        return reportsByID.values.sorted {
            if $0.reviewedAt != $1.reviewedAt {
                return $0.reviewedAt < $1.reviewedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static let cloudConflictHeader =
        "【OpenWriting 同步冲突：请人工核对以下版本】"
    private static let cloudConflictSeparator =
        "\n\n【--- 同步版本分隔 ---】\n\n"

    private static func mergeConflictPreservingText(
        _ first: String,
        _ second: String
    ) -> String {
        let variants = Set(
            cloudConflictVariants(in: first)
                + cloudConflictVariants(in: second)
        )
        .filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .sorted()

        guard let only = variants.first else { return "" }
        guard variants.count > 1 else { return only }
        return cloudConflictHeader
            + cloudConflictSeparator
            + variants.joined(separator: cloudConflictSeparator)
    }

    private static func cloudConflictVariants(in text: String) -> [String] {
        guard text.hasPrefix(cloudConflictHeader) else {
            return [text]
        }
        let payload = String(text.dropFirst(cloudConflictHeader.count))
        guard payload.hasPrefix(cloudConflictSeparator) else {
            return [text]
        }
        return String(payload.dropFirst(cloudConflictSeparator.count))
            .components(separatedBy: cloudConflictSeparator)
    }

    private static func mergeCloudChapterDrafts(
        local: [ChapterDraft],
        remote: [ChapterDraft]
    ) -> [ChapterDraft] {
        var draftsByID: [String: ChapterDraft] = [:]
        for draft in local + remote {
            if let existing = draftsByID[draft.id] {
                var selected: ChapterDraft
                if existing.savedAtDate != draft.savedAtDate {
                    selected = existing.savedAtDate > draft.savedAtDate
                        ? existing
                        : draft
                } else {
                    selected = canonicalCloudValue(existing, draft)
                }
                selected.versionHistory = mergeCloudChapterVersions(
                    existing.versionHistory,
                    draft.versionHistory
                )
                draftsByID[draft.id] = selected
            } else {
                draftsByID[draft.id] = draft
            }
        }
        return draftsByID.values.sorted(by: cloudChapterSortsBefore)
    }

    private static func mergeCloudChapterVersions(
        _ first: [ChapterDraftVersion],
        _ second: [ChapterDraftVersion]
    ) -> [ChapterDraftVersion] {
        var versionsByID: [String: ChapterDraftVersion] = [:]
        for version in first + second {
            guard let existing = versionsByID[version.id] else {
                versionsByID[version.id] = version
                continue
            }
            if existing.savedAtDate != version.savedAtDate {
                versionsByID[version.id] = existing.savedAtDate > version.savedAtDate
                    ? existing
                    : version
            } else {
                versionsByID[version.id] = canonicalCloudValue(existing, version)
            }
        }
        return versionsByID.values.sorted {
            if $0.savedAtDate != $1.savedAtDate {
                return $0.savedAtDate < $1.savedAtDate
            }
            return $0.id < $1.id
        }
    }

    private static func cloudChapterSortsBefore(
        _ lhs: ChapterDraft,
        _ rhs: ChapterDraft
    ) -> Bool {
        if lhs.volumeNumber != rhs.volumeNumber {
            return lhs.volumeNumber > rhs.volumeNumber
        }
        if lhs.chapterNumber != rhs.chapterNumber {
            return lhs.chapterNumber > rhs.chapterNumber
        }
        if lhs.savedAtDate != rhs.savedAtDate {
            return lhs.savedAtDate > rhs.savedAtDate
        }
        return lhs.id < rhs.id
    }

    static func preservedCloudSelection(
        selectedProjectID: NovelProject.ID?,
        activeProjectID: NovelProject.ID?,
        snapshotActiveProjectID: NovelProject.ID?,
        projectIDs: Set<NovelProject.ID>
    ) -> NovelProject.ID? {
        [
            selectedProjectID,
            activeProjectID,
            snapshotActiveProjectID
        ]
        .compactMap { $0 }
        .first { projectIDs.contains($0) }
    }
}
