import XCTest
@testable import GitRanger

final class PRListCacheTests: XCTestCase {
    func testListPersistsAndRemainsScopedToItsFilter() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitranger-pr-list-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let openKey = PRListCacheKey(
            repoURL: "https://github.com/example/project",
            provider: "github",
            filter: "Open",
            account: "reviewer",
            host: nil
        )
        let closedKey = PRListCacheKey(
            repoURL: openKey.repoURL,
            provider: openKey.provider,
            filter: "Closed",
            account: openKey.account,
            host: nil
        )
        let pullRequest = PullRequest(
            number: 42,
            title: "Keep navigation responsive",
            authorLogin: "author",
            state: "OPEN",
            headRefName: "smooth-navigation",
            headRefOid: "abc123",
            baseRefName: "main",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            additions: 20,
            deletions: 4,
            changedFiles: 3,
            url: "https://github.com/example/project/pull/42",
            isDraft: false,
            reviewDecision: "",
            reviewRequests: ["reviewer"],
            latestReviews: []
        )

        let writer = PRListCache(cacheDirectory: directory)
        await writer.store([pullRequest], for: openKey)

        let reader = PRListCache(cacheDirectory: directory)
        let cached = await reader.snapshot(for: openKey)
        let wrongFilter = await reader.snapshot(for: closedKey)

        XCTAssertEqual(cached?.pullRequests.first?.number, pullRequest.number)
        XCTAssertEqual(cached?.pullRequests.first?.headRefOid, pullRequest.headRefOid)
        XCTAssertNil(wrongFilter)
    }
}
