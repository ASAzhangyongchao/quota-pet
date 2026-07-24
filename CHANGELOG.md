# Changelog

[简体中文](CHANGELOG.zh-CN.md)

All notable changes follow Semantic Versioning.

## [Unreleased]

## [0.1.5] - 2026-07-24

### Added

- Dedicated **Keyboard shortcuts** settings row that opens a sheet listing every assignable global hotkey with title, explanation, and per-row change/reset.
- Codex rescan now shows an explicit scan-result message when only ChatGPT’s bundled binary exists (or when a terminal install is found / nothing is found).
- Clearer settings `?` help for appearance, notifications, launch at login, and connection mode (when to pick energy saving vs real-time).

### Changed

- Settings “Codex sources” is two fixed cards (ChatGPT app vs terminal) with Use / Rescan / Choose file.
- Idle animation is **face-only**; energy-saver still allows short idle face beats.
- Codex/ChatGPT updates that only change inode or code hash no longer fail trust revalidation; provider rebuilds after trust failures or repeated App Server exits.
- Public metadata updated to version 0.1.5 build 13.
- GitHub Release ships an **ad-hoc** (non-notarized) DMG/ZIP for interim distribution until Developer ID is available.

### Fixed

- Settings update check no longer duplicates “Checking…” under the button.
- Manual refresh no longer stays stuck on “Reconnecting…” forever after a second timeout.
- When ChatGPT’s bundled Codex fails mid-update, QuotaPet fails over across other trusted binaries and temporarily demotes the broken path.
- Terminal Codex discovery merges login-shell PATH so GUI launches are less blind to Homebrew/nvm installs.

## [0.1.4] - 2026-07-21

### Added

- Manual refresh timeout notice before a single automatic reconnect.
- Scrollable, wider Settings with grouped sections; click `?` on toggles for a help popover.
- Settings shows the current version and a manual Check for Updates action against the public Releases Atom feed.
- Settings language override: System / 简体中文 / English with live UI updates.
- Menu bar Help and About actions; popover positioning that stays below the menu bar.

### Changed

- Manual refresh recovers a stopped provider instead of no-op spinning.
- Trust paths in Settings wrap and remain selectable instead of truncating to ellipsis.
- Updated the public metadata to version 0.1.4 build 12.

### Fixed

- Auto-trust official ChatGPT-bundled Codex even when the file is user-owned after app updates.
- Keep `dist/` build artifacts out of Spotlight/Launchpad so only `/Applications/QuotaPet.app` appears.
- Codex trust Settings preview shows a few prioritized rows; full list opens in a scrollable sheet.
- User guide links point at `ASAzhangyongchao/quota-pet`.
- Right-click menu language refreshes from the current Settings language before opening.
- Settings pickers no longer clip leading label characters.
- Pet visibility toggle reads legacy numeric defaults correctly; detail card language updates live while expanded.

## [0.1.3] - 2026-07-20

### Added

- Static semantic glow around the collapsed pet and expanded glass card.
- High-contrast used/remaining ring segments and matching accessible quota meters.
- Separate English and Chinese legal, brand, and contribution guidance.
- A localized About & Legal disclosure in Settings and release legal-review gates.

### Changed

- Kept the visible pet at 72 points while adding a six-point on-screen glow margin.
- Updated the public metadata to version 0.1.3 build 4.

## [0.1.2] - 2026-07-19

### Added

- English-first localization with Simplified Chinese resources and English fallback.
- Separate English and Chinese user, release, and changelog documentation.
- A canonical `VERSION` file and package checks for version/resource consistency.

### Changed

- Renamed the service limits to General usage limit and GPT-5.3-Codex-Spark usage limit.
- Anchored expanded and collapsed windows at the pet's top-left position.
- Kept dragged and resized windows completely inside the active display.

### Fixed

- Removed backend-only `primary` labels and the misleading unknown-name note.
- Localized menus, settings, notifications, accessibility text, dates, and provider errors.

## [0.1.1] - 2026-07-19

- Added local Codex usage reading, menu bar ring, vector pet, glass details, refresh feedback, trust review, performance gates, and release-preparation automation.
