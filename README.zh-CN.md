# QuotaPet

[English](README.md)

QuotaPet 是一款非官方、本地优先的 macOS Codex 用量桌宠与菜单栏工具，与 OpenAI 不存在隶属或背书关系。

## 安装完成后怎么用

1. 打开 QuotaPet。它只驻留菜单栏，不显示 Dock 图标。
2. 点击桌宠展开或收起额度详情；头像始终作为窗口左上角锚点。
3. 拖动折叠头像或详情窗口即可移动；窗口只能贴边，不能拖出当前屏幕。
4. 点击菜单栏环形图可快速查看用量。
5. 按 `⌥⌘U` 可唤起桌宠，并在鼠标穿透后恢复交互。
6. 如果要求信任 Codex 可执行文件，请先核对界面展示的真实路径和签名，再确认读取。

两类额度分别显示为 **通用使用限额** 和 **GPT-5.3-Codex-Spark 使用限额**。距重置低于 24 小时按小时显示，达到或超过 24 小时按天显示。

设置、更新、排障与卸载请阅读[中文使用指南](docs/USER_GUIDE.zh-CN.md)。

## 功能

- 展示剩余、已用、重置日期和距重置时间
- 菜单栏环形图与带数字反馈的桌宠
- 拟态玻璃详情卡片，以及刷新中、成功和失败反馈
- 可选始终置顶、屏幕边界限制和多显示器适配
- 新安装默认节能，也可切换实时模式
- 本地阈值通知、登录启动和全局快捷键
- 支持英文与简体中文；其他系统语言默认回退英文

## 隐私与性能

QuotaPet 没有第三方运行时依赖。主进程不主动联网，不读取 Codex 凭据、浏览器数据、项目目录、剪贴板、屏幕、摄像头或麦克风；最新额度只保存在内存中，不持久化账号信息和用量历史。

QuotaPet 只会启动用户确认过的官方 Codex App Server 子进程，由该子进程按 Codex 正常认证方式连接 OpenAI。可执行文件会在启动前检查，文件变化后必须重新确认。详见 [PRIVACY.md](PRIVACY.md)、[SECURITY.md](SECURITY.md) 与 [THREAT_MODEL.md](THREAT_MODEL.md)。

节能模式在读取完成后退出子进程。性能门禁和实测基线见 [docs/performance-baseline.md](docs/performance-baseline.md)。

## 系统要求

- macOS 13 或更高版本
- 官方 Codex App，或经过用户明确审核的 Codex CLI
- 仅源码构建时需要 Swift 6 和 Xcode Command Line Tools

## 源码构建与本机安装

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

安装脚本会先验证暂存 App，只替换 `/Applications/QuotaPet.app`，失败时自动回滚；不会调用 `sudo`，也不会清空用户偏好。

## GitHub Release 与 Homebrew 状态

在具备有效的 Developer ID Application 证书、Apple `notarytool` 凭据、受保护的 GitHub `release` 环境及干净机器 Gatekeeper 验收前，本仓库只完成公开发布准备。本机临时签名构建不能作为公开发布包。

版本标签触发的流程会构建通用架构 ZIP 和 DMG，完成公证与装订，生成 SHA256、SPDX SBOM、固定版本 Homebrew Cask 和 GitHub 证明。不要为了试跑流程随意创建版本标签。详见[中文发布指南](docs/RELEASING.zh-CN.md)和[中文更新记录](CHANGELOG.zh-CN.md)。

## 版本维护

`VERSION` 是市场版本号唯一来源，`Resources/Info.plist` 必须与它一致；每次对外分发还要递增 `CFBundleVersion`。GitHub 仓库和标准 Git 历史是事实来源，后续维护不依赖 Codex、某个插件、某个 AI 客户端或私有知识库。

## 许可证

MIT，见 [LICENSE](LICENSE)。
