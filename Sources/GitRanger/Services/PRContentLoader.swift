import Foundation

struct PRContentRequest: Codable, Hashable, Sendable {
    let repoURL: String
    let prNumber: Int
    let headSHA: String
    let githubAccount: String?
    let gitlabHost: String?
}

struct PRContent: Codable, Sendable {
    let diff: String
    let detail: PRDetail
    let fetchedAt: Date
}

struct PRContentLoadResult: Sendable {
    let content: PRContent
    let isCached: Bool
}

/// Loads immutable pull-request content once per head SHA and keeps it off the
/// main actor. Memory serves rapid navigation while the bounded disk cache
/// makes revisits fast across app launches.
actor PRContentLoader {
    static let shared = PRContentLoader()

    private struct CacheEntry: Codable {
        let request: PRContentRequest
        let content: PRContent
    }

    private let cacheDirectory: URL
    private let maxMemoryEntries = 12
    private let maxDiskEntries = 50
    private var memory: [PRContentRequest: PRContent] = [:]
    private var memoryOrder: [PRContentRequest] = []
    private var inFlight: [PRContentRequest: Task<PRContent, Error>] = [:]

    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
    }

    func load(_ request: PRContentRequest) async throws -> PRContentLoadResult {
        if let cached = cachedContent(for: request) {
            return PRContentLoadResult(content: cached, isCached: true)
        }
        if let task = inFlight[request] {
            return PRContentLoadResult(
                content: try await task.value,
                isCached: false
            )
        }

        let task = Task.detached(priority: .utility) {
            try await Self.fetchRemoteContent(for: request)
        }
        inFlight[request] = task
        do {
            let content = try await task.value
            inFlight.removeValue(forKey: request)
            store(content, for: request)
            return PRContentLoadResult(content: content, isCached: false)
        } catch {
            inFlight.removeValue(forKey: request)
            throw error
        }
    }

    func prefetch(_ requests: [PRContentRequest]) {
        let candidates = Array(requests.prefix(3))
        Task(priority: .utility) {
            for request in candidates where cachedContent(for: request) == nil {
                _ = try? await load(request)
            }
        }
    }

    func cachedContent(for request: PRContentRequest) -> PRContent? {
        if let content = memory[request] {
            markAccessed(request)
            return content
        }
        guard let data = try? Data(contentsOf: cacheURL(for: request)),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
              entry.request == request else {
            return nil
        }
        remember(entry.content, for: request)
        return entry.content
    }

    func store(_ content: PRContent, for request: PRContentRequest) {
        remember(content, for: request)
        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let entry = CacheEntry(request: request, content: content)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: cacheURL(for: request), options: .atomic)
            pruneDiskCache()
        } catch {
            // A disk cache miss must never prevent a pull request from loading.
        }
    }

    private func remember(
        _ content: PRContent,
        for request: PRContentRequest
    ) {
        memory[request] = content
        markAccessed(request)
        while memoryOrder.count > maxMemoryEntries {
            memory.removeValue(forKey: memoryOrder.removeFirst())
        }
    }

    private func markAccessed(_ request: PRContentRequest) {
        memoryOrder.removeAll { $0 == request }
        memoryOrder.append(request)
    }

    private func cacheURL(for request: PRContentRequest) -> URL {
        let identity = "\(request.repoURL)|\(request.prNumber)|\(request.headSHA)"
        return cacheDirectory
            .appendingPathComponent(Self.stableHash(identity))
            .appendingPathExtension("json")
    }

    private func pruneDiskCache() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: keys
        ), files.count > maxDiskEntries else { return }
        let sorted = files.sorted {
            let lhs = try? $0.resourceValues(forKeys: Set(keys))
                .contentModificationDate
            let rhs = try? $1.resourceValues(forKeys: Set(keys))
                .contentModificationDate
            return (lhs ?? .distantPast) < (rhs ?? .distantPast)
        }
        for file in sorted.prefix(files.count - maxDiskEntries) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func fetchRemoteContent(
        for request: PRContentRequest
    ) async throws -> PRContent {
        let detail: PRDetail
        let diff: String
        if GitLabService.shared.isGitLabRepo(url: request.repoURL) {
            async let loadedDiff = GitLabService.shared.getMRDiff(
                repoUrl: request.repoURL,
                mrNumber: request.prNumber,
                host: request.gitlabHost
            )
            async let loadedDetail = GitLabService.shared.getMRDetail(
                repoUrl: request.repoURL,
                mrNumber: request.prNumber,
                host: request.gitlabHost
            )
            (diff, detail) = try await (loadedDiff, loadedDetail)
        } else {
            async let loadedDiff = GitHubService.shared.getPRDiff(
                repoUrl: request.repoURL,
                prNumber: request.prNumber,
                account: request.githubAccount
            )
            async let loadedDetail = GitHubService.shared.getPRDetail(
                repoUrl: request.repoURL,
                prNumber: request.prNumber,
                account: request.githubAccount
            )
            (diff, detail) = try await (loadedDiff, loadedDetail)
        }
        return PRContent(diff: diff, detail: detail, fetchedAt: Date())
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("GitRanger", isDirectory: true)
            .appendingPathComponent("PullRequests", isDirectory: true)
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
