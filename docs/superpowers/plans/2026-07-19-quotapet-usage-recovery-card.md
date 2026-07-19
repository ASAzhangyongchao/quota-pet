# QuotaPet Usage Recovery Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore safe Codex usage reads from the failure card, show unambiguous reset/update times, and give the expanded desktop card an opaque visual surface.

**Architecture:** Resolve executable candidates once in `AppComposition`, expose only the first confirmation-required candidate, and route an explicit confirmation callback through the existing controllers. Keep presentation formatting pure and make the floating-card appearance an AppKit layer contract that can be tested without screenshot matching.

**Tech Stack:** Swift 6 package, AppKit, SwiftUI, Combine, XCTest, Codex App Server stdio.

---

### Task 1: Expose a safe pending Codex candidate

**Files:**
- Modify: `Sources/QuotaPet/App/AppModel.swift`
- Modify: `Tests/QuotaPetTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing composition test**

```swift
func testCompositionExposesRequiresConfirmationCandidate() {
    let candidate = compositionCandidate()
    let composition = AppComposition(
        resolver: CompositionResolver(resolution: .accepted(candidate, trust: .requiresConfirmation)),
        sessionFactory: CompositionSessionFactory(),
        store: makeStore()
    )
    XCTAssertEqual(composition.pendingConfirmationCandidate, candidate)
    XCTAssertTrue(composition.provider is UnavailableUsageProvider)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --disable-sandbox --filter AppModelTests.testCompositionExposesRequiresConfirmationCandidate`

Expected: compile failure because `pendingConfirmationCandidate` does not exist.

- [ ] **Step 3: Resolve once and expose the pending candidate**

```swift
let resolutions: [ExecutableResolution]
let pendingConfirmationCandidate: ExecutableCandidate?

let resolutions = resolver.resolve(userSelectedURL: nil, path: ProcessInfo.processInfo.environment["PATH"])
self.resolutions = resolutions
pendingConfirmationCandidate = resolutions.first { $0.requiresConfirmation }?.candidate
```

- [ ] **Step 4: Verify GREEN**

Run: `swift test --disable-sandbox --filter AppModelTests`

Expected: all `AppModelTests` pass.

### Task 2: Connect directly from both usage cards

**Files:**
- Modify: `Sources/QuotaPet/App/AppDelegate.swift`
- Modify: `Sources/QuotaPet/MenuBar/StatusItemController.swift`
- Modify: `Sources/QuotaPet/Pet/FloatingPetController.swift`
- Modify: `Sources/QuotaPet/MenuBar/UsagePopoverView.swift`
- Modify: `Tests/QuotaPetTests/UsageDetailsTests.swift`
- Modify: `Tests/QuotaPetTests/PetAppKitViewTests.swift`

- [ ] **Step 1: Write failing action-visibility and callback tests**

```swift
XCTAssertEqual(
    UsageDetailsPresentation(snapshot: unavailableSnapshot).connectionActionTitle,
    "确认并读取用量"
)
```

The controller test expands the detail view with a non-nil callback and verifies the hosted hierarchy contains the connection action accessibility label.

- [ ] **Step 2: Verify RED**

Run: `swift test --disable-sandbox --filter 'UsageDetailsTests|PetAppKitViewTests'`

Expected: failure because the presentation action and callback do not exist.

- [ ] **Step 3: Add the explicit confirmation path**

```swift
Button("确认并读取用量", action: onConnectCodex)
    .accessibilityLabel("确认并读取本机 Codex 用量")
```

`AppDelegate` passes a closure only when `pendingConfirmationCandidate` exists. The closure calls `resolver.confirm(candidate)`, persists `TrustFingerprint(candidate:)`, and invokes the existing `restartProvider(resolver:)` path. After restart, the replacement composition has no pending candidate and the button disappears.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --disable-sandbox --filter 'UsageDetailsTests|PetAppKitViewTests|AppModelTests'`

Expected: all selected tests pass.

### Task 3: Correct time semantics and add an opaque floating card

**Files:**
- Modify: `Sources/QuotaPet/MenuBar/UsagePopoverView.swift`
- Modify: `Sources/QuotaPet/Pet/FloatingPetController.swift`
- Modify: `Tests/QuotaPetTests/UsageDetailsTests.swift`
- Modify: `Tests/QuotaPetTests/PetAppKitViewTests.swift`

- [ ] **Step 1: Write failing presentation tests**

```swift
XCTAssertNil(UsageDetailsPresentation(snapshot: unavailableSnapshot).updatedText)
XCTAssertEqual(ready.updatedText, "数据更新：2026/7/19 20:00 GMT+8")
XCTAssertEqual(ready.windows.first?.resetText, "重置时间：2026/7/20 09:00 GMT+8")
```

Add a controller assertion that the expanded hosting view has an alpha-1 background layer, `cornerRadius == 16`, a border, and `panel.hasShadow == true`; collapse restores `panel.hasShadow == false`.

- [ ] **Step 2: Verify RED**

Run: `swift test --disable-sandbox --filter 'UsageDetailsTests|PetAppKitViewTests'`

Expected: failures on old wording, non-optional update text, and missing card layer.

- [ ] **Step 3: Implement the minimal presentation and layer changes**

```swift
updatedText = snapshot.windows.isEmpty ? nil : "数据更新：\(formatter.string(from: snapshot.updatedAt))"
resetText = window.resetsAt.map { "重置时间：\(formatter.string(from: $0))" } ?? "重置时间：未提供"
```

```swift
hostedView.wantsLayer = true
hostedView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
hostedView.layer?.cornerRadius = 16
hostedView.layer?.borderWidth = 1
hostedView.layer?.borderColor = NSColor.separatorColor.cgColor
panel.hasShadow = true
```

- [ ] **Step 4: Verify GREEN**

Run: `swift test --disable-sandbox --filter 'UsageDetailsTests|PetAppKitViewTests'`

Expected: all selected tests pass.

### Task 4: Version, full verification, publish, and reinstall

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `README.md`
- Verify: all repository files and `/Applications/QuotaPet.app`

- [ ] **Step 1: Set patch version**

Set `CFBundleShortVersionString` to `0.1.1` and document the direct recovery action and time labels.

- [ ] **Step 2: Run full verification**

Run:

```bash
QUOTAPET_CODEX_INTEGRATION=0 swift test --disable-sandbox
./scripts/build-app.sh
./scripts/verify-package.sh
QUOTAPET_CODEX_INTEGRATION=1 swift test --disable-sandbox --filter CodexIntegrationTests.testTrustedOfficialCodexHandshakeAndRateLimitsRead
git diff --check
```

Expected: 0 failures; the live integration emits only sanitized used/remaining/reset values.

- [ ] **Step 3: Commit and push**

```bash
git add Sources Tests Resources README.md docs
git commit -m "fix: recover Codex usage from detail card"
git push origin main
```

- [ ] **Step 4: Reinstall and inspect**

```bash
./scripts/install-local.sh
open /Applications/QuotaPet.app
```

Expected: version `0.1.1`; the failure card offers confirmation, successful connection shows remaining and reset time, the expanded card is opaque, and the collapsed pet remains transparent.
