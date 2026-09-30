import SwiftUI

struct PRListView: View {
    @Bindable var viewModel: PRListViewModel
    @Environment(\.colorScheme) private var colorScheme
    var repo: Repo?
    var onSelectPR: (PullRequest) -> Void

    @State private var selectedPRNumber: Int?
    @State private var showReviewPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            Group {
                if viewModel.isLoading && viewModel.pullRequests.isEmpty {
                    ProgressView(viewModel.isGitLabRepo
                        ? "Loading merge requests..."
                        : "Loading pull requests...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    errorView(error)
                } else if displayedPRs.isEmpty {
                    ContentUnavailableView(
                        viewModel.isGitLabRepo
                            ? "No Merge Requests"
                            : "No Pull Requests",
                        systemImage: "arrow.triangle.pull",
                        description: Text(emptyMessage)
                    )
                } else {
                    prList
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(GRTheme.background(colorScheme))
        .onAppear {
            guard let repo, viewModel.pullRequests.isEmpty else { return }
            Task { await viewModel.loadPullRequests(repo: repo) }
        }
        .onChange(of: repo?.id) { _, _ in
            selectedPRNumber = nil
        }
        .sheet(isPresented: $showReviewPrompt) {
            if let repo {
                ReviewPromptSheet(repo: repo, isPresented: $showReviewPrompt)
            }
        }
    }

    private var displayedPRs: [PullRequest] {
        guard viewModel.filterMode == .pendingMyReview,
              let user = currentUser else {
            return viewModel.pullRequests
        }
        return viewModel.pullRequests.sorted { lhs, rhs in
            let lhsWaiting = lhs.isAwaitingReview(by: user)
                || lhs.wasReviewedBy(user) == nil
            let rhsWaiting = rhs.isAwaitingReview(by: user)
                || rhs.wasReviewedBy(user) == nil
            return lhsWaiting && !rhsWaiting
        }
    }

    private var currentUser: String? {
        viewModel.currentGhUser ?? viewModel.currentGlUser
    }

    private var emptyMessage: String {
        let label = viewModel.isGitLabRepo ? "merge requests" : "pull requests"
        switch viewModel.filterMode {
        case .open: return "This repository has no open \(label)."
        case .closed: return "No closed \(label) found."
        case .merged: return "No merged \(label) found."
        case .pendingMyReview: return "No \(label) are waiting for your review."
        }
    }

    private var filterBar: some View {
        HStack(spacing: 16) {
            ForEach(PRFilterMode.allCases, id: \.self) { mode in
                Button {
                    guard mode != viewModel.filterMode else { return }
                    viewModel.filterMode = mode
                    selectedPRNumber = nil
                    guard let repo else { return }
                    Task { await viewModel.refresh(repo: repo) }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight:
                                    viewModel.filterMode == mode ? .semibold : .regular))
                            if viewModel.filterMode == mode {
                                Text("\(viewModel.pullRequests.count)")
                                    .foregroundStyle(GRTheme.muted(colorScheme))
                            }
                        }
                        Rectangle()
                            .fill(viewModel.filterMode == mode ? GRTheme.accent : .clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    viewModel.filterMode == mode
                        ? Color.primary : GRTheme.muted(colorScheme)
                )
            }

            Spacer(minLength: 4)

            if let currentUser {
                Text(currentUser)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GRTheme.muted(colorScheme))
                    .lineLimit(1)
            }

            Menu {
                Button("Refresh") {
                    guard let repo else { return }
                    Task { await viewModel.refresh(repo: repo) }
                }
                Button("Review Instructions...") {
                    showReviewPrompt = true
                }
                accountMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(height: 56, alignment: .top)
        .overlay(alignment: .bottom) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var accountMenu: some View {
        if let repo, viewModel.isGitHubRepo, !viewModel.ghAccounts.isEmpty {
            Menu("GitHub Account") {
                ForEach(viewModel.ghAccounts, id: \.self) { account in
                    Button(account) {
                        repo.ghAccount = account
                        Task { await viewModel.refresh(repo: repo) }
                    }
                }
            }
        }
        if let repo, viewModel.isGitLabRepo, !viewModel.glHosts.isEmpty {
            Menu("GitLab Host") {
                ForEach(viewModel.glHosts, id: \.self) { host in
                    Button(host) {
                        repo.glHost = host
                        Task { await viewModel.refresh(repo: repo) }
                    }
                }
            }
        }
    }

    private var prList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedPRs) { pr in
                    Button {
                        selectedPRNumber = pr.number
                        onSelectPR(pr)
                    } label: {
                        PRItemView(
                            pr: pr,
                            isSelected: selectedPRNumber == pr.number,
                            currentUser: currentUser
                        )
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.hasMore {
                    loadMoreButton
                }
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            guard let repo else { return }
            Task { await viewModel.loadMore(repo: repo) }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isLoadingMore {
                    ProgressView().controlSize(.small)
                }
                Text(viewModel.isLoadingMore ? "Loading more..." : "Load More")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoadingMore)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                guard let repo else { return }
                Task { await viewModel.loadPullRequests(repo: repo) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
