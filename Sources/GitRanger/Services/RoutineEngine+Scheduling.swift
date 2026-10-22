import Foundation

@MainActor
extension RoutineEngine {
    func schedulePolling() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollDueRoutines()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func pollDueRoutines() async {
        guard !isPolling else { return }
        let due = routines.filter {
            $0.isEnabled && $0.nextRunAt <= Date()
        }
        guard !due.isEmpty else { return }

        isPolling = true
        error = nil
        for routine in due {
            await discoverPullRequests(for: routine, trigger: .schedule)
            routine.markScheduled()
        }
        persistAndRefresh()
        lastPollDate = Date()
        isPolling = false
    }

    func backfillMissingRunMetadata() async {
        let runsNeedingBackfill = runs.filter(\.needsMetadataBackfill)
        let repoIDs = Set(runsNeedingBackfill.map(\.repoID))
        guard !repoIDs.isEmpty else { return }

        var changed = false
        for repo in repositories() where repoIDs.contains(repo.id) {
            guard let pullRequests = try? await fetchPullRequests(
                for: repo,
                scope: .open
            ) else { continue }
            let pullRequestsByIdentity = Dictionary(
                uniqueKeysWithValues: pullRequests.map {
                    ("\($0.number):\($0.headRefOid)", $0)
                }
            )
            for run in runsNeedingBackfill where run.repoID == repo.id {
                let key = "\(run.prNumber):\(run.headSHA)"
                if let pullRequest = pullRequestsByIdentity[key] {
                    if run.prAuthorLogin == nil,
                       !pullRequest.authorLogin.isEmpty {
                        run.prAuthorLogin = pullRequest.authorLogin
                    }
                    run.prCreatedAt = pullRequest.createdAt
                }
                run.metadataBackfillAttemptedAt = Date()
                changed = true
            }
        }
        if changed { persistAndRefresh() }
    }

    func discoverPullRequests(
        for routine: ReviewRoutine,
        trigger: RoutineRunTrigger
    ) async {
        routine.lastError = nil
        let scopedRepos = repositories().filter {
            routine.repoIDs.contains($0.id)
        }

        for repo in scopedRepos {
            do {
                let pullRequests = try await fetchPullRequests(
                    for: repo,
                    scope: routine.scope
                )
                updateRunMetadata(from: pullRequests, repositoryID: repo.id)
                let candidates = pullRequests.filter {
                    !routine.skipDrafts || !$0.isDraft
                }
                let pending = candidates.filter { pullRequest in
                    RoutineRunPolicy.shouldEnqueue(
                        RoutineRunIdentity(
                            routineID: routine.id,
                            repoURL: repo.url,
                            prNumber: pullRequest.number,
                            headSHA: pullRequest.headRefOid
                        ),
                        existingRuns: runs
                    )
                }
                for pullRequest in pending.prefix(
                    routine.maxPullRequestsPerRun
                ) {
                    enqueue(
                        routine: routine,
                        repo: repo,
                        pullRequest: pullRequest,
                        trigger: trigger
                    )
                }
            } catch {
                routine.lastError = error.localizedDescription
                self.error = error.localizedDescription
            }
        }

        if trigger == .manual {
            routine.lastRunAt = Date()
            routine.updatedAt = Date()
        }
        persistAndRefresh()
    }

    private func updateRunMetadata(
        from pullRequests: [PullRequest],
        repositoryID: UUID
    ) {
        let pullRequestsByIdentity = Dictionary(
            uniqueKeysWithValues: pullRequests.map {
                ("\($0.number):\($0.headRefOid)", $0)
            }
        )
        for run in runs where run.repoID == repositoryID
            && run.needsMetadataBackfill {
            let key = "\(run.prNumber):\(run.headSHA)"
            guard let pullRequest = pullRequestsByIdentity[key] else { continue }
            if run.prAuthorLogin == nil, !pullRequest.authorLogin.isEmpty {
                run.prAuthorLogin = pullRequest.authorLogin
            }
            run.prCreatedAt = pullRequest.createdAt
        }
    }

    func fetchPullRequests(
        for repo: Repo,
        scope: RoutinePRScope
    ) async throws -> [PullRequest] {
        if GitLabService.shared.isGitLabRepo(url: repo.url) {
            switch scope {
            case .open:
                return try await GitLabService.shared.listMergeRequests(
                    repoUrl: repo.url,
                    host: repo.glHost
                )
            case .pendingMyReview:
                return try await GitLabService.shared.listPendingReviews(
                    repoUrl: repo.url,
                    host: repo.glHost
                )
            }
        }

        switch scope {
        case .open:
            return try await GitHubService.shared.listPullRequests(
                repoUrl: repo.url,
                account: repo.ghAccount
            )
        case .pendingMyReview:
            return try await GitHubService.shared.listPendingReviews(
                repoUrl: repo.url,
                account: repo.ghAccount
            )
        }
    }

    func enqueue(
        routine: ReviewRoutine,
        repo: Repo,
        pullRequest: PullRequest,
        trigger: RoutineRunTrigger,
        allowRetry: Bool = false,
        agentIDs: [String]? = nil,
        seedSnapshots: [RoutineAgentSnapshot] = []
    ) {
        let selectedAgentIDs = agentIDs ?? routine.agentIDs
        guard !selectedAgentIDs.isEmpty else { return }
        let identity = RoutineRunIdentity(
            routineID: routine.id,
            repoURL: repo.url,
            prNumber: pullRequest.number,
            headSHA: pullRequest.headRefOid
        )
        guard RoutineRunPolicy.shouldEnqueue(
            identity,
            existingRuns: runs,
            allowRetry: allowRetry
        ) else {
            return
        }

        guard let modelContext else { return }
        let run = RoutineRun(
            routine: routine,
            repo: repo,
            pullRequest: pullRequest,
            trigger: trigger
        )
        run.agentSnapshots = seedSnapshots
        modelContext.insert(run)
        try? modelContext.save()
        runs.insert(run, at: 0)

        let repository = RoutineRepositoryContext(
            id: repo.id,
            name: repo.name,
            url: repo.url,
            localPath: repo.localPath,
            githubAccount: repo.ghAccount,
            gitlabHost: repo.glHost,
            agentPrompts: repo.agentPrompts ?? [:],
            customAgents: repo.customAgents
        )
        let request = RoutinePipelineRequest(
            routineID: routine.id,
            repository: repository,
            pullRequest: pullRequest,
            agentIDs: selectedAgentIDs,
            provider: routine.provider,
            modelName: routine.modelName
        )
        schedule(runID: run.id, request: request)
    }
}
