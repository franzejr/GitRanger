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
                AIModelOption(id: "", name: "CLI default"),
                AIModelOption(id: "sonnet", name: "Claude Sonnet"),
                AIModelOption(id: "opus", name: "Claude Opus"),
                AIModelOption(id: "fable", name: "Claude Fable"),
                AIModelOption(id: "haiku", name: "Claude Haiku")
            ]
        case .codexCLI:
            return [
                AIModelOption(id: "", name: "CLI default")
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
        case .claudeCode:
            return try LocalAIModelCatalog.claudeOptions()
        case .codexCLI:
            return try LocalAIModelCatalog.codexOptions()
        case .anthropicAPI:
            return try await anthropicModels(apiKey: settings.anthropicAPIKey)
        case .openAI:
            return try await openAIModels(apiKey: settings.openAIAPIKey)
        case .ollama:
            return try await ollamaModels(baseURL: settings.ollamaURL)
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

enum LocalAIModelCatalog {
    static func codexOptions() throws -> [AIModelOption] {
        let directory = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        let data = try Data(contentsOf: directory.appendingPathComponent(
            "models_cache.json"
        ))
        return try decodeCodexOptions(from: data)
    }

    static func claudeOptions() throws -> [AIModelOption] {
        let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
        let catalogDirectory = directory
            .appendingPathComponent("cache/model-catalog", isDirectory: true)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: catalogDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        let newest = try files
            .filter { $0.pathExtension == "json" }
            .max {
                let lhs = try $0.resourceValues(forKeys: keys)
                    .contentModificationDate ?? .distantPast
                let rhs = try $1.resourceValues(forKeys: keys)
                    .contentModificationDate ?? .distantPast
                return lhs < rhs
            }
        guard let newest else {
            throw AIError.providerError("Claude CLI model catalog is unavailable.")
        }
        return try decodeClaudeOptions(from: Data(contentsOf: newest))
    }

    static func configuredModel(for provider: AIProvider) -> String? {
        switch provider {
        case .codexCLI:
            let directory = ProcessInfo.processInfo.environment["CODEX_HOME"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex", isDirectory: true)
            let url = directory.appendingPathComponent("config.toml")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            return codexConfiguredModel(from: text)
        case .claudeCode:
            let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude", isDirectory: true)
            let url = directory.appendingPathComponent("settings.json")
            guard let data = try? Data(contentsOf: url),
                  let settings = try? JSONDecoder().decode(
                    ClaudeSettings.self, from: data
                  ) else {
                return nil
            }
            return settings.model
        case .anthropicAPI, .openAI, .ollama:
            return nil
        }
    }

    static func configuredReasoningEffort() -> String? {
        let directory = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return codexConfiguredValue(
            named: "model_reasoning_effort",
            from: text
        )
    }

    static func decodeCodexOptions(from data: Data) throws -> [AIModelOption] {
        let catalog = try JSONDecoder().decode(CodexCatalog.self, from: data)
        return catalog.models
            .filter { $0.visibility == "list" }
            .sorted { $0.priority < $1.priority }
            .map { AIModelOption(id: $0.slug, name: $0.displayName) }
    }

    static func decodeClaudeOptions(from data: Data) throws -> [AIModelOption] {
        let catalog = try JSONDecoder().decode(ClaudeCatalog.self, from: data)
        return catalog.catalog.config.models.map {
            AIModelOption(id: $0.id, name: $0.name)
        }
    }

    static func codexConfiguredModel(from text: String) -> String? {
        codexConfiguredValue(named: "model", from: text)
    }

    private static func codexConfiguredValue(
        named key: String,
        from text: String
    ) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == key else {
                continue
            }
            return parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

private struct CodexCatalog: Decodable {
    struct Model: Decodable {
        let slug: String
        let displayName: String
        let visibility: String
        let priority: Int

        enum CodingKeys: String, CodingKey {
            case slug, visibility, priority
            case displayName = "display_name"
        }
    }

    let models: [Model]
}

private struct ClaudeCatalog: Decodable {
    struct Catalog: Decodable {
        struct Config: Decodable {
            struct Model: Decodable {
                let id: String
                let name: String
            }

            let models: [Model]
        }

        let config: Config
    }

    let catalog: Catalog
}

private struct ClaudeSettings: Decodable {
    let model: String?
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
