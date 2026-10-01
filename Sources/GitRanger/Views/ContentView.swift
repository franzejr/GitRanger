import SwiftData
import SwiftUI

enum ContentMode: String, CaseIterable {
    case commits = "Commits"
    case pullRequests = "Pull Requests"
    case changes = "Changes"
}

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var repoListVM = RepoListViewModel()
    @State private var commitListVM = CommitListViewModel()
    @State private var commitDetailVM = CommitDetailViewModel()
    @State private var narrativeVM = NarrativeViewModel()
    @State private var prListVM = PRListViewModel()
    @State private var prReviewSessions = PRReviewSessionStore()
    @State private var changesVM = ChangesViewModel()
    @State private var selectedCommit: Commit?
    @State private var contentMode: ContentMode = .commits

    var body: some View {
        NavigationSplitView {
            RepoListView(viewModel: repoListVM)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 330, ideal: 380, max: 440)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1_000, minHeight: 640)
        .background(GRTheme.background(colorScheme))
        .onAppear(perform: initializeViewModels)
        .onChange(of: repoListVM.selectedRepoId) { _, newId in
            handleRepoChanged(newId)
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private var contentColumn: some View {
        if repoListVM.selectedRepoId != nil {
            VStack(spacing: 0) {
                modePicker
                switch contentMode {
                case .commits:
                    commitsContent
                case .pullRequests:
                    pullRequestsContent
                case .changes:
                    changesContent
                }
            }
            .background(GRTheme.background(colorScheme))
        } else {
            ContentUnavailableView(
                "Select a Repository",
                systemImage: "folder",
                description: Text("Choose a repository from the sidebar or add a new one.")
            )
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if contentMode == .changes {
            ChangesDetailView(viewModel: changesVM, repo: repoListVM.selectedRepo)
        } else if narrativeVM.isLoading || narrativeVM.narrative != nil || narrativeVM.error != nil {
            NarrativeView(viewModel: narrativeVM)
        } else if let prReviewVM = prReviewSessions.selectedViewModel {
            PRReviewView(viewModel: prReviewVM, repo: repoListVM.selectedRepo)
        } else if commitDetailVM.commit != nil {
            CommitDetailView(viewModel: commitDetailVM)
        } else {
            ContentUnavailableView(
                "Select a Commit",
                systemImage: "doc.text",
                description: Text("Choose a commit or pull request to view details.")
            )
        }
    }

    // MARK: - Content Helpers

    private var modePicker: some View {
        Picker("Mode", selection: $contentMode) {
            ForEach(ContentMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: 330)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(GRTheme.background(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GRTheme.line(colorScheme))
                .frame(height: 1)
        }
    }

    private var commitsContent: some View {
        CommitListView(
            viewModel: commitListVM,
            checkedIds: $commitListVM.checkedCommitIds,
            repo: repoListVM.selectedRepo,
            onSelectCommit: { commit in
                selectedCommit = commit
                narrativeVM.dismiss()
                prReviewSessions.deselect()
                Task { await commitDetailVM.loadDetail(commit: commit) }
            },
            onTellStory: {
                selectedCommit = nil
                commitDetailVM.clear()
                prReviewSessions.deselect()
                Task {
                    await narrativeVM.generateNarrative(
                        commitIds: commitListVM.checkedCommitIds
                    )
                }
            },
            onSync: {
                guard let repo = repoListVM.selectedRepo else { return }
                Task {
                    await repoListVM.syncRepo(repo)
                    if let repoId = repoListVM.selectedRepoId {
                        commitListVM.loadCommits(repoId: repoId)
                        await commitListVM.loadBranches(repo: repo)
                    }
                }
            },
            isSyncing: repoListVM.isSyncing
        )
    }

    private var pullRequestsContent: some View {
        PRListView(
            viewModel: prListVM,
            repo: repoListVM.selectedRepo,
            reviewActivity: { pr in
                guard let repo = repoListVM.selectedRepo else { return nil }
                return prReviewSessions.activity(for: pr, repoURL: repo.url)
            },
            onSelectPR: { pr in
                guard let repo = repoListVM.selectedRepo else { return }
                selectedCommit = nil
                commitDetailVM.clear()
                narrativeVM.dismiss()
                let needsLoad = prReviewSessions.select(
                    pr,
                    repoURL: repo.url,
                    modelContext: modelContext
                )
                guard needsLoad,
                      let viewModel = prReviewSessions.selectedViewModel else {
                    return
                }
                Task { await viewModel.loadPR(pr, repo: repo) }
            }
        )
    }

    private var changesContent: some View {
        ChangesListView(
            viewModel: changesVM,
            repo: repoListVM.selectedRepo
        )
    }

    // MARK: - Actions

    private func initializeViewModels() {
        repoListVM.setModelContext(modelContext)
        commitListVM.setModelContext(modelContext)
        commitDetailVM.setModelContext(modelContext)
        narrativeVM.setModelContext(modelContext)
        repoListVM.loadRepos()
    }

    private func handleRepoChanged(_ newId: UUID?) {
        selectedCommit = nil
        commitDetailVM.clear()
        narrativeVM.dismiss()
        prReviewSessions.deselect()
        prListVM.clear()
        changesVM.clear()
        contentMode = .commits
        if let newId {
            commitListVM.selectedBranch = ""
            commitListVM.loadCommits(repoId: newId)
            if let repo = repoListVM.selectedRepo {
                Task { await commitListVM.loadBranches(repo: repo) }
            }
        }
    }
}
