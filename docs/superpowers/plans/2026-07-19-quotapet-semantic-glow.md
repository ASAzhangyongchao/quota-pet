# QuotaPet 0.1.3 Semantic Glow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a static semantic halo, a clearly separated used/remaining ring, an inset glass detail card, and matching split meters without changing quota acquisition, refresh frequency, authentication, or the visible 72-point pet size.

**Architecture:** Keep `NSPanel` and screen geometry in AppKit, put the 72-point pet or 320×354 detail surface inside a shared six-point transparent glow margin, and keep quota-card composition in SwiftUI. A small pure visual-style model supplies shared semantic colors and halo state so Core Graphics, Core Animation, and SwiftUI cannot drift. All glow layers use explicit paths and update only for state, bounds, appearance, or accessibility changes.

**Tech Stack:** Swift 5, AppKit, SwiftUI, Core Graphics, Core Animation, XCTest, Swift Package Manager

---

### Task 1: Define one testable semantic visual style

**Files:**
- Create: `Sources/QuotaPet/Presentation/QuotaVisualStyle.swift`
- Create: `Tests/QuotaPetTests/QuotaVisualStyleTests.swift`
- Modify: `Sources/QuotaPet/Pet/PetDrawingScene.swift`
- Modify: `Sources/QuotaPet/MenuBar/UsageRingView.swift`

- [ ] **Step 1: Write failing tests for colors, fractions, and halo states**

Add exact tests proving that the shared palette exposes distinct warm used and mint remaining colors, clamps fractions, dims stale data, maps ready/warning/depleted/unavailable states to the required halo semantics, and reduces halo opacity in energy-saver mode:

```swift
func testReadyStyleUsesDistinctUsedAndRemainingSegments() {
    let style = QuotaVisualStyle(
        usedFraction: 0.38,
        dataState: .ready,
        remainingPercent: 62,
        connectionMode: .realtime
    )
    XCTAssertEqual(style.usedFraction, 0.38, accuracy: 0.0001)
    XCTAssertEqual(style.remainingFraction, 0.62, accuracy: 0.0001)
    XCTAssertEqual(style.usedColor, .used)
    XCTAssertEqual(style.remainingColor, .remaining)
    XCTAssertNotEqual(style.usedColor, style.remainingColor)
    XCTAssertEqual(style.haloKind, .ready)
}

func testEnergySaverReducesButDoesNotAnimateHalo() {
    let realtime = QuotaVisualStyle.fixture(connectionMode: .realtime)
    let saver = QuotaVisualStyle.fixture(connectionMode: .energySaver)
    XCTAssertLessThan(saver.haloOpacity, realtime.haloOpacity)
    XCTAssertFalse(saver.repeatsAnimation)
}
```

Use a test-only fixture extension in the test target; production code must not gain a fixture API.

- [ ] **Step 2: Run the focused test and verify red**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter QuotaVisualStyleTests
```

Expected: compilation fails because `QuotaVisualStyle`, `QuotaSemanticColor`, and `QuotaHaloKind` do not exist.

- [ ] **Step 3: Implement the smallest pure style model**

Create value types with no AppKit/SwiftUI ownership:

```swift
struct QuotaRGBA: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

enum QuotaSemanticColor: Equatable {
    case used
    case remaining
    case track

    var rgba: QuotaRGBA {
        switch self {
        case .used: QuotaRGBA(red: 0.96, green: 0.39, blue: 0.24, alpha: 1)
        case .remaining: QuotaRGBA(red: 0.15, green: 0.88, blue: 0.68, alpha: 1)
        case .track: QuotaRGBA(red: 0.10, green: 0.13, blue: 0.16, alpha: 0.46)
        }
    }
}

enum QuotaHaloKind: Equatable { case ready, warning, depleted, unavailable }

struct QuotaVisualStyle: Equatable {
    let usedFraction: Double
    let remainingFraction: Double
    let usedColor: QuotaSemanticColor
    let remainingColor: QuotaSemanticColor
    let haloKind: QuotaHaloKind
    let haloOpacity: Double
    let contentOpacity: Double
    let repeatsAnimation = false
}
```

Initialize from explicit primitive state rather than importing a controller. Clamp each fraction to `0...1`; use `.warning` at 20 percent or below, `.depleted` at 5 percent or below, `.unavailable` for missing/incompatible data, and reduce saturation/opacity for stale data. Add narrow conversion extensions from `QuotaRGBA` to `PetDrawingColor`, `Color`, and `NSColor` at the consuming files.

- [ ] **Step 4: Reuse the shared colors in both ring implementations**

Change `PetDrawingScene` from a same-color track plus used arc to a neutral backing track, warm used arc, and mint remaining arc. Preserve dashed neutral unavailable rendering and keep the operation count within the existing path budget. Change `UsageRingView` to use the same semantic constants and a slightly stronger 2.8-point stroke; do not add a menu-bar halo.

- [ ] **Step 5: Run style, ring, and render contract tests and verify green**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'QuotaVisualStyleTests|UsageRingTests|PetRenderContractTests'
```

Expected: all selected tests pass; `PetRenderContractTests` still reports at most 16 paths and no continuous timeline.

### Task 2: Add bounded collapsed and expanded glow containers

**Files:**
- Create: `Sources/QuotaPet/Pet/PetGlowContainerView.swift`
- Modify: `Sources/QuotaPet/Pet/FloatingPetController.swift`
- Modify: `Tests/QuotaPetTests/PetAppKitViewTests.swift`
- Modify: `Tests/QuotaPetTests/FloatingPanelGeometryTests.swift`

- [ ] **Step 1: Change window contract tests to the transparent-margin geometry**

Assert these exact invariants:

```swift
XCTAssertEqual(FloatingPetPanelContract.visiblePetSize, CGSize(width: 72, height: 72))
XCTAssertEqual(FloatingPetPanelContract.glowInset, 6)
XCTAssertEqual(FloatingPetPanelContract.default.size, CGSize(width: 84, height: 84))
XCTAssertEqual(FloatingPetPanelContract.expandedSize, CGSize(width: 332, height: 366))
```

Update geometry expectations so expansion and collapse preserve the full panel's top-left anchor and clamp the full 84×84 or 332×366 outer frame. Add AppKit tests proving the collapsed container embeds a 72×72 `PetAppKitView` at `(6,6)`, the expanded container embeds a 320×354 material card at `(6,6)`, and `NSPanel.hasShadow` stays false in both states.

- [ ] **Step 2: Run the focused tests and verify red**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'PetAppKitViewTests|FloatingPanelGeometryTests'
```

Expected: assertions fail on the old 72×72/320×354 panel sizes and direct content views.

- [ ] **Step 3: Implement shared six-point outer containers**

Keep the visible surfaces unchanged and move only the outer panel geometry:

```swift
struct FloatingPetPanelContract: Equatable {
    static let glowInset: CGFloat = 6
    static let visiblePetSize = CGSize(width: 72, height: 72)
    static let detailContentSize = CGSize(width: 320, height: 354)
    static let expandedSize = CGSize(width: 332, height: 366)
    let size = CGSize(width: 84, height: 84)
    // existing level/space behavior remains unchanged
}
```

Implement `PetGlowContainerView` as a transparent `NSView` whose child pet is pinned to the six-point inset. Implement `DetailGlowContainerView` as a transparent `NSView` that owns an inset `NSVisualEffectView`. Keep `.hudWindow`, `.behindWindow`, `.active`, 22-point continuous corners, and an adaptive one-point border. With Reduce Transparency enabled, replace material visibility with `NSColor.windowBackgroundColor`; with Increase Contrast, strengthen the border and track, not the glow.

- [ ] **Step 4: Give every shadow an explicit static path**

Use two sibling backing layers behind the pet/card, each with `shadowPath` equal to a circle or rounded rectangle. The ambient layer uses a dark neutral color and the accent layer uses the current `QuotaHaloKind`. Set `masksToBounds = false`; never install a `CABasicAnimation`, repeating timer, shader, or display link. Refresh halo color/opacity only from `update(style:)`, `layout()`, and accessibility/appearance notifications.

- [ ] **Step 5: Update controller installation and anchoring**

`installCollapsedView()` sets a `PetGlowContainerView` as panel content and keeps the inner pet at 72 points. Expansion uses `FloatingPetPanelContract.expandedSize`, installs `DetailGlowContainerView`, keeps `panel.hasShadow = false`, and updates the container from the latest snapshot and connection mode. Collapse reverses the content without resizing the inner pet. Existing top-left anchoring, cross-display selection, normalized-position persistence, and drag-completion clamping continue to operate on the outer frame.

- [ ] **Step 6: Run AppKit and geometry tests and verify green**

Run the command from Step 2. Expected: all selected tests pass and no test sees a pet view larger than 72×72.

### Task 3: Add adaptive split meters to detail cards

**Files:**
- Create: `Sources/QuotaPet/MenuBar/QuotaSplitMeter.swift`
- Modify: `Sources/QuotaPet/MenuBar/UsagePopoverView.swift`
- Modify: `Sources/QuotaPet/System/Localization.swift`
- Modify: `Sources/QuotaPet/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/QuotaPet/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/QuotaPetTests/UsageDetailsTests.swift`
- Modify: `Tests/QuotaPetTests/LocalizationTests.swift`

- [ ] **Step 1: Write failing presentation and localization tests**

Extend `UsageDetailsPresentation.Window` tests to assert numeric `usedFraction` and `remainingFraction`, and exact bilingual meter accessibility text:

```swift
XCTAssertEqual(window.usedFraction, 0.38, accuracy: 0.0001)
XCTAssertEqual(window.remainingFraction, 0.62, accuracy: 0.0001)
XCTAssertEqual(window.meterAccessibilityText, "Used 38%, remaining 62%")
```

Require the Chinese value `已用 38%，剩余 62%`. Add `.meterAccessibility` to the localization-key completeness test.

- [ ] **Step 2: Run focused presentation tests and verify red**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'UsageDetailsTests|LocalizationTests'
```

Expected: compilation fails because the numeric fractions and localization key do not exist.

- [ ] **Step 3: Add numeric presentation values and the SwiftUI meter**

Store clamped numeric fractions alongside the existing authoritative strings. Implement a 6-point `GeometryReader` meter with a neutral base and adjacent used/remaining rounded segments. Apply `.accessibilityElement(children: .ignore)` and the combined localized label/value. Disable implicit animation with `.transaction { $0.animation = nil }` so refreshes update atomically.

- [ ] **Step 4: Insert the meter and adapt card chrome**

Place `QuotaSplitMeter` below the title/remaining row and above summary/reset text. Retain exact quota names and all existing fields. Replace the fixed white card stroke with `Color.primary.opacity(...)`; increase it under `accessibilityDifferentiateWithoutColor`/Increase Contrast and use a solid adaptive fill under Reduce Transparency.

- [ ] **Step 5: Run focused tests and verify green**

Run the command from Step 2. Expected: both languages and all numeric fraction assertions pass.

### Task 4: Verify accessibility, performance, and real UI behavior

**Files:**
- Modify: `Tests/QuotaPetTests/PetRenderContractTests.swift`
- Modify: `Tests/QuotaPetTests/PerformanceBaselineTests.swift`
- Verify: all source and test files changed above

- [ ] **Step 1: Add release-blocking static contracts**

Assert there is no `TimelineView`, `Canvas` timeline schedule, `CABasicAnimation`, `CAKeyframeAnimation`, display link, repeating timer, shader, or third-party dependency in the new glow path. Assert every layer with nonzero shadow opacity also has a non-nil explicit `shadowPath`. Preserve the existing pet path-count and rendering-time thresholds.

- [ ] **Step 2: Run the full test suite**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox
```

Expected: zero failures.

- [ ] **Step 3: Build the real bundle and inspect UI states**

```bash
bash scripts/build-app.sh
open build/QuotaPet.app
```

Inspect collapsed and expanded states in light/dark appearances, Reduce Transparency, Increase Contrast, Reduce Motion, realtime/energy-saver modes, and at all four visible-screen edges. Expected: the visible pet remains 72 points, the avatar does not jump, the full halo stays on-screen, used/remaining colors remain distinct, and refresh feedback still restores the avatar after one second.

- [ ] **Step 4: Measure idle impact**

Run `scripts/measure-performance.sh` using the method and thresholds recorded in `docs/performance-baseline.md` against the built app. Expected: no repeating CPU wakeup, no disk-write loop, and no material regression outside the documented baseline thresholds.
