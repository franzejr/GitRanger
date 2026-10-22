import Foundation

struct PRListCacheKey: Codable, Hashable, Sendable {
    let repoURL: String
    let provider: String
    let filter: String
    let account: String?
    let host: String?
}

struct PRListSnapshot: Codable, Sendable {
    let pullRequests: [PullRequest]
    let fetchedAt: Date
}

/// A small stale-while-revalidate cache for pull-request lists.
///
/// The last successful result is rendered immediately on later visits and the
/// provider is still queried in the background. This keeps navigation useful
/// during network and CLI startup latency without treating cached data as fresh.
actor PRListCache {
    static let shared = PRListCache()

    private struct CacheEntry: Codable {
        let key: PRListCacheKey
        let snapshot: PRListSnapshot
    }

    private let cacheDirectory: URL
    private let maxMemoryEntries = 12
    private let maxDiskEntries = 40
    private var memory: [PRListCacheKey: PRListSnapshot] = [:]
    private var memoryOrder: [PRListCacheKey] = []

    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
    }

    func snapshot(for key: PRListCacheKey) -> PRListSnapshot? {
        if let snapshot = memory[key] {
            markAccessed(key)
            return snapshot
        }
        guard let data = try? Data(contentsOf: cacheURL(for: key)),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
              entry.key == key else {
            return nil
        }
        remember(entry.snapshot, for: key)
        return entry.snapshot
    }

    func store(_ pullRequests: [PullRequest], for key: PRListCacheKey) {
        let snapshot = PRListSnapshot(
            pullRequests: pullRequests,
            fetchedAt: Date()
        )
        remember(snapshot, for: key)

        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let entry = CacheEntry(key: key, snapshot: snapshot)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: cacheURL(for: key), options: .atomic)
            pruneDiskCache()
        } catch {
            // Cache persistence must never prevent fresh data from rendering.
        }
    }

    private func remember(
        _ snapshot: PRListSnapshot,
        for key: PRListCacheKey
    ) {
        memory[key] = snapshot
        markAccessed(key)
        while memoryOrder.count > maxMemoryEntries {
            memory.removeValue(forKey: memoryOrder.removeFirst())
        }
    }

    private func markAccessed(_ key: PRListCacheKey) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
    }

    private func cacheURL(for key: PRListCacheKey) -> URL {
        let identity = [
            key.repoURL,
            key.provider,
            key.filter,
            key.account ?? "",
            key.host ?? ""
        ].joined(separator: "|")
        return cacheDirectory
            .appendingPathComponent(Self.stableHash(identity))
            .appendingPathExtension("json")
    }

    private func pruneDiskCache() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: Array(keys)
        ), files.count > maxDiskEntries else { return }
        let sorted = files.sorted {
            let lhs = try? $0.resourceValues(forKeys: keys).contentModificationDate
            let rhs = try? $1.resourceValues(forKeys: keys).contentModificationDate
            return (lhs ?? .distantPast) < (rhs ?? .distantPast)
        }
        for file in sorted.prefix(files.count - maxDiskEntries) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("GitRanger", isDirectory: true)
            .appendingPathComponent("PullRequestLists", isDirectory: true)
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
