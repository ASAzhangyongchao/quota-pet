import XCTest
@testable import QuotaPet

@MainActor
final class InteractionViewModelTests: XCTestCase {
    func testPetAndDetailsViewModelsPublishNewSnapshotWithoutReplacement() {
        let first = makeSnapshot(used: 10)
        let second = makeSnapshot(used: 70)
        let pet = PetViewModel(snapshot: first)
        let details = UsageDetailsViewModel(snapshot: first)
        let identity = ObjectIdentifier(details)
        pet.update(second)
        details.update(second)
        XCTAssertEqual(pet.snapshot, second)
        XCTAssertEqual(pet.renderState.usedFraction, 0.7)
        XCTAssertEqual(ObjectIdentifier(details), identity)
        XCTAssertEqual(details.presentation.primaryText, "剩余 30% · 已用 70%")
        XCTAssertEqual(details.updateCount, 1)
    }
}

private func makeSnapshot(used: Double) -> QuotaSnapshot {
    QuotaSnapshot(planType: nil, windows: [QuotaWindow(id: "a", bucketID: "codex", displayName: "Codex", usedPercent: used, remainingPercent: 100-used, windowDurationMinutes: nil, resetsAt: nil, isReached: false)], updatedAt: .now, state: .ready)
}
