# QuotaPet 0.1.2 public polish design

## Goal

Match the two quota cards to the names shown by the Codex usage interface:

- The `codex` bucket is displayed as `通用使用限额`.
- The second Codex bucket is displayed as `GPT-5.3-Codex-Spark 使用限额`.

## Scope

Only the presentation mapping changes. Percentages, reset dates, countdowns, refresh behavior, window layout, privacy boundaries, and provider parsing remain unchanged.

Because the second bucket now has a confirmed product-facing name, the previous `服务端未提供公开名称` note is removed.

## Anchored window interaction

The 72-point collapsed pet is the top-left anchor of the expanded detail window:

- Expansion grows from the pet toward the right and bottom.
- The expanded header pet remains at the same visual top-left anchor.
- Moving the expanded window moves the pet with it.
- Collapse shrinks back to the expanded window's current top-left corner instead of restoring an older position.

Both collapsed and expanded frames are clamped to the visible frame of the current display. A pet can touch a display edge but cannot be dragged beyond it. If an expanded window would cross the right or bottom edge, the complete window shifts left or up just enough to remain visible; the pet remains in the window's top-left corner. The same rule applies independently on each display.

This behavior is implemented as pure frame geometry plus controller-level application, without adding timers, polling, or continuous animation.

## Localization

English is the development language and universal fallback. The application follows the macOS preferred language and ships complete English and Simplified Chinese resources in `0.1.2`; unsupported languages fall back to English without mixed-language UI or missing localization keys. Additional languages require only a new localization resource, not business-logic changes.

All user-facing text is routed through one localization boundary, including the menu bar, detail card, pet accessibility text, settings, local notifications, trust recovery, and provider errors. Tests exercise both English and Simplified Chinese independently of the machine running the test.

## Documentation

Public documentation is not bilingual inside one README. Each maintained document has a clear language boundary:

- `README.md` is the English GitHub landing page and links to `README.zh-CN.md`.
- `README.zh-CN.md` is the complete Simplified Chinese landing page and links back to English.
- `docs/USER_GUIDE.md` and `docs/USER_GUIDE.zh-CN.md` prioritize what to do after installation: first launch, trust confirmation, quota meanings, pet movement, expand/collapse, refresh feedback, shortcut, settings, updates, uninstall, and troubleshooting.
- `CHANGELOG.md` and `CHANGELOG.zh-CN.md` record user-visible changes by version.
- `docs/RELEASING.md` and `docs/RELEASING.zh-CN.md` define versioning, verification, GitHub Release, Homebrew, rollback, and maintenance procedures.

Security and privacy source documents remain independently versioned and are linked prominently from both landing pages. Generated evidence such as the performance baseline is not duplicated because two drifting audit records would weaken traceability.

## Version governance

Version `0.1.2` uses Semantic Versioning. A top-level `VERSION` file is the human- and automation-readable source of the marketing version; packaging verifies that it matches `CFBundleShortVersionString`. `CFBundleVersion` advances to `3` for this build.

The changelog marks `0.1.2` as unreleased until the existing fail-closed Developer ID, notarization, checksum, attestation, and clean-machine checks pass. Updating source and installing a local ad-hoc build does not create or imply a public GitHub Release. User updates are documented for both GitHub downloads and a future pinned Homebrew cask; the app does not add a background updater or a new network client.

## Verification

- Update the presentation unit test to assert the two exact names and no legacy note.
- Add geometry tests covering top-left expansion, right/bottom edge adjustment, collapse anchoring, and drag clamping.
- Verify the controller keeps the same top-left anchor through expand, move, and collapse transitions.
- Add localization contract tests for complete English and Simplified Chinese catalogs and deterministic fallback to English.
- Verify every user-facing source string uses the localization boundary.
- Verify `VERSION`, `Info.plist`, changelogs, and release documentation agree on `0.1.2` and build `3`.
- Check English and Chinese documentation for navigation, command parity, and the post-install workflow.
- Run the full Swift test suite.
- Build and verify the application package.
- Reinstall the local application and confirm the names, anchored transition, and screen-edge behavior with real usage data.
