import Foundation

struct RoutineRepositoryContext: Sendable {
    let id: UUID
    let name: String
    let url: String
    let localPath: String
    let githubAccount: String?
    let gitlabHost: String?
    let agentPrompts: [String: String]
    let customAgents: [CustomReviewAgent]
}

struct RoutinePipelineRequest: Sendable {
    let routineID: UUID
    let repository: RoutineRepositoryContext
    let pullRequest: PullRequest
    let agentIDs: [String]
    let provider: AIProvider?
    let modelName: String?
}

enum RoutinePipelineEvent: Sendable {
    case run(RoutineRunStatus, String)
    case agent(RoutineAgentSnapshot)
}

struct RoutinePipelineOutput: Sendable {
    let agents: [RoutineAgentSnapshot]
    let comment: String

    var hasFailures: Bool {
        agents.contains { $0.status != .completed }
    }

    var failureSummary: String? {
        let unsuccessful = agents.filter { $0.status != .completed }
        let messages = Array(Set(unsuccessful.compactMap(\.error))).sorted()
        guard !unsuccessful.isEmpty else { return nil }
        guard !messages.isEmpty else {
            return "\(unsuccessful.count) review agent(s) did not complete. Nothing was posted."
        }
        if messages.count == 1, let message = messages.first {
            return "\(unsuccessful.count) review agent(s) failed: \(message)"
        }
        return "\(unsuccessful.count) review agent(s) failed. Nothing was posted.\n"
            + messages.map { "• \($0)" }.joined(separator: "\n")
    }
}

private enum RoutinePipelineJob: Sendable {
    case builtIn(ReviewAgent)
    case custom(CustomReviewAgent)

    var id: String {
        switch self {
        case .builtIn(let agent): agent.rawValue
        case .custom(let agent): "custom:\(agent.id)"
        }
    }

    var name: String {
        switch self {
        case .builtIn(let agent): agent.displayName
        case .custom(let agent): agent.name
        }
    }
}

actor RoutineReviewPipeline {
    static let shared = RoutineReviewPipeline()
    nonisolated static let quickReviewReasoningEffort = "low"

    typealias ProgressHandler = @Sendable (RoutinePipelineEvent) async -> Void

    // swiftlint:disable:next function_body_length
    func run(
        _ request: RoutinePipelineRequest,
        progress: @escaping ProgressHandler
    ) async throws -> RoutinePipelineOutput {
        await progress(.run(.loading, "Loading pull request content"))

        let contentRequest = PRContentRequest(
            repoURL: request.repository.url,
            prNumber: request.pullRequest.number,
            headSHA: request.pullRequest.headRefOid,
            githubAccount: request.repository.githubAccount,
            gitlabHost: request.repository.gitlabHost
        )
        let content = try await PRContentLoader.shared.load(contentRequest).content
        try Task.checkCancellation()

        let input = PromptBuilder.PRReviewInput(
            prTitle: request.pullRequest.title,
            prBody: content.detail.body,
            prAuthor: request.pullRequest.authorLogin,
            baseBranch: request.pullRequest.baseRefName,
            headBranch: request.pullRequest.headRefName,
            diff: content.diff
        )
        let provider = configuredProvider(
            request.provider,
            modelName: request.modelName
        )
        let jobs = jobs(for: request)

        guard !jobs.isEmpty else {
            throw RoutinePipelineError.noAgents
        }

        for job in jobs {
            await progress(.agent(RoutineAgentSnapshot(
                id: job.id,
                name: job.name,
                status: .queued,
                phase: "Waiting for AI capacity",
                providerName: provider.displayName,
                modelName: provider.modelName,
                reasoningEffort: Self.quickReviewReasoningEffort
            )))
        }

        await progress(.run(.reviewing, "Running \(jobs.count) review agents"))
        let results = await runJobs(
            jobs,
            input: input,
            request: request,
            provider: provider,
            progress: progress
        )

        try Task.checkCancellation()
        await progress(.run(.aggregating, "Combining agent findings"))
        return RoutinePipelineOutput(
            agents: results,
            comment: Self.buildComment(request: request, agents: results, diff: content.diff)
        )
    }

    private func configuredProvider(
        _ override: AIProvider?,
        modelName: String?
    ) -> any AIServiceProtocol {
        var settings = AIServiceFactory.settingsFromUserDefaults()
        let provider = override ?? settings.aiProvider
        settings.aiProvider = provider
        return CoordinatedAIService(
            base: AIServiceFactory.create(
                provider: provider,
                settings: settings,
                modelOverride: modelName,
                reasoningEffortOverride: Self.quickReviewReasoningEffort
            )
        )
    }

    private func jobs(
        for request: RoutinePipelineRequest
    ) -> [RoutinePipelineJob] {
        request.agentIDs.compactMap { id in
            if let agent = ReviewAgent(rawValue: id) {
                return .builtIn(agent)
            }
            guard id.hasPrefix("custom:") else { return nil }
            let customID = String(id.dropFirst("custom:".count))
            guard let agent = request.repository.customAgents.first(where: {
                $0.id == customID && $0.isEnabled
            }) else { return nil }
            return .custom(agent)
        }
    }

    private func runJobs(
        _ jobs: [RoutinePipelineJob],
        input: PromptBuilder.PRReviewInput,
        request: RoutinePipelineRequest,
        provider: any AIServiceProtocol,
        progress: @escaping ProgressHandler
    ) async -> [RoutineAgentSnapshot] {
        var snapshots = Self.reviewingSnapshots(jobs, provider: provider)
        for snapshot in snapshots {
            await progress(.agent(snapshot))
        }

        do {
            try Task.checkCancellation()
            let response = try await provider.generate(
                prompt: Self.buildBatchPrompt(
                    jobs: jobs,
                    input: input,
                    request: request
                ),
                repoPath: nil,
                timeout: 180
            )
            let sections = Self.parseBatchSections(
                response,
                agentIDs: jobs.map(\.id)
            )
            snapshots = Self.applying(sections, to: snapshots)
        } catch is CancellationError {
            snapshots = Self.finishing(
                snapshots,
                status: .cancelled,
                phase: "Cancelled"
            )
        } catch {
            snapshots = Self.finishing(
                snapshots,
                status: .failed,
                phase: "Review failed",
                error: error.localizedDescription
            )
        }

        for snapshot in snapshots {
            await progress(.agent(snapshot))
        }
        return snapshots
    }
}

extension RoutineReviewPipeline {
    private nonisolated static func reviewingSnapshots(
        _ jobs: [RoutinePipelineJob],
        provider: any AIServiceProtocol
    ) -> [RoutineAgentSnapshot] {
        let startedAt = Date()
        return jobs.map { job in
            RoutineAgentSnapshot(
                id: job.id,
                name: job.name,
                status: .reviewing,
                phase: "Reviewing pull request",
                providerName: provider.displayName,
                modelName: provider.modelName,
                reasoningEffort: Self.quickReviewReasoningEffort,
                startedAt: startedAt
            )
        }
    }

    private nonisolated static func applying(
        _ sections: [String: String],
        to snapshots: [RoutineAgentSnapshot]
    ) -> [RoutineAgentSnapshot] {
        snapshots.map { snapshot in
            guard let review = sections[snapshot.id], !review.isEmpty else {
                var failed = snapshot
                failed.status = .failed
                failed.phase = "Review failed"
                failed.error = "The AI response omitted this agent's section."
                failed.completedAt = Date()
                return failed
            }
            var completed = snapshot
            completed.status = .completed
            completed.phase = "Review complete"
            completed.reviewText = review
            completed.verdict = parseVerdict(review)
            completed.completedAt = Date()
            return completed
        }
    }

    private nonisolated static func finishing(
        _ snapshots: [RoutineAgentSnapshot],
        status: RoutineAgentStatus,
        phase: String,
        error: String? = nil
    ) -> [RoutineAgentSnapshot] {
        let completedAt = Date()
        return snapshots.map { snapshot in
            var result = snapshot
            result.status = status
            result.phase = phase
            result.error = error
            result.completedAt = completedAt
            return result
        }
    }

    // swiftlint:disable:next function_body_length
    private nonisolated static func buildBatchPrompt(
        jobs: [RoutinePipelineJob],
        input: PromptBuilder.PRReviewInput,
        request: RoutinePipelineRequest
    ) -> String {
        let roles = jobs.map { job in
            let instructions: String
            switch job {
            case .builtIn(let agent):
                instructions = request.repository.agentPrompts[agent.rawValue]
                    .flatMap { $0.isEmpty ? nil : $0 }
                    ?? PromptBuilder.agentPrompt(for: agent)
            case .custom(let agent):
                instructions = agent.prompt
            }
            return """
            Agent ID: \(job.id)
            Agent name: \(job.name)
            Instructions:
            \(instructions)
            """
        }.joined(separator: "\n\n")
        let outputFormat = jobs.map { job in
            """
            <<<GITRANGER_AGENT:\(job.id)>>>
            VERDICT: PASS or VERDICT: FAIL
            Concise findings for \(job.name)
            <<<GITRANGER_END_AGENT>>>
            """
        }.joined(separator: "\n")
        let truncatedDiff = ReviewDiffScope.promptDiff(input.diff)

        return """
        Perform a quick review covering the following independent roles in one pass. Use low \
        reasoning effort and complete the entire batch within 3 minutes. Analyze only the supplied \
        pull request context and diff. Do not inspect the repository, run commands, or perform broad \
        searches. Prefer concise, high-confidence findings. If a role finds no significant issue, \
        mark it PASS and say so briefly.

        --- Roles ---
        \(roles)

        --- Required output format ---
        Return every section exactly once, in this order, using these exact markers:
        \(outputFormat)

        --- Pull Request ---
        Title: \(input.prTitle)
        Author: \(input.prAuthor)
        Branch: \(input.headBranch) -> \(input.baseBranch)

        Description:
        \(input.prBody.isEmpty ? "(no description)" : input.prBody)

        --- Diff ---
        \(truncatedDiff)
        """
    }

    nonisolated static func parseBatchSections(
        _ response: String,
        agentIDs: [String]
    ) -> [String: String] {
        let endMarker = "<<<GITRANGER_END_AGENT>>>"
        var sections: [String: String] = [:]
        for id in agentIDs {
            let startMarker = "<<<GITRANGER_AGENT:\(id)>>>"
            guard let start = response.range(of: startMarker),
                  let end = response.range(
                    of: endMarker,
                    range: start.upperBound..<response.endIndex
                  ) else {
                continue
            }
            sections[id] = response[start.upperBound..<end.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sections
    }

    nonisolated static func buildComment(
        request: RoutinePipelineRequest,
        agents: [RoutineAgentSnapshot],
        diff: String? = nil
    ) -> String {
        var lines = ReviewCommentFormatter.header(
            mode: "Quick review",
            agentCount: agents.count,
            headSHA: request.pullRequest.headRefOid
        )

        if let diff, let warning = ReviewDiffScope.warning(for: diff) {
            lines += ["> **\(warning)**", ""]
        }

        for agent in agents where agent.status == .completed {
            let icon = agent.verdict == false ? "⚠️" : "✅"
            lines.append("### \(icon) \(agent.name)")
            if let provider = agent.providerName, let model = agent.modelName {
                let effort = agent.reasoningEffort
                    ?? Self.quickReviewReasoningEffort
                lines.append(ReviewCommentFormatter.metadata(
                    provider: provider,
                    model: model,
                    reasoningEffort: effort
                ))
            }
            lines.append(Self.stripVerdictLine(agent.reviewText ?? ""))
            lines.append("")
        }

        lines.append(RoutinePublicationMarker.value(
            routineID: request.routineID,
            headSHA: request.pullRequest.headRefOid
        ))
        return lines.joined(separator: "\n")
    }

    private static func parseVerdict(_ text: String) -> Bool? {
        let firstLine = text.components(separatedBy: .newlines)
            .first?
            .uppercased() ?? ""
        if firstLine.contains("VERDICT: PASS") { return true }
        if firstLine.contains("VERDICT: FAIL") { return false }
        return nil
    }

    private static func stripVerdictLine(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let first = lines.first,
              first.uppercased().contains("VERDICT:") else {
            return text
        }
        return lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RoutinePipelineError: LocalizedError {
    case noAgents

    var errorDescription: String? {
        switch self {
        case .noAgents: "This routine has no available review agents."
        }
    }
}
