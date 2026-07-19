# QuotaPet 0.1.3 Legal and Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make QuotaPet's unofficial status, original-asset provenance, contribution rules, and release checks explicit in English and Simplified Chinese while retaining the neutral QuotaPet title and descriptive quota labels.

**Architecture:** Treat legal text as versioned repository documentation, expose only a concise localized disclosure inside Settings, and enforce the high-risk naming/document/link rules with repository contract tests. Do not add a backend, analytics, a legal-document web request, or a claim of formal trademark clearance.

**Tech Stack:** Markdown, SwiftUI, Swift localization resources, XCTest, Swift Package Manager, Bash

---

### Task 1: Add bilingual legal and contribution documents

**Files:**
- Create: `LEGAL.md`
- Create: `LEGAL.zh-CN.md`
- Create: `CONTRIBUTING.md`
- Create: `CONTRIBUTING.zh-CN.md`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/USER_GUIDE.md`
- Modify: `docs/USER_GUIDE.zh-CN.md`
- Modify: `Tests/QuotaPetTests/ReleasePreparationContractTests.swift`

- [ ] **Step 1: Write failing repository contract tests**

Add tests that require all four new files, reciprocal language links, correct-language legal links from each README and guide, and these concepts in both legal documents: unofficial/non-affiliated, third-party marks, documented Codex App Server dependency, no rate-limit circumvention, interface-change risk, user responsibility, MIT warranty limits, not legal advice, and repository-generated mascot/icon provenance.

Also assert the app title, `CFBundleName`, and `CFBundleDisplayName` do not contain any case-insensitive occurrence of `openai`, `chatgpt`, `gpt`, or `codex`:

```swift
let forbidden = ["openai", "chatgpt", "gpt", "codex"]
for value in [appProductName, bundleName, bundleDisplayName] {
    XCTAssertTrue(forbidden.allSatisfy { !value.lowercased().contains($0) })
}
```

- [ ] **Step 2: Run the focused contracts and verify red**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter ReleasePreparationContractTests
```

Expected: failures because the legal/contribution files and links do not exist.

- [ ] **Step 3: Write `LEGAL.md` and `LEGAL.zh-CN.md` as maintained peers**

Use equivalent section structure and narrowly worded claims. State that QuotaPet is an independent, unofficial open-source project and is not affiliated with, endorsed by, or sponsored by OpenAI; OpenAI, ChatGPT, GPT, Codex, and related marks belong to their respective owners. Explain that model/product names are used only to identify compatibility and usage data. Link directly to:

- `https://openai.com/brand/`
- `https://openai.com/policies/terms-of-use/`
- `https://learn.chatgpt.com/docs/app-server`

State that the app reads the documented local App Server interface, does not bypass usage limits or rate controls, and may need changes if the interface changes. Record that the QuotaPet name, Q-shaped mascot, quota-ring treatment, and generated application icon originate in this repository's drawing/build code and do not incorporate OpenAI artwork or third-party image files. Include user responsibility, MIT warranty limits, and a clear “not legal advice” paragraph. Say that preliminary public searching is not formal trademark clearance.

- [ ] **Step 4: Write contribution provenance requirements**

Require contributors to document origin and license for code, fonts, images, icons, sounds, screenshots, and dependencies; prohibit copied product art, confidential data, credentials, and assets without redistribution rights. Require dependency-license and privacy-impact review. Keep English and Chinese guides as separate maintained files with reciprocal links.

- [ ] **Step 5: Link the correct documents from user entry points**

English documents link to `LEGAL.md` and `CONTRIBUTING.md`; Chinese documents link to `LEGAL.zh-CN.md` and `CONTRIBUTING.zh-CN.md`. Preserve reciprocal language navigation and the existing installation-first structure.

- [ ] **Step 6: Run repository contracts and verify green**

Run the command from Step 2. Expected: all legal, naming, provenance, and link assertions pass.

### Task 2: Add a localized About & Legal disclosure in Settings

**Files:**
- Modify: `Sources/QuotaPet/Settings/SettingsView.swift`
- Modify: `Sources/QuotaPet/System/Localization.swift`
- Modify: `Sources/QuotaPet/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/QuotaPet/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/QuotaPetTests/LocalizationTests.swift`
- Modify: `Tests/QuotaPetTests/ReleasePreparationContractTests.swift`

- [ ] **Step 1: Add failing localized disclosure tests**

Require keys for section title, unofficial notice, and third-party-marks notice. Assert exact concise meaning in both languages:

```swift
XCTAssertEqual(
    L10n.text(.settingsUnofficialNotice, language: .english),
    "QuotaPet is an unofficial independent project and is not affiliated with or endorsed by OpenAI."
)
XCTAssertEqual(
    L10n.text(.settingsUnofficialNotice, language: .simplifiedChinese),
    "QuotaPet 是独立的非官方项目，与 OpenAI 无隶属关系，也未获其认可或赞助。"
)
```

- [ ] **Step 2: Run localization tests and verify red**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'LocalizationTests|ReleasePreparationContractTests'
```

Expected: compilation or completeness assertions fail because the keys do not exist.

- [ ] **Step 3: Add the Settings section without a remote request**

Append a localized `Section` after Codex Trust with the two short text blocks in caption/secondary styling. Keep full documents in the repository/release archive; do not add an external link opener, network request, telemetry, or account data. Increase the settings window height only enough to avoid clipping, and preserve keyboard/VoiceOver reading order.

- [ ] **Step 4: Run focused tests and verify green**

Run the command from Step 2. Expected: both language strings, key completeness, and static Settings disclosure contracts pass.

### Task 3: Harden release governance and ship version metadata

**Files:**
- Modify: `docs/RELEASING.md`
- Modify: `docs/RELEASING.zh-CN.md`
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG.zh-CN.md`
- Modify: `VERSION`
- Modify: `Resources/Info.plist`
- Modify: `Tests/QuotaPetTests/PackagingContractTests.swift`
- Modify: `Tests/QuotaPetTests/ReleasePreparationContractTests.swift`

- [ ] **Step 1: Add failing release-gate and version tests**

Require both release guides to cover: product/title conflict search, current OpenAI brand-rule review, third-party asset provenance, dependency-license scan, privacy-change review, and formal target-market trademark clearance before commercialization or App Store submission. Require `VERSION` and `CFBundleShortVersionString` to equal `0.1.3`, and `CFBundleVersion` to equal `4`.

- [ ] **Step 2: Run the focused tests and verify red**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox --filter 'PackagingContractTests|ReleasePreparationContractTests'
```

Expected: failures on the old `0.1.2`/`3` metadata and missing release-gate wording.

- [ ] **Step 3: Update release manuals and changelogs**

Add the six manual checks to both release guides with equivalent meaning. Document that public-name searching and Global Brand Database/CNIPA searching are preliminary only; formal clearance requires appropriate professional review for the intended markets. Add `0.1.3` changelog entries for semantic glow/accessibility and legal/release hardening, marked unreleased until publication.

- [ ] **Step 4: Update version sources**

Set `VERSION` and `CFBundleShortVersionString` to `0.1.3`; set `CFBundleVersion` to `4`. Do not create a tag or claim notarization until the corresponding release steps actually succeed.

- [ ] **Step 5: Run focused tests and verify green**

Run the command from Step 2. Expected: version, packaging, documents, links, and release gates all pass.

### Task 4: Package, privacy-review, install, and publish safely

**Files:**
- Verify: all source, resources, tests, documentation, and packaging files changed by both `0.1.3` plans
- Update after public-repository commit: parent repository gitlink `apps/QuotaPet`

- [ ] **Step 1: Run all tests and packaging verification**

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/quotapet-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/quotapet-swiftpm-cache \
    swift test --disable-sandbox
bash scripts/build-app.sh
bash scripts/verify-package.sh
```

Expected: zero test failures; bundle and ZIP report version `0.1.3` build `4`; localization, dependency, icon, privacy/source, and sensitive-string checks pass.

- [ ] **Step 2: Review the final diff for legal and privacy regressions**

Search the staged diff and packaged archive for credentials, account data, private absolute paths, copied binary/media assets, misleading affiliation language, remote analytics, and new runtime dependencies. Expected: none. Confirm the only product title is `QuotaPet` and all descriptive Codex/model references appear in compatibility/content context rather than branding the app itself.

- [ ] **Step 3: Install and smoke-test the verified bundle**

```bash
bash scripts/install-local.sh
open /Applications/QuotaPet.app
```

Expected: Settings shows the localized disclosure, quota acquisition and refresh behavior are unchanged, legal text causes no network activity, and the app remains a menu-bar accessory.

- [ ] **Step 4: Commit and publish without overstating release status**

Commit implementation in the public repository, push the feature branch, and open a reviewable pull request. Merge/publish only after CI passes. Create a GitHub Release, tag, notarized artifact, or Homebrew update only when those release steps are explicitly completed; otherwise leave `0.1.3` marked unreleased. Update the parent knowledge-system gitlink only after the public repository commit exists.
