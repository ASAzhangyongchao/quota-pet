# QuotaPet UX Recovery Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix stuck refresh with prompted reconnect, redesign scrollable settings with help and language, keep menu-bar popover off the menu bar, and add Help/About to the status menu—all bilingual.

**Architecture:** Drive manual-refresh UX from `UsageDetailsViewModel` (timeout → notice → one recover callback). Prefer `recover(restartIfStopped: true)` for user refresh so a stopped provider wakes up. Centralize language in `Preferences.languagePreference` and pass resolved `AppLanguage` into menus, details, and settings. Redesign settings as grouped scrollable Form in a wider window.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Combine, XCTest

**Files map:**
- `UsagePopoverView.swift` / `InteractionViewModelTests.swift` — refresh states + timeout
- `AppModel.swift` / `AppModelTests.swift` — refresh via recover
- `StatusItemController.swift` / `FloatingPetController.swift` — wire recover, popover inset, menu
- `Preferences.swift` / `Localization.swift` / `*.lproj` — language + strings
- `SettingsView.swift` — layout, scroll, help, language

---

### Task 1: Refresh timeout → notice → one recover

**Files:**
- Modify: `Sources/QuotaPet/MenuBar/UsagePopoverView.swift`
- Modify: `Tests/QuotaPetTests/InteractionViewModelTests.swift`

- [ ] Add `RefreshFeedbackState.timeoutNotice` and `.recovering`
- [ ] `beginRefresh(timeout:notice:onRecover:)` starts 20s timer; on fire → `.timeoutNotice`, wait 2.5s, call `onRecover` once, set `.recovering`
- [ ] Snapshot ready/failed clears as today; second timeout in same cycle does not call recover again
- [ ] Tests with short nanosecond delays

### Task 2: Manual refresh uses recover-if-stopped

**Files:**
- Modify: `Sources/QuotaPet/App/AppModel.swift`
- Modify: `Sources/QuotaPet/MenuBar/StatusItemController.swift`
- Modify: `Sources/QuotaPet/Pet/FloatingPetController.swift`
- Test: `Tests/QuotaPetTests/AppModelTests.swift`

- [ ] `AppModel.refresh()` calls `provider.recover(mode: connectionMode, restartIfStopped: true)`
- [ ] Wire popover/pet refresh: `beginRefresh` + timeout recover → `model.refresh()` / recover path

### Task 3: Language preference

**Files:**
- Modify: `Preferences.swift`, `Localization.swift`, both `Localizable.strings`
- Test: `PreferencesTests.swift`, `LocalizationTests.swift`

- [ ] `LanguagePreference`: `system` | `simplifiedChinese` | `english`
- [ ] `Preferences.languagePreference`; `resolvedLanguage` helper
- [ ] All new L10n keys for help, sections, menu, timeout, about, language

### Task 4: Settings redesign

**Files:**
- Modify: `SettingsView.swift`

- [ ] Window ~540×520, min width 480, ScrollView
- [ ] Sections: appearance / connection / notifications / language / trust / about
- [ ] Toggle+`?` help tooltips; trust paths multiline + textSelection

### Task 5: Status menu Help / About + popover inset

**Files:**
- Modify: `StatusItemController.swift`

- [ ] Menu: Help opens guide URL/file by language; About alert with version + notice
- [ ] Popover show with vertical clamp below menu bar

### Task 6: Wire language through UI + verify

- [ ] Rebuild menus/details/settings on language change
- [ ] `swift test --disable-sandbox` (or project equivalent)
- [ ] Bump patch notes in CHANGELOG if versioned this release

**Commits:** only if user asks.

---

### Spec coverage check
| Spec | Task |
| A timeout+notice+one recover | 1–2 |
| B settings scroll/width/groups/help/paths | 4 |
| C popover inset | 5 |
| D help/about/quit | 5 |
| E language | 3, 6 |
