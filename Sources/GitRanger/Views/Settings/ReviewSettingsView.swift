import SwiftData
import SwiftUI

/// The permanent home for review-agent configuration.
///
/// Review settings are stored per repository because prompts and specialist
/// agents tend to be codebase-specific. The global prompt remains the fallback
/// for repositories without their own single-pass instructions.
struct ReviewSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Repo.name) private var repos: [Repo]
    @AppStorage("prReviewPrompt") private var globalReviewPrompt = ""
    @State private var selectedRepoID: UUID?
    @State private var showGlobalPromptEditor = false

    private var selectedRepo: Repo? {
        repos.first { $0.id == selectedRepoID } ?? repos.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let repo = selectedRepo {
                ReviewPromptSheet(
                    repo: repo,
                    isPresented: .constant(true),
                    presentation: .settings
                )
                .id(repo.id)
            } else {
                ContentUnavailableView(
                    "Add a Repository First",
                    systemImage: "folder.badge.plus",
                    description: Text(
                        "Review agents are configured per repository. Add one to edit prompts or create agents."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("review-settings-view")
        .sheet(isPresented: $showGlobalPromptEditor) {
            globalPromptEditor
        }
        .onAppear {
            if selectedRepoID == nil {
                selectedRepoID = repos.first?.id
            }
        }
        .onChange(of: repos.map(\.id)) { _, ids in
            if let selectedRepoID, ids.contains(selectedRepoID) { return }
            selectedRepoID = ids.first
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Review Agents")
                    .font(.system(size: 15, weight: .semibold))
                Text("Edit specialist prompts, enable or disable built-in reviewers, and create your own agents.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
            }

            HStack(spacing: 12) {
                Text("Repository")
                    .font(.system(size: 11.5))
                    .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                    .frame(width: 100, alignment: .leading)

                Picker("Repository", selection: selectedRepoBinding) {
                    ForEach(repos) { repo in
                        Text(repo.name).tag(Optional(repo.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)

                Spacer()

                Button("Edit Global Prompt...") {
                    showGlobalPromptEditor = true
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var selectedRepoBinding: Binding<UUID?> {
        Binding(
            get: { selectedRepo?.id },
            set: { selectedRepoID = $0 }
        )
    }

    private var globalPromptEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Global Review Prompt")
                .font(.title3.weight(.semibold))
            Text("Used for single-pass reviews when a repository has no custom instructions.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $globalReviewPrompt)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(GRTheme.background(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GRTheme.line(colorScheme))
                }

            HStack {
                Button("Reset") { globalReviewPrompt = "" }
                    .disabled(globalReviewPrompt.isEmpty)
                Button("Load Default Template") {
                    globalReviewPrompt = PromptBuilder.defaultPRReviewPrompt
                }
                Spacer()
                Button("Done") { showGlobalPromptEditor = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 680, height: 480)
    }
}
