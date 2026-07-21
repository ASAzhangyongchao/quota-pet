import XCTest
@testable import QuotaPet

final class UpdateCheckTests: XCTestCase {
    func testAppVersionParsesTagsAndComparesSemantically() {
        XCTAssertEqual(AppVersion.parse("0.1.4"), AppVersion(major: 0, minor: 1, patch: 4))
        XCTAssertEqual(AppVersion.parse("v1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(AppVersion.parse("2.0"), AppVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(AppVersion.parse("1.0.0-beta"), AppVersion(major: 1, minor: 0, patch: 0))
        XCTAssertNil(AppVersion.parse(""))
        XCTAssertNil(AppVersion.parse("not-a-version"))
        XCTAssertLessThan(AppVersion.parse("0.1.4")!, AppVersion.parse("0.1.5")!)
        XCTAssertFalse(AppVersion.parse("0.2.0")! < AppVersion.parse("0.1.9")!)
    }

    func testEmptyAtomFeedMeansNoPublicRelease() {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Release notes from quota-pet</title>
          <updated>2026-07-21T01:10:37Z</updated>
        </feed>
        """.data(using: .utf8)!
        XCTAssertEqual(
            UpdateCheckEvaluator.outcome(currentMarketingVersion: "0.1.4", statusCode: 200, data: atom),
            .noPublicRelease
        )
    }

    func testAtomEntryReportsUpdateWhenRemoteIsNewer() {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>QuotaPet 0.2.0</title>
            <link rel="alternate" type="text/html" href="https://github.com/ASAzhangyongchao/quota-pet/releases/tag/v0.2.0"/>
          </entry>
        </feed>
        """.data(using: .utf8)!
        let outcome = UpdateCheckEvaluator.outcome(
            currentMarketingVersion: "0.1.4",
            statusCode: 200,
            data: atom
        )
        guard case let .updateAvailable(version, url) = outcome else {
            return XCTFail("expected updateAvailable, got \(outcome)")
        }
        XCTAssertEqual(version, AppVersion(major: 0, minor: 2, patch: 0))
        XCTAssertEqual(url.absoluteString, "https://github.com/ASAzhangyongchao/quota-pet/releases/tag/v0.2.0")
    }

    func testAtomEntryReportsUpToDateWhenRemoteMatches() {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>v0.1.4</title>
            <link rel="alternate" type="text/html" href="https://github.com/ASAzhangyongchao/quota-pet/releases/tag/v0.1.4"/>
          </entry>
        </feed>
        """.data(using: .utf8)!
        XCTAssertEqual(
            UpdateCheckEvaluator.outcome(currentMarketingVersion: "0.1.4", statusCode: 200, data: atom),
            .upToDate(remote: AppVersion(major: 0, minor: 1, patch: 4))
        )
    }

    func testEvaluatorReportsNoPublicReleaseOn404() {
        XCTAssertEqual(
            UpdateCheckEvaluator.outcome(currentMarketingVersion: "0.1.4", statusCode: 404, data: Data()),
            .noPublicRelease
        )
    }

    func testLegacyJSONStillWorks() {
        let json = """
        {"tag_name":"v0.2.0","html_url":"https://github.com/ASAzhangyongchao/quota-pet/releases/tag/v0.2.0"}
        """.data(using: .utf8)!
        guard case let .updateAvailable(version, _) = UpdateCheckEvaluator.outcome(
            currentMarketingVersion: "0.1.4",
            statusCode: 200,
            data: json
        ) else {
            return XCTFail("expected updateAvailable from legacy JSON")
        }
        XCTAssertEqual(version.displayString, "0.2.0")
    }

    func testEvaluatorRejectsNonHTTPSReleaseURL() {
        let json = """
        {"tag_name":"v0.2.0","html_url":"http://example.com/unsafe"}
        """.data(using: .utf8)!
        XCTAssertEqual(
            UpdateCheckEvaluator.outcome(currentMarketingVersion: "0.1.4", statusCode: 200, data: json),
            .failed
        )
    }

    func testServiceUsesLoaderAndMapsNetworkFailure() async {
        let service = UpdateCheckService(currentMarketingVersion: "0.1.4") { _ in
            throw URLError(.notConnectedToInternet)
        }
        let outcome = await service.check()
        XCTAssertEqual(outcome, .failed)
    }

    func testServiceRequestsAtomFeed() async {
        var requested: URL?
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom"></feed>
        """.data(using: .utf8)!
        let service = UpdateCheckService(currentMarketingVersion: "0.1.4") { request in
            requested = request.url
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/atom+xml"]
            )!
            return (atom, response)
        }
        let outcome = await service.check()
        XCTAssertEqual(requested, UpdateCheckService.releasesAtomURL)
        XCTAssertEqual(outcome, .noPublicRelease)
    }

    func testAppVersionInfoDisplayLabel() {
        let info = AppVersionInfo(marketing: "0.1.4", build: "10")
        XCTAssertEqual(info.displayLabel, "0.1.4 (10)")
    }
}
