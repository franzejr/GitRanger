import SwiftUI

struct CommitListView: View {
    @Bindable var viewModel: CommitListViewModel
    @Binding var checkedIds: Set<UUID>
    var repo: Repo?
    var onSelectCommit: (Commit) -> Void
    var onTellStory: () -> Void
    var onSync: () -> Void
    var isSyncing: Bool

    @State private var selectedCommitId: UUID?
    @State private var authorFilter = ""
    @State private var sinceDate: Date?
    @State private var untilDate: Date?
    @State private var showFilters = false

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            Divider()

            // Commit list
            if viewModel.isLoading && viewModel.commits.isEmpty {
                ProgressView("Loading commits...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.commits.isEmpty {
                ContentUnavailableView(
                    "No Commits Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Try adjusting your filters.")
                )
            } else {
                List(selection: $selectedCommitId) {
                    ForEach(viewModel.commits, id: \.id) { commit in
                        CommitItemView(
                            commit: commit,
                            isChecked: checkedIds.contains(commit.id),
                            isSelected: selectedCommitId == commit.id,
                            onToggleCheck: { viewModel.toggleCheck(commit.id) },
                            onSelect: {
                                selectedCommitId = commit.id
                                onSelectCommit(commit)
                            }
                        )
                        .tag(commit.id)
                    }

                    if viewModel.hasMore {
                        Button("Load More") {
                            viewModel.loadMore()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else if let repo {
                        Button {
                            Task { await viewModel.loadMoreFromGit(repo: repo) }
                        } label: {
                            if viewModel.isLoadingMore {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                    Text("Loading older commits...")
                                        .font(.caption)
                                }
                            } else {
                                Text("Load Older Commits")
                                    .font(.caption)
                            }
                        }
                        .disabled(viewModel.isLoadingMore)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .onChange(of: selectedCommitId) { _, newId in
                    guard let newId,
                          let commit = viewModel.commits.first(where: { $0.id == newId })
                    else { return }
                    onSelectCommit(commit)
                }
            }

            // Narrative action bar
            if viewModel.checkedCount >= 2 {
                narrativeBar
            }
        }
        .navigationTitle("Commits")
        .navigationSubtitle("\(viewModel.total) total")
    }

    private var filterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if !viewModel.branches.isEmpty {
                    Picker("", selection: $viewModel.selectedBranch) {
                        ForEach(viewModel.branches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                    .onChange(of: viewModel.selectedBranch) { oldBranch, newBranch in
                        // Setting the initial branch follows an import and must not
                        // trigger a second, much larger history scan.
                        guard CommitListViewModel.shouldSwitchBranch(
                            from: oldBranch, to: newBranch
                        ),
                              let repo else { return }
                        Task { await viewModel.switchBranch(newBranch, repo: repo) }
                    }
                }

                TextField("Filter by author...", text: $authorFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .onSubmit { applyFilters() }

                Spacer()

                Text("\(viewModel.total) commits")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onSync()
                } label: {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSyncing)
                .help("Pull latest commits")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var narrativeBar: some View {
        HStack {
            Text("\(viewModel.checkedCount) commits selected")
                .font(.callout)

            Spacer()

            Button("Clear") {
                viewModel.clearChecked()
            }

            Button("Tell the Story") {
                onTellStory()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canGenerateNarrative)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func applyFilters() {
        var filters = viewModel.filters
        filters.author = authorFilter
        filters.since = sinceDate
        filters.until = untilDate
        viewModel.setFilters(filters)
    }
}
