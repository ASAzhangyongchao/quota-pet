# QuotaPet 发布指南

[English](RELEASING.md)

QuotaPet 目前只完成公开分发准备。不得发布本机临时签名构建。公开版本必须具备 Developer ID Application 身份、Apple 公证凭据、受保护的 GitHub `release` 环境，以及独立干净机器上的 Gatekeeper 验收。

## 版本规则

QuotaPet 遵循语义化版本：

- PATCH：兼容性的修复、体验、文档或翻译调整。
- MINOR：向后兼容的新功能。
- MAJOR：不兼容的行为、存储、信任或分发变化。

`VERSION` 是市场版本唯一来源，`Resources/Info.plist` 中的 `CFBundleShortVersionString` 必须一致。每次对外分发都要递增 `CFBundleVersion`，包括重新构建的发布候选版。

## 准备版本

1. 从干净并经过审核的分支开始。
2. 同步更新 `VERSION`、Info.plist 两个版本字段、`CHANGELOG.md` 和 `CHANGELOG.zh-CN.md`。
3. 执行：

   ```bash
   git diff --check
   swift test --disable-sandbox
   ./scripts/build-app.sh
   ./scripts/verify-package.sh
   ./scripts/measure-performance.sh
   ```

4. 确认构建 App 的版本正确，并包含 `en.lproj` 与 `zh-Hans.lproj`。
5. 复核隐私、安全、依赖、许可证和发布说明变化。

## 发布前提

配置名为 `release` 的受保护 GitHub 环境，只允许版本标签触发并要求审核人；仅在该环境配置：

- `BUILD_CERTIFICATE_BASE64`、`P12_PASSWORD`、`KEYCHAIN_PASSWORD`
- `SIGNING_IDENTITY`
- `APPLE_API_KEY_BASE64`、`APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID`

任何前提缺失时流程都会直接失败。流程使用加固运行时和时间戳签名，经 `notarytool` 公证，装订并校验 App 与 DMG，执行 Gatekeeper 检查，生成 SHA256、SPDX SBOM、GitHub 证明和固定版本 Homebrew Cask。

## 创建标签与发布

只有全部前提确认后才执行：

```bash
git tag -s v0.1.2 -m "QuotaPet 0.1.2"
git push origin v0.1.2
```

标签必须与 `VERSION` 和 Info.plist 完全一致。发布流程会生成版本化 ZIP、DMG、`SHA256SUMS`、SBOM 和 `quotapet.rb`。

使用普通用户在干净 macOS 账号或虚拟机下载最终产物，校验哈希与证明，确认 Gatekeeper 可启动，检查英文和简体中文，再完成一次不记录隐私输出的真实读取。全部通过后才能公告。

## Homebrew

生成的 Cask 固定到带版本号的 GitHub Release 地址和 DMG 明文 SHA256，绝不使用 `latest`。只有对应 Release 已公开并验收后才能提交到维护中的 tap。后续用户通过 `brew upgrade --cask quotapet` 更新。

## 回滚

不要改写或删除已经发布的标签。若版本存在安全问题，应在 GitHub 明确标记、从 Homebrew tap 下架，并发布更高的补丁版本修正。用户可临时重装之前已验证的版本化产物。保留校验值、发布说明和 Git 历史，保证可审计。

## 当前 0.1.2 状态

0.1.2 build 3 可以本机构建和安装。在签名、公证、受保护环境和干净机器验收条件真正具备之前，不创建标签，也不发布公开安装包。
