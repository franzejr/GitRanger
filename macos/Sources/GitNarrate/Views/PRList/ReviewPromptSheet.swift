import SwiftUI

struct ReviewPromptSheet: View {
    let repo: Repo
    @Binding var isPresented: Bool
    @State private var promptText: String = ""
    @State private var selectedAccount: String = ""
    @State private var ghAccounts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Repo Settings")
                    .font(.title3.bold())
                Text(repo.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // GitHub Account
            if !ghAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub Account")
                        .font(.caption.bold())
                    HStack {
                        Picker("", selection: $selectedAccount) {
                            Text("Default").tag("")
                            ForEach(ghAccounts, id: \.self) { account in
                                Text(account).tag(account)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)

                        Text("Used for PR access via gh CLI")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            // Review Instructions
            Text("Review Instructions")
                .font(.caption.bold())

            Text("Custom instructions for AI code reviews. Overrides the global prompt in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $promptText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)

                if promptText.isEmpty {
                    Text("e.g. Focus on security, check for SQL injection, ensure proper error handling...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            )

            if promptText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("When empty, the global prompt from Settings is used.")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Load Default Template") {
                    promptText = PromptBuilder.defaultPRReviewPrompt
                }
                .controlSize(.small)

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    repo.reviewPrompt = promptText.isEmpty ? nil : promptText
                    repo.ghAccount = selectedAccount.isEmpty ? nil : selectedAccount
                    repo.updatedAt = Date()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .onAppear {
            promptText = repo.reviewPrompt ?? ""
            selectedAccount = repo.ghAccount ?? ""
            Task {
                ghAccounts = await GitHubService.shared.listAccounts()
            }
        }
    }
}
