# QuotaPet

QuotaPet is an unofficial, local-first macOS menu bar companion that shows Codex usage limits as a small vector pet. It is not affiliated with or endorsed by OpenAI.

QuotaPet 是一款非官方、本地优先的 macOS 菜单栏工具，用原创矢量桌宠展示 Codex 额度。项目与 OpenAI 无隶属或背书关系。

## Features / 功能

- Menu bar usage ring and detail popover / 菜单栏额度环与详情卡片
- Optional floating vector pet / 可选悬浮矢量桌宠
- Energy-saving by default on new installs, with an optional real-time mode / 新安装默认节能，可手动切换实时模式
- Local threshold notifications and launch at login / 本地阈值通知与登录时启动
- Explicit Codex executable trust review / Codex 可执行文件显式信任审核

## Screenshot / 截图

Screenshot coming soon. 截图将在首次公开验收后补充。

## Requirements / 系统要求

- macOS 13.0 or later
- An official Codex app bundle or an explicitly reviewed Codex CLI executable
- Swift 6 toolchain and Xcode Command Line Tools when building from source

QuotaPet has no third-party runtime dependencies. The current local package is ad-hoc signed; a public downloadable release must use Developer ID signing and Apple notarization.

## Privacy model / 隐私模型

The QuotaPet main process does not make outgoing network requests and does not read Codex credentials, browser data, project directories, the clipboard, screen, camera, or microphone. It keeps the latest usage snapshot in memory and does not save account details or usage history.

QuotaPet launches the user-approved official Codex App Server as a child process. That official child process follows normal Codex authentication, reads Codex configuration or credentials as needed, and connects to OpenAI. See [PRIVACY.md](PRIVACY.md) and [THREAT_MODEL.md](THREAT_MODEL.md).

QuotaPet 主进程不发起网络请求，也不读取 Codex 凭据；用户确认的官方 Codex App Server 子进程会按正常认证流程读取配置或凭据并连接 OpenAI。

## Build from source / 源码构建

```bash
git clone https://github.com/ASAzhangyongchao/quota-pet.git
cd quota-pet
./scripts/generate-icon.swift
./scripts/build-app.sh
./scripts/verify-package.sh
```

The build creates `dist/QuotaPet.app` and `dist/QuotaPet.zip`. Existing artifacts are replaced only after the staged app has been signed, verified, and zipped successfully.

The icon generator first uses `iconutil`. On macOS 26 systems where `iconutil` rejects an otherwise valid bitmap iconset, it writes the same locally generated PNG payloads into a validated standard ICNS container and then verifies that macOS can read and unpack it.

## Local install / 本地安装

```bash
./scripts/install-local.sh
open /Applications/QuotaPet.app
```

The installer verifies `dist/QuotaPet.app`, copies it to a same-volume staging directory, stops only the currently installed QuotaPet executable, and rolls back if replacement fails. It never clears saved preferences.

Before installing, run `swift test`, `./scripts/build-app.sh`, and `./scripts/verify-package.sh`. The installer writes `/Applications/QuotaPet.app`, so review the script and use an account that can write to `/Applications`; it never invokes `sudo` itself.

## Usage / 使用

- Click the menu bar ring to open details.
- Press `⌥⌘U` to show the pet and restore interaction if mouse passthrough was enabled.
- New installs default to energy-saving mode. Open Settings to switch to real-time manually, toggle the pet, enable local notifications, or enable launch at login. A previously saved mode is preserved.

### Trusting a Codex path / 信任 Codex 路径

QuotaPet inspects candidate paths without executing them. It resolves symbolic links, checks ownership and writable permissions, records signing identity and a file fingerprint, and shows the real path for review. Automatically trusted official app-bundle candidates must match the maintained signing allow-list. Homebrew, local `PATH`, and manually selected candidates require explicit confirmation; changed files require confirmation again.

QuotaPet does not bundle, modify, or download Codex. Only approve a path you recognize from an official Codex installation.

### Read-only Codex integration test / Codex 只读集成测试

The real Codex integration test is skipped by default. It uses the same executable resolver and revalidation gates as the app, performs one App Server handshake and one `account/rateLimits/read`, prints only sanitized window percentages/reset times, and shuts the child down. Run it explicitly on a machine with an authenticated, automatically trusted official Codex bundle:

```bash
QUOTAPET_CODEX_INTEGRATION=1 swift test --filter CodexIntegrationTests
```

It never calls `account/read` and never prints account identifiers, email, tokens, executable paths, stderr, or complete JSON responses.

### Performance gate / 性能门禁

Build the app, then run `./scripts/measure-performance.sh`; realtime is the measurement default. A formal run warms up for five minutes and samples for fifteen minutes. If realtime fails a hard gate, repeat the complete formal run with `QUOTAPET_PERF_MODE=energy-saving`. Short duration environment overrides exist only for non-formal script testing and must write to an explicit alternate `QUOTAPET_PERF_REPORT`; they cannot replace the formal baseline. The native sampler records the exact QuotaPet process and direct Codex children without recording command lines or paths.

The same-machine empty AppKit control measured 67.938 MB median RSS, so the release gates are calibrated to main RSS <= 80 MB and main-plus-direct-Codex RSS <= 160 MB. RSS remains the release gate; physical footprint is reported only as a secondary diagnostic. See the [latest performance baseline](docs/performance-baseline.md) for all metrics, thresholds, method, and limitations.

## Public release preparation / 公开发布准备

The repository is preparation-only until all release prerequisites are available. Do not treat an ad-hoc build as a public release. At the time this workflow was prepared, this machine had no usable `Developer ID Application` identity, and release publication was intentionally not attempted.

CI runs ordinary tests, an ad-hoc build, and package verification without repository secrets. It explicitly disables the real Codex integration test, so CI never performs an authenticated quota read. A `vMAJOR.MINOR.PATCH` tag is the only release trigger; the release job targets the protected GitHub `release` environment and fails closed before building if any signing or notarization prerequisite is absent.

Configure the release environment named `release` with required reviewers, restrict it to version tags, and add these secrets only there:

- `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, and `KEYCHAIN_PASSWORD` for a Developer ID Application certificate in a temporary keychain.
- `SIGNING_IDENTITY`, including the full `Developer ID Application: ...` identity.
- `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER_ID` for `notarytool`.

The release workflow builds a Universal `arm64`/`x86_64` app, enables hardened runtime and a secure timestamp, submits with `notarytool`, staples and validates both the app and DMG, and runs Gatekeeper assessment. It publishes versioned ZIP and DMG files, SHA256 checksums, an SPDX JSON SBOM, a pinned Homebrew cask, and GitHub artifact attestations. A separate clean macOS user or VM must still download the final artifacts, verify `SHA256SUMS` and the attestation, and confirm Gatekeeper launch before announcing the release.

To generate the fixed-version Homebrew cask after obtaining the final DMG checksum:

```bash
./scripts/update-cask.sh 0.1.0 <64-character-dmg-sha256> /path/to/homebrew-tap/Casks/quotapet.rb
```

The cask URL is fixed to this repository's versioned GitHub Release path and the SHA256 is always literal; it never follows a `latest` URL. Do not create or push a tag until the `release` environment, Developer ID identity, notarization API key, clean-machine verification plan, and authenticated GitHub publishing access have all been confirmed.

### Notifications and login item / 通知与开机启动

Notifications are opt-in and use the macOS local notification service. Each threshold is notified at most once per quota window. “Launch at login” uses `SMAppService.mainApp`; it adds no helper executable or privileged entitlement.

## Uninstall / 卸载

Quit QuotaPet, then remove the application:

```bash
rm -rf /Applications/QuotaPet.app
```

Saved preferences remain so reinstalling restores settings. To reset them intentionally:

```bash
defaults delete io.github.asazhangyongchao.quotapet
```

Also disable “Launch at login” before uninstalling if it was enabled.

## Known limitations / 已知限制

- macOS does not reliably show third-party menu bar UI while the screen is locked. Unlock first, then use `⌥⌘U` if the pet needs to be restored.
- Global shortcut registration can conflict with another app. QuotaPet reports the conflict and keeps the menu bar entry available.
- Usage availability depends on the installed official Codex App Server and its authenticated service connection.
- The integration test and live usage require an authenticated official Codex installation; offline, signed-out, or incompatible App Server versions report unavailable rather than falling back to credential or account reads.
- Performance counters are machine- and OS-specific. Short-lived Codex children can fall between sample boundaries, and unprivileged native counters do not provide every wakeup classification exposed by Instruments.
- Ad-hoc signatures are for local builds only. Public distribution requires Developer ID signing, hardened runtime, notarization, stapling, and clean-machine Gatekeeper verification.

## Maintenance / 维护

The public GitHub repository and standard Git history are the source of truth. Build, test, install, and security instructions are versioned here and do not depend on a specific Codex task, plugin, AI client, or private workspace. See [AGENTS.md](AGENTS.md) and [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
