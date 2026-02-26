import SwiftUI

struct SettingsView: View {
    @AppStorage("aiProvider") private var aiProvider: String = AIProvider.claudeCode.rawValue
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""
    @AppStorage("anthropicModel") private var anthropicModel = "claude-sonnet-4-5-20250514"
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
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
        .frame(width: 550, height: 520)
    }

    // MARK: - AI Provider Tab

    private var aiProviderTab: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $aiProvider) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                        VStack(alignment: .leading) {
                            Text(provider.displayName)
                            Text(provider.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(provider.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

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
                Text("Customize the instructions sent to the AI when reviewing pull requests. Leave blank to use the default prompt.")
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
                Text("PR Review requires the GitHub CLI (gh) to be installed and authenticated.")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("brew install gh")
                            .font(.system(.body, design: .monospaced))
                        Text("gh auth login")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
        .padding()
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
