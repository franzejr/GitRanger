import XCTest
@testable import GitRanger

final class GitHubPRDiffLoaderTests: XCTestCase {
    private let metadata = #"{"changed_files":326,"head":{"sha":"head"},"base":{"sha":"base"}}"#

    func testLargeDiffUsesAllPagesAndRechecksRevision() async throws {
        var calls: [[String]] = []
        let diff = try await GitHubPRDiffLoader.load(slug: "owner/repo", number: 42) { args in
            calls.append(args)
            if args[0] == "pr" { throw self.tooLarge() }
            if args[1].contains("/files?") {
                let page = Int(args[1].components(separatedBy: "page=").last!)!
                let start = (page - 1) * 100
                let files = (start..<min(start + 100, 326)).map {
                    ["filename": "test-\($0).swift", "status": "removed",
                     "additions": 0, "deletions": 1, "patch": "@@ -1 +0,0 @@\n-old"] as [String: Any]
                }
                return String(decoding: try JSONSerialization.data(withJSONObject: files), as: UTF8.self)
            }
            return self.metadata
        }
        XCTAssertEqual(calls.count, 7)
        XCTAssertTrue(calls[5][1].hasSuffix("page=4"))
        XCTAssertEqual(calls[1], calls[6])
        XCTAssertEqual(diff.components(separatedBy: "diff --git").count - 1, 326)
        XCTAssertTrue(diff.contains("test-325.swift\n--- a/test-325.swift\n+++ /dev/null"))
    }

    func testNormalDiffDoesNotCallAPI() async throws {
        var calls = 0
        let result = try await GitHubPRDiffLoader.load(slug: "owner/repo", number: 42) { _ in
            calls += 1
            return "normal diff"
        }
        XCTAssertEqual(result, "normal diff")
        XCTAssertEqual(calls, 1)
    }

    func testAuthenticationFailureDoesNotTriggerFallback() async {
        var calls = 0
        do {
            _ = try await GitHubPRDiffLoader.load(slug: "owner/repo", number: 42) { _ in
                calls += 1
                throw ShellError.nonZeroExit(code: 1, stderr: "HTTP 401")
            }
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
        }
        XCTAssertEqual(calls, 1)
    }

    func testMissingAndTruncatedPatchesFailClosed() async {
        for patch in ["null", #""@@ -1 +1 @@\n+only one addition""#] {
            do {
                _ = try await GitHubPRDiffLoader.load(slug: "owner/repo", number: 42) { args in
                    if args[0] == "pr" { throw self.tooLarge() }
                    if args[1].contains("/files?") {
                        return "[{\"filename\":\"file\",\"status\":\"added\","
                            + "\"additions\":2,\"deletions\":0,\"patch\":\(patch)}]"
                    }
                    return self.metadata.replacingOccurrences(of: "326", with: "1")
                }
                XCTFail("Incomplete patches must not become a successful review")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("Incomplete PR diff"))
                XCTAssertFalse(RoutineRunPolicy.isTransientFailure(error.localizedDescription))
            }
        }
    }

    func testChangedHeadDuringPaginationFails() async {
        var metadataReads = 0
        do {
            _ = try await GitHubPRDiffLoader.load(slug: "owner/repo", number: 42) { args in
                if args[0] == "pr" { throw self.tooLarge() }
                if args[1].contains("/files?") { return "[]" }
                metadataReads += 1
                return "{\"changed_files\":0,\"head\":{\"sha\":\"\(metadataReads)\"},"
                    + "\"base\":{\"sha\":\"base\"}}"
            }
            XCTFail("Expected revision mismatch")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("changed while downloading"))
        }
    }

    func testLargeReviewPromptDisclosesLimitedCoverage() {
        let diff = String(repeating: "+line\n", count: 6_000)
        XCTAssertNotNil(ReviewDiffScope.warning(for: diff))
        XCTAssertTrue(ReviewDiffScope.promptDiff(diff).hasPrefix("Partial review:"))
        XCTAssertNil(ReviewDiffScope.warning(for: "small diff"))
    }

    func testLiveLargePRReadOnlyWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let repository = environment["VERIFY_LARGE_PR_REPOSITORY"],
              let number = environment["VERIFY_LARGE_PR_NUMBER"].flatMap(Int.init),
              let files = environment["VERIFY_LARGE_PR_FILES"].flatMap(Int.init) else {
            throw XCTSkip("Set VERIFY_LARGE_PR_REPOSITORY, NUMBER and FILES for read-only integration validation")
        }
        let diff = try await GitHubService.shared.getPRDiff(
            repoUrl: "https://github.com/\(repository)", prNumber: number
        )
        XCTAssertEqual(diff.components(separatedBy: "diff --git").count - 1, files)
    }

    private func tooLarge() -> ShellError {
        .nonZeroExit(code: 1, stderr: "HTTP 406: diff exceeded the maximum number of files (300). too_large")
    }
}
