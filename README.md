# GitNarrate

An open-source tool that narrates the full history of any git project with AI-powered summaries and real-time monitoring.

## Features

- **Import repositories** by GitHub URL or any git URL
- **AI-powered commit summaries** with impact levels (patch/minor/major/breaking)
- **Multiple AI providers**: Claude Code (recommended), Anthropic API, OpenAI, Ollama
- **Filter commits** by author and date range
- **Background monitoring** with notifications for new commits
- **Cost tracking** for AI usage

## Platforms

GitNarrate is available on two platforms:

### macOS App (Native)

A full-featured SwiftUI application with:
- 3-column NavigationSplitView layout
- SwiftData persistence
- Native notifications
- Menu bar status icon
- Auto-updates via Sparkle

**Requirements:**
- macOS 14 (Sonoma) or later
- Claude Code CLI (recommended) or API keys for other providers

### Web App (Self-hosted)

A React + Node.js application with:
- Modern React 18 frontend with Tailwind CSS
- Express + TypeScript backend
- SQLite database
- Docker support for easy deployment

**Requirements:**
- Node.js 18+
- Redis (for background job queue)
- Docker (optional, for containerized deployment)

## Quick Start

### macOS App

```bash
# Clone the repository
git clone https://github.com/yourusername/gitnarrate.git
cd gitnarrate/macos

# Open in Xcode
open GitNarrate.xcodeproj

# Build and run (Cmd+R)
```

### Web App

```bash
# Clone the repository
git clone https://github.com/yourusername/gitnarrate.git
cd gitnarrate/web

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
cd gitnarrate/web
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

Install Ollama and pull a model:

```bash
# Install Ollama
brew install ollama

# Pull a model
ollama pull llama3.2

# Start the server
ollama serve
```

## Project Structure

```
gitnarrate/
├── macos/          # SwiftUI macOS app (Xcode project)
├── web/
│   ├── client/     # React frontend (Vite + Tailwind)
│   └── server/     # Express backend (TypeScript)
├── docs/           # Documentation
├── README.md
├── CONTRIBUTING.md
└── LICENSE
```

## Documentation

See the [docs/](./docs) folder for detailed documentation:

- [Architecture](./docs/architecture-v4.md) - System design and technical details

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](./LICENSE) for details.
