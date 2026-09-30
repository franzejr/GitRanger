# GitRanger — Architecture Document v4

## Vision
An open-source tool to narrate the full history of any git project with AI-powered summaries and real-time monitoring.

**Two platforms:**
- **macOS App**: Native SwiftUI, full window app
- **Web App**: React + Node.js, self-hostable via Docker

**Two AI engines (user's choice):**
- **Claude Code (local)**: Uses the `claude` CLI in headless mode — zero API key setup needed
- **Cloud API**: Anthropic, OpenAI, Ollama, or any compatible LLM provider

---

## AI Engine Architecture

The core innovation: GitRanger treats the AI layer as a **pluggable protocol**. The user picks how they want commit analysis to run.

```
┌──────────────────────────────────────────────────────────────┐
│                     GitRanger AI Engine                      │
│                                                              │
│   User selects one:                                          │
│                                                              │
│   ┌─────────────────────────────────┐                        │
│   │  Option A: Claude Code (Local)  │  ← Recommended         │
│   │                                 │                        │
│   │  • Uses `claude -p` CLI         │  No API key needed!    │
│   │  • --output-format json         │  Uses user's own       │
│   │  • --cwd <repo_path>           │  Claude subscription   │
│   │  • --allowedTools Read,Grep     │  (Pro/Max/API)         │
│   │  • Runs locally via Process()   │                        │
│   └─────────────────────────────────┘                        │
│                                                              │
│   ┌─────────────────────────────────┐                        │
│   │  Option B: Anthropic Cloud API  │                        │
│   │                                 │                        │
│   │  • Direct HTTPS to Claude API   │  Requires API key      │
│   │  • Structured JSON outputs      │  Pay-per-use           │
│   │  • Works without CLI installed  │                        │
│   └─────────────────────────────────┘                        │
│                                                              │
│   ┌─────────────────────────────────┐                        │
│   │  Option C: OpenAI / Other       │                        │
│   │                                 │                        │
│   │  • GPT-4o, GPT-4-turbo, etc.   │  Requires API key      │
│   │  • Compatible JSON schema       │                        │
│   └─────────────────────────────────┘                        │
│                                                              │
│   ┌─────────────────────────────────┐                        │
│   │  Option D: Ollama (Fully Local) │                        │
│   │                                 │                        │
│   │  • Llama, Mistral, CodeLlama   │  100% offline           │
│   │  • HTTP to localhost:11434      │  No API key, no cost   │
│   │  • Lower quality summaries      │  Requires local GPU    │
│   └─────────────────────────────────┘                        │
└──────────────────────────────────────────────────────────────┘
```

### Why Claude Code is the recommended option:

1. **Zero configuration**: If the user has Claude Code installed (`npm i -g @anthropic-ai/claude-code`), it just works
2. **Uses existing auth**: Claude Code uses the user's Pro/Max subscription or API key — no separate key needed
3. **Can read the repo**: With `--cwd`, Claude Code can navigate the repo, read files for context — much richer analysis
4. **Structured JSON**: `--output-format json` gives clean, parseable results
5. **Tool access**: Claude Code can use `Read`, `Grep`, `Glob` to understand the broader codebase context before summarizing

---

## Claude Code Integration — How It Works

### The Core Command

For each commit, GitRanger runs:

```bash
# Step 1: Get the diff
git -C /path/to/repo show <sha> --stat --patch --no-color > /tmp/diff.txt

# Step 2: Pipe to Claude Code with JSON output
cat /tmp/diff.txt | claude -p \
  "Analyze this git commit diff. You MUST respond ONLY with a JSON object:
  {
    \"one_liner\": \"one sentence summary of what changed\",
    \"explanation\": \"2-3 sentences explaining why it matters\",
    \"impact\": \"patch|minor|major|breaking\",
    \"categories\": [\"bugfix\", \"feature\", \"refactor\", \"docs\", \"test\", \"chore\"]
  }
  
  Commit message: <commit_message>
  
  The diff follows:" \
  --output-format json \
  --allowedTools Read,Grep \
  --cwd /path/to/repo
```

### Parsing Claude Code JSON Output

Claude Code with `--output-format json` returns:

```json
{
  "type": "result",
  "subtype": "success",
  "cost_usd": 0.003,
  "is_error": false,
  "duration_ms": 2340,
  "duration_api_ms": 1850,
  "num_turns": 1,
  "result": "{\"one_liner\": \"Fix null pointer crash in user auth flow\", \"explanation\": \"The login handler was not checking for null session tokens before accessing user data, causing crashes for users with expired sessions. This adds a guard clause and redirects to the login page instead.\", \"impact\": \"patch\", \"categories\": [\"bugfix\"]}",
  "session_id": "abc-123-def"
}
```

GitRanger extracts `.result`, parses the inner JSON, and saves it.

### Advanced: Using Claude Code's Repo Awareness

For richer analysis, we can let Claude Code actually read related files:

```bash
claude -p \
  "I need you to analyze a git commit in this repository.
  
  1. First, read the diff I'm providing
  2. Then, use Read and Grep to understand the broader context of the changed files
  3. Return your analysis as JSON:
  {
    \"one_liner\": \"...\",
    \"explanation\": \"...\",
    \"impact\": \"patch|minor|major|breaking\",
    \"categories\": [...],
    \"related_files\": [\"files that might be affected by this change\"],
    \"risk_notes\": \"any potential risks or things to watch out for\"
  }
  
  Here is the diff:
  $(git -C /path/to/repo show <sha> --stat --patch --no-color)" \
  --output-format json \
  --allowedTools Read,Grep,Glob \
  --cwd /path/to/repo
```

This is something **no pure API call can do** — Claude Code can actually browse the codebase for context.

---

## Part 1: macOS Native App (SwiftUI)

### Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| UI Framework | SwiftUI | Modern, declarative, native macOS |
| Data Layer | SwiftData | Apple's native persistence (SQLite) |
| Git Operations | Shell `git` via Process() | Simple, reliable |
| AI Engine | Claude Code CLI / Cloud APIs | Pluggable (see above) |
| Networking | URLSession + async/await | For cloud API fallback |
| Concurrency | Swift actors + structured concurrency | Safe background processing |
| Notifications | UserNotifications framework | Native macOS notifications |
| Menubar | MenuBarExtra (SwiftUI) | Status icon |
| Auto-Update | Sparkle 2 | Industry standard |
| Keychain | Security framework | Secure credential storage |
| Min Target | macOS 14 (Sonoma) | SwiftData requires 14+ |

### AI Service Protocol & Implementations

```swift
// MARK: - Protocol (shared contract)
protocol AIServiceProtocol {
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    func isAvailable() async -> Bool
    func summarize(commitMessage: String, diff: String, repoPath: URL?) async throws -> CommitSummary
}

struct CommitSummary: Codable {
    let oneLiner: String
    let explanation: String
    let impact: String          // patch | minor | major | breaking
    let categories: [String]    // bugfix, feature, refactor, docs, test, chore
    let relatedFiles: [String]? // only with Claude Code
    let riskNotes: String?      // only with Claude Code
}

enum AIProvider: String, CaseIterable, Codable {
    case claudeCode = "claude_code"
    case anthropicAPI = "anthropic_api"
    case openAI = "openai"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code (Local)"
        case .anthropicAPI: return "Anthropic API"
        case .openAI: return "OpenAI API"
        case .ollama: return "Ollama (Local)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .claudeCode, .ollama: return false
        case .anthropicAPI, .openAI: return true
        }
    }

    var description: String {
        switch self {
        case .claudeCode:
            return "Uses your local Claude Code installation. No API key needed — uses your existing Claude subscription."
        case .anthropicAPI:
            return "Direct API calls to Anthropic's Claude. Requires an API key from console.anthropic.com."
        case .openAI:
            return "Uses OpenAI's GPT models. Requires an API key from platform.openai.com."
        case .ollama:
            return "Fully local AI via Ollama. No internet needed, but requires Ollama installed with a model."
        }
    }
}
```

### Claude Code Service (the key implementation)

```swift
// MARK: - Claude Code Implementation
final class ClaudeCodeService: AIServiceProtocol {
    let displayName = "Claude Code (Local)"
    let requiresAPIKey = false

    /// Check if `claude` CLI is installed and authenticated
    func isAvailable() async -> Bool {
        do {
            let output = try await shell("which", "claude")
            guard !output.isEmpty else { return false }

            // Check if authenticated by running doctor
            let doctorOutput = try await shell("claude", "doctor")
            return !doctorOutput.contains("not authenticated")
        } catch {
            return false
        }
    }

    /// Summarize a commit diff using Claude Code CLI
    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        // Truncate diff to avoid token limits
        let truncatedDiff = String(diff.prefix(12000))

        let prompt = """
        Analyze this git commit diff. You MUST respond ONLY with a valid JSON object, no other text:
        {
          "one_liner": "one sentence summary of what changed",
          "explanation": "2-3 sentences explaining why this matters and the context",
          "impact": "patch|minor|major|breaking",
          "categories": ["bugfix"|"feature"|"refactor"|"docs"|"test"|"chore"],
          "related_files": ["files that might be affected"],
          "risk_notes": "potential risks or things to watch, or null if none"
        }

        Commit message: \(commitMessage)

        Diff:
        \(truncatedDiff)
        """

        // Build the Claude Code command
        var arguments = [
            "-p", prompt,
            "--output-format", "json",
            "--allowedTools", "Read,Grep,Glob"
        ]

        // If we have a repo path, let Claude Code navigate the codebase
        if let repoPath {
            arguments += ["--cwd", repoPath.path]
        }

        let output = try await shell("claude", arguments)

        // Parse Claude Code's JSON envelope
        guard let data = output.data(using: .utf8) else {
            throw AIError.invalidResponse("Empty output from Claude Code")
        }

        let envelope = try JSONDecoder().decode(ClaudeCodeResponse.self, from: data)

        guard !envelope.isError else {
            throw AIError.providerError(envelope.result)
        }

        // Parse the inner JSON result
        guard let resultData = envelope.result.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not parse result JSON")
        }

        return try JSONDecoder().decode(CommitSummary.self, from: resultData)
    }
}

// Claude Code's JSON output envelope
struct ClaudeCodeResponse: Codable {
    let type: String            // "result"
    let subtype: String         // "success" | "error"
    let costUsd: Double?        // cost of this call
    let isError: Bool
    let durationMs: Int?
    let numTurns: Int?
    let result: String          // inner JSON string
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type, subtype, result
        case costUsd = "cost_usd"
        case isError = "is_error"
        case durationMs = "duration_ms"
        case numTurns = "num_turns"
        case sessionId = "session_id"
    }
}
```

### Anthropic Cloud API Service (fallback)

```swift
// MARK: - Anthropic API Implementation
final class AnthropicAPIService: AIServiceProtocol {
    let displayName = "Anthropic API"
    let requiresAPIKey = true

    private let apiKey: String
    private let model: String
    private let session = URLSession.shared

    init(apiKey: String, model: String = "claude-sonnet-4-5-20250514") {
        self.apiKey = apiKey
        self.model = model
    }

    func isAvailable() async -> Bool {
        return !apiKey.isEmpty
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL? = nil   // not used — no local access
    ) async throws -> CommitSummary {
        let truncatedDiff = String(diff.prefix(8000))

        let prompt = """
        Analyze this git commit diff. Respond ONLY with valid JSON:
        {
          "one_liner": "one sentence summary",
          "explanation": "2-3 sentences on why it matters",
          "impact": "patch|minor|major|breaking",
          "categories": ["bugfix"|"feature"|"refactor"|"docs"|"test"|"chore"]
        }

        Commit message: \(commitMessage)

        Diff:
        \(truncatedDiff)
        """

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 600,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIError.providerError("Anthropic API returned error")
        }

        // Parse Anthropic response → extract text → parse JSON
        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = apiResponse.content.first(where: { $0.type == "text" })?.text ?? ""
        let cleanJSON = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not parse API response")
        }
        return try JSONDecoder().decode(CommitSummary.self, from: jsonData)
    }
}
```

### OpenAI Service

```swift
// MARK: - OpenAI Implementation
final class OpenAIService: AIServiceProtocol {
    let displayName = "OpenAI API"
    let requiresAPIKey = true

    private let apiKey: String
    private let model: String
    private let session = URLSession.shared

    init(apiKey: String, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.model = model
    }

    func isAvailable() async -> Bool { !apiKey.isEmpty }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL? = nil
    ) async throws -> CommitSummary {
        let truncatedDiff = String(diff.prefix(8000))

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": "You analyze git diffs and return JSON summaries."],
                ["role": "user", "content": """
                    Analyze this commit. Return JSON:
                    {"one_liner":"...","explanation":"...","impact":"patch|minor|major|breaking","categories":[...]}
                    
                    Commit: \(commitMessage)
                    Diff: \(truncatedDiff)
                    """]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let text = response.choices.first?.message.content ?? ""
        guard let jsonData = text.data(using: .utf8) else {
            throw AIError.invalidResponse("Empty OpenAI response")
        }
        return try JSONDecoder().decode(CommitSummary.self, from: jsonData)
    }
}
```

### Ollama Service (fully offline)

```swift
// MARK: - Ollama Implementation (100% local)
final class OllamaService: AIServiceProtocol {
    let displayName = "Ollama (Local)"
    let requiresAPIKey = false

    private let model: String
    private let baseURL: String
    private let session = URLSession.shared

    init(model: String = "llama3.2", baseURL: String = "http://localhost:11434") {
        self.model = model
        self.baseURL = baseURL
    }

    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL? = nil
    ) async throws -> CommitSummary {
        let truncatedDiff = String(diff.prefix(4000)) // smaller for local models

        var request = URLRequest(url: URL(string: "\(baseURL)/api/generate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": """
                Analyze this git commit. Return ONLY valid JSON:
                {"one_liner":"...","explanation":"...","impact":"patch|minor|major|breaking","categories":[...]}
                Commit: \(commitMessage)
                Diff: \(truncatedDiff)
                """,
            "stream": false,
            "format": "json"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        guard let jsonData = ollamaResponse.response.data(using: .utf8) else {
            throw AIError.invalidResponse("Empty Ollama response")
        }
        return try JSONDecoder().decode(CommitSummary.self, from: jsonData)
    }
}
```

### AI Service Factory

```swift
// MARK: - Factory (creates the right service based on user settings)
final class AIServiceFactory {

    static func create(provider: AIProvider, settings: AppSettings) -> AIServiceProtocol {
        switch provider {
        case .claudeCode:
            return ClaudeCodeService()

        case .anthropicAPI:
            return AnthropicAPIService(
                apiKey: settings.anthropicAPIKey,
                model: settings.anthropicModel
            )

        case .openAI:
            return OpenAIService(
                apiKey: settings.openAIAPIKey,
                model: settings.openAIModel
            )

        case .ollama:
            return OllamaService(
                model: settings.ollamaModel,
                baseURL: settings.ollamaURL
            )
        }
    }

    /// Auto-detect the best available provider
    static func autoDetect(settings: AppSettings) async -> AIProvider {
        // Priority: Claude Code > Anthropic API > OpenAI > Ollama
        let claudeCode = ClaudeCodeService()
        if await claudeCode.isAvailable() {
            return .claudeCode
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

        // Default to Claude Code (will prompt user to install)
        return .claudeCode
    }
}
```

---

## Settings UI (SwiftUI) — AI Provider Selection

```swift
struct SettingsView: View {
    @AppStorage("aiProvider") private var aiProvider: AIProvider = .claudeCode
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""
    @AppStorage("anthropicModel") private var anthropicModel = "claude-sonnet-4-5-20250514"
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("pollInterval") private var pollInterval = 300
    @State private var providerAvailable: Bool?

    var body: some View {
        TabView {
            // AI Provider Tab
            Form {
                Section("AI Provider") {
                    Picker("Provider", selection: $aiProvider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            VStack(alignment: .leading) {
                                Text(provider.displayName)
                                Text(provider.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(provider)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    // Availability check
                    if let available = providerAvailable {
                        Label(
                            available ? "Provider is available" : "Provider not detected",
                            systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(available ? .green : .red)
                    }

                    Button("Check Availability") {
                        Task {
                            let service = AIServiceFactory.create(
                                provider: aiProvider,
                                settings: currentSettings()
                            )
                            providerAvailable = await service.isAvailable()
                        }
                    }
                }

                // Claude Code section
                if aiProvider == .claudeCode {
                    Section("Claude Code") {
                        Text("GitRanger will use your local Claude Code installation.")
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

                        Link("Claude Code Documentation",
                             destination: URL(string: "https://docs.claude.com/en/docs/claude-code/overview")!)
                    }
                }

                // Anthropic API section
                if aiProvider == .anthropicAPI {
                    Section("Anthropic API") {
                        SecureField("API Key", text: $anthropicAPIKey)
                        Picker("Model", selection: $anthropicModel) {
                            Text("Claude Sonnet 4.5").tag("claude-sonnet-4-5-20250514")
                            Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                            Text("Claude Opus 4.5").tag("claude-opus-4-5-20250918")
                        }
                        Link("Get API Key",
                             destination: URL(string: "https://console.anthropic.com/")!)
                    }
                }

                // OpenAI section
                if aiProvider == .openAI {
                    Section("OpenAI API") {
                        SecureField("API Key", text: $openAIAPIKey)
                        Picker("Model", selection: $openAIModel) {
                            Text("GPT-4o").tag("gpt-4o")
                            Text("GPT-4o Mini").tag("gpt-4o-mini")
                            Text("GPT-4 Turbo").tag("gpt-4-turbo")
                        }
                    }
                }

                // Ollama section
                if aiProvider == .ollama {
                    Section("Ollama (Local)") {
                        TextField("Model", text: $ollamaModel)
                        TextField("URL", text: $ollamaURL)
                        Text("Make sure Ollama is running: ollama serve")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tabItem { Label("AI Provider", systemImage: "brain") }
            .padding()

            // General Tab
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
            }
            .tabItem { Label("General", systemImage: "gear") }
            .padding()
        }
        .frame(width: 550, height: 450)
    }
}
```

---

## Part 2: Web App — AI Engine Integration (Node.js)

The web app supports the same 4 providers, but Claude Code is only available if the server has `claude` CLI installed.

### AI Service Interface (TypeScript)

```typescript
// server/src/services/ai/ai.interface.ts
export interface CommitSummary {
  one_liner: string;
  explanation: string;
  impact: 'patch' | 'minor' | 'major' | 'breaking';
  categories: string[];
  related_files?: string[];
  risk_notes?: string | null;
}

export interface AIService {
  name: string;
  requiresAPIKey: boolean;
  isAvailable(): Promise<boolean>;
  summarize(commitMessage: string, diff: string, repoPath?: string): Promise<CommitSummary>;
}
```

### Claude Code Service (Node.js)

```typescript
// server/src/services/ai/claude-code.service.ts
import { exec } from 'child_process';
import { promisify } from 'util';
import { AIService, CommitSummary } from './ai.interface';

const execAsync = promisify(exec);

export class ClaudeCodeService implements AIService {
  name = 'Claude Code (Local)';
  requiresAPIKey = false;

  async isAvailable(): Promise<boolean> {
    try {
      await execAsync('which claude');
      return true;
    } catch {
      return false;
    }
  }

  async summarize(
    commitMessage: string,
    diff: string,
    repoPath?: string
  ): Promise<CommitSummary> {
    const truncatedDiff = diff.slice(0, 12000);

    const prompt = `Analyze this git commit diff. Respond ONLY with valid JSON:
{
  "one_liner": "one sentence summary",
  "explanation": "2-3 sentences on context and impact",
  "impact": "patch|minor|major|breaking",
  "categories": ["bugfix"|"feature"|"refactor"|"docs"|"test"|"chore"],
  "related_files": ["potentially affected files"],
  "risk_notes": "risks to watch, or null"
}

Commit message: ${commitMessage}

Diff:
${truncatedDiff}`;

    const cwdArg = repoPath ? `--cwd "${repoPath}"` : '';
    const command = `echo ${JSON.stringify(prompt)} | claude -p --output-format json --allowedTools Read,Grep,Glob ${cwdArg}`;

    const { stdout } = await execAsync(command, {
      timeout: 60000, // 60s timeout
      maxBuffer: 1024 * 1024 * 10 // 10MB buffer
    });

    const envelope = JSON.parse(stdout);

    if (envelope.is_error) {
      throw new Error(`Claude Code error: ${envelope.result}`);
    }

    // Parse inner JSON from result string
    return JSON.parse(envelope.result) as CommitSummary;
  }
}
```

### Anthropic API Service (Node.js)

```typescript
// server/src/services/ai/anthropic.service.ts
import { AIService, CommitSummary } from './ai.interface';

export class AnthropicAPIService implements AIService {
  name = 'Anthropic API';
  requiresAPIKey = true;

  constructor(
    private apiKey: string,
    private model: string = 'claude-sonnet-4-5-20250514'
  ) {}

  async isAvailable(): Promise<boolean> {
    return !!this.apiKey;
  }

  async summarize(commitMessage: string, diff: string): Promise<CommitSummary> {
    const truncatedDiff = diff.slice(0, 8000);

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': this.apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: 600,
        messages: [{
          role: 'user',
          content: `Analyze this commit. Return ONLY JSON:
{"one_liner":"...","explanation":"...","impact":"patch|minor|major|breaking","categories":[...]}

Commit: ${commitMessage}
Diff: ${truncatedDiff}`
        }]
      })
    });

    const data = await response.json();
    const text = data.content[0]?.text || '';
    const clean = text.replace(/```json|```/g, '').trim();
    return JSON.parse(clean);
  }
}
```

### AI Service Factory (Node.js)

```typescript
// server/src/services/ai/factory.ts
import { AIService } from './ai.interface';
import { ClaudeCodeService } from './claude-code.service';
import { AnthropicAPIService } from './anthropic.service';
import { OpenAIService } from './openai.service';
import { OllamaService } from './ollama.service';

export type AIProvider = 'claude_code' | 'anthropic_api' | 'openai' | 'ollama';

export function createAIService(provider: AIProvider, config: Record<string, string>): AIService {
  switch (provider) {
    case 'claude_code':
      return new ClaudeCodeService();
    case 'anthropic_api':
      return new AnthropicAPIService(config.ANTHROPIC_API_KEY, config.ANTHROPIC_MODEL);
    case 'openai':
      return new OpenAIService(config.OPENAI_API_KEY, config.OPENAI_MODEL);
    case 'ollama':
      return new OllamaService(config.OLLAMA_MODEL, config.OLLAMA_URL);
    default:
      throw new Error(`Unknown AI provider: ${provider}`);
  }
}

export async function autoDetectProvider(config: Record<string, string>): Promise<AIProvider> {
  const cc = new ClaudeCodeService();
  if (await cc.isAvailable()) return 'claude_code';
  if (config.ANTHROPIC_API_KEY) return 'anthropic_api';
  if (config.OPENAI_API_KEY) return 'openai';
  const ollama = new OllamaService();
  if (await ollama.isAvailable()) return 'ollama';
  return 'claude_code'; // default, will prompt to install
}
```

---

## Cost Tracking

Since Claude Code reports `cost_usd` in its JSON output, GitRanger can track AI costs:

```swift
@Model
final class AIUsageLog {
    var provider: String         // "claude_code" | "anthropic_api" | ...
    var commitSha: String
    var costUsd: Double?         // from Claude Code's cost_usd field
    var durationMs: Int?
    var tokensUsed: Int?
    var createdAt: Date = Date()
}
```

The Settings view can show a cost summary:
```
This month: $0.47 (156 commits analyzed)
Today: $0.03 (12 commits)
Average per commit: $0.003
```

---

## First-Run Experience

```
┌─────────────────────────────────────────────────────────┐
│                                                          │
│                    Welcome to GitRanger                  │
│                                                          │
│   Let's set up your AI engine for commit analysis.       │
│                                                          │
│   ┌─────────────────────────────────────────────────┐    │
│   │ ⭐ Claude Code (Recommended)                    │    │
│   │    Uses your local Claude Code installation.    │    │
│   │    No API key needed.                           │    │
│   │    ✅ Detected! Ready to go.                    │    │
│   └─────────────────────────────────────────────────┘    │
│                                                          │
│   ┌─────────────────────────────────────────────────┐    │
│   │    Anthropic API                                │    │
│   │    Direct API calls. Requires API key.          │    │
│   │    [ Enter API Key ]                            │    │
│   └─────────────────────────────────────────────────┘    │
│                                                          │
│   ┌─────────────────────────────────────────────────┐    │
│   │    OpenAI                                       │    │
│   │    GPT-4o models. Requires API key.             │    │
│   │    [ Enter API Key ]                            │    │
│   └─────────────────────────────────────────────────┘    │
│                                                          │
│   ┌─────────────────────────────────────────────────┐    │
│   │    Ollama (Fully Offline)                       │    │
│   │    100% local. Requires Ollama installed.       │    │
│   │    ❌ Not detected.                             │    │
│   └─────────────────────────────────────────────────┘    │
│                                                          │
│                              [ Continue → ]              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Monorepo Structure

```
gitranger/
├── macos/                          # Native macOS app
│   ├── GitRanger.xcodeproj
│   ├── GitRanger/
│   │   ├── App/
│   │   ├── Models/
│   │   ├── ViewModels/
│   │   ├── Views/
│   │   ├── Services/
│   │   │   ├── AI/
│   │   │   │   ├── AIServiceProtocol.swift
│   │   │   │   ├── ClaudeCodeService.swift   ← Key file
│   │   │   │   ├── AnthropicAPIService.swift
│   │   │   │   ├── OpenAIService.swift
│   │   │   │   ├── OllamaService.swift
│   │   │   │   └── AIServiceFactory.swift
│   │   │   ├── Git/
│   │   │   ├── PollService.swift
│   │   │   └── KeychainService.swift
│   │   └── Utilities/
│   └── GitRangerTests/
│
├── web/                            # React + Node.js web app
│   ├── client/
│   ├── server/
│   │   └── src/
│   │       └── services/
│   │           └── ai/
│   │               ├── ai.interface.ts
│   │               ├── claude-code.service.ts  ← Key file
│   │               ├── anthropic.service.ts
│   │               ├── openai.service.ts
│   │               ├── ollama.service.ts
│   │               └── factory.ts
│   ├── docker-compose.yml
│   └── Dockerfile
│
├── docs/
│   ├── architecture.md             ← This file
│   ├── ai-prompts.md
│   └── schema.sql
│
├── .github/workflows/
│   ├── ci-macos.yml
│   ├── ci-web.yml
│   ├── release-macos.yml
│   └── release-web.yml
│
├── README.md
├── CONTRIBUTING.md
└── LICENSE (MIT)
```

---

## Roadmap

### v1.0 — MVP
- [x] macOS native SwiftUI app
- [x] Web app (React + Node.js)
- [x] **Claude Code as local AI engine** (recommended)
- [x] Anthropic API, OpenAI, Ollama as alternatives
- [x] Auto-detect best available provider
- [x] Import repos (GitHub URL + any git URL)
- [x] AI commit summaries with impact levels
- [x] Filter by author and date range
- [x] Background polling + notifications
- [x] Cost tracking (Claude Code reports cost_usd)

### v1.1
- [ ] Batch analysis mode (analyze all commits at once)
- [ ] Multi-branch support
- [ ] PR / Merge Request summaries
- [ ] Syntax-highlighted diff viewer
- [ ] Claude Code `--cwd` deep analysis mode (reads related files)

### v2.0
- [ ] "Ask about this project" — chat with repo history
- [ ] Team dashboards (web)
- [ ] Slack / Discord notifications
- [ ] macOS Widgets (WidgetKit)
- [ ] Export timeline as PDF / Markdown

### v3.0
- [ ] iOS companion app
- [ ] VS Code extension
- [ ] Claude Code subagent for automated repo monitoring
