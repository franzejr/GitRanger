import SwiftUI

struct SettingsView: View {
    @AppStorage("aiProvider") private var aiProvider: String = AIProvider.claudeCode.rawValue
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""
    @AppStorage("anthropicModel") private var anthropicModel = "claude-sonnet-4-5-20250514"
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("ghPath") private var ghPath = ""
    @AppStorage("glabPath") private var glabPath = ""
    @AppStorage("pollInterval") private var pollInterval = 300
    @AppStorage("prReviewPrompt") private var prReviewPrompt = ""

    @State private var settingsVM = AISettingsViewModel()

    private var selectedProvider: AIProvider {
        get { AIProvider(rawValue: aiProvider) ?? .claudeCode }
        set { aiProvider = newValue.rawValue }
    }

    var body: some View {
        TabView {
            aiProviderTab
                .tabItem { Label("AI Provider", systemImage: "brain") }

            prReviewTab
                .tabItem { Label("PR Review", systemImage: "arrow.triangle.pull") }

            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 600, height: 560)
    }

    // MARK: - AI Provider Tab

    private var aiProviderTab: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $aiProvider) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName)
                            .tag(provider.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(selectedProvider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if let available = settingsVM.isAvailable(selectedProvider) {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(available ? .green : .red)
                        Text(available ? "Provider is available" : "Provider not detected")
                            .font(.caption)
                    }

                    Spacer()

                    Button("Check Availability") {
                        Task { await settingsVM.checkAvailability() }
                    }
                    .disabled(settingsVM.isChecking)
                }
            }

            providerConfigSection
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var providerConfigSection: some View {
        switch selectedProvider {
        case .claudeCode:
            Section("Claude Code") {
                Text("GitNarrate will use your local Claude Code installation.")
                    .foregroundStyle(.secondary)
                Text("Make sure Claude Code is installed and authenticated:")
                    .foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("npm install -g @anthropic-ai/claude-code")
                            .font(.system(.body, design: .monospaced))
                        Text("claude login")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Text("Binary path (leave empty for auto-detect):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Auto-detect", text: $claudePath)
                        .font(.system(.body, design: .monospaced))
                    browseButton(for: $claudePath, message: "Select the claude binary")
                }

                if !claudePath.isEmpty {
                    Text("Using: \(claudePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .anthropicAPI:
            Section("Anthropic API") {
                SecureField("API Key", text: $anthropicAPIKey)
                Picker("Model", selection: $anthropicModel) {
                    Text("Claude Sonnet 4.5").tag("claude-sonnet-4-5-20250514")
                    Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                    Text("Claude Opus 4.5").tag("claude-opus-4-5-20250918")
                }
            }

        case .openAI:
            Section("OpenAI API") {
                SecureField("API Key", text: $openAIAPIKey)
                Picker("Model", selection: $openAIModel) {
                    Text("GPT-4o").tag("gpt-4o")
                    Text("GPT-4o Mini").tag("gpt-4o-mini")
                    Text("GPT-4 Turbo").tag("gpt-4-turbo")
                }
            }

        case .ollama:
            Section("Ollama (Local)") {
                TextField("Model", text: $ollamaModel)
                TextField("URL", text: $ollamaURL)
                Text("Make sure Ollama is running: ollama serve")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    // MARK: - PR Review Tab

    private var prReviewTab: some View {
        Form {
            Section("Review Prompt") {
                Text(
                    "Customize the instructions sent to the AI when reviewing PRs. " +
                    "Leave blank to use the default prompt."
                )
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextEditor(text: $prReviewPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)

                HStack {
                    Button("Reset to Default") {
                        prReviewPrompt = ""
                    }
                    Spacer()
                    Button("Load Default Template") {
                        prReviewPrompt = PromptBuilder.defaultPRReviewPrompt
                    }
                }
            }

            Section("Requirements") {
                Text("PR Review requires the GitHub CLI (gh) or GitLab CLI (glab) to be installed.")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("brew install gh && gh auth login")
                            .font(.system(.caption, design: .monospaced))
                        Text("brew install glab && glab auth login")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            Section("CLI Paths") {
                Text("Leave empty for auto-detect via PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("gh")
                        .frame(width: 40, alignment: .trailing)
                    TextField("Auto-detect", text: $ghPath)
                        .font(.system(.body, design: .monospaced))
                    browseButton(for: $ghPath, message: "Select the gh binary")
                }

                HStack {
                    Text("glab")
                        .frame(width: 40, alignment: .trailing)
                    TextField("Auto-detect", text: $glabPath)
                        .font(.system(.body, design: .monospaced))
                    browseButton(for: $glabPath, message: "Select the glab binary")
                }
            }
        }
        .padding()
    }

    private func browseButton(
        for binding: Binding<String>, message: String
    ) -> some View {
        Button("Browse...") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = message
            if panel.runModal() == .OK, let url = panel.url {
                binding.wrappedValue = url.path
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Monitoring") {
                Picker("Poll Interval", selection: $pollInterval) {
                    Text("Every 1 minute").tag(60)
                    Text("Every 5 minutes").tag(300)
                    Text("Every 15 minutes").tag(900)
                    Text("Every 30 minutes").tag(1800)
                    Text("Every hour").tag(3600)
                }
            }

            Section("Storage") {
                let appSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first?.appendingPathComponent("GitNarrate/repos").path ?? "Unknown"

                LabeledContent("Repos Location") {
                    Text(appSupport)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
    }
}
