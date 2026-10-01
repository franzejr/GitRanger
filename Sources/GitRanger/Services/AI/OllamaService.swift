import Foundation

final class OllamaService: AIServiceProtocol {
    let displayName = "Ollama (Local)"
    let requiresAPIKey = false

    private let model: String
    private let baseURL: String

    init(model: String = "llama3.2", baseURL: String = "http://localhost:11434") {
        self.model = model
        self.baseURL = baseURL
    }

    func isAvailable() async -> Bool {
        await availabilityStatus().isAvailable
    }

    func availabilityStatus() async -> AIAvailabilityStatus {
        let endpoint = "\(baseURL)/api/tags"
        guard let url = URL(string: endpoint) else {
            return AIAvailabilityStatus(
                isAvailable: false,
                detail: "The Ollama server URL is invalid: \(baseURL)"
            )
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return AIAvailabilityStatus(
                isAvailable: statusCode == 200,
                detail: statusCode == 200
                    ? "Connected to Ollama at \(baseURL)."
                    : "Ollama at \(baseURL) returned HTTP \(statusCode)."
            )
        } catch {
            return AIAvailabilityStatus(
                isAvailable: false,
                detail: "Could not reach Ollama at \(baseURL): \(error.localizedDescription)"
            )
        }
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        let truncatedDiff = String(diff.prefix(4000))
        let prompt = PromptBuilder.buildCommitPrompt(
            commitMessage: commitMessage,
            diff: truncatedDiff
        )

        let text = try await callAPI(prompt: prompt, jsonFormat: true)
        return try PromptBuilder.parseCommitSummary(raw: text)
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        try await callAPI(prompt: prompt, jsonFormat: false)
    }

    private func callAPI(prompt: String, jsonFormat: Bool) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw AIError.providerError("Invalid Ollama URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]

        if jsonFormat {
            body["format"] = "json"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.providerError("Ollama returned status \(statusCode)")
        }

        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return ollamaResponse.response
    }
}
