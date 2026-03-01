import AppKit
import SwiftUI

// MARK: - Sub-Agent Review Sections

extension PRReviewView {
    var disabledAgentSet: Set<String> {
        Set(repo?.disabledAgents ?? [])
    }

    var enabledCustomAgents: [CustomReviewAgent] {
        repo?.customAgents.filter(\.isEnabled) ?? []
    }

    var subAgentReviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            subAgentProgressHeader

            ForEach(ReviewAgent.allCases) { agent in
                let isDisabled = disabledAgentSet.contains(agent.rawValue)
                if isDisabled {
                    disabledBuiltInAgentRow(agent)
                } else {
                    agentSection(agent)
                }
            }

            ForEach(repo?.customAgents ?? [], id: \.id) { agent in
                if agent.isEnabled {
                    customAgentSection(agent)
                } else {
                    disabledCustomAgentRow(
                        icon: agent.icon, name: agent.name
                    )
                }
            }
        }
    }

    var subAgentProgressHeader: some View {
        HStack {
            Text(
                "\(viewModel.completedAgentCount)/\(viewModel.totalAgentCount) reviews complete"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if viewModel.isAnyAgentLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }

            Spacer()

            Button {
                guard let repo else { return }
                Task {
                    await viewModel.generateSubAgentReviews(repo: repo)
                }
            } label: {
                Label("Re-run All", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isAnyAgentLoading)
        }
    }

    // MARK: - Built-in Agent Section

    @ViewBuilder
    func agentSection(_ agent: ReviewAgent) -> some View {
        let isExpanded = expandedAgents.contains(agent)

        VStack(alignment: .leading, spacing: 0) {
            agentHeaderRow(agent, isExpanded: isExpanded)

            if isExpanded {
                agentExpandedContent(agent)
                    .padding(.top, 8)
                    .padding(.leading, 22)
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func agentHeaderRow(
        _ agent: ReviewAgent, isExpanded: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(
                    .easeInOut(duration: 0.15), value: isExpanded
                )

            agentSectionLabel(agent)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedAgents.remove(agent)
                } else {
                    expandedAgents.insert(agent)
                }
            }
        }
    }

    @ViewBuilder
    private func agentExpandedContent(
        _ agent: ReviewAgent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.agentLoading.contains(agent) {
                agentLoadingRow()
            } else if let error = viewModel.agentErrors[agent] {
                inlineError(error) {
                    guard let repo else { return }
                    Task {
                        await viewModel.regenerateSingleAgent(
                            agent, repo: repo
                        )
                    }
                }
            } else if let text = viewModel.agentReviews[agent] {
                verdictBanner(for: agent)
                markdownView(PRReviewViewModel.stripVerdictLine(text))
                agentActionButtons(agent)
            }
        }
    }

    @ViewBuilder
    private func agentActionButtons(_ agent: ReviewAgent) -> some View {
        HStack(spacing: 8) {
            if viewModel.agentCached.contains(agent) {
                cachedBadge
            }

            Button {
                guard let repo else { return }
                Task {
                    await viewModel.regenerateSingleAgent(
                        agent, repo: repo
                    )
                }
            } label: {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    func disabledBuiltInAgentRow(
        _ agent: ReviewAgent
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: agent.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(agent.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(agent.shortDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            disabledBadge
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.25)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func disabledCustomAgentRow(
        icon: String, name: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            disabledBadge
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.25)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Custom Agent Section

    @ViewBuilder
    func customAgentSection(
        _ agent: CustomReviewAgent
    ) -> some View {
        let agentId = agent.id

        VStack(alignment: .leading, spacing: 0) {
            customAgentHeaderRow(agent, agentId: agentId)

            if expandedCustomAgents.contains(agentId) {
                customAgentExpandedContent(agent, agentId: agentId)
                    .padding(.top, 8)
                    .padding(.leading, 22)
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func customAgentHeaderRow(
        _ agent: CustomReviewAgent, agentId: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(
                    .degrees(
                        expandedCustomAgents.contains(agentId) ? 90 : 0
                    )
                )
                .animation(
                    .easeInOut(duration: 0.15),
                    value: expandedCustomAgents.contains(agentId)
                )

            Image(systemName: agent.icon)
                .foregroundStyle(agent.iconColor)
                .frame(width: 20)

            Text(agent.name)
                .font(.subheadline.weight(.medium))

            Spacer()

            customAgentStatusBadge(agentId)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedCustomAgents.contains(agentId) {
                    expandedCustomAgents.remove(agentId)
                } else {
                    expandedCustomAgents.insert(agentId)
                }
            }
        }
    }

    @ViewBuilder
    private func customAgentExpandedContent(
        _ agent: CustomReviewAgent, agentId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.customAgentLoading.contains(agentId) {
                agentLoadingRow()
            } else if let error = viewModel.customAgentErrors[agentId] {
                inlineError(error) {
                    guard let repo else { return }
                    Task {
                        await viewModel.regenerateSingleCustomAgent(
                            agent, repo: repo
                        )
                    }
                }
            } else if let text = viewModel.customAgentReviews[agentId] {
                customVerdictBanner(for: agentId)
                markdownView(
                    PRReviewViewModel.stripVerdictLine(text)
                )
                customAgentActionButtons(agent, agentId: agentId)
            }
        }
    }

    @ViewBuilder
    private func customAgentActionButtons(
        _ agent: CustomReviewAgent, agentId: String
    ) -> some View {
        HStack(spacing: 8) {
            if viewModel.customAgentCached.contains(agentId) {
                cachedBadge
            }

            Button {
                guard let repo else { return }
                Task {
                    await viewModel.regenerateSingleCustomAgent(
                        agent, repo: repo
                    )
                }
            } label: {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Shared Sub-Agent Components

    func agentSectionLabel(_ agent: ReviewAgent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: agent.icon)
                .foregroundStyle(agent.iconColor)
                .frame(width: 20)

            Text(agent.displayName)
                .font(.subheadline.weight(.medium))

            Text(agent.shortDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            agentStatusBadge(agent)
        }
    }

    @ViewBuilder
    func agentStatusBadge(_ agent: ReviewAgent) -> some View {
        if viewModel.agentLoading.contains(agent) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        } else if viewModel.agentErrors[agent] != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if viewModel.agentReviews[agent] != nil {
            verdictCheckmark(viewModel.agentVerdicts[agent])
        }
    }

    @ViewBuilder
    func customAgentStatusBadge(_ agentId: String) -> some View {
        if viewModel.customAgentLoading.contains(agentId) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        } else if viewModel.customAgentErrors[agentId] != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if viewModel.customAgentReviews[agentId] != nil {
            verdictCheckmark(viewModel.customAgentVerdicts[agentId])
        }
    }

    @ViewBuilder
    private func verdictCheckmark(_ passed: Bool?) -> some View {
        if let passed {
            Image(
                systemName: passed
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .foregroundStyle(passed ? .green : .orange)
            .font(.caption)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
    }

    @ViewBuilder
    func verdictBanner(for agent: ReviewAgent) -> some View {
        if let passed = viewModel.agentVerdicts[agent] {
            verdictBannerContent(passed: passed)
        }
    }

    @ViewBuilder
    func customVerdictBanner(for agentId: String) -> some View {
        if let passed = viewModel.customAgentVerdicts[agentId] {
            verdictBannerContent(passed: passed)
        }
    }

    private func verdictBannerContent(passed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(
                systemName: passed
                    ? "checkmark.shield.fill"
                    : "exclamationmark.shield.fill"
            )
            .font(.subheadline)
            Text(passed ? "Passed" : "Issues Found")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(passed ? .green : .orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (passed ? Color.green : Color.orange).opacity(0.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func agentLoadingRow() -> some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.7)
            Text("Analyzing...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    var cachedBadge: some View {
        Text("Cached")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }

    var disabledBadge: some View {
        Text("Disabled")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
