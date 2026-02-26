import SwiftUI

struct RepoListView: View {
    @Bindable var viewModel: RepoListViewModel
    @State private var showAddSheet = false
    @State private var reviewPromptRepo: Repo?

    var body: some View {
        List(selection: $viewModel.selectedRepoId) {
            ForEach(viewModel.repos, id: \.id) { repo in
                RepoItemView(
                    repo: repo,
                    isSyncing: viewModel.isSyncing && viewModel.selectedRepoId == repo.id,
                    onSync: { Task { await viewModel.syncRepo(repo) } }
                )
                .tag(repo.id)
                .contextMenu {
                    Button("Sync") {
                        Task { await viewModel.syncRepo(repo) }
                    }

                    Button("Settings...") {
                        reviewPromptRepo = repo
                    }

                    Divider()

                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteRepo(repo) }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteRepo(repo) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Repositories")
        .toolbar {
            ToolbarItem {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Repository", systemImage: "plus")
                }
            }

            ToolbarItem {
                if viewModel.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRepoSheet(viewModel: viewModel, isPresented: $showAddSheet)
        }
        .sheet(item: $reviewPromptRepo) { repo in
            ReviewPromptSheet(
                repo: repo,
                isPresented: Binding(
                    get: { reviewPromptRepo != nil },
                    set: { if !$0 { reviewPromptRepo = nil } }
                )
            )
        }
        .overlay {
            if viewModel.repos.isEmpty {
                ContentUnavailableView {
                    Label("No Repositories", systemImage: "folder.badge.plus")
                } description: {
                    Text("Add a repository to get started.")
                } actions: {
                    Button("Add Repository") {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert(
            "Sync Error",
            isPresented: Binding(
                get: { viewModel.syncError != nil },
                set: { if !$0 { viewModel.syncError = nil } }
            )
        ) {
            Button("OK") { viewModel.syncError = nil }
        } message: {
            Text(viewModel.syncError ?? "")
        }
    }
}

struct RepoItemView: View {
    let repo: Repo
    let isSyncing: Bool
    var onSync: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Label("\(repo.commitCount)", systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastPolled = repo.lastPolledAt {
                        Text("Synced at \(lastPolled, format: .dateTime.hour().minute())")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button {
                onSync()
            } label: {
                if isSyncing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)
            .help("Sync latest commits")
        }
        .padding(.vertical, 2)
    }
}
