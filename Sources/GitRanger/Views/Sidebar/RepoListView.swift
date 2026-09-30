import SwiftUI

struct RepoListView: View {
    @Bindable var viewModel: RepoListViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("aiProvider") private var aiProvider = AIProvider.claudeCode.rawValue
    @AppStorage("pollInterval") private var pollInterval = 300
    @State private var showAddSheet = false
    @State private var reviewPromptRepo: Repo?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.repos, id: \.id) { repo in
                        repoRow(repo)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            pollingFooter
        }
        .background(GRTheme.sidebar(colorScheme))
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
                    Button("Add Repository") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert(
            "Sync Error",
            isPresented: Binding(
                get: { viewModel.syncError != nil },
                set: {
                    if !$0 {
                        viewModel.syncError = nil
                        viewModel.syncErrorDetail = nil
                    }
                }
            )
        ) {
            Button("OK") {
                viewModel.syncError = nil
                viewModel.syncErrorDetail = nil
            }
        } message: {
            Text(viewModel.syncErrorDetail ?? viewModel.syncError ?? "")
        }
    }

    private var header: some View {
        HStack {
            GRSectionLabel(title: "Repositories")
            Spacer()
            if viewModel.isSyncing {
                ProgressView().controlSize(.small)
            }
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Add Repository")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func repoRow(_ repo: Repo) -> some View {
        let isSelected = viewModel.selectedRepoId == repo.id

        return Button {
            viewModel.selectedRepoId = repo.id
        } label: {
            HStack(spacing: 10) {
                Text(initials(for: repo.name))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? GRTheme.onAccent : .secondary)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? GRTheme.accent : GRTheme.segment(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("\(repo.commitCount)")
                        Text("·")
                        if let lastPolled = repo.lastPolledAt {
                            Text(lastPolled, format: .dateTime.hour().minute())
                        } else {
                            Text("not synced")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(GRTheme.muted(colorScheme))
                }

                Spacer(minLength: 4)

                if viewModel.isSyncing && isSelected {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isSelected ? GRTheme.selection(colorScheme) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Sync") { Task { await viewModel.syncRepo(repo) } }
            Button("Settings...") { reviewPromptRepo = repo }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteRepo(repo) }
            }
        }
    }

    private var pollingFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(GRTheme.accent)
                .frame(width: 6, height: 6)
            Text("Polling every \(max(1, pollInterval / 60)) min · \(providerName)")
                .font(.system(size: 10.5))
                .foregroundStyle(GRTheme.muted(colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
    }

    private var providerName: String {
        switch AIProvider(rawValue: aiProvider) ?? .claudeCode {
        case .claudeCode: "Claude Code"
        case .anthropicAPI: "Anthropic"
        case .openAI: "OpenAI"
        case .ollama: "Ollama"
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count > 1 {
            return parts.prefix(2).compactMap(\.first).map(String.init).joined().lowercased()
        }
        return String(name.prefix(2)).lowercased()
    }
}
