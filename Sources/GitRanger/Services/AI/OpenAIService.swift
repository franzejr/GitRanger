import Foundation

final class OpenAIService: AIServiceProtocol {
    let displayName = "OpenAI API"
    let requiresAPIKey = true

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4o") {
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

        let text = try await callAPI(
            prompt: prompt,
            systemMessage: "You analyze git commit diffs and return structured JSON summaries.",
            jsonMode: true
        )
        return try PromptBuilder.parseCommitSummary(raw: text)
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        try await callAPI(
            prompt: prompt,
            systemMessage: "You are a helpful assistant.",
            jsonMode: false
        )
    }

    private func callAPI(prompt: String, systemMessage: String, jsonMode: Bool) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIError.providerError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": prompt]
            ]
        ]

        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.providerError("OpenAI API returned status \(statusCode)")
        }

        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = apiResponse.choices.first?.message.content else {
            throw AIError.invalidResponse("No content in OpenAI response")
        }

        return text
    }
}
