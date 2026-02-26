import SwiftUI
import SwiftData

enum ContentMode: String, CaseIterable {
    case commits = "Commits"
    case pullRequests = "Pull Requests"
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var repoListVM = RepoListViewModel()
    @State private var commitListVM = CommitListViewModel()
    @State private var commitDetailVM = CommitDetailViewModel()
    @State private var narrativeVM = NarrativeViewModel()
    @State private var prListVM = PRListViewModel()
    @State private var prReviewVM = PRReviewViewModel()
    @State private var selectedCommit: Commit?
    @State private var contentMode: ContentMode = .commits

    var body: some View {
        NavigationSplitView {
            RepoListView(viewModel: repoListVM)
        } content: {
            if repoListVM.selectedRepoId != nil {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $contentMode) {
                        ForEach(ContentMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    switch contentMode {
                    case .commits:
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

                    case .pullRequests:
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
                }
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "folder",
                    description: Text("Choose a repository from the sidebar or add a new one.")
                )
            }
        } detail: {
            if narrativeVM.isLoading || narrativeVM.narrative != nil || narrativeVM.error != nil {
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
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            repoListVM.setModelContext(modelContext)
            commitListVM.setModelContext(modelContext)
            commitDetailVM.setModelContext(modelContext)
            narrativeVM.setModelContext(modelContext)
            prReviewVM.setModelContext(modelContext)
            repoListVM.loadRepos()
        }
        .onChange(of: repoListVM.selectedRepoId) { _, newId in
            selectedCommit = nil
            commitDetailVM.clear()
            narrativeVM.dismiss()
            prReviewVM.dismiss()
            prListVM.clear()
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
}
