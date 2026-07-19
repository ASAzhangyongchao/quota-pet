import AppKit
import Combine
import QuartzCore
import SwiftUI

enum FloatingPetLevelName: Equatable { case normal, floating }
struct FloatingPetPanelContract: Equatable {
    static let glowInset: CGFloat = 6
    static let visiblePetSize = CGSize(width: 72, height: 72)
    static let detailContentSize = CGSize(width: 320, height: 354)
    static let expandedSize = CGSize(width: 332, height: 366)
    let size: CGSize = CGSize(width: 84, height: 84)
    let levelName: FloatingPetLevelName
    let joinsAllSpaces: Bool
    init(alwaysOnTop: Bool = true) { levelName = alwaysOnTop ? .floating : .normal; joinsAllSpaces = alwaysOnTop }
    static let `default` = FloatingPetPanelContract()
}

struct FloatingPetInteractionState: Equatable {
    var ignoresMouseEvents: Bool
    var visible: Bool
    mutating func recoverForMenuOrHotKey() { ignoresMouseEvents = false; visible = true }
}

struct FloatingPanelGeometry {
    static func topLeft(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX, y: frame.maxY)
    }

    static func resizedFrame(from frame: CGRect, to size: CGSize, within visibleFrame: CGRect) -> CGRect {
        let anchor = topLeft(of: frame)
        let resized = CGRect(
            x: anchor.x,
            y: anchor.y - size.height,
            width: size.width,
            height: size.height
        )
        return clamped(frame: resized, within: visibleFrame)
    }

    static func clamped(frame: CGRect, within visibleFrame: CGRect) -> CGRect {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - frame.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - frame.height)
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), maximumX),
            y: min(max(frame.minY, visibleFrame.minY), maximumY),
            width: frame.width,
            height: frame.height
        )
    }

    static func displayFrame(containing point: CGPoint, from displayFrames: [CGRect]) -> CGRect? {
        displayFrames.first { $0.contains(point) }
    }
}

enum PetDetailTapResult: Equatable { case playThenExpand, expandImmediately }
struct PetDetailInteractionState: Equatable {
    private(set) var detailVisible = false
    private(set) var pendingExpansion = false
    mutating func tap(animationEnabled: Bool) -> PetDetailTapResult {
        if detailVisible { detailVisible = false; pendingExpansion = false; return .expandImmediately }
        pendingExpansion = animationEnabled
        if !animationEnabled { detailVisible = true }
        return animationEnabled ? .playThenExpand : .expandImmediately
    }
    mutating func animationCompleted() { guard pendingExpansion else { return }; pendingExpansion = false; detailVisible = true }
    mutating func tapDetailPet() { detailVisible = false; pendingExpansion = false }
    mutating func cancelPending() { pendingExpansion = false }
}

@MainActor
final class PetInteractionVisualState: ObservableObject {
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var rotation: Angle = .zero
    @Published private(set) var isBlinking = false

    func activate(_ event: PetAnimationEvent) {
        switch event {
        case .stateChange: scale = 1.06
        case .click: scale = 1.12
        case .hover: rotation = .degrees(4)
        case .idleBlink: isBlinking = true
        }
    }

    func reset() { scale = 1; rotation = .zero; isBlinking = false }
}

@MainActor
final class PetViewModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot
    @Published private(set) var renderState: PetRenderState
    init(snapshot: QuotaSnapshot) { self.snapshot = snapshot; renderState = PetRenderState(snapshot: snapshot) }
    func update(_ snapshot: QuotaSnapshot) { self.snapshot = snapshot; renderState = PetRenderState(snapshot: snapshot) }
}

struct AnimationResetGeneration {
    private var value = 0
    mutating func begin() -> Int { value += 1; return value }
    mutating func cancel() { value += 1 }
    func accepts(_ candidate: Int) -> Bool { candidate == value }
}

@MainActor
final class FloatingPetController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let preferences: Preferences
    private let panel: NSPanel
    private let detailsViewModel: UsageDetailsViewModel
    private var latestRenderState: PetRenderState
    private var petView: PetAppKitView!
    private var collapsedContainer: PetGlowContainerView!
    private var detailHosting: ExpandableConstruction<NSView>!
    private var snapshotSubscription: AnyCancellable?
    private var preferencesSubscriptions = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var idleWorkItem: DispatchWorkItem?
    private var animationGate = PetAnimationGate()
    private var reduceMotionObserver: NSObjectProtocol?
    private var detailState = PetDetailInteractionState()
    private var pendingDetailWork: DispatchWorkItem?
    private var animationResetWork: DispatchWorkItem?
    private var animationGeneration = AnimationResetGeneration()
    private var moveClampWork: DispatchWorkItem?
    private var isCorrectingFrame = false

    init(model: AppModel, preferences: Preferences, connectionOffer: CodexConnectionOffer? = nil) {
        self.model = model
        self.preferences = preferences
        detailsViewModel = UsageDetailsViewModel(snapshot: model.snapshot)
        latestRenderState = PetRenderState(snapshot: model.snapshot)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: FloatingPetPanelContract.default.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        petView = PetAppKitView(
            renderState: latestRenderState,
            onClick: { [weak self] in self?.tapPet() },
            onHover: { [weak self] in self?.play(.hover) }
        )
        collapsedContainer = PetGlowContainerView(
            petView: petView,
            style: QuotaVisualStyle(snapshot: model.snapshot, connectionMode: preferences.connectionMode)
        )
        detailHosting = ExpandableConstruction { [weak self] in
            guard let self else { return NSView() }
            let hostingView = NSHostingView(rootView: UsagePopoverView(
                viewModel: self.detailsViewModel,
                onPetTap: { [weak self] in self?.collapseDetail() },
                connectionOffer: connectionOffer,
                onRefresh: { [weak self] in Task { await self?.model.refresh() } }
            ))
            return DetailGlowContainerView(
                hostedView: hostingView,
                style: QuotaVisualStyle(snapshot: self.model.snapshot, connectionMode: self.preferences.connectionMode)
            )
        }
        configurePanel()
        installCollapsedView()
        snapshotSubscription = model.$snapshot.sink { [weak self] snapshot in
            guard let self else { return }
            self.latestRenderState = PetRenderState(snapshot: snapshot)
            self.petView.update(renderState: self.latestRenderState)
            self.updateGlowStyle(snapshot: snapshot)
            self.detailsViewModel.update(snapshot)
            self.play(.stateChange)
            self.scheduleIdleBlink()
        }
        Publishers.CombineLatest4(preferences.$petVisible, preferences.$alwaysOnTop, preferences.$ignoresMouseEvents, preferences.$connectionMode)
            .sink { [weak self] _, _, _, _ in self?.applyPreferences() }
            .store(in: &preferencesSubscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.clampToScreen() }
        }
        reduceMotionObserver = NotificationCenter.default.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyPreferences() }
        }
        applyPreferences()
    }

    deinit {
        idleWorkItem?.cancel()
        pendingDetailWork?.cancel()
        animationResetWork?.cancel()
        moveClampWork?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let reduceMotionObserver { NotificationCenter.default.removeObserver(reduceMotionObserver) }
    }

    func showAndRecoverInteraction() {
        preferences.ignoresMouseEvents = false
        preferences.petVisible = true
        applyPreferences()
        NSApp.activate(ignoringOtherApps: true)
    }

    func invalidate() {
        panel.delegate = nil
        panel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isCorrectingFrame else { return }
        scheduleMoveCompletionClamp()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { panel.orderOut(nil); return false }
    func cancelOperation(_ sender: Any?) { collapseDetail() }

    private func configurePanel() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .floating
    }

    private func installCollapsedView() {
        // Replace the intrinsic-size SwiftUI detail first. Otherwise its constraints can
        // prevent setContentSize from shrinking the panel and stretch the pet to 320 pt.
        panel.contentView = collapsedContainer
        panel.setContentSize(FloatingPetPanelContract.default.size)
        collapsedContainer.frame = NSRect(origin: .zero, size: FloatingPetPanelContract.default.size)
        collapsedContainer.layoutSubtreeIfNeeded()
    }

    private func applyPreferences() {
        panel.level = preferences.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = preferences.alwaysOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        panel.ignoresMouseEvents = preferences.ignoresMouseEvents
        updateGlowStyle(snapshot: model.snapshot)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !preferences.petVisible || preferences.connectionMode == .energySaver {
            cancelAnimationAndIdle()
        }
        if preferences.petVisible {
            if !panel.isVisible { restorePosition() }
            panel.orderFrontRegardless()
            scheduleIdleBlink()
        } else {
            cancelAnimationAndIdle(); panel.orderOut(nil)
        }
    }

    private func tapPet() {
        pendingDetailWork?.cancel()
        if detailState.detailVisible { collapseDetail(); return }
        let animated = play(.click)
        switch detailState.tap(animationEnabled: animated) {
        case .expandImmediately: expandDetail()
        case .playThenExpand:
            let work = DispatchWorkItem { [weak self] in guard let self else { return }; self.detailState.animationCompleted(); self.expandDetail() }
            pendingDetailWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
        }
    }
    private func expandDetail() {
        guard detailState.detailVisible else { return }
        let previousFrame = panel.frame
        let visibleFrame = currentScreen(for: previousFrame)?.visibleFrame ?? previousFrame
        let hostedView = detailHosting.expand()
        hostedView.frame = NSRect(origin: .zero, size: FloatingPetPanelContract.expandedSize)
        panel.contentView = hostedView
        panel.hasShadow = false
        setPanelFrame(FloatingPanelGeometry.resizedFrame(from: previousFrame, to: FloatingPetPanelContract.expandedSize, within: visibleFrame))
    }

    private func collapseDetail() {
        pendingDetailWork?.cancel()
        let previousFrame = panel.frame
        let visibleFrame = currentScreen(for: previousFrame)?.visibleFrame ?? previousFrame
        detailState.tapDetailPet()
        installCollapsedView()
        detailHosting.collapse()
        panel.hasShadow = false
        setPanelFrame(FloatingPanelGeometry.resizedFrame(from: previousFrame, to: FloatingPetPanelContract.default.size, within: visibleFrame))
        savePosition()
    }

    private func updateGlowStyle(snapshot: QuotaSnapshot) {
        let style = QuotaVisualStyle(snapshot: snapshot, connectionMode: preferences.connectionMode)
        collapsedContainer?.update(style: style)
        (detailHosting?.expandedValue as? DetailGlowContainerView)?.update(style: style)
    }

    private func scheduleIdleBlink() {
        idleWorkItem?.cancel()
        let policy = PetAnimationPolicy(event: .idleBlink, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, petVisible: preferences.petVisible, connectionMode: preferences.connectionMode)
        guard policy.animationEnabled, let seconds = policy.nextIdleBlinkDelay(randomUnit: Double.random(in: 0...1)) else { return }
        let work = DispatchWorkItem { [weak self] in self?.play(.idleBlink); self?.scheduleIdleBlink() }
        idleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
    }

    @discardableResult private func play(_ event: PetAnimationEvent) -> Bool {
        guard let policy = animationGate.consume(event, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, petVisible: preferences.petVisible, connectionMode: preferences.connectionMode), let duration = policy.durationMilliseconds else { return false }
        if event == .idleBlink { petView.update(renderState: latestRenderState.blinking()) }
        petView.play(event: event, durationMilliseconds: duration)
        animationResetWork?.cancel()
        let generation = animationGeneration.begin()
        let reset = DispatchWorkItem { [weak self] in
            guard let self, self.animationGeneration.accepts(generation) else { return }
            self.petView.update(renderState: self.latestRenderState)
            self.animationGate.complete()
        }
        animationResetWork = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(duration), execute: reset)
        return true
    }

    private func cancelAnimationAndIdle() {
        idleWorkItem?.cancel()
        idleWorkItem = nil
        pendingDetailWork?.cancel()
        animationResetWork?.cancel()
        animationGeneration.cancel()
        detailState.cancelPending()
        animationGate.cancel()
        petView.cancelAnimation()
        petView.update(renderState: latestRenderState)
    }

    private func savePosition() {
        guard !detailState.detailVisible, let screen = panel.screen else { return }
        preferences.normalizedPosition = NormalizedScreenPosition(panelOrigin: panel.frame.origin, panelSize: panel.frame.size, visibleFrame: screen.visibleFrame, screenIdentifier: screen.localizedName)
    }

    private func restorePosition() {
        guard let position = preferences.normalizedPosition else { return }
        let screen = NSScreen.screens.first { $0.localizedName == position.screenIdentifier } ?? NSScreen.main
        guard let screen else { return }
        let origin = position.panelOrigin(panelSize: panel.frame.size, visibleFrame: screen.visibleFrame)
        setPanelFrame(FloatingPanelGeometry.clamped(frame: CGRect(origin: origin, size: panel.frame.size), within: screen.visibleFrame))
    }

    private func clampToScreen() {
        clampCurrentFrame()
        savePosition()
    }

    private func clampCurrentFrame(preferPointerDisplay: Bool = false) {
        let preferredPoint = preferPointerDisplay ? NSEvent.mouseLocation : nil
        guard let screen = currentScreen(for: panel.frame, preferredPoint: preferredPoint) else { return }
        let clamped = FloatingPanelGeometry.clamped(frame: panel.frame, within: screen.visibleFrame)
        guard clamped != panel.frame else { return }
        setPanelFrame(clamped)
    }

    private func setPanelFrame(_ frame: CGRect) {
        isCorrectingFrame = true
        panel.setFrame(frame, display: true)
        isCorrectingFrame = false
    }

    private func currentScreen(for frame: CGRect, preferredPoint: CGPoint? = nil) -> NSScreen? {
        if let preferredPoint,
           let displayFrame = FloatingPanelGeometry.displayFrame(containing: preferredPoint, from: NSScreen.screens.map(\.frame)),
           let screen = NSScreen.screens.first(where: { $0.frame == displayFrame }) {
            return screen
        }
        if let screen = panel.screen { return screen }
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        } ?? NSScreen.main
    }

    private func scheduleMoveCompletionClamp() {
        moveClampWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if NSEvent.pressedMouseButtons != 0 {
                self.scheduleMoveCompletionClamp()
                return
            }
            self.clampCurrentFrame(preferPointerDisplay: true)
            self.savePosition()
        }
        moveClampWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80), execute: work)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
