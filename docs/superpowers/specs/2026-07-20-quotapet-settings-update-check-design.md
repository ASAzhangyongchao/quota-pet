# QuotaPet：设置显示版本号 + 手动检查更新

## 背景

设置「关于与法律说明」未展示当前版本；用户需要手动确认是否有新版本。仓库尚无正式 GitHub Release（公开分发仍为准备期），不能做自动下载安装。

## 目标

1. 设置里显示当前营销版本与 build：`0.1.4 (8)`。
2. 「检查更新」按钮：仅用户点击时请求 GitHub `releases/latest`，比对版本并给出可读结果。
3. 发现新版本时可打开 Release 页；不自动下载、不静默轮询、不上传本机数据。

## 行为

| 情况 | 结果 |
|---|---|
| HTTP 200 且远程版本 > 本机 | 「发现新版本 x.y.z」+「打开下载页」 |
| HTTP 200 且远程版本 ≤ 本机 | 「已是最新」 |
| HTTP 404 / 无可用 Release | 「尚未发布正式版本」 |
| 网络或其它错误 | 「检查失败」短文案，可再试 |

- API：`https://api.github.com/repos/ASAzhangyongchao/quota-pet/releases/latest`
- 解析 `tag_name`（去掉前缀 `v`）与 `html_url`
- 比较：语义化 `major.minor.patch`；非法 tag 视为检查失败
- 请求带合理 `User-Agent`（如 `QuotaPet/0.1.4`）与 `Accept: application/vnd.github+json`

## UI

- 落在「关于与法律说明」顶部：版本行 + 检查按钮 + 状态文案
- 检查中：按钮禁用，「正在检查…」
- 中英 L10n；菜单「关于」顺带显示 build

## 非目标

- Sparkle / 自动下载安装
- 启动时静默检查
- 比对 pre-release（仅用 `/releases/latest`，不含 draft/prerelease）

## 测试

- 版本比较与 JSON 解析单测（mock，不打真网）
- 打包合约：版本元数据与既有规则一致
