import SwiftUI

struct AIProviderSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("aiProvider") private var aiProvider = AIProvider.claudeCode.rawValue
    @AppStorage("claudeModel") private var claudeModel = "haiku"
    @AppStorage("claudeCustomModel") private var claudeCustomModel = ""
    @AppStorage("claudeRepoContext") private var claudeRepoContext = true
    @AppStorage("codexModel") private var codexModel = ""
    @AppStorage("codexRepoContext") private var codexRepoContext = true
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""
    @AppStorage("anthropicModel") private var anthropicModel = "claude-sonnet-4-5-20250514"
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("prReviewPrompt") private var prReviewPrompt = ""

    @Bindable var settingsVM: AISettingsViewModel

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: aiProvider) ?? .claudeCode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Used for summaries, narratives, commit messages and PR reviews.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                        ProviderCard(
                            provider: provider,
                            isSelected: selectedProvider == provider
                        ) {
                            aiProvider = provider.rawValue
                        }
                    }
                }

                providerDetail
            }
            .padding(28)
        }
    }

    @ViewBuilder
    private var providerDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedProvider.cardDisplayName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                providerStatus
                Button {
                    Task { await settingsVM.checkAvailability() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(settingsVM.isChecking)
            }

            availabilityDiagnostic

            switch selectedProvider {
            case .claudeCode: claudeConfiguration
            case .codexCLI: codexConfiguration
            case .anthropicAPI: anthropicConfiguration
            case .openAI: openAIConfiguration
            case .ollama: ollamaConfiguration
            }
        }
        .padding(14)
        .grCard()
    }

    @ViewBuilder
    private var providerStatus: some View {
        if settingsVM.isChecking {
            ProgressView().controlSize(.small)
        } else if let available = settingsVM.isAvailable(selectedProvider) {
            HStack(spacing: 6) {
                Circle()
                    .fill(available ? GRTheme.success : GRTheme.danger)
                    .frame(width: 6, height: 6)
                Text(available ? "Connected" : "Not available")
                    .font(.system(size: 11))
                    .foregroundStyle(available ? GRTheme.success : GRTheme.danger)
            }
        }
    }

    @ViewBuilder
    private var availabilityDiagnostic: some View {
        if let status = settingsVM.availabilityStatus(for: selectedProvider) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Connection diagnostic")
                        .font(.system(size: 10.5, weight: .semibold))
                    Spacer()
                    Text(status.checkedAt, style: .time)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(GRTheme.muted(colorScheme))
                }
                Text(status.detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(
                        status.isAvailable
                            ? GRTheme.mutedSecondary(colorScheme)
                            : GRTheme.danger
                    )
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GRTheme.background(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(GRTheme.line(colorScheme))
            }
        }
    }

    private var claudeConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Model") {
                HStack(spacing: 10) {
                    Picker("Model", selection: $claudeModel) {
                        Text("Claude Haiku").tag("haiku")
                        Text("Claude Sonnet").tag("sonnet")
                        Text("Claude Opus").tag("opus")
                        Text("Custom model ID").tag("custom")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)

                    if claudeModel == "custom" {
                        TextField("Claude model ID", text: $claudeCustomModel)
                            .font(.system(size: 11, design: .monospaced))
                            .accessibilityIdentifier("claude-custom-model-field")
                    }
                }
            }
            SettingsRow("Repo context") {
                HStack(spacing: 8) {
                    Toggle("", isOn: $claudeRepoContext)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("Let agents read the working tree for richer reviews")
                        .font(.system(size: 11))
                        .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                }
            }
            SettingsRow("Global review instructions", alignment: .top) {
                TextEditor(text: $prReviewPrompt)
                    .font(.system(size: 10.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 58)
                    .padding(6)
                    .background(GRTheme.background(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(GRTheme.line(colorScheme))
                    }
            }
        }
    }

    private var anthropicConfiguration: some View {
        VStack(spacing: 10) {
            SettingsRow("API key") {
                SecureField("Anthropic API key", text: $anthropicAPIKey)
            }
            SettingsRow("Model") {
                Picker("Model", selection: $anthropicModel) {
                    Text("Claude Sonnet 4.5").tag("claude-sonnet-4-5-20250514")
                    Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                    Text("Claude Opus 4.5").tag("claude-opus-4-5-20250918")
                }.labelsHidden()
            }
        }
    }

    private var codexConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Model") {
                TextField("Use Codex CLI default", text: $codexModel)
                    .font(.system(size: 11, design: .monospaced))
            }
            SettingsRow("Repo context") {
                HStack(spacing: 8) {
                    Toggle("", isOn: $codexRepoContext)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("Let Codex inspect the working tree in read-only mode")
                        .font(.system(size: 11))
                        .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                }
            }
            SettingsRow("Execution") {
                Text("Ephemeral session · read-only sandbox · no approval prompts")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
            }
        }
    }

    private var openAIConfiguration: some View {
        VStack(spacing: 10) {
            SettingsRow("API key") { SecureField("OpenAI API key", text: $openAIAPIKey) }
            SettingsRow("Model") {
                Picker("Model", selection: $openAIModel) {
                    Text("GPT-4o").tag("gpt-4o")
                    Text("GPT-4o Mini").tag("gpt-4o-mini")
                    Text("GPT-4 Turbo").tag("gpt-4-turbo")
                }.labelsHidden()
            }
        }
    }

    private var ollamaConfiguration: some View {
        VStack(spacing: 10) {
            SettingsRow("Model") { TextField("Model", text: $ollamaModel) }
            SettingsRow("Server URL") { TextField("URL", text: $ollamaURL) }
        }
    }
}

private struct ProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                heading
                Text(provider.cardDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                tags
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(isSelected ? GRTheme.accentSoft(colorScheme) : GRTheme.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? GRTheme.accent : GRTheme.line(colorScheme),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var heading: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(
                        isSelected ? GRTheme.accent : GRTheme.muted(colorScheme),
                        lineWidth: 1.5
                    )
                    .frame(width: 14, height: 14)
                if isSelected {
                    Circle().fill(GRTheme.accent).frame(width: 7, height: 7)
                }
            }
            Text(provider.cardDisplayName)
                .font(.system(size: 12.5, weight: .semibold))
            if provider == .claudeCode {
                Text("RECOMMENDED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(GRTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(GRTheme.accentSoft(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: 0)
        }
    }

    private var tags: some View {
        HStack(spacing: 6) {
            ForEach(provider.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(GRTheme.segment(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    let alignment: VerticalAlignment
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        _ label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                .frame(width: 140, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension AIProvider {
    var cardDisplayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codexCLI: "Codex CLI"
        case .anthropicAPI: "Anthropic API"
        case .openAI: "OpenAI"
        case .ollama: "Ollama"
        }
    }

    var cardDescription: String {
        switch self {
        case .claudeCode:
            "Uses your existing Claude subscription. No API key. Can read the repo for richer context."
        case .codexCLI:
            "Uses your existing Codex login. Runs non-interactively with a read-only sandbox."
        case .anthropicAPI:
            "Direct API access with your own key."
        case .openAI:
            "GPT models with your own key."
        case .ollama:
            "Fully local. No internet required."
        }
    }

    var tags: [String] {
        switch self {
        case .claudeCode: ["no key", "repo context"]
        case .codexCLI: ["no key", "read only"]
        case .anthropicAPI, .openAI: ["api key"]
        case .ollama: ["no key", "local"]
        }
    }
}
