import XCTest
@testable import GitRanger

/// Opt-in microbenchmarks for local work that affects interface responsiveness.
///
/// Run with `scripts/benchmark`. Keeping these benchmarks opt-in prevents
/// machine-dependent timings from making the regular test suite flaky.
final class PerformanceBenchmarkTests: XCTestCase {
    func testLargeDiffParsing() throws {
        try requirePerformanceRun()
        let lineCount = 50_000
        let diff = Self.makeDiff(lineCount: lineCount)
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let parsed = DiffParser.parse(diff)
            XCTAssertEqual(parsed.count, lineCount + 3)
        }
    }

    func testColdDiskPRListCacheRead() throws {
        try requirePerformanceRun()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitranger-list-benchmark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = PRListCacheKey(
            repoURL: "https://github.com/example/project",
            provider: "github",
            filter: "Open",
            account: nil,
            host: nil
        )
        let pullRequests = Self.makePullRequests(count: 1_000)
        let writer = PRListCache(cacheDirectory: directory)
        let writeComplete = expectation(description: "cache write")
        Task {
            await writer.store(pullRequests, for: key)
            writeComplete.fulfill()
        }
        wait(for: [writeComplete], timeout: 5)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let reader = PRListCache(cacheDirectory: directory)
            let readComplete = expectation(description: "cache read")
            Task {
                let snapshot = await reader.snapshot(for: key)
                XCTAssertEqual(snapshot?.pullRequests.count, pullRequests.count)
                readComplete.fulfill()
            }
            wait(for: [readComplete], timeout: 5)
        }
    }

    private func requirePerformanceRun() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_PERFORMANCE_TESTS"] == "1",
            "Run performance benchmarks with scripts/benchmark."
        )
    }

    private static func makeDiff(lineCount: Int) -> String {
        var lines = [
            "diff --git a/example.swift b/example.swift",
            "--- a/example.swift",
            "+++ b/example.swift"
        ]
        lines.reserveCapacity(lineCount + lines.count)

        for index in 0..<lineCount {
            switch index % 4 {
            case 0:
                lines.append("@@ -\(index + 1),1 +\(index + 1),1 @@")
            case 1:
                lines.append("-let oldValue\(index) = \(index)")
            case 2:
                lines.append("+let newValue\(index) = \(index + 1)")
            default:
                lines.append(" let retainedValue\(index) = \(index)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func makePullRequests(count: Int) -> [PullRequest] {
        (0..<count).map { index in
            PullRequest(
                number: index,
                title: "Pull request \(index)",
                authorLogin: "author-\(index % 10)",
                state: "OPEN",
                headRefName: "feature-\(index)",
                headRefOid: "head-\(index)",
                baseRefName: "main",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                additions: index,
                deletions: index / 2,
                changedFiles: index % 20,
                url: "https://github.com/example/project/pull/\(index)",
                isDraft: false,
                reviewDecision: "",
                reviewRequests: [],
                latestReviews: []
            )
        }
    }
}
