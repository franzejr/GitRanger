import SwiftUI

struct ChangesListView: View {
    @Bindable var viewModel: ChangesViewModel
    var repo: Repo?
    @State private var commitFormHeight: CGFloat = 200
    @State private var dragStartHeight: CGFloat = 200

    private let minFormHeight: CGFloat = 140
    private let maxFormHeight: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if viewModel.isLoading && viewModel.changedFiles.isEmpty {
                ProgressView("Checking for changes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.changedFiles.isEmpty {
                emptyState
            } else {
                fileList
            }

            resizeHandle
            commitForm
                .frame(height: commitFormHeight)
        }
        .onAppear {
            guard let repo else { return }
            Task { await viewModel.loadChanges(repo: repo) }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            if let branch = viewModel.currentBranch {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                Text(branch)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            Spacer()

            Text("\(viewModel.changedFiles.count) changed")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                guard let repo else { return }
                Task { await viewModel.loadChanges(repo: repo) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: Binding(
            get: { viewModel.selectedFile?.id },
            set: { newId in
                guard let repo else { return }
                let file = viewModel.changedFiles.first { $0.id == newId }
                Task { await viewModel.selectFile(file, repo: repo) }
            }
        )) {
            if !viewModel.stagedFiles.isEmpty {
                stagedSection
            }
            if !viewModel.unstagedFiles.isEmpty {
                unstagedSection
            }
        }
        .listStyle(.plain)
    }

    private var stagedSection: some View {
        Section {
            ForEach(viewModel.stagedFiles) { file in
                fileRow(file)
                    .tag(file.id)
            }
        } header: {
            HStack {
                Text("Staged (\(viewModel.stagedFiles.count))")
                    .font(.caption.bold())
                Spacer()
                Button("Unstage All") {
                    guard let repo else { return }
                    Task { await viewModel.unstageAll(repo: repo) }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private var unstagedSection: some View {
        Section {
            ForEach(viewModel.unstagedFiles) { file in
                fileRow(file)
                    .tag(file.id)
            }
        } header: {
            HStack {
                Text("Unstaged (\(viewModel.unstagedFiles.count))")
                    .font(.caption.bold())
                Spacer()
                Button("Stage All") {
                    guard let repo else { return }
                    Task { await viewModel.stageAll(repo: repo) }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        ChangedFileRow(
            file: file,
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

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(width: 36, height: 4)
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newHeight = dragStartHeight - value.translation.height
                        commitFormHeight = min(max(newHeight, minFormHeight), maxFormHeight)
                    }
                    .onEnded { _ in
                        dragStartHeight = commitFormHeight
                    }
            )
    }

    // MARK: - Commit Form

    private var commitForm: some View {
        VStack(spacing: 8) {
            TextField("Summary (required)", text: $viewModel.commitSummary)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isCommitting)

            TextEditor(text: $viewModel.commitDescription)
                .font(.body)
                .frame(maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.quaternary)
                )
                .disabled(viewModel.isCommitting)

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                aiGenerateButton

                Button {
                    guard let repo else { return }
                    Task { await viewModel.commitChanges(repo: repo) }
                } label: {
                    if viewModel.isCommitting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                            Text("Committing...")
                        }
                    } else {
                        Text(commitButtonLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCommit)
            }
        }
        .padding(12)
    }

    private var aiGenerateButton: some View {
        Button {
            guard let repo else { return }
            Task { await viewModel.generateCommitMessage(repo: repo) }
        } label: {
            if viewModel.isGeneratingMessage {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.stagedFiles.isEmpty || viewModel.isGeneratingMessage)
        .help("AI-generate commit message from staged changes")
    }

    private var commitButtonLabel: String {
        if let branch = viewModel.currentBranch {
            return "Commit to \(branch)"
        }
        return "Commit"
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView(
            "No Local Changes",
            systemImage: "checkmark.circle",
            description: Text("Your working tree is clean.")
        )
        .frame(maxHeight: .infinity)
    }
}
