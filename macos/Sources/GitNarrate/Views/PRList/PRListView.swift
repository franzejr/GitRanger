import SwiftUI

struct PRListView: View {
    @Bindable var viewModel: PRListViewModel
    var repo: Repo?
    var onSelectPR: (PullRequest) -> Void

    @State private var selectedPRNumber: Int?
    @State private var showReviewPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            filterPicker

            Divider()

            Group {
                if viewModel.isLoading {
                    ProgressView("Loading pull requests...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    errorView(error)
                } else if viewModel.pullRequests.isEmpty {
                    ContentUnavailableView(
                        "No Open Pull Requests",
                        systemImage: "arrow.triangle.pull",
                        description: Text(emptyMessage)
                    )
                } else {
                    prList
                }
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle("Pull Requests")
        .navigationSubtitle(navigationSubtitle)
        .onAppear {
            guard let repo, viewModel.pullRequests.isEmpty else { return }
            Task { await viewModel.loadPullRequests(repo: repo) }
        }
    }

    private var navigationSubtitle: String {
        let count = viewModel.pullRequests.count
        switch viewModel.filterMode {
        case .all: return "\(count) open"
        case .pendingMyReview: return "\(count) pending"
        case .merged: return "\(count) merged"
        }
    }

    private var emptyMessage: String {
        switch viewModel.filterMode {
        case .all:
            "This repository has no open pull requests."
        case .pendingMyReview:
            "No pull requests are waiting for your review."
        case .merged:
            "No merged pull requests found."
        }
    }

    private var prList: some View {
        List(selection: $selectedPRNumber) {
            ForEach(viewModel.pullRequests) { pr in
                PRItemView(
                    pr: pr,
                    isSelected: selectedPRNumber == pr.number,
                    currentUser: viewModel.currentGhUser
                )
                .tag(pr.number)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPRNumber = pr.number
                    onSelectPR(pr)
                }
            }

            if viewModel.hasMore {
                loadMoreButton
            }
        }
        .listStyle(.plain)
        .onChange(of: selectedPRNumber) { _, newNumber in
            guard let newNumber,
                  let pr = viewModel.pullRequests.first(where: { $0.number == newNumber })
            else { return }
            onSelectPR(pr)
        }
    }

    private var loadMoreButton: some View {
        Button {
            guard let repo else { return }
            Task { await viewModel.loadMore(repo: repo) }
        } label: {
            if viewModel.isLoadingMore {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Loading more...")
                        .font(.caption)
                }
            } else {
                Text("Load More")
                    .font(.caption)
            }
        }
        .disabled(viewModel.isLoadingMore)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var filterPicker: some View {
        Picker("", selection: $viewModel.filterMode) {
            ForEach(PRFilterMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: viewModel.filterMode) { _, _ in
            guard let repo else { return }
            Task { await viewModel.refresh(repo: repo) }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .foregroundStyle(.secondary)

            Text("\(viewModel.pullRequests.count) open PRs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !viewModel.ghAccounts.isEmpty, let repo {
                Picker("", selection: Binding(
                    get: { repo.ghAccount ?? viewModel.ghAccounts.first ?? "" },
                    set: { newAccount in
                        repo.ghAccount = newAccount
                        repo.updatedAt = Date()
                        Task { await viewModel.refresh(repo: repo) }
                    }
                )) {
                    ForEach(viewModel.ghAccounts, id: \.self) { account in
                        Text(account).tag(account)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
                .controlSize(.small)
                .help("GitHub account for API access")
            }

            Button {
                showReviewPrompt = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.line")
                    if repo?.reviewPrompt != nil {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Edit review instructions for this repo")

            Button {
                guard let repo else { return }
                Task { await viewModel.refresh(repo: repo) }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
            .help("Refresh pull requests")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $showReviewPrompt) {
            if let repo {
                ReviewPromptSheet(repo: repo, isPresented: $showReviewPrompt)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.ghAvailable == false {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install GitHub CLI:")
                            .font(.caption.bold())
                        Text("brew install gh")
                            .font(.system(.caption, design: .monospaced))
                        Text("gh auth login")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: 250)
            }

            Button("Retry") {
                guard let repo else { return }
                Task { await viewModel.loadPullRequests(repo: repo) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
