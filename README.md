# GitNarrate

An open-source tool that narrates the full history of any git project with AI-powered summaries and real-time monitoring.

## Features

- **Import repositories** by GitHub URL or any git URL
- **AI-powered commit summaries** with impact levels (patch/minor/major/breaking)
- **AI-powered PR code reviews** with customizable prompts per repo
- **Multi-commit narratives** — select multiple commits and get a story of what changed
- **Multiple AI providers**: Claude Code (recommended), Anthropic API, OpenAI, Ollama
- **Filter commits** by author, date range, and branch
- **Background monitoring** with notifications for new commits
- **Cost tracking** for AI usage

## Platforms

### macOS App (Native)

A full-featured SwiftUI application with:
- 3-column NavigationSplitView layout (sidebar, commit/PR list, detail)
- Branch switching and incremental commit loading
- GitHub PR listing and AI code review via `gh` CLI
- Per-repo GitHub account selection and custom review prompts
- Live clone progress with object/delta streaming
- SwiftData persistence with cached AI reviews
- Native notifications and menu bar status icon

### Web App (Self-hosted)

A React + Node.js application with:
- Modern React 18 frontend with Tailwind CSS
- Express + TypeScript backend
- SQLite database
- Docker support for easy deployment

## Quick Start

### macOS App

**Requirements:**
- macOS 14 (Sonoma) or later
- Xcode 15+ or Swift 5.9+ toolchain
- Claude Code CLI (recommended) or API keys for other providers
- `gh` CLI for PR reviews (optional): `brew install gh && gh auth login`

```bash
# Clone the repository
git clone https://github.com/franzejr/GitNarrate.git
cd GitNarrate/macos

# Build with Swift Package Manager
swift build

# Run the app
swift run

# Or build release
swift build -c release
.build/release/GitNarrate
```

### Web App

**Requirements:**
- Node.js 18+
- Redis (for background job queue)
- Docker (optional, for containerized deployment)

```bash
# Clone the repository
git clone https://github.com/franzejr/GitNarrate.git
cd GitNarrate/web

# Install dependencies
cd server && npm install
cd ../client && npm install

# Start the backend (from web/server)
npm run dev

# Start the frontend (from web/client, in another terminal)
npm run dev

# Open http://localhost:5173
```

### Docker Deployment

```bash
cd GitNarrate/web
docker-compose up -d
```

## AI Provider Setup

GitNarrate supports 4 AI providers. Claude Code is recommended for the best experience.

### Claude Code (Recommended)

No API key needed. Uses your existing Claude subscription.

```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Authenticate
claude login
```

### Anthropic API

Get an API key from [console.anthropic.com](https://console.anthropic.com/).

### OpenAI

Get an API key from [platform.openai.com](https://platform.openai.com/).

### Ollama (Fully Local)

```bash
# Install Ollama
brew install ollama

# Pull a model
ollama pull llama3.2

# Start the server
ollama serve
```

## PR Code Reviews (macOS)

The macOS app can list open GitHub PRs and generate AI-powered code reviews.

**Setup:**
1. Install GitHub CLI: `brew install gh`
2. Authenticate: `gh auth login`
3. Import a GitHub repo in the app
4. Switch to the "Pull Requests" tab

**Per-repo settings** (right-click repo > Settings):
- Choose which `gh` account to use (if you have multiple)
- Write custom review instructions per repo

## Project Structure

```
GitNarrate/
├── macos/              # SwiftUI macOS app (Swift Package Manager)
│   ├── Package.swift
│   ├── Sources/
│   │   └── GitNarrate/
│   │       ├── App/            # App entry point
│   │       ├── Models/         # SwiftData models (Repo, Commit, PRReview)
│   │       ├── Services/       # Git, GitHub, AI, Shell, Polling
│   │       ├── ViewModels/     # @Observable view models
│   │       └── Views/          # SwiftUI views
│   └── Tests/
├── web/
│   ├── client/         # React frontend (Vite + Tailwind)
│   └── server/         # Express backend (TypeScript)
├── .github/
│   └── workflows/      # CI: build, lint, audit, release, binary size
├── docs/               # Architecture documentation
├── README.md
├── CONTRIBUTING.md
└── LICENSE             # MIT
```

## CI/CD

GitHub Actions workflows:

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| **Build & Lint** | Push/PR to main | `swift build`, `swift test`, SwiftLint |
| **Dependency Audit** | Package.swift changes + weekly | osv-scanner vulnerability check |
| **Binary Size** | PRs | Comments binary size delta on PRs |
| **Release** | Tag `v*` | Builds .app bundle, creates GitHub Release |

## Documentation

See the [docs/](./docs) folder for detailed documentation:

- [Architecture](./docs/architecture-v4.md) — System design and technical details

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

## License

MIT License — see [LICENSE](./LICENSE) for details.
