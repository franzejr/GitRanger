import Foundation

final class AIServiceFactory {

    static func create(provider: AIProvider, settings: AISettings) -> AIServiceProtocol {
        switch provider {
        case .claudeCode:
            ClaudeCodeService()
        case .codexCLI:
            CodexCLIService()
        case .anthropicAPI:
            AnthropicAPIService(
                apiKey: settings.anthropicAPIKey,
                model: settings.anthropicModel
            )
        case .openAI:
            OpenAIService(
                apiKey: settings.openAIAPIKey,
                model: settings.openAIModel
            )
        case .ollama:
            OllamaService(
                model: settings.ollamaModel,
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
            anthropicModel: defaults.string(forKey: "anthropicModel") ?? "claude-sonnet-4-5-20250514",
            openAIAPIKey: defaults.string(forKey: "openAIAPIKey") ?? "",
            openAIModel: defaults.string(forKey: "openAIModel") ?? "gpt-4o",
            ollamaModel: defaults.string(forKey: "ollamaModel") ?? "llama3.2",
            ollamaURL: defaults.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        )
    }

    static func activeProvider() -> AIServiceProtocol {
        let settings = settingsFromUserDefaults()
        return create(provider: settings.aiProvider, settings: settings)
    }
}
