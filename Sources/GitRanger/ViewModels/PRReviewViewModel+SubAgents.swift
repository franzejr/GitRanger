import Foundation

// MARK: - Sub-Agent Review Generation

extension PRReviewViewModel {
    struct ReviewContext {
        let input: PromptBuilder.PRReviewInput
        let repo: Repo
        let pr: PullRequest
        let provider: any AIServiceProtocol
        let repoPath: URL
    }

    func enabledAgents(for repo: Repo) -> [ReviewAgent] {
        let disabled = Set(repo.disabledAgents ?? [])
        return ReviewAgent.allCases.filter {
            !disabled.contains($0.rawValue)
        }
    }

    func generateSubAgentReviews(repo: Repo) async {
        guard let pr = selectedPR, let diff else { return }
        let agents = enabledAgents(for: repo)
        let customAgents = repo.customAgents.filter(\.isEnabled)
        guard !agents.isEmpty || !customAgents.isEmpty else { return }

        resetSubAgentState(
            agents: agents, customAgents: customAgents
        )

        do {
            let input = try await buildPRInput(
                pr: pr, repo: repo, diff: diff
            )
            let ctx = ReviewContext(
                input: input,
                repo: repo,
                pr: pr,
                provider: AIServiceFactory.activeProvider(),
                repoPath: URL(fileURLWithPath: repo.localPath)
            )

            await runAllAgents(
                agents: agents,
                customAgents: customAgents,
                ctx: ctx
            )
        } catch {
            self.error = error.localizedDescription
            agentLoading = []
            agentQueued = []
            customAgentLoading = []
            customAgentQueued = []
        }

        isLoading = false
    }

    func regenerateSingleAgent(
        _ agent: ReviewAgent, repo: Repo
    ) async {
        guard let pr = selectedPR, let diff else { return }
        agentQueued.remove(agent)
        agentLoading.insert(agent)
        agentErrors.removeValue(forKey: agent)
        agentCached.remove(agent)
        agentVerdicts.removeValue(forKey: agent)

        do {
            let input = try await buildPRInput(
                pr: pr, repo: repo, diff: diff
            )

            let customInstructions = repo.agentPrompts?[agent.rawValue]
            let prompt = PromptBuilder.buildSubAgentPrompt(
                agent: agent,
                input: input,
                customInstructions: customInstructions
            )
            let provider = AIServiceFactory.activeProvider()
            let result = try await provider.generate(
                prompt: prompt,
                repoPath: URL(fileURLWithPath: repo.localPath)
            )

            agentReviews[agent] = result
            agentVerdicts[agent] = Self.parseVerdict(result)
            agentMetadata[agent] = reviewMetadata(
                reviewerName: agent.displayName,
                provider: provider
            )
            saveSubAgentReview(.init(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid,
                agentKind: agent.rawValue,
                reviewText: result,
                providerName: provider.displayName,
                reviewerName: agent.displayName,
                modelName: provider.modelName
            ))
        } catch {
            agentErrors[agent] = error.localizedDescription
        }

        agentLoading.remove(agent)
    }

    func regenerateSingleCustomAgent(
        _ customAgent: CustomReviewAgent, repo: Repo
    ) async {
        guard let pr = selectedPR, let diff else { return }
        let agentId = customAgent.id
        customAgentQueued.remove(agentId)
        customAgentLoading.insert(agentId)
        customAgentErrors.removeValue(forKey: agentId)
        customAgentCached.remove(agentId)
        customAgentVerdicts.removeValue(forKey: agentId)

        do {
            let input = try await buildPRInput(
                pr: pr, repo: repo, diff: diff
            )
            let prompt = PromptBuilder.buildCustomAgentPrompt(
                customAgent: customAgent,
                input: input
            )
            let provider = AIServiceFactory.activeProvider()
            let result = try await provider.generate(
                prompt: prompt,
                repoPath: URL(fileURLWithPath: repo.localPath)
            )

            customAgentReviews[agentId] = result
            customAgentVerdicts[agentId] = Self.parseVerdict(result)
            customAgentMetadata[agentId] = reviewMetadata(
                reviewerName: customAgent.name,
                provider: provider
            )
            saveSubAgentReview(.init(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid,
                agentKind: "custom_\(agentId)",
                reviewText: result,
                providerName: provider.displayName,
                reviewerName: customAgent.name,
                modelName: provider.modelName
            ))
        } catch {
            customAgentErrors[agentId] = error.localizedDescription
        }

        customAgentLoading.remove(agentId)
    }

    // MARK: - Deep Verify (second pass per agent)

    func deepVerifyAgent(
        _ agent: ReviewAgent, repo: Repo
    ) async {
        guard let pr = selectedPR, let diff,
              let firstReview = agentReviews[agent] else { return }

        agentDeepLoading.insert(agent)
        agentDeepErrors.removeValue(forKey: agent)
        agentDeepVerdicts.removeValue(forKey: agent)

        do {
            let input = try await buildPRInput(
                pr: pr, repo: repo, diff: diff
            )
            let prompt = PromptBuilder.buildDeepVerifyPrompt(
                agent: agent,
                firstReview: firstReview,
                input: input
            )
            let provider = AIServiceFactory.activeProvider()
            let result = try await provider.generate(
                prompt: prompt,
                repoPath: URL(fileURLWithPath: repo.localPath)
            )

            agentDeepReviews[agent] = result
            agentDeepVerdicts[agent] = Self.parseVerdict(result)
            agentDeepMetadata[agent] = reviewMetadata(
                reviewerName: "\(agent.displayName) verification",
                provider: provider
            )
        } catch {
            agentDeepErrors[agent] = error.localizedDescription
        }

        agentDeepLoading.remove(agent)
    }

    // MARK: - Private Helpers

    private func resetSubAgentState(
        agents: [ReviewAgent],
        customAgents: [CustomReviewAgent]
    ) {
        isLoading = true
        error = nil
        agentReviews = [:]
        agentErrors = [:]
        agentLoading = []
        agentQueued = Set(agents)
        agentCached = []
        agentVerdicts = [:]
        agentMetadata = [:]
        customAgentReviews = [:]
        customAgentErrors = [:]
        customAgentLoading = []
        customAgentQueued = Set(customAgents.map(\.id))
        customAgentCached = []
        customAgentVerdicts = [:]
        customAgentMetadata = [:]
        launchedAgentCount = agents.count + customAgents.count
    }

    func buildPRInput(
        pr: PullRequest, repo: Repo, diff: String
    ) async throws -> PromptBuilder.PRReviewInput {
        let detail: PRDetail
        if let prDetail {
            detail = prDetail
        } else if gitlabService.isGitLabRepo(url: repo.url) {
            detail = try await gitlabService.getMRDetail(
                repoUrl: repo.url, mrNumber: pr.number, host: repo.glHost
            )
            prDetail = detail
        } else {
            detail = try await githubService.getPRDetail(
                repoUrl: repo.url, prNumber: pr.number, account: repo.ghAccount
            )
            prDetail = detail
        }
        return PromptBuilder.PRReviewInput(
            prTitle: pr.title,
            prBody: detail.body,
            prAuthor: pr.authorLogin,
            baseBranch: pr.baseRefName,
            headBranch: pr.headRefName,
            diff: diff
        )
    }

    private func runAllAgents(
        agents: [ReviewAgent],
        customAgents: [CustomReviewAgent],
        ctx: ReviewContext
    ) async {
        let jobs = agents.map(ReviewJob.builtIn)
            + customAgents.map(ReviewJob.custom)
        let parallelReviewLimit = 2

        await withTaskGroup(of: AgentTaskResult.self) { group in
            var nextJobIndex = 0
            for _ in 0..<min(parallelReviewLimit, jobs.count) {
                enqueueReviewJob(jobs[nextJobIndex], in: &group, ctx: ctx)
                nextJobIndex += 1
            }

            while let taskResult = await group.next() {
                handleAgentResult(taskResult, ctx: ctx)
                if nextJobIndex < jobs.count {
                    enqueueReviewJob(
                        jobs[nextJobIndex], in: &group, ctx: ctx
                    )
                    nextJobIndex += 1
                }
            }
        }
    }

    private func enqueueReviewJob(
        _ job: ReviewJob,
        in group: inout TaskGroup<AgentTaskResult>,
        ctx: ReviewContext
    ) {
        switch job {
        case .builtIn(let agent):
            agentQueued.remove(agent)
            agentLoading.insert(agent)
            let prompts = ctx.repo.agentPrompts
            group.addTask {
                do {
                    let prompt = PromptBuilder.buildSubAgentPrompt(
                        agent: agent,
                        input: ctx.input,
                        customInstructions: prompts?[agent.rawValue]
                    )
                    let result = try await ctx.provider.generate(
                        prompt: prompt,
                        repoPath: ctx.repoPath
                    )
                    return .builtIn(agent, .success(result))
                } catch {
                    return .builtIn(agent, .failure(error))
                }
            }

        case .custom(let custom):
            customAgentQueued.remove(custom.id)
            customAgentLoading.insert(custom.id)
            group.addTask {
                do {
                    let prompt = PromptBuilder.buildCustomAgentPrompt(
                        customAgent: custom,
                        input: ctx.input
                    )
                    let result = try await ctx.provider.generate(
                        prompt: prompt,
                        repoPath: ctx.repoPath
                    )
                    return .custom(custom.id, .success(result))
                } catch {
                    return .custom(custom.id, .failure(error))
                }
            }
        }
    }

    private func handleAgentResult(
        _ taskResult: AgentTaskResult, ctx: ReviewContext
    ) {
        switch taskResult {
        case .builtIn(let agent, let result):
            handleBuiltInResult(agent, result: result, ctx: ctx)

        case .custom(let agentId, let result):
            handleCustomResult(agentId, result: result, ctx: ctx)
        }
    }

    private func handleBuiltInResult(
        _ agent: ReviewAgent,
        result: Result<String, Error>,
        ctx: ReviewContext
    ) {
        agentLoading.remove(agent)
        switch result {
        case .success(let text):
            agentReviews[agent] = text
            agentVerdicts[agent] = Self.parseVerdict(text)
            agentMetadata[agent] = reviewMetadata(
                reviewerName: agent.displayName,
                provider: ctx.provider
            )
            saveSubAgentReview(.init(
                repoUrl: ctx.repo.url,
                prNumber: ctx.pr.number,
                headSha: ctx.pr.headRefOid,
                agentKind: agent.rawValue,
                reviewText: text,
                providerName: ctx.provider.displayName,
                reviewerName: agent.displayName,
                modelName: ctx.provider.modelName
            ))
        case .failure(let error):
            agentErrors[agent] = error.localizedDescription
        }
    }

    private func handleCustomResult(
        _ agentId: String,
        result: Result<String, Error>,
        ctx: ReviewContext
    ) {
        customAgentLoading.remove(agentId)
        switch result {
        case .success(let text):
            customAgentReviews[agentId] = text
            customAgentVerdicts[agentId] = Self.parseVerdict(text)
            let reviewerName = ctx.repo.customAgents.first {
                $0.id == agentId
            }?.name ?? "Custom reviewer"
            customAgentMetadata[agentId] = reviewMetadata(
                reviewerName: reviewerName,
                provider: ctx.provider
            )
            saveSubAgentReview(.init(
                repoUrl: ctx.repo.url,
                prNumber: ctx.pr.number,
                headSha: ctx.pr.headRefOid,
                agentKind: "custom_\(agentId)",
                reviewText: text,
                providerName: ctx.provider.displayName,
                reviewerName: reviewerName,
                modelName: ctx.provider.modelName
            ))
        case .failure(let error):
            customAgentErrors[agentId] = error.localizedDescription
        }
    }

    private func reviewMetadata(
        reviewerName: String,
        provider: any AIServiceProtocol
    ) -> ReviewRunMetadata {
        ReviewRunMetadata(
            reviewerName: reviewerName,
            providerName: provider.displayName,
            modelName: provider.modelName,
            reviewedAt: Date()
        )
    }
}
