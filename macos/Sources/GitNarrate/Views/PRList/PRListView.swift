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

            Divider()

            if viewModel.isLoading {
                ProgressView("Loading pull requests...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.pullRequests.isEmpty {
                ContentUnavailableView(
                    "No Open Pull Requests",
                    systemImage: "arrow.triangle.pull",
                    description: Text("This repository has no open pull requests.")
                )
            } else {
                List(selection: $selectedPRNumber) {
                    ForEach(viewModel.pullRequests) { pr in
                        PRItemView(pr: pr, isSelected: selectedPRNumber == pr.number)
                            .tag(pr.number)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPRNumber = pr.number
                                onSelectPR(pr)
                            }
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
        }
        .navigationTitle("Pull Requests")
        .navigationSubtitle("\(viewModel.pullRequests.count) open")
        .onAppear {
            guard let repo, viewModel.pullRequests.isEmpty else { return }
            Task { await viewModel.loadPullRequests(repo: repo) }
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
