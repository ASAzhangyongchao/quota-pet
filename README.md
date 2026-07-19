# QuotaPet

[简体中文](README.zh-CN.md)

QuotaPet is an unofficial, local-first macOS companion that shows Codex usage as a tiny vector desktop pet and menu bar ring. It is not affiliated with or endorsed by OpenAI.

## After installation

1. Open QuotaPet. It runs in the menu bar and does not add a Dock icon.
2. Click the pet to expand or collapse usage details. The pet remains the top-left anchor of the window.
3. Drag either view to move it. QuotaPet keeps the complete window inside the current display.
4. Click the menu bar ring for another compact usage view.
5. Press `⌥⌘U` to show the pet and restore interaction.
6. If QuotaPet asks to trust a Codex executable, review the displayed path and signature before confirming.

The two service limits are shown as **General usage limit** and **GPT-5.3-Codex-Spark usage limit**. Reset countdowns use hours below 24 hours and days at or above 24 hours.

For settings, updates, troubleshooting, and removal, read the [English user guide](docs/USER_GUIDE.md).

## Features

- Remaining and used quota, reset date, and reset countdown
- Menu bar usage ring plus a numeric desktop-pet indicator
- Glass detail card with visible refresh progress and success feedback
- Always-on-top optional pet, screen-edge containment, and multi-display support
- Energy-saving mode by default; optional real-time mode
- Local threshold notifications, launch at login, and global shortcut
- English and Simplified Chinese; unsupported system languages fall back to English

## Privacy and performance

QuotaPet has no third-party runtime dependencies. Its main process makes no outgoing network requests and does not read Codex credentials, browser data, project directories, clipboard, screen, camera, or microphone. It keeps the latest quota snapshot in memory and does not persist account details or usage history.

QuotaPet launches only a user-approved official Codex App Server child process. That child follows normal Codex authentication and connects to OpenAI. Candidate executables are inspected before execution; changed files require confirmation again. See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), and [THREAT_MODEL.md](THREAT_MODEL.md).

Energy-saving mode exits the child process after a read. The performance gate and measured baseline are documented in [docs/performance-baseline.md](docs/performance-baseline.md).

## Requirements

- macOS 13 or later
- An official Codex app bundle or an explicitly reviewed Codex CLI executable
- Swift 6 and Xcode Command Line Tools only when building from source

## Build and local install

```bash
git clone https://github.com/ASAzhangyongchao/quota-pet.git
cd quota-pet
./scripts/generate-icon.swift
swift test --disable-sandbox
./scripts/build-app.sh
./scripts/verify-package.sh
./scripts/install-local.sh
open /Applications/QuotaPet.app
```

The installer verifies the staged app, replaces only `/Applications/QuotaPet.app`, and rolls back on failure. It never invokes `sudo` or clears preferences.

## Release and Homebrew status

This repository remains **preparation-only** for public binaries until a valid Developer ID Application certificate, Apple `notarytool` credentials, a protected GitHub release environment named `release`, and clean-machine Gatekeeper verification are available. An ad-hoc local build is not a public release.

The tag-gated workflow builds Universal ZIP and DMG artifacts, notarizes and staples them, creates SHA256 checksums and an SPDX SBOM, generates a pinned Homebrew cask, and publishes GitHub attestations. Do not create a version tag merely to test the workflow. See [docs/RELEASING.md](docs/RELEASING.md) and [CHANGELOG.md](CHANGELOG.md).

## Maintenance

`VERSION` is the canonical marketing version. `Resources/Info.plist` must match it, while `CFBundleVersion` increases for every distributed build. The repository and standard Git history are the source of truth; maintenance does not depend on Codex, a plugin, a particular AI client, or a private workspace.

## License

MIT. See [LICENSE](LICENSE).
