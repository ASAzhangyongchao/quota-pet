import AppKit
import SwiftUI
import XCTest
@testable import QuotaPet

@MainActor
final class PetAppKitViewTests: XCTestCase {
    func testViewKeepsRenderStateAndAccessibilityInSyncWithoutSwiftUISubviews() {
        let initial = PetRenderState(snapshot: appKitSnapshot(remaining: 70))
        let updated = PetRenderState(snapshot: appKitSnapshot(remaining: 8))
        let view = PetAppKitView(renderState: initial, onClick: {}, onHover: {})

        XCTAssertEqual(view.frame.size, FloatingPetPanelContract.visiblePetSize)
        XCTAssertEqual(view.renderState, initial)
        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityRole(), .button)
        XCTAssertEqual(view.accessibilityLabel(), initial.accessibilityLabel)
        XCTAssertEqual(view.accessibilityValue() as? String, initial.accessibilityValue)
        XCTAssertTrue(view.subviews.isEmpty)

        view.update(renderState: updated)

        XCTAssertEqual(view.renderState, updated)
        XCTAssertEqual(view.accessibilityLabel(), updated.accessibilityLabel)
        XCTAssertEqual(view.accessibilityValue() as? String, updated.accessibilityValue)
    }

    func testPointerStateTreatsMovementAsWindowDragAndOnlyStationaryReleaseAsClick() {
        var pointer = PetPointerInteractionState()

        pointer.mouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertTrue(pointer.mouseUp(at: CGPoint(x: 12, y: 12), dragThreshold: 4))

        pointer.mouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(pointer.mouseUp(at: CGPoint(x: 20, y: 10), dragThreshold: 4))
    }

    func testInteractionAnimationIsOneShotCoreAnimation() {
        let view = PetAppKitView(
            renderState: PetRenderState(snapshot: appKitSnapshot(remaining: 70)),
            onClick: {},
            onHover: {}
        )

        view.play(event: .click, durationMilliseconds: 200)

        let animation = view.layer?.animation(forKey: PetAppKitView.interactionAnimationKey)
        XCTAssertNotNil(animation)
        XCTAssertEqual(animation?.duration ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(animation?.repeatCount, 0)
        XCTAssertFalse(animation?.autoreverses ?? true)
        XCTAssertFalse(view.mouseDownCanMoveWindow)
    }

    func testIdleViewDoesNotKeepACompositionLayerAfterOneShotAnimation() {
        let view = PetAppKitView(
            renderState: PetRenderState(snapshot: appKitSnapshot(remaining: 70)),
            onClick: {},
            onHover: {}
        )
        XCTAssertFalse(view.wantsLayer)

        view.play(event: .hover, durationMilliseconds: 20)
        XCTAssertTrue(view.wantsLayer)

        let released = expectation(description: "temporary animation layer released")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
            XCTAssertFalse(view.wantsLayer)
            XCTAssertNil(view.layer)
            released.fulfill()
        }
        wait(for: [released], timeout: 1)
    }

    func testControllerCreatesDetailHostingOnlyWhileExpanded() throws {
        let suite = "QuotaPetTests.PetAppKitView.Controller.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        store.removePersistentDomain(forName: suite)
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = Preferences(store: store)
        preferences.connectionMode = .energySaver
        let model = AppModel(provider: UnavailableUsageProvider(message: "offline"), store: store)
        let controller = FloatingPetController(model: model, preferences: preferences)
        let children = Dictionary(uniqueKeysWithValues: Mirror(reflecting: controller).children.compactMap { child in
            child.label.map { ($0, child.value) }
        })
        let petView = try XCTUnwrap(children["petView"] as? PetAppKitView)
        let detailHosting = try XCTUnwrap(children["detailHosting"] as? ExpandableConstruction<NSView>)
        let panel = try XCTUnwrap(children["panel"] as? NSPanel)

        XCTAssertFalse(detailHosting.isExpanded)
        let collapsedContainer = try XCTUnwrap(panel.contentView as? PetGlowContainerView)
        XCTAssertTrue(collapsedContainer.petView === petView)
        XCTAssertEqual(collapsedContainer.frame.size, FloatingPetPanelContract.default.size)
        XCTAssertEqual(petView.frame, NSRect(origin: CGPoint(x: 6, y: 6), size: FloatingPetPanelContract.visiblePetSize))
        XCTAssertTrue(collapsedContainer.shadowLayersHaveExplicitPaths)
        XCTAssertFalse(panel.hasShadow)

        XCTAssertTrue(petView.accessibilityPerformPress())
        XCTAssertTrue(detailHosting.isExpanded)
        let hostedView = try XCTUnwrap(detailHosting.expandedValue)
        let detailContainer = try XCTUnwrap(hostedView as? DetailGlowContainerView)
        XCTAssertFalse(panel.hasShadow)
        let expectedMaterial: NSVisualEffectView.Material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? .windowBackground
            : .hudWindow
        XCTAssertEqual(detailContainer.materialView.material, expectedMaterial)
        XCTAssertEqual(detailContainer.materialView.blendingMode, .behindWindow)
        XCTAssertEqual(detailContainer.materialView.state, .active)
        XCTAssertTrue(detailContainer.materialView.wantsLayer)
        XCTAssertEqual(detailContainer.materialView.layer?.cornerRadius, 22)
        XCTAssertEqual(detailContainer.materialView.layer?.borderWidth, 1)
        XCTAssertTrue(detailContainer.hostedView is NSHostingView<UsagePopoverView>)
        detailContainer.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            detailContainer.materialView.frame,
            NSRect(origin: CGPoint(x: 6, y: 6), size: FloatingPetPanelContract.detailContentSize)
        )
        XCTAssertTrue(detailContainer.shadowLayersHaveExplicitPaths)

        controller.cancelOperation(nil)
        XCTAssertFalse(detailHosting.isExpanded)
        XCTAssertNil(detailHosting.expandedValue)
        let restoredContainer = try XCTUnwrap(panel.contentView as? PetGlowContainerView)
        XCTAssertTrue(restoredContainer.petView === petView)
        XCTAssertEqual(panel.contentLayoutRect.size, FloatingPetPanelContract.default.size)
        XCTAssertEqual(petView.frame.size, FloatingPetPanelContract.visiblePetSize)
        XCTAssertFalse(panel.hasShadow)
    }

    func testInvalidatedControllerOrdersItsPanelOut() throws {
        let suite = "QuotaPetTests.PetAppKitView.Release.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        store.removePersistentDomain(forName: suite)
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = Preferences(store: store)
        let model = AppModel(provider: UnavailableUsageProvider(message: "offline"), store: store)
        let controller = FloatingPetController(model: model, preferences: preferences)
        let children = Dictionary(uniqueKeysWithValues: Mirror(reflecting: controller).children.compactMap { child in
            child.label.map { ($0, child.value) }
        })
        let panel = try XCTUnwrap(children["panel"] as? NSPanel)
        XCTAssertTrue(panel.isVisible)

        controller.invalidate()

        XCTAssertFalse(panel.isVisible)
    }
}

final class ExpandableConstructionTests: XCTestCase {
    func testExpandedContentIsLazyAndCollapseReleasesIt() {
        var creationCount = 0
        weak var released: NSObject?
        let lifecycle = ExpandableConstruction {
            creationCount += 1
            let value = NSObject()
            released = value
            return value
        }

        XCTAssertFalse(lifecycle.isExpanded)
        XCTAssertNil(released)
        XCTAssertEqual(creationCount, 0)

        var first: NSObject? = lifecycle.expand()
        XCTAssertTrue(lifecycle.isExpanded)
        XCTAssertTrue(first === lifecycle.expand())
        XCTAssertEqual(creationCount, 1)

        first = nil
        XCTAssertNotNil(released)
        lifecycle.collapse()
        XCTAssertFalse(lifecycle.isExpanded)
        XCTAssertNil(lifecycle.expandedValue)
        XCTAssertNil(released)
    }
}

private func appKitSnapshot(remaining: Double) -> QuotaSnapshot {
    QuotaSnapshot(
        planType: "Plus",
        windows: [
            QuotaWindow(
                id: "codex.primary",
                bucketID: "codex",
                displayName: "Codex",
                usedPercent: 100 - remaining,
                remainingPercent: remaining,
                windowDurationMinutes: 300,
                resetsAt: nil,
                isReached: remaining <= 0
            ),
        ],
        updatedAt: .now,
        state: .ready
    )
}
