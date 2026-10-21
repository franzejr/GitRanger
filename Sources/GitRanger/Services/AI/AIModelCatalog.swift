import Foundation

struct AIModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

enum AIModelCatalog {
    static func builtInOptions(for provider: AIProvider) -> [AIModelOption] {
        switch provider {
        case .claudeCode:
            return [
                AIModelOption(id: "haiku", name: "Claude Haiku"),
                AIModelOption(id: "sonnet", name: "Claude Sonnet"),
                AIModelOption(id: "opus", name: "Claude Opus")
            ]
        case .codexCLI:
            return [
                AIModelOption(id: "", name: "Provider default"),
                AIModelOption(id: "gpt-5.1", name: "GPT-5.1"),
                AIModelOption(id: "gpt-5", name: "GPT-5")
            ]
        case .anthropicAPI:
            return [
                AIModelOption(id: "claude-sonnet-5", name: "Claude Sonnet 5"),
                AIModelOption(id: "claude-opus-5", name: "Claude Opus 5"),
                AIModelOption(id: "claude-fable-5", name: "Claude Fable 5"),
                AIModelOption(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6"),
                AIModelOption(id: "claude-opus-4-8", name: "Claude Opus 4.8"),
                AIModelOption(
                    id: "claude-haiku-4-5-20251001",
                    name: "Claude Haiku 4.5"
                )
            ]
        case .openAI:
            return [
                AIModelOption(id: "gpt-5.1", name: "GPT-5.1"),
                AIModelOption(id: "gpt-5-mini", name: "GPT-5 mini"),
                AIModelOption(id: "gpt-5-nano", name: "GPT-5 nano"),
                AIModelOption(id: "gpt-4.1", name: "GPT-4.1"),
                AIModelOption(id: "gpt-4.1-mini", name: "GPT-4.1 mini"),
                AIModelOption(id: "gpt-4o", name: "GPT-4o")
            ]
        case .ollama:
            return [AIModelOption(id: "llama3.2", name: "llama3.2")]
        }
    }
}

actor AIModelDiscoveryService {
    static let shared = AIModelDiscoveryService()

    func discover(
        provider: AIProvider,
        settings: AISettings
    ) async throws -> [AIModelOption] {
        switch provider {
        case .anthropicAPI:
            return try await anthropicModels(apiKey: settings.anthropicAPIKey)
        case .openAI:
            return try await openAIModels(apiKey: settings.openAIAPIKey)
        case .ollama:
            return try await ollamaModels(baseURL: settings.ollamaURL)
        case .claudeCode, .codexCLI:
            return []
        }
    }

    private func anthropicModels(apiKey: String) async throws -> [AIModelOption] {
        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.anthropic.com/v1/models?limit=100") else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let envelope = try JSONDecoder().decode(AnthropicModels.self, from: data)
        return envelope.data.map {
            AIModelOption(id: $0.id, name: $0.displayName)
        }
    }

    private func openAIModels(apiKey: String) async throws -> [AIModelOption] {
        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.openai.com/v1/models") else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let envelope = try JSONDecoder().decode(OpenAIModels.self, from: data)
        return envelope.data
            .map(\.id)
            .filter(Self.isOpenAITextModel)
            .sorted()
            .map { AIModelOption(id: $0, name: $0) }
    }

    private func ollamaModels(baseURL: String) async throws -> [AIModelOption] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let envelope = try JSONDecoder().decode(OllamaModels.self, from: data)
        return envelope.models
            .map(\.name)
            .sorted()
            .map { AIModelOption(id: $0, name: $0) }
    }

    private func validate(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.providerError("Model discovery returned HTTP \(status)")
        }
    }

    private static func isOpenAITextModel(_ id: String) -> Bool {
        let supportedPrefix = ["gpt-", "o1", "o3", "o4"]
            .contains { id.hasPrefix($0) }
        let excluded = [
            "audio", "codex", "image", "realtime", "search", "transcribe", "tts"
        ].contains { id.localizedCaseInsensitiveContains($0) }
        return supportedPrefix && !excluded
    }
}

private struct AnthropicModels: Decodable {
    struct Model: Decodable {
        let id: String
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    let data: [Model]
}

private struct OpenAIModels: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct OllamaModels: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}
