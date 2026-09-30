import SwiftUI

struct ReviewPromptSheet: View {
    let repo: Repo
    @Binding var isPresented: Bool
    @State private var promptText: String = ""
    @State private var selectedAccount: String = ""
    @State private var ghAccounts: [String] = []
    @State var agentPromptTexts: [ReviewAgent: String] = [:]
    @State var agentEnabled: [ReviewAgent: Bool] = [:]
    @State var customAgents: [CustomReviewAgent] = []
    @State var editingCustomAgent: CustomReviewAgent?
    @State var showAddAgent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            Divider()
            sheetContent
            Divider()
            sheetFooter
        }
        .frame(width: 780, height: 860)
        .onAppear {
            promptText = repo.reviewPrompt ?? ""
            selectedAccount = repo.ghAccount ?? ""
            customAgents = repo.customAgents
            loadAgentPrompts()
            Task {
                ghAccounts = await GitHubService.shared.listAccounts()
            }
        }
    }

    // MARK: - Layout Sections

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Repo Settings")
                .font(.title3.bold())
            Text(repo.name)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var sheetContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ghAccountSection
                reviewInstructionsSection
                builtInAgentsSection
                customAgentsSection
            }
            .padding(20)
        }
    }

    private var sheetFooter: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - GitHub Account

    @ViewBuilder
    private var ghAccountSection: some View {
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

            Divider()
        }
    }

    // MARK: - Review Instructions

    private var reviewInstructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Instructions")
                .font(.caption.bold())

            Text("Custom instructions for the single-pass AI review.")
                .font(.caption)
                .foregroundStyle(.secondary)

            promptEditor(
                text: $promptText,
                placeholder: "e.g. Focus on security, check for SQL injection..."
            )
            .frame(height: 100)

            if promptText.isEmpty {
                usingDefaultHint(
                    "When empty, the global prompt from Settings is used."
                )
            }

            HStack {
                Button("Load Default Template") {
                    promptText = PromptBuilder.defaultPRReviewPrompt
                }
                .controlSize(.small)
            }

            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Built-in Agents

    private var builtInAgentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built-in Agents")
                .font(.caption.bold())

            Text("Customize the prompt for each review agent.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ReviewAgent.allCases) { agent in
                agentPromptSection(agent)
            }

            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Custom Agents

    private var customAgentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom Agents")
                    .font(.caption.bold())

                Spacer()

                Button {
                    let newAgent = CustomReviewAgent(
                        name: "",
                        icon: "eye",
                        colorName: "blue",
                        prompt: ""
                    )
                    editingCustomAgent = newAgent
                    showAddAgent = true
                } label: {
                    Label("Add Agent", systemImage: "plus")
                }
                .controlSize(.small)
            }

            Text("Create your own review agents with custom prompts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if customAgents.isEmpty {
                emptyCustomAgentsPlaceholder
            } else {
                ForEach(
                    Array(customAgents.enumerated()),
                    id: \.element.id
                ) { index, agent in
                    customAgentRow(agent, index: index)
                }
            }

            if showAddAgent, let editing = editingCustomAgent {
                customAgentForm(editing)
            }
        }
    }

    private var emptyCustomAgentsPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No custom agents yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            Spacer()
        }
    }

    // MARK: - Shared Components

    func promptEditor(
        text: Binding<String>, placeholder: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary)
        )
    }

    // MARK: - Persistence

    private func loadAgentPrompts() {
        let disabled = Set(repo.disabledAgents ?? [])
        for agent in ReviewAgent.allCases {
            agentEnabled[agent] = !disabled.contains(agent.rawValue)
            if let value = repo.agentPrompts?[agent.rawValue] {
                agentPromptTexts[agent] = value
            }
        }
    }

    private func save() {
        repo.reviewPrompt = promptText.isEmpty ? nil : promptText
        repo.ghAccount = selectedAccount.isEmpty
            ? nil : selectedAccount

        var prompts: [String: String] = [:]
        for agent in ReviewAgent.allCases {
            if let text = agentPromptTexts[agent], !text.isEmpty {
                prompts[agent.rawValue] = text
            }
        }
        repo.agentPrompts = prompts.isEmpty ? nil : prompts

        let disabled = ReviewAgent.allCases
            .filter { !(agentEnabled[$0] ?? true) }
            .map(\.rawValue)
        repo.disabledAgents = disabled.isEmpty ? nil : disabled

        repo.customAgents = customAgents

        repo.updatedAt = Date()
        isPresented = false
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
