# 架构

## 产品层

`Sources/aulycZip` 是纯 AppKit 菜单栏应用：

- `StatusBarController` 维护 `NSStatusItem` 与原生菜单
- `ArchiveWorkflowController` 维护选择文件、保存位置、密码、进度和结果反馈
- `FinderServiceProvider` 接收 Finder Services 传入的文件 URL
- `FinderArchiveRequest` 校验右键选择并生成不覆盖现有文件的输出路径
- `PasswordPrompt` 只在内存中接收密码，不保存、不记录
- `OperationProgressPanelController` 提供可取消的非阻塞进度面板
- `AppOperationCoordinator` 保证归档任务与更新替换互斥；检查更新本身不阻塞归档
- `UpdateController` 编排自动/手动检查、用户提示、下载和退出前安装准备
- `UpdateManifest` 固定 Schema v2、产品身份、镜像顺序和可信 URL
- `UpdateInstaller` 验证 provenance、DMG、签名、公证和 App 身份；替换 helper 在移动前再次核对精确哈希、签名、Team ID 和 Gatekeeper

应用使用 `LSUIElement`，没有常驻 Dock 图标或主窗口。

更新清单和安装器位于 `aulycZipAppSupport`，便于在不依赖 AppKit 界面的测试中验证
Schema、镜像顺序、SHA-256、provenance 和替换路径；提示与进度窗口留在 AppKit
应用目标中。

## ZIP 核心

`Sources/ZipCore` 不依赖 UI，也不启动外部进程：

- `ArchiveIO` 提供基于 `FileHandle` 的 64 位有界读取和固定大小分块复制
- `ZipArchiveWriter` 使用最终归档、单条目 payload、中央目录三层临时文件，按需写入 ZIP64 extra、ZIP64 EOCD 和 Locator
- `ZipArchiveReader` 从文件尾部定位 EOCD/ZIP64 EOCD，流式解析中央目录并校验本地头与记录边界
- `RawDeflateEncoder` / `RawDeflateDecoder` 使用系统 Compression 流式处理 Deflate
- `WinZipAES` 使用系统 CommonCrypto 实现 WinZip AES 协议要求的 PBKDF2-HMAC-SHA1、AES-CTR 与认证
- `WinZipAESCTR` 批量生成小端计数器 keystream；HMAC 与 CRC 均跨 chunk 增量计算
- `SafeExtractionPath` 和 `ZipArchive` 负责路径预检、两遍 AES 认证/解密、staging 与最终原子提交

常规创建和解压只保留当前 chunk、格式元数据及系统编解码状态。所有大小和偏移在内部使用 `UInt64`，仅当前实际分配的 chunk 转为 `Int`。

## 产品与格式边界

- 用户可见写入：仅 WinZip AES-256 AE-2
- 读取：普通 ZIP、ZIP64、WinZip AES-128/192/256 AE-1/AE-2，以及带/不带 data descriptor 的条目
- 压缩方法：Store、Deflate
- 文件名编码：UTF-8
- 不支持：多卷 ZIP、符号链接归档、读取或创建 ZipCrypto

ZIP64 只扩大条目大小、偏移和数量字段，不改变 Deflate、AES 或文件名可见性。只有普通字段无法表示实际值时才自动启用 ZIP64；测试可用小文件强制 ZIP64 夹具覆盖格式边界。

ZIP 核心仍保留普通 ZIP 写入能力用于格式测试和兼容性夹具，但菜单栏与 Finder 右键均不向用户提供普通 ZIP 创建入口。
