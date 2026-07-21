# Settings Update Check Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show app version in Settings and let users manually check GitHub Releases for a newer marketing version.

**Architecture:** Pure `AppVersion` / `UpdateCheckService` for parse + compare; Settings UI observes check state; open `html_url` in browser when newer.

**Tech Stack:** SwiftUI, URLSession, GitHub REST API, XCTest

---

### Task 1: Version model + update check service

**Files:**
- Create: `Sources/QuotaPet/System/AppVersion.swift`
- Create: `Sources/QuotaPet/System/UpdateCheckService.swift`
- Create: `Tests/QuotaPetTests/UpdateCheckTests.swift`

- [ ] SemVer parse/compare from marketing string / `v`-prefixed tag
- [ ] Decode latest release JSON (`tag_name`, `html_url`)
- [ ] Map HTTP status to outcomes: upToDate / updateAvailable / noRelease / failed
- [ ] Unit tests with fixture JSON (no live network)

### Task 2: Settings UI + L10n + About build

**Files:**
- Modify: `Sources/QuotaPet/Settings/SettingsView.swift`
- Modify: `Sources/QuotaPet/MenuBar/StatusItemController.swift`
- Modify: `Sources/QuotaPet/System/Localization.swift`
- Modify: `Sources/QuotaPet/Resources/{en,zh-Hans}.lproj/Localizable.strings`
- Modify: `CHANGELOG.md`, `CHANGELOG.zh-CN.md`, `Resources/Info.plist` (build bump)

- [ ] About section: version label, check button, status, open-download when available
- [ ] About menu shows `version (build)`
- [ ] Bilingual strings

### Task 3: Verify + install

- [ ] `swift test`
- [ ] `./scripts/build-app.sh && ./scripts/verify-package.sh && ./scripts/install-local.sh`
