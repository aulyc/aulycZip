# 架构

## 产品层

`Sources/aulycZip` 是纯 AppKit 菜单栏应用：

- `StatusBarController` 维护 `NSStatusItem` 与原生菜单
- `ArchiveWorkflowController` 维护选择文件、保存位置、密码、进度和结果反馈
- `FinderServiceProvider` 接收 Finder Services 传入的文件 URL
- `FinderArchiveRequest` 校验右键选择并生成不覆盖现有文件的输出路径
- `PasswordPrompt` 只在内存中接收密码，不保存、不记录
- `OperationProgressPanelController` 提供非阻塞进度面板
- `UpdateController` 编排自动/手动检查、用户提示、下载和退出前安装准备
- `UpdateManifest` 固定 Schema v2、产品身份、镜像顺序和可信 URL
- `UpdateInstaller` 验证 provenance、DMG、签名、公证和 App 身份，并生成受限替换任务

应用使用 `LSUIElement`，没有常驻 Dock 图标或主窗口。

更新清单和安装器位于 `aulycZipAppSupport`，便于在不依赖 AppKit 界面的测试中验证
Schema、镜像顺序、SHA-256、provenance 和替换路径；提示与进度窗口留在 AppKit
应用目标中。

## ZIP 核心

`Sources/ZipCore` 不依赖 UI，也不启动外部进程：

- `ZipArchiveWriter` 写入 ZIP 本地头、中央目录与 EOCD
- `ZipArchiveReader` 解析中央目录并校验记录边界
- `RawDeflate` 使用系统 zlib 处理原始 Deflate 数据
- `WinZipAES` 使用系统 CommonCrypto 实现 WinZip AES 协议要求的 PBKDF2-HMAC-SHA1、AES-CTR 与认证
- `SafeExtractionPath` 和 `ZipArchive` 共同负责安全解压边界

初始实现将单个文件完整载入内存，且暂不写入 ZIP64；超大文件与流式读写是后续独立工作。

## 产品与格式边界

- 用户可见写入：仅 WinZip AES-256 AE-2
- 读取：普通 ZIP、WinZip AES-128/192/256 AE-1/AE-2
- 压缩方法：Store、Deflate
- 文件名编码：UTF-8
- 暂不支持：ZIP64、多卷 ZIP、符号链接归档、创建 ZipCrypto

ZIP 核心仍保留普通 ZIP 写入能力用于格式测试和兼容性夹具，但菜单栏与 Finder 右键均不向用户提供普通 ZIP 创建入口。
