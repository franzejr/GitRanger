import Foundation

/// Finds the Claude Code CLI when Settings leaves the path blank.
/// GUI apps do not inherit a Terminal PATH, so the usual install
/// locations are checked before asking the login shell.
struct ClaudeExecutableLocator {
    enum Lookup: Equatable {
        case found(String)
        case configuredMissing(String)
        case notFound
    }

    static func candidatePaths(homeDirectory: String) -> [String] {
        [
            "\(homeDirectory)/.local/bin/claude",
            "\(homeDirectory)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
    }

    static func resolve(
        configuredPath: String,
        homeDirectory: String,
        isExecutable: (String) -> Bool,
        fallbackPath: String? = nil
    ) -> Lookup {
        let configured = configuredPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !configured.isEmpty {
            return isExecutable(configured)
                ? .found(configured)
                : .configuredMissing(configured)
        }

        if let known = candidatePaths(homeDirectory: homeDirectory)
            .first(where: isExecutable) {
            return .found(known)
        }

        if let fallbackPath {
            let fallback = fallbackPath.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if fallback.hasPrefix("/"), isExecutable(fallback) {
                return .found(fallback)
            }
        }

        return .notFound
    }

    /// Last absolute path whose final component is `claude`.
    /// Login shells can print startup text before `command -v`.
    static func executablePath(fromLoginShellOutput output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { line in
                line.hasPrefix("/")
                    && !line.contains(" ")
                    && URL(fileURLWithPath: line).lastPathComponent == "claude"
            }
    }

    static func augmentedPath(
        _ path: String,
        homeDirectory: String
    ) -> String {
        let extras = [
            "\(homeDirectory)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        let components = path.split(separator: ":").map(String.init)
        let missing = extras.filter { !components.contains($0) }
        guard !missing.isEmpty else { return path }
        return (missing + components).joined(separator: ":")
    }
}

/// Resolves Claude Code for a blank Settings path, including installs
/// that only show up in the user's login shell (nvm, mise, Volta).
struct ClaudeExecutableResolver {
    private static let fallbackPathLock = NSLock()
    private static var fallbackPath: String?

    func resolve(using shell: ShellService) async -> ClaudeExecutableLocator.Lookup {
        let configured = UserDefaults.standard.string(forKey: "claudePath") ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let isExecutable: (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        let direct = ClaudeExecutableLocator.resolve(
            configuredPath: configured,
            homeDirectory: home,
            isExecutable: isExecutable
        )
        guard case .notFound = direct else { return direct }

        let fallback = await fallbackExecutable(
            using: shell,
            isExecutable: isExecutable
        )
        return ClaudeExecutableLocator.resolve(
            configuredPath: configured,
            homeDirectory: home,
            isExecutable: isExecutable,
            fallbackPath: fallback
        )
    }

    static func environment(_ base: [String: String]) -> [String: String] {
        var env = base
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = ClaudeExecutableLocator.augmentedPath(
            env["PATH"] ?? "",
            homeDirectory: home
        )
        return env
    }

    private func fallbackExecutable(
        using shell: ShellService,
        isExecutable: (String) -> Bool
    ) async -> String? {
        if let cached = Self.cachedFallbackPath(), isExecutable(cached) {
            return cached
        }
        let discovered: String?
        if let fromShell = await pathFromLoginShell(using: shell) {
            discovered = fromShell
        } else {
            discovered = await pathFromSearchPath(using: shell)
        }
        guard let discovered, isExecutable(discovered) else { return nil }
        Self.storeFallbackPath(discovered)
        return discovered
    }

    private func pathFromLoginShell(using shell: ShellService) async -> String? {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard shellPath.hasPrefix("/") else { return nil }
        guard let result = try? await shell.runDirect(
            shellPath,
            arguments: ["-lc", "command -v claude"],
            timeout: 5
        ), result.exitCode == 0 else {
            return nil
        }
        return ClaudeExecutableLocator.executablePath(
            fromLoginShellOutput: result.stdout
        )
    }

    private func pathFromSearchPath(using shell: ShellService) async -> String? {
        guard let output = try? await shell.execute(
            "which", arguments: ["claude"], timeout: 5
        ) else { return nil }
        let resolved = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolved.hasPrefix("/") else { return nil }
        return resolved
    }

    private static func cachedFallbackPath() -> String? {
        fallbackPathLock.lock()
        defer { fallbackPathLock.unlock() }
        return fallbackPath
    }

    private static func storeFallbackPath(_ path: String) {
        fallbackPathLock.lock()
        fallbackPath = path
        fallbackPathLock.unlock()
    }
}
