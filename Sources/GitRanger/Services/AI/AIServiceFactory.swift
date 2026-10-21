import Foundation

final class AIServiceFactory {

    static func create(
        provider: AIProvider,
        settings: AISettings,
        modelOverride: String? = nil,
        reasoningEffortOverride: String? = nil
    ) -> AIServiceProtocol {
        switch provider {
        case .claudeCode:
            ClaudeCodeService(modelOverride: modelOverride)
        case .codexCLI:
            CodexCLIService(
                modelOverride: modelOverride,
                reasoningEffortOverride: reasoningEffortOverride
            )
        case .anthropicAPI:
            AnthropicAPIService(
                apiKey: settings.anthropicAPIKey,
                model: modelOverride ?? settings.anthropicModel
            )
        case .openAI:
            OpenAIService(
                apiKey: settings.openAIAPIKey,
                model: modelOverride ?? settings.openAIModel
            )
        case .ollama:
            OllamaService(
                model: modelOverride ?? settings.ollamaModel,
                baseURL: settings.ollamaURL
            )
        }
    }

    static func autoDetect(settings: AISettings) async -> AIProvider {
        let claudeCode = ClaudeCodeService()
        if await claudeCode.isAvailable() {
            return .claudeCode
        }

        let codexCLI = CodexCLIService()
        if await codexCLI.isAvailable() {
            return .codexCLI
        }

        if !settings.anthropicAPIKey.isEmpty {
            return .anthropicAPI
        }

        if !settings.openAIAPIKey.isEmpty {
            return .openAI
        }

        let ollama = OllamaService()
        if await ollama.isAvailable() {
            return .ollama
        }

        return .claudeCode
    }

    static func settingsFromUserDefaults() -> AISettings {
        let defaults = UserDefaults.standard
        return AISettings(
            aiProvider: AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .claudeCode,
            anthropicAPIKey: defaults.string(forKey: "anthropicAPIKey") ?? "",
            anthropicModel: defaults.string(forKey: "anthropicModel") ?? "claude-sonnet-4-6",
            openAIAPIKey: defaults.string(forKey: "openAIAPIKey") ?? "",
            openAIModel: defaults.string(forKey: "openAIModel") ?? "gpt-4.1",
            ollamaModel: defaults.string(forKey: "ollamaModel") ?? "llama3.2",
            ollamaURL: defaults.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        )
    }

    static func activeProvider() -> AIServiceProtocol {
        let settings = settingsFromUserDefaults()
        return CoordinatedAIService(
            base: create(provider: settings.aiProvider, settings: settings)
        )
    }
}
