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
        }

        isLoading = false
    }

    func regenerateSingleAgent(
        _ agent: ReviewAgent, repo: Repo
    ) async {
        guard let pr = selectedPR, let diff else { return }
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
            saveSubAgentReview(.init(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid,
                agentKind: agent.rawValue,
                reviewText: result,
                providerName: provider.displayName
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
            saveSubAgentReview(.init(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid,
                agentKind: "custom_\(agentId)",
                reviewText: result,
                providerName: provider.displayName
            ))
        } catch {
            customAgentErrors[agentId] = error.localizedDescription
        }

        customAgentLoading.remove(agentId)
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
        agentLoading = Set(agents)
        agentCached = []
        agentVerdicts = [:]
        customAgentReviews = [:]
        customAgentErrors = [:]
        customAgentLoading = Set(customAgents.map(\.id))
        customAgentCached = []
        customAgentVerdicts = [:]
        launchedAgentCount = agents.count + customAgents.count
    }

    func buildPRInput(
        pr: PullRequest, repo: Repo, diff: String
    ) async throws -> PromptBuilder.PRReviewInput {
        let prDetail: PRDetail
        if gitlabService.isGitLabRepo(url: repo.url) {
            prDetail = try await gitlabService.getMRDetail(
                repoUrl: repo.url,
                mrNumber: pr.number,
                host: repo.glHost
            )
        } else {
            prDetail = try await githubService.getPRDetail(
                repoUrl: repo.url,
                prNumber: pr.number,
                account: repo.ghAccount
            )
        }
        return PromptBuilder.PRReviewInput(
            prTitle: pr.title,
            prBody: prDetail.body,
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
        await withTaskGroup(of: AgentTaskResult.self) { group in
            for agent in agents {
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
            }

            for custom in customAgents {
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

            for await taskResult in group {
                handleAgentResult(taskResult, ctx: ctx)
            }
        }
    }

    private func handleAgentResult(
        _ taskResult: AgentTaskResult, ctx: ReviewContext
    ) {
        switch taskResult {
        case .builtIn(let agent, let result):
            agentLoading.remove(agent)
            switch result {
            case .success(let text):
                agentReviews[agent] = text
                agentVerdicts[agent] = Self.parseVerdict(text)
                saveSubAgentReview(.init(
                    repoUrl: ctx.repo.url,
                    prNumber: ctx.pr.number,
                    headSha: ctx.pr.headRefOid,
                    agentKind: agent.rawValue,
                    reviewText: text,
                    providerName: ctx.provider.displayName
                ))
            case .failure(let err):
                agentErrors[agent] = err.localizedDescription
            }

        case .custom(let agentId, let result):
            customAgentLoading.remove(agentId)
            switch result {
            case .success(let text):
                customAgentReviews[agentId] = text
                customAgentVerdicts[agentId] = Self.parseVerdict(text)
                saveSubAgentReview(.init(
                    repoUrl: ctx.repo.url,
                    prNumber: ctx.pr.number,
                    headSha: ctx.pr.headRefOid,
                    agentKind: "custom_\(agentId)",
                    reviewText: text,
                    providerName: ctx.provider.displayName
                ))
            case .failure(let err):
                customAgentErrors[agentId] = err.localizedDescription
            }
        }
    }
}
