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
- 权威版本源：`Config/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`
- Bundle ID：`com.aulyc.aulyczip`
- 初始本地版本：`0.1.0`，build `1`
- 当前仓库尚未登记到中央项目注册表，也没有正式签名、公证、发布与安装流水线；任何真实测试版或正式版发布必须先完成登记和发布门禁，不得把本地 ad-hoc bundle 当成 release
- 发布流程变化影响分类默认为 `project-only`；若要修改共享 Profile/Core，必须另行确认

## Data and compatibility

- ZIP 的文件名未加密，所有用户说明必须保持这一事实
- 解压默认创建新的唯一目录，不能静默覆盖现有目录
- 外部兼容测试只使用固定测试密码；产品代码不得把密码传给进程
- Finder 右键输出使用新的唯一文件名，不能覆盖现有文件
- 当前不写 ZIP64，不归档符号链接；不要在没有测试和文档变更时扩大格式承诺
