# GitRanger

## Project Overview
GitRanger is an open-source native macOS app that narrates the full history of any git project with AI-powered summaries and real-time monitoring.

## Project Structure
```
gitranger/
├── Package.swift       # Swift Package Manager manifest
├── Sources/            # SwiftUI macOS app source
│   └── GitRanger/
│       ├── App/        # App entry point
│       ├── Models/     # SwiftData models + AI types
│       ├── Services/   # Git, GitHub, AI, Shell services
│       ├── ViewModels/ # @Observable view models
│       └── Views/      # SwiftUI views
├── Tests/              # XCTest + Swift Testing
├── docs/               # Documentation
├── scripts/            # Build/release scripts
├── .swiftlint.yml      # SwiftLint config
├── CLAUDE.md           # This file
├── README.md
├── CONTRIBUTING.md
└── LICENSE             # MIT
```

## Architecture Document
The full architecture is in `docs/architecture-v4.md`. ALWAYS reference it before making decisions.

## Core Features (v1)
1. Import repos by GitHub URL or any git URL
2. List all commits with metadata (author, date, files changed, insertions/deletions)
3. AI-generated plain-English summaries with impact levels (patch/minor/major/breaking)
4. Filter by author and date range
5. Background polling for new commits + notifications
6. 4 pluggable AI providers: Claude Code (recommended), Anthropic API, OpenAI, Ollama

## AI Engine — Critical Design
The AI layer is protocol-based and pluggable. ALL providers must return the same JSON schema:

```json
{
  "one_liner": "one sentence summary",
  "explanation": "2-3 sentences on context and impact",
  "impact": "patch|minor|major|breaking",
  "categories": ["bugfix", "feature", "refactor", "docs", "test", "chore"],
  "related_files": ["optional — only Claude Code can provide this"],
  "risk_notes": "optional — only Claude Code can provide this"
}
```

### Claude Code provider (recommended):
```bash
cat diff.txt | claude -p "Analyze this commit..." --output-format json --allowedTools Read,Grep,Glob --cwd /repo/path
```
- Zero API key setup (uses user's existing auth)
- Can read the repo for context via --cwd
- Reports cost_usd in response

### Other providers:
- Anthropic API: Direct HTTPS to api.anthropic.com/v1/messages
- OpenAI: HTTPS to api.openai.com/v1/chat/completions with json_object format
- Ollama: HTTP to localhost:11434/api/generate with format: "json"

## App Guidelines
- **SwiftUI** with NavigationSplitView (3-column: sidebar, commit list, detail)
- **SwiftData** for persistence (@Model classes: Repo, Commit, PRReview, SubAgentReview)
- **MVVM** architecture (ViewModels as @MainActor @Observable classes)
- **Swift Concurrency** (async/await, actors for background work)
- **Minimum target**: macOS 14 (Sonoma) — required for SwiftData
- **Shell git** via Process() for git operations
- **Keychain** for API key storage
- **Sparkle 2** for auto-updates
- **MenuBarExtra** for status icon

## Code Style
- Swift: Follow Apple's Swift API Design Guidelines
- Use protocols/interfaces for all services (testable, mockable)
- Descriptive variable names, no abbreviations
- Comments for non-obvious logic only

## Testing
- XCTest + Swift Testing framework
- Mock all AI services in tests (never call real APIs in tests)

## Git Conventions
- Conventional commits: feat:, fix:, docs:, refactor:, test:, chore:
- Branch per feature: feat/commit-timeline, feat/ai-claude-code, etc.
- PR-based workflow
