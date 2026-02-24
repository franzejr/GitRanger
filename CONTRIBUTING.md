# Contributing to GitNarrate

Thank you for your interest in contributing to GitNarrate! This document provides guidelines for contributing to the project.

## Code of Conduct

Please be respectful and constructive in all interactions. We're building this together.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Set up the development environment for the platform you want to work on

### macOS App Development

Requirements:
- Xcode 15+
- macOS 14 (Sonoma) or later
- Swift 5.9+

```bash
cd macos
open GitNarrate.xcodeproj
```

### Web App Development

Requirements:
- Node.js 18+
- npm or pnpm

```bash
# Backend
cd web/server
npm install
npm run dev

# Frontend (separate terminal)
cd web/client
npm install
npm run dev
```

## Development Guidelines

### Git Workflow

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```

2. Make your changes with clear, focused commits

3. Push your branch and open a Pull Request

### Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

Examples:
```
feat: add commit filtering by author
fix: resolve crash when repo has no commits
docs: update installation instructions
refactor: extract AI service into separate module
test: add tests for commit parser
```

### Code Style

**Swift (macOS):**
- Follow Apple's Swift API Design Guidelines
- Use SwiftLint for linting
- Write descriptive names, avoid abbreviations

**TypeScript (Web):**
- ESLint + Prettier for formatting
- Strict TypeScript mode
- Use interfaces for all service contracts

### Testing

- Write tests for new features
- Ensure existing tests pass before submitting PR
- Mock AI services in tests (never call real APIs)

**macOS:**
```bash
# Run tests in Xcode: Cmd+U
```

**Web:**
```bash
# Backend tests
cd web/server && npm test

# Frontend tests
cd web/client && npm test
```

## Pull Request Process

1. Update documentation if needed
2. Add tests for new functionality
3. Ensure all tests pass
4. Update CHANGELOG.md if applicable
5. Request review from maintainers

### PR Title Format

Use the same format as commit messages:
```
feat: add dark mode support
fix: handle empty commit messages
```

## Reporting Issues

When reporting bugs, please include:

1. Platform (macOS version or browser/OS for web)
2. Steps to reproduce
3. Expected behavior
4. Actual behavior
5. Screenshots if applicable

## Feature Requests

Feature requests are welcome! Please:

1. Check existing issues first
2. Describe the use case
3. Explain why this would be useful

## Questions?

Open a Discussion or Issue on GitHub.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
