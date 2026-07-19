# QuotaPet

QuotaPet is an unofficial, local-first macOS menu bar companion that shows Codex usage limits as a small vector pet. It is not affiliated with or endorsed by OpenAI.

QuotaPet 是一款非官方、本地优先的 macOS 菜单栏工具，用原创矢量桌宠展示 Codex 额度。项目与 OpenAI 无隶属或背书关系。

## Features / 功能

- Menu bar usage ring and detail popover / 菜单栏额度环与详情卡片
- Optional floating vector pet / 可选悬浮矢量桌宠
- Real-time and energy-saving refresh modes / 实时与节能刷新模式
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

## Usage / 使用

- Click the menu bar ring to open details.
- Press `⌥⌘U` to show the pet and restore interaction if mouse passthrough was enabled.
- Open Settings to choose real-time or energy-saving mode, toggle the pet, enable local notifications, or enable launch at login.

### Trusting a Codex path / 信任 Codex 路径

QuotaPet inspects candidate paths without executing them. It resolves symbolic links, checks ownership and writable permissions, records signing identity and a file fingerprint, and shows the real path for review. Automatically trusted official app-bundle candidates must match the maintained signing allow-list. Homebrew, local `PATH`, and manually selected candidates require explicit confirmation; changed files require confirmation again.

QuotaPet does not bundle, modify, or download Codex. Only approve a path you recognize from an official Codex installation.

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
- Ad-hoc signatures are for local builds only. Public distribution requires Developer ID signing, hardened runtime, notarization, stapling, and clean-machine Gatekeeper verification.

## Maintenance / 维护

The public GitHub repository and standard Git history are the source of truth. Build, test, install, and security instructions are versioned here and do not depend on a specific Codex task, plugin, AI client, or private workspace. See [AGENTS.md](AGENTS.md) and [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
