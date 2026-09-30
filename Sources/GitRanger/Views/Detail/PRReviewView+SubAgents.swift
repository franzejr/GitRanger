import SwiftUI

@MainActor
extension PRReviewView {
    var disabledAgentSet: Set<String> {
        Set(repo?.disabledAgents ?? [])
    }

    var enabledCustomAgents: [CustomReviewAgent] {
        repo?.customAgents.filter(\.isEnabled) ?? []
    }

    var subAgentReviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            narrativeCard
            subAgentProgressHeader

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                    count: ReviewAgent.allCases.count
                ),
                spacing: 8
            ) {
                ForEach(ReviewAgent.allCases) { agent in
                    agentCard(agent)
                }
            }

            ForEach(ReviewAgent.allCases) { agent in
                if expandedAgents.contains(agent) {
                    agentExpandedPanel(agent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            ForEach(repo?.customAgents ?? [], id: \.id) { agent in
                if agent.isEnabled {
                    customAgentSection(agent)
                }
            }
        }
    }

    @ViewBuilder
    private var narrativeCard: some View {
        if let text = viewModel.agentReviews[.summary] {
            HStack(alignment: .top, spacing: 14) {
                GRMonogram(size: 26)
                VStack(alignment: .leading, spacing: 5) {
                    Text("NARRATIVE · AI REVIEW")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    markdownView(PRReviewViewModel.stripVerdictLine(text))
                        .font(.system(size: 12.5))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .grCard()
        }
    }

    var subAgentProgressHeader: some View {
        HStack(spacing: 8) {
            GRSectionLabel(
                title: "Sub-agent review · \(viewModel.completedAgentCount)/\(enabledReviewCount) complete"
            )

            if viewModel.isAnyAgentLoading {
                ProgressView().controlSize(.small)
            }

            Spacer()

            if !viewModel.agentCached.isEmpty,
               let sha = viewModel.selectedPR?.headRefOid {
                Text("cached · head \(String(sha.prefix(7)))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if viewModel.completedAgentCount > 0 && !viewModel.isAnyAgentLoading {
                Button {
                    guard let repo else { return }
                    Task { await viewModel.postReviewAsComment(repo: repo) }
                } label: {
                    Image(systemName: "paperplane")
                }
                .buttonStyle(.plain)
                .help("Post reviews as a comment")
                .disabled(viewModel.isSubmittingAction)
            }
        }
    }

    private var enabledReviewCount: Int {
        ReviewAgent.allCases.filter {
            !disabledAgentSet.contains($0.rawValue)
        }.count + enabledCustomAgents.count
    }

    private func agentCard(_ agent: ReviewAgent) -> some View {
        let isDisabled = disabledAgentSet.contains(agent.rawValue)
        let passed = viewModel.agentVerdicts[agent]
        let warning = passed == false

        return VStack(alignment: .leading, spacing: 8) {
            agentCardHeader(agent, disabled: isDisabled)

            Text(agent.shortDescription)
                .font(.system(size: 10.5))
                .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                .lineLimit(3)
                .frame(minHeight: 30, alignment: .topLeading)

            HStack(spacing: 6) {
                Text(agentVerdictLabel(agent, disabled: isDisabled))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(agentVerdictColor(agent, disabled: isDisabled))
                Spacer(minLength: 0)
                if !isDisabled {
                    agentRunButton(agent)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(GRTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(warning ? GRTheme.warning : GRTheme.line(colorScheme), lineWidth: 1)
        }
        .opacity(isDisabled ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDisabled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                if expandedAgents.contains(agent) {
                    expandedAgents.remove(agent)
                } else {
                    expandedAgents.insert(agent)
                }
            }
        }
    }

    private func agentCardHeader(_ agent: ReviewAgent, disabled: Bool) -> some View {
        HStack(spacing: 4) {
            Text(agent.displayName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if !disabled {
                agentStatusDot(agent)
            }
        }
    }

    private func agentRunButton(_ agent: ReviewAgent) -> some View {
        let hasReview = viewModel.agentReviews[agent] != nil
        return Button(hasReview ? "Re-run" : "Run") {
            guard let repo else { return }
            Task { await viewModel.regenerateSingleAgent(agent, repo: repo) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(GRTheme.link(colorScheme))
        .disabled(viewModel.agentLoading.contains(agent))
        .help("\(hasReview ? "Re-run" : "Run") \(agent.displayName)")
    }

    @ViewBuilder
    private func agentStatusDot(_ agent: ReviewAgent) -> some View {
        if viewModel.agentLoading.contains(agent) {
            ProgressView().controlSize(.mini)
        } else if viewModel.agentErrors[agent] != nil {
            Circle().fill(GRTheme.danger).frame(width: 8, height: 8)
        } else if let passed = viewModel.agentVerdicts[agent] {
            Circle()
                .fill(passed ? GRTheme.success : GRTheme.warning)
                .frame(width: 8, height: 8)
        } else if viewModel.agentReviews[agent] != nil {
            Circle().fill(GRTheme.success).frame(width: 8, height: 8)
        }
    }

    private func agentVerdictLabel(_ agent: ReviewAgent, disabled: Bool) -> String {
        if disabled { return "DISABLED" }
        if viewModel.agentLoading.contains(agent) { return "ANALYZING" }
        if viewModel.agentErrors[agent] != nil { return "FAILED" }
        if let passed = viewModel.agentVerdicts[agent] {
            return passed ? "PASSED" : "ISSUES FOUND"
        }
        if viewModel.agentReviews[agent] != nil { return "COMPLETE" }
        return "PENDING"
    }

    private func agentVerdictColor(_ agent: ReviewAgent, disabled: Bool) -> Color {
        if disabled { return GRTheme.muted(colorScheme) }
        if viewModel.agentErrors[agent] != nil { return GRTheme.danger }
        if viewModel.agentVerdicts[agent] == false { return GRTheme.warning }
        if viewModel.agentReviews[agent] != nil { return GRTheme.success }
        return GRTheme.muted(colorScheme)
    }

    @ViewBuilder
    private func agentExpandedPanel(_ agent: ReviewAgent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.agentLoading.contains(agent) {
                agentLoadingRow()
            } else if let error = viewModel.agentErrors[agent] {
                inlineError(error) {
                    guard let repo else { return }
                    Task { await viewModel.regenerateSingleAgent(agent, repo: repo) }
                }
            } else if let text = viewModel.agentReviews[agent] {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(viewModel.agentVerdicts[agent] == false
                            ? GRTheme.warning : GRTheme.success)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(agent.displayName)
                            .font(.system(size: 11.5, weight: .semibold))
                        markdownView(PRReviewViewModel.stripVerdictLine(text))
                            .font(.system(size: 11.5))
                        agentActions(agent)
                        deepVerifySection(agent)
                    }
                }
            }
        }
        .padding(12)
        .grCard(radius: 9)
    }

    private func agentActions(_ agent: ReviewAgent) -> some View {
        HStack(spacing: 8) {
            if viewModel.agentCached.contains(agent) { cachedBadge }
            Button("Re-run") {
                guard let repo else { return }
                Task { await viewModel.regenerateSingleAgent(agent, repo: repo) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Verify") {
                guard let repo else { return }
                Task { await viewModel.deepVerifyAgent(agent, repo: repo) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.agentDeepLoading.contains(agent))
        }
    }

    @ViewBuilder
    private func deepVerifySection(_ agent: ReviewAgent) -> some View {
        if viewModel.agentDeepLoading.contains(agent) {
            agentLoadingRow()
        } else if let error = viewModel.agentDeepErrors[agent] {
            inlineError(error) {
                guard let repo else { return }
                Task { await viewModel.deepVerifyAgent(agent, repo: repo) }
            }
        } else if let text = viewModel.agentDeepReviews[agent] {
            Divider()
            customVerdictBanner(for: agent.rawValue)
            markdownView(PRReviewViewModel.stripVerdictLine(text))
        }
    }

    @ViewBuilder
    func customAgentStatusBadge(_ agentId: String) -> some View {
        if viewModel.customAgentLoading.contains(agentId) {
            ProgressView().controlSize(.mini)
        } else if viewModel.customAgentErrors[agentId] != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GRTheme.danger)
        } else if let passed = viewModel.customAgentVerdicts[agentId] {
            Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(passed ? GRTheme.success : GRTheme.warning)
        }
    }

    @ViewBuilder
    func customVerdictBanner(for agentId: String) -> some View {
        let passed = viewModel.customAgentVerdicts[agentId]
            ?? viewModel.agentDeepVerdicts[ReviewAgent(rawValue: agentId) ?? .summary]
        if let passed {
            Label(
                passed ? "Passed" : "Issues Found",
                systemImage: passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(passed ? GRTheme.success : GRTheme.warning)
        }
    }

    func agentLoadingRow() -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Analyzing...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    var cachedBadge: some View {
        Text("CACHED")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(GRTheme.segment(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
