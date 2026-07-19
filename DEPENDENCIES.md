# Dependencies

QuotaPet has **No third-party runtime dependencies**.

## Runtime

| Dependency | Purpose | Source |
| --- | --- | --- |
| macOS 13.0 or later | Supported operating system | Apple |
| Swift standard library / Foundation / Combine | Process, data, concurrency, preferences, observation | Apple toolchain / macOS |
| AppKit / SwiftUI | Menu bar, popover, settings, floating vector pet | macOS system frameworks |
| Carbon | Global hotkey registration | macOS system framework |
| Security | Code-signature inspection and trust fingerprint metadata | macOS system framework |
| ServiceManagement | `SMAppService.mainApp` login item | macOS system framework |
| UserNotifications | Opt-in local notifications | macOS system framework |
| Network | Passive connectivity recovery signal | macOS system framework |
| Official Codex executable | Authenticated Codex App Server and usage source | Installed separately by the user |

QuotaPet does not bundle, download, update, or modify Codex. The official Codex child process is not a linked library; it is an external executable approved by the user and communicates over standard I/O.

## Build and packaging

- Swift Package Manager using `swift-tools-version: 6.0`
- Xcode Command Line Tools: `swift`, `strip`, `codesign`, `iconutil`, `plutil`
- macOS tools: `ditto`, `unzip`, `file`, standard shell utilities

The icon generator uses only AppKit/CoreGraphics drawing code and creates all iconset sizes locally. It uses no online assets, OpenAI marks, emoji, fonts as artwork, or third-party images.

The generator tries `iconutil` first. On macOS 26 versions where `iconutil` cannot pack a valid bitmap iconset, the script uses a minimal standard ICNS container writer for those same PNG payloads, validates every big-endian header/chunk length and dimension, and leaves the result readable by `file`, `sips`, and `iconutil` extraction.

## Dependency review

Review `Package.swift` and this file together for every release. Adding any package, SDK, helper executable, or network service requires a threat-model and privacy review before merge.
