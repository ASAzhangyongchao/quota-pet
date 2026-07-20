import Combine
import XCTest
@testable import QuotaPet

@MainActor
final class InteractionViewModelTests: XCTestCase {
    func testPetAndDetailsViewModelsPublishNewSnapshotWithoutReplacement() {
        let first = makeSnapshot(used: 10)
        let second = makeSnapshot(used: 70)
        let pet = PetViewModel(snapshot: first)
        let details = UsageDetailsViewModel(snapshot: first, language: .simplifiedChinese)
        let identity = ObjectIdentifier(details)
        pet.update(second)
        details.update(second)
        XCTAssertEqual(pet.snapshot, second)
        XCTAssertEqual(pet.renderState.usedFraction, 0.7)
        XCTAssertEqual(ObjectIdentifier(details), identity)
        XCTAssertEqual(details.presentation.primaryText, "剩余 30% · 已用 70%")
        XCTAssertEqual(details.updateCount, 1)
    }

    func testRefreshFeedbackOnlyReportsSuccessAfterAReadySnapshotArrives() {
        let details = UsageDetailsViewModel(snapshot: makeSnapshot(used: 10))

        details.beginRefresh()
        XCTAssertEqual(details.refreshFeedback, .refreshing)

        details.update(QuotaSnapshot(
            planType: nil,
            windows: [],
            updatedAt: .now,
            state: .loading
        ))
        XCTAssertEqual(details.refreshFeedback, .refreshing)

        details.update(makeSnapshot(used: 20))
        XCTAssertEqual(details.refreshFeedback, .succeeded)
    }

    func testRefreshFeedbackReportsFailureForUnavailableSnapshot() {
        let details = UsageDetailsViewModel(snapshot: makeSnapshot(used: 10))

        details.beginRefresh()
        details.update(QuotaSnapshot(
            planType: nil,
            windows: [],
            updatedAt: .now,
            state: .unavailable("连接失败")
        ))

        XCTAssertEqual(details.refreshFeedback, .failed)
    }

    func testSuccessfulRefreshReturnsToPetAfterFeedbackDelay() async throws {
        let details = UsageDetailsViewModel(
            snapshot: makeSnapshot(used: 10),
            successFeedbackDurationNanoseconds: 10_000_000
        )
        let restored = expectation(description: "refresh feedback returned to idle")
        var subscriptions = Set<AnyCancellable>()
        details.$refreshFeedback
            .dropFirst()
            .sink { feedback in
                if feedback == .idle { restored.fulfill() }
            }
            .store(in: &subscriptions)

        details.beginRefresh()
        details.update(makeSnapshot(used: 20))
        XCTAssertEqual(details.refreshFeedback, .succeeded)

        await fulfillment(of: [restored], timeout: 1)
        XCTAssertEqual(details.refreshFeedback, .idle)
    }

    func testRefreshTimeoutShowsNoticeThenRecoversOnce() async throws {
        var recoverCount = 0
        var recoverCountAtNotice = -1
        let details = UsageDetailsViewModel(
            snapshot: makeSnapshot(used: 10),
            refreshTimeoutNanoseconds: 50_000_000,
            recoverNoticeNanoseconds: 50_000_000
        )
        let noticeSeen = expectation(description: "timeout notice")
        let recoveringSeen = expectation(description: "recovering")
        var subscriptions = Set<AnyCancellable>()
        details.$refreshFeedback
            .dropFirst()
            .sink { feedback in
                if feedback == .timeoutNotice {
                    recoverCountAtNotice = recoverCount
                    noticeSeen.fulfill()
                }
                if feedback == .recovering {
                    recoveringSeen.fulfill()
                }
            }
            .store(in: &subscriptions)

        details.beginRefresh {
            recoverCount += 1
        }
        XCTAssertEqual(details.refreshFeedback, .refreshing)

        await fulfillment(of: [noticeSeen], timeout: 2)
        XCTAssertEqual(recoverCountAtNotice, 0)

        await fulfillment(of: [recoveringSeen], timeout: 2)
        XCTAssertEqual(recoverCount, 1)

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recoverCount, 1)
    }

    func testRefreshTimeoutDoesNotRecoverAfterSuccessfulSnapshot() async throws {
        var recoverCount = 0
        let details = UsageDetailsViewModel(
            snapshot: makeSnapshot(used: 10),
            refreshTimeoutNanoseconds: 50_000_000,
            recoverNoticeNanoseconds: 20_000_000
        )

        details.beginRefresh { recoverCount += 1 }
        details.update(makeSnapshot(used: 20))
        XCTAssertEqual(details.refreshFeedback, .succeeded)

        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(recoverCount, 0)
    }
}

private func makeSnapshot(used: Double) -> QuotaSnapshot {
    QuotaSnapshot(planType: nil, windows: [QuotaWindow(id: "a", bucketID: "codex", displayName: "Codex", usedPercent: used, remainingPercent: 100-used, windowDurationMinutes: nil, resetsAt: nil, isReached: false)], updatedAt: .now, state: .ready)
}
