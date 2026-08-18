# aulycZip

原生 macOS 菜单栏 ZIP 工具。纯 AppKit + SwiftPM；ZIP 核心不得依赖 `7zz` 或其他外部压缩进程。

## Build and verification

代码变更后运行：

```bash
bash scripts/compile-check.sh
```

菜单栏或打包变更还要运行：

```bash
bash scripts/bundle.sh --debug
```

本地 bundle 只能写入 `.cache/build/aulycZip.app`；未经明确授权不得安装到 `/Applications`。

## Engineering rules

- UI 只使用 AppKit 和程序化布局，不加入 SwiftUI、Storyboard 或 XIB
- 最低系统 macOS 14.0；应用产物仅支持 Apple Silicon `arm64`
- `Sources/ZipCore` 必须保持 UI 无关，不启动外部归档程序
- 创建加密 ZIP 固定为 WinZip AES-256 AE-2；读取兼容 AES-128/192/256 AE-1/AE-2
- 用户界面不提供普通 ZIP 创建；普通压缩由 macOS Finder 负责，核心只为测试夹具保留普通写入能力
- Finder 右键入口通过 `NSServices` 和 `NSApplication.servicesProvider` 实现，只接收 Finder 文件 URL
- 协议要求的 PBKDF2-HMAC-SHA1、AES-CTR 和 HMAC 必须通过系统 CommonCrypto 实现，不编写自定义弱密码学
- 加密数据必须先验证认证码，再写出明文
- 保持路径穿越、符号链接逃逸、输出大小和条目数量防护
- 不记录、保存或通过命令行传递用户密码
- `design/iconMark.svg` 是图标的唯一几何源；修改后运行 `make icons`，构建前运行 `make icon-check`

## Versioning and release profile

- Profile：`macos-arm64-app` 2.0.0
- Distribution：公共 GitHub `aulyc/aulycZip` 是唯一源码权威和 GitHub Release 仓库；Gitee `aulyc/aulycZip` 只承载正式分发，不推送源码
- Architecture：仅 `arm64`
- 权威版本源：`Config/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`
- 版本同步：`make prepare-formal-release TARGET_VERSION=... TARGET_BUILD=...`
- 版本漂移检查：`make version-check`
- Bundle ID：`com.aulyc.aulyczip`
- 初始本地版本：`0.1.0`，build `1`
- 正式发布使用稳定 SemVer、持续递增正整数 build、独立 `chore: release <version>` 提交和同版本 annotated tag
- 测试发布为 `N/A`；本地 ad-hoc bundle 和正式候选不得改名冒充 release
- 发布文档：`docs/RELEASE.md`
- 发布流程变化影响分类默认为 `project-only`；若要修改共享 Profile/Core，必须另行确认

## Release gates

- 中央严格门禁与 Developer ID 候选：`make release-check DEVELOPER_ID_APPLICATION='Developer ID Application: ...'`
- 创建或验证 annotated tag：`make release-tag`
- 精确标签隔离构建、DMG 签名、公证和 provenance：`make release-formal DEVELOPER_ID_APPLICATION='Developer ID Application: ...' NOTARY_PROFILE=...`
- 重新验证发布产物：`make verify-artifact RELEASE_PROVENANCE=/absolute/path/...release-provenance.json`
- 中央原子推送及 GitHub/Gitee 双镜像发布：`make publish-release RELEASE_PROVENANCE=/absolute/path/...release-provenance.json`
- 显式安装：`make install-release RELEASE_PROVENANCE=/absolute/path/...release-provenance.json`
- 已安装应用只读验证：`make verify-installed RELEASE_PROVENANCE=/absolute/path/...release-provenance.json`
- 正式产物必须从精确 annotated tag 的隔离干净 worktree 重建，构建前后 source 均保持 clean
- 正式 App 与 DMG 必须通过 Developer ID、timestamp、Hardened Runtime、notarization Accepted、staple、Gatekeeper 和挂载 App 验证
- `*.release-provenance.json` 必须记录 `dirty: false`，并与 Git、DMG、挂载 App、签名和远端 ref 交叉验证
- `正式发版` 和 `完整发版` 不写 `/Applications`，报告 `installationStatus: not-requested`；只有明确要求安装时才执行安装命令

## Dual-mirror release policy

- 显式策略：`aulyc-dual-mirror-v1` 1.7.0；不改变 `macos-arm64-app` Profile
- 附件/更新模式：`macos-compact` / `dual-manifest`
- 项目包装：`scripts/dual-mirror-release.sh` 只绑定 `aulyczip`；`scripts/publish-update-mirrors.sh` 组合中央 `prepare`、`preflight`、`publish`、`verify`
- 两端 Release 只发布同一份已验证 DMG；最终 provenance 位于两端不可覆盖的 `updates/<version>/...`，checksum sidecar 只保留为本地证据
- 更新器只接受 Schema v2，固定 GitHub-first/Gitee-fallback，并对 provenance、DMG 与挂载 App 使用相同完整验证链
- 仅 `publish` 阶段可写远端；单端失败必须保留 partial/failed 状态并复用同一 immutable plan，不得覆盖旧版本
- 双镜像说明：`docs/DUAL_MIRROR_RELEASE.md`

## Data and compatibility

- ZIP 的文件名未加密，所有用户说明必须保持这一事实
- 解压默认创建新的唯一目录，不能静默覆盖现有目录
- 外部兼容测试只使用固定测试密码；产品代码不得把密码传给进程
- Finder 右键输出使用新的唯一文件名，不能覆盖现有文件
- 读取和创建均支持按需 ZIP64；小归档保持普通 ZIP；不支持多卷 ZIP，也不归档符号链接
