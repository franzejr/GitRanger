import AppKit
import SwiftUI

// MARK: - Custom Agent Review Sections

@MainActor
extension PRReviewView {
    @ViewBuilder
    func customAgentSection(_ agent: CustomReviewAgent) -> some View {
        let agentId = agent.id

        VStack(alignment: .leading, spacing: 0) {
            customAgentHeaderRow(agent, agentId: agentId)

            if expandedCustomAgents.contains(agentId) {
                customAgentExpandedContent(agent, agentId: agentId)
                    .padding(.top, 8)
                    .padding(.leading, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
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
                    .degrees(expandedCustomAgents.contains(agentId) ? 90 : 0)
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
                markdownView(PRReviewViewModel.stripVerdictLine(text))
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
                    await viewModel.regenerateSingleCustomAgent(agent, repo: repo)
                }
            } label: {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
