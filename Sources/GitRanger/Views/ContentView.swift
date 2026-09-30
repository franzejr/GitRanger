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

    @State private var repoListVM = RepoListViewModel()
    @State private var commitListVM = CommitListViewModel()
    @State private var commitDetailVM = CommitDetailViewModel()
    @State private var narrativeVM = NarrativeViewModel()
    @State private var prListVM = PRListViewModel()
    @State private var prReviewVM = PRReviewViewModel()
    @State private var changesVM = ChangesViewModel()
    @State private var selectedCommit: Commit?
    @State private var contentMode: ContentMode = .commits

    var body: some View {
        NavigationSplitView {
            RepoListView(viewModel: repoListVM)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 900, minHeight: 600)
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
            ChangesDetailView(viewModel: changesVM)
        } else if narrativeVM.isLoading || narrativeVM.narrative != nil || narrativeVM.error != nil {
            NarrativeView(viewModel: narrativeVM)
        } else if prReviewVM.selectedPR != nil {
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
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var commitsContent: some View {
        CommitListView(
            viewModel: commitListVM,
            checkedIds: $commitListVM.checkedCommitIds,
            repo: repoListVM.selectedRepo,
            onSelectCommit: { commit in
                selectedCommit = commit
                narrativeVM.dismiss()
                prReviewVM.dismiss()
                Task { await commitDetailVM.loadDetail(commit: commit) }
            },
            onTellStory: {
                selectedCommit = nil
                commitDetailVM.clear()
                prReviewVM.dismiss()
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
            onSelectPR: { pr in
                guard let repo = repoListVM.selectedRepo else { return }
                selectedCommit = nil
                commitDetailVM.clear()
                narrativeVM.dismiss()
                Task { await prReviewVM.loadPR(pr, repo: repo) }
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
        prReviewVM.setModelContext(modelContext)
        repoListVM.loadRepos()
    }

    private func handleRepoChanged(_ newId: UUID?) {
        selectedCommit = nil
        commitDetailVM.clear()
        narrativeVM.dismiss()
        prReviewVM.dismiss()
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
