import Foundation

extension AppState {
    @discardableResult
    func extractAndStoreMemoryItems(
        from chapterContent: String,
        chapterNumber: Int,
        for projectID: NovelProject.ID,
        review: ChapterReviewResult? = nil,
        reviewFailureReason: String? = nil,
        contractOverride: LongformStoryContractBundle? = nil
    ) -> LongformChapterCommit? {
        let chapterDraft = ChapterDraft(
            volumeNumber: max(project(for: projectID)?.currentVolumeNumber ?? 1, 1),
            chapterNumber: chapterNumber,
            chapterTitle: project(for: projectID)?.currentChapterTitle ?? "未命名章节",
            content: chapterContent,
            savedAt: Self.currentTimestampLabel()
        )
        return extractAndStoreMemoryItems(
            from: chapterDraft,
            for: projectID,
            review: review,
            reviewFailureReason: reviewFailureReason,
            contractOverride: contractOverride
        )
    }

    @discardableResult
    func extractAndStoreMemoryItems(
        from chapterDraft: ChapterDraft,
        for projectID: NovelProject.ID,
        review: ChapterReviewResult? = nil,
        reviewFailureReason: String? = nil,
        contractOverride: LongformStoryContractBundle? = nil
    ) -> LongformChapterCommit? {
        var builtCommit: LongformChapterCommit?

        updateProject(projectID) { project in
            let outcome = ChapterCommitUseCase.commit(ChapterCommitRequest(
                project: project,
                chapterDraft: chapterDraft,
                review: review,
                reviewFailureReason: reviewFailureReason,
                contractOverride: contractOverride,
                updatedAt: Self.currentTimestampLabel()
            ))
            project = outcome.project
            builtCommit = outcome.commit
        }

        return builtCommit
    }

    /// AI-powered memory extraction - runs after chapter save.
    /// Sends chapter text to LLM to extract structured memory items across all 6 buckets.
    /// Merges with keyword-based extraction for completeness.
    func runAIMemoryExtraction(
        from chapterContent: String,
        chapterNumber: Int,
        volumeNumber: Int? = nil,
        expectedCommitID: LongformChapterCommit.ID? = nil,
        projectID: NovelProject.ID
    ) {
        Task { [weak self] in
            guard let self else { return }
            let configuration = self.aiConfiguration

            // Capture project context before the async call
            let projectSnapshot: (
                title: String,
                genre: String,
                summary: String,
                volumeNumber: Int,
                chapterSummary: String,
                chapterFocus: String,
                longformContext: String,
                memoryContext: String,
                reviewContext: String
            )?
            if let project = self.project(for: projectID) {
                let runtime = project.longformRuntimeState
                let reviewContext = [
                    runtime.latestCommit?.reviewSummary,
                    runtime.latestCommit?.revisionHints?.prefix(4).joined(separator: "；")
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                projectSnapshot = (
                    project.title,
                    project.genre,
                    project.summary,
                    max(project.currentVolumeNumber, 1),
                    project.currentChapterSummary,
                    project.chapterFocus,
                    Self.boundedPromptContext(project.longformStorySystemContext, limit: 3_600),
                    Self.boundedPromptContext(project.enhancedMemoryContext, limit: 2_400),
                    Self.boundedPromptContext(reviewContext, limit: 1_200)
                )
            } else {
                projectSnapshot = nil
            }

            guard let config = configuration, let context = projectSnapshot else { return }
            let sourceVolumeNumber = max(volumeNumber ?? context.volumeNumber, 1)

            let systemPrompt = MemoryExtractionService.extractionSystemPrompt
            let userPrompt = MemoryExtractionService.extractionUserPrompt(
                chapterText: MemoryExtractionService.sampledChapterText(chapterContent),
                chapterNumber: chapterNumber,
                volumeNumber: sourceVolumeNumber,
                projectContext: """
                作品名：\(context.title)
                题材：\(context.genre)
                简介：\(context.summary)
                当前章节：\(context.chapterSummary)
                本章目标：\(context.chapterFocus)
                """,
                longformContext: context.longformContext,
                existingMemoryContext: context.memoryContext,
                reviewContext: context.reviewContext
            )

            do {
                let response = try await aiService.generateText(
                    configuration: config,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    temperature: 0.2,
                    maxTokens: 3000
                )

                guard let extractionResult = MemoryExtractionService.parseExtractionResult(from: response) else {
                    self.recordAIMemoryExtractionStatus(
                        "parse_failed",
                        volumeNumber: sourceVolumeNumber,
                        chapterNumber: chapterNumber,
                        expectedCommitID: expectedCommitID,
                        projectID: projectID
                    )
                    return
                }

                let aiItems = extractionResult.allItems(
                    sourceVolumeNumber: sourceVolumeNumber,
                    sourceChapterNumber: chapterNumber
                )
                guard !aiItems.isEmpty else {
                    self.recordAIMemoryExtractionStatus(
                        "empty",
                        volumeNumber: sourceVolumeNumber,
                        chapterNumber: chapterNumber,
                        expectedCommitID: expectedCommitID,
                        projectID: projectID
                    )
                    return
                }

                self.updateProject(projectID) { project in
                    var runtime = project.longformRuntimeState
                    if var latestCommit = runtime.latestCommit,
                       latestCommit.chapterNumber == chapterNumber,
                       latestCommit.volumeNumber == sourceVolumeNumber,
                       expectedCommitID.map({ latestCommit.id == $0 }) ?? true,
                       latestCommit.isAccepted {
                        var buckets = project.memoryBuckets
                        buckets.removeItems(
                            sourceVolumeNumber: sourceVolumeNumber,
                            sourceChapter: chapterNumber
                        )
                        for item in latestCommit.extractedMemoryItems {
                            buckets.upsert(item)
                        }
                        for item in aiItems {
                            buckets.upsert(item)
                        }
                        buckets.compact(currentVolumeNumber: sourceVolumeNumber, currentChapter: chapterNumber)
                        project.memoryBuckets = buckets

                        let existingIDs = Set(latestCommit.extractedMemoryItems.map(\.id))
                        let newItems = aiItems.filter { !existingIDs.contains($0.id) }
                        latestCommit.extractedMemoryItems.append(contentsOf: newItems)
                        latestCommit.projectionStatus["ai_memory"] = "done"
                        runtime.record(commit: latestCommit)
                        if let latestContract = runtime.latestContract {
                            runtime.record(writeGate: LongformStorySystem.buildWriteGateReport(
                                commit: latestCommit,
                                contract: latestContract
                            ))
                        }
                        project.longformRuntimeState = runtime
                    }
                }
            } catch {
                self.recordAIMemoryExtractionStatus(
                    "failed",
                    volumeNumber: sourceVolumeNumber,
                    chapterNumber: chapterNumber,
                    expectedCommitID: expectedCommitID,
                    projectID: projectID
                )
            }
        }
    }

    private func recordAIMemoryExtractionStatus(
        _ status: String,
        volumeNumber: Int,
        chapterNumber: Int,
        expectedCommitID: LongformChapterCommit.ID?,
        projectID: NovelProject.ID
    ) {
        updateProject(projectID) { project in
            var runtime = project.longformRuntimeState
            guard var latestCommit = runtime.latestCommit,
                  latestCommit.chapterNumber == chapterNumber,
                  latestCommit.volumeNumber == volumeNumber,
                  expectedCommitID.map({ latestCommit.id == $0 }) ?? true,
                  latestCommit.isAccepted
            else { return }

            latestCommit.projectionStatus["ai_memory"] = status
            runtime.record(commit: latestCommit)
            if let latestContract = runtime.latestContract {
                runtime.record(writeGate: LongformStorySystem.buildWriteGateReport(
                    commit: latestCommit,
                    contract: latestContract
                ))
            }
            project.longformRuntimeState = runtime
        }
    }
}
