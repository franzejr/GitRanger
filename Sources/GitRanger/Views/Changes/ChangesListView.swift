import SwiftUI

struct ChangesListView: View {
    @Bindable var viewModel: ChangesViewModel
    @Environment(\.colorScheme) private var colorScheme
    var repo: Repo?

    var body: some View {
        VStack(spacing: 0) {
            repositoryHeader

            if viewModel.isLoading && viewModel.changedFiles.isEmpty {
                ProgressView("Checking for changes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.changedFiles.isEmpty {
                emptyState
            } else {
                fileList
            }

            commitPanel
        }
        .background(GRTheme.sidebar(colorScheme))
        .onAppear {
            guard let repo else { return }
            Task { await viewModel.loadChanges(repo: repo) }
        }
    }

    private var repositoryHeader: some View {
        HStack(spacing: 8) {
            Text(repo?.name ?? "Repository")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if let branch = viewModel.currentBranch {
                Text(branch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GRTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                guard let repo else { return }
                Task { await viewModel.loadChanges(repo: repo) }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !viewModel.stagedFiles.isEmpty {
                    sectionHeader(
                        "Staged · \(viewModel.stagedFiles.count)",
                        action: "Unstage all"
                    ) {
                        guard let repo else { return }
                        Task { await viewModel.unstageAll(repo: repo) }
                    }
                    ForEach(viewModel.stagedFiles) { file in fileRow(file) }
                }

                if !viewModel.unstagedFiles.isEmpty {
                    sectionHeader(
                        "Changes · \(viewModel.unstagedFiles.count)",
                        action: "Stage all"
                    ) {
                        guard let repo else { return }
                        Task { await viewModel.stageAll(repo: repo) }
                    }
                    ForEach(viewModel.unstagedFiles) { file in fileRow(file) }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func sectionHeader(
        _ title: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        HStack {
            GRSectionLabel(title: title)
            Spacer()
            Button(action, action: perform)
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(GRTheme.link(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        ChangedFileRow(
            file: file,
            isSelected: viewModel.selectedFile?.id == file.id,
            onSelect: {
                guard let repo else { return }
                Task { await viewModel.selectFile(file, repo: repo) }
            },
            onToggle: {
                guard let repo else { return }
                Task { await viewModel.toggleStaged(file, repo: repo) }
            },
            onDiscard: file.isStaged || file.status == .untracked ? nil : {
                guard let repo else { return }
                Task { await viewModel.discardChanges(file, repo: repo) }
            }
        )
    }

    private var commitPanel: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    GRMonogram(size: 16)
                    GRSectionLabel(title: "AI Draft")
                    Spacer()
                    Button(viewModel.isGeneratingMessage ? "Generating..." : "Regenerate") {
                        guard let repo else { return }
                        Task { await viewModel.generateCommitMessage(repo: repo) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(GRTheme.link(colorScheme))
                    .disabled(viewModel.stagedFiles.isEmpty || viewModel.isGeneratingMessage)
                }

                TextField("Commit summary", text: $viewModel.commitSummary)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))

                TextEditor(text: $viewModel.commitDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                    .scrollContentBackground(.hidden)
                    .frame(height: 48)
            }
            .padding(10)
            .grCard(radius: 8)

            if let error = viewModel.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(GRTheme.danger)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                Button {
                    guard let repo else { return }
                    Task { await viewModel.commitChanges(repo: repo) }
                } label: {
                    if viewModel.isCommitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Commit \(viewModel.stagedFiles.count) files")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(GRTheme.accent)
                .foregroundStyle(GRTheme.onAccent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!viewModel.canCommit)

                Text("⌘↵")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(GRTheme.line(colorScheme))
                    }
            }
        }
        .padding(12)
        .overlay(alignment: .top) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Local Changes",
            systemImage: "checkmark.circle",
            description: Text("Your working tree is clean.")
        )
        .frame(maxHeight: .infinity)
    }
}
