import Foundation

final class AnthropicAPIService: AIServiceProtocol {
    let displayName = "Anthropic API"
    let requiresAPIKey = true

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "claude-sonnet-4-5-20250514") {
        self.apiKey = apiKey
        self.model = model
    }

    func isAvailable() async -> Bool {
        !apiKey.isEmpty
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        let truncatedDiff = String(diff.prefix(8000))
        let prompt = PromptBuilder.buildCommitPrompt(
            commitMessage: commitMessage,
            diff: truncatedDiff
        )

        let text = try await callAPI(prompt: prompt)
        return try PromptBuilder.parseCommitSummary(raw: text)
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        try await callAPI(prompt: prompt)
    }

    private func callAPI(prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.providerError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.providerError("Anthropic API returned status \(statusCode)")
        }

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = apiResponse.content.first(where: { $0.type == "text" })?.text else {
            throw AIError.invalidResponse("No text content in Anthropic response")
        }

        return text
    }
}
