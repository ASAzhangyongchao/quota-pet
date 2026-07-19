# QuotaPet 0.1.2 Public Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the official quota names, top-left anchored and screen-bounded pet interaction, English-first localization, bilingual public documentation, and durable `0.1.2` version governance.

**Architecture:** Keep quota parsing unchanged. Add pure window-frame geometry, a typed localization boundary backed by SwiftPM resources, and a top-level version contract; controllers consume those boundaries without new polling, network access, or background services.

**Tech Stack:** Swift 5, SwiftUI, AppKit, XCTest, Swift Package Manager, Bash, GitHub Actions

---

### Task 1: Add deterministic localization and version contracts

**Files:**
- Create: `VERSION`
- Create: `Sources/QuotaPet/System/Localization.swift`
- Create: `Sources/QuotaPet/Resources/en.lproj/Localizable.strings`
- Create: `Sources/QuotaPet/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/QuotaPetTests/LocalizationTests.swift`
- Modify: `Package.swift`
- Modify: `Resources/Info.plist`
- Modify: `scripts/build-app.sh`
- Modify: `scripts/verify-package.sh`
- Modify: `Tests/QuotaPetTests/PackagingContractTests.swift`

- [ ] **Step 1: Write failing localization and version tests**

Assert that English and Simplified Chinese return non-key values for every `L10n.Key`, unsupported language resolves to English, `VERSION` equals `0.1.2`, `CFBundleShortVersionString` equals `0.1.2`, and `CFBundleVersion` equals `3`.

- [ ] **Step 2: Run focused tests and verify failure**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'LocalizationTests|PackagingContractTests.testInfoPlistDefinesMinimalMenuBarBundle'
```

Expected: compilation or assertions fail because localization resources, `VERSION`, and version `0.1.2` do not exist.

- [ ] **Step 3: Implement the localization boundary and version source**

Add `defaultLocalization: "en"` and `.process("Resources")` to `Package.swift`. Implement `AppLanguage` with English, Simplified Chinese, and English fallback, plus `L10n.text(_:language:arguments:)` using `Bundle.module`. Set `VERSION` and `CFBundleShortVersionString` to `0.1.2`, build number to `3`, and copy `QuotaPet_QuotaPet.bundle` into the packaged app.

- [ ] **Step 4: Run focused tests and verify pass**

Run the command from Step 2 and expect zero failures.

### Task 2: Localize all user-visible application text and official quota names

**Files:**
- Modify: `Sources/QuotaPet/MenuBar/UsagePopoverView.swift`
- Modify: `Sources/QuotaPet/MenuBar/UsageRingView.swift`
- Modify: `Sources/QuotaPet/MenuBar/StatusItemController.swift`
- Modify: `Sources/QuotaPet/Pet/PetMood.swift`
- Modify: `Sources/QuotaPet/Settings/SettingsView.swift`
- Modify: `Sources/QuotaPet/Settings/Preferences.swift`
- Modify: `Sources/QuotaPet/System/NotificationPolicy.swift`
- Modify: `Sources/QuotaPet/Domain/QuotaParser.swift`
- Modify: `Sources/QuotaPet/App/AppModel.swift`
- Modify: `Sources/QuotaPet/Usage/CodexAppServerStdioProvider.swift`
- Modify: presentation, ring, pet, preference, provider, and notification tests

- [ ] **Step 1: Change tests to request English and Chinese explicitly**

Assert the English quota names are `General usage limit` and `GPT-5.3-Codex-Spark usage limit`; assert the Chinese names are `通用使用限额` and `GPT-5.3-Codex-Spark 使用限额`; both second cards have no legacy note.

- [ ] **Step 2: Run the focused presentation tests and verify failure**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'UsageDetailsTests|UsageRingTests|PetRenderContractTests|GlobalHotKeyTests'
```

Expected: failures on missing language parameters and old Chinese-only strings.

- [ ] **Step 3: Replace user-facing literals with typed localization keys**

Pass `AppLanguage` into pure presentation/render models for deterministic tests; UI controllers use `.current`. Replace menu, settings, card, accessibility, notification, trust, and provider-status literals. Update the app-server client version to `0.1.2`.

- [ ] **Step 4: Run focused tests and verify pass**

Run the command from Step 2 and expect zero failures in both language paths.

### Task 3: Anchor the pet at the detail window's top-left and clamp every frame

**Files:**
- Modify: `Sources/QuotaPet/Pet/FloatingPetController.swift`
- Modify: `Tests/QuotaPetTests/PetAppKitViewTests.swift`
- Create: `Tests/QuotaPetTests/FloatingPanelGeometryTests.swift`

- [ ] **Step 1: Write failing geometry tests**

Cover these exact contracts: an unconstrained expansion preserves the collapsed frame's top-left; right/bottom overflow shifts the complete expanded frame inside `visibleFrame`; collapse preserves the expanded frame's current top-left; arbitrary dragged origins clamp both 72-point and 320×354 frames to the display edge.

- [ ] **Step 2: Run focused geometry tests and verify failure**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'FloatingPanelGeometryTests|PetAppKitViewTests'
```

Expected: compilation or assertions fail because frame geometry and anchored transitions are absent.

- [ ] **Step 3: Implement pure geometry and controller transitions**

Add `FloatingPanelGeometry.frame(topLeft:size:visibleFrame:)` and `clamped(frame:visibleFrame:)`. Expand from the collapsed top-left, collapse from the detail frame's current top-left, clamp `windowDidMove`, and save the final collapsed normalized position. Keep the existing 72-point and 320×354 sizes.

- [ ] **Step 4: Run focused tests and verify pass**

Run the command from Step 2 and expect zero failures.

### Task 4: Replace mixed documentation with mirrored English and Chinese sets

**Files:**
- Replace: `README.md`
- Create: `README.zh-CN.md`
- Create: `docs/USER_GUIDE.md`
- Create: `docs/USER_GUIDE.zh-CN.md`
- Create: `CHANGELOG.md`
- Create: `CHANGELOG.zh-CN.md`
- Create: `docs/RELEASING.md`
- Create: `docs/RELEASING.zh-CN.md`
- Modify: `Tests/QuotaPetTests/ReleasePreparationContractTests.swift`

- [ ] **Step 1: Add failing documentation parity tests**

Require both language landing pages, guides, changelogs, and release manuals; require reciprocal language links, `0.1.2`, post-install first steps, update/uninstall instructions, SemVer, GitHub Release, Homebrew, rollback, signing, notarization, checksums, and attestation.

- [ ] **Step 2: Run documentation contract tests and verify failure**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter ReleasePreparationContractTests
```

Expected: failures because the mirrored documents do not exist and `README.md` is mixed-language.

- [ ] **Step 3: Write the independent documentation sets**

Make English the default GitHub landing page. Put installation and first-use commands before contributor build details. Keep commands and security claims equivalent across language pairs. Mark `0.1.2` unreleased and do not create a tag.

- [ ] **Step 4: Run documentation contract tests and verify pass**

Run the command from Step 2 and expect zero failures.

### Task 5: Full verification, local install, and publication

**Files:**
- Verify all changed source, resource, test, documentation, and packaging files
- Update the parent knowledge-system repository's `apps/QuotaPet` gitlink

- [ ] **Step 1: Run all tests and real read-only Codex integration**

Run `swift test --disable-sandbox`, then run the opt-in `CodexIntegrationTests.testTrustedOfficialCodexHandshakeAndRateLimitsRead` outside the workspace sandbox. Expect all ordinary tests and the real integration to pass.

- [ ] **Step 2: Build and verify the package**

Run `./scripts/build-app.sh` and `./scripts/verify-package.sh`. Expect a signed local `QuotaPet.app`, valid ZIP, copied localization bundle, matching version, and no sensitive strings.

- [ ] **Step 3: Install and perform visual interaction acceptance**

Run `./scripts/install-local.sh`, launch `/Applications/QuotaPet.app`, confirm real usage names, English/Chinese fallback rules, top-left anchoring, edge clamping, expand/move/collapse position, and 72×72 collapsed size.

- [ ] **Step 4: Commit and push**

Commit the public repository without a release tag, push `main`, confirm GitHub CI, update the knowledge-system submodule to `origin/main`, commit its gitlink, push its `main`, and verify both worktrees are clean.
