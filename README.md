# aulycZip

aulycZip 是一个原生 macOS 菜单栏 ZIP 工具，界面使用 AppKit 编写，不依赖 `7zz`、Keka 或其他外部压缩进程。

当前功能：

- 创建 WinZip AES-256（AE-2）加密 ZIP
- 按实际大小和偏移自动创建普通 ZIP 或 ZIP64，小归档保持普通 ZIP
- 在 Finder 右键菜单中加密压缩所选文件或文件夹
- 解压普通 ZIP 和 WinZip AES-128/192/256 ZIP
- 读取普通 ZIP、ZIP64、Store、Deflate，以及 WinZip AES-128/192/256 AE-1/AE-2
- 在写出文件前验证密码与认证码
- 以固定大小分块压缩、加密、认证和解压，不把整个归档或单个大文件载入内存
- 使用同级临时文件/目录，全部成功后原子提交；菜单栏只在系统保存面板确认后替换普通文件，失败或取消时保留原文件
- 阻止路径穿越、文件名碰撞、符号链接逃逸和超限解压
- 每日自动检查正式更新，也可从菜单栏手动“检查更新…”
- 更新源固定 GitHub 优先、Gitee 回退，安装前验证 SHA-256、发布溯源、签名与公证
- 在“关于 aulycZip”中查看版本、系统要求、产品说明、官网与致谢

## 使用

Finder 中选中文件或文件夹后，右键选择“使用 aulycZip 加密压缩”。密码窗口会显示本次选中的名称和源文件目录，并允许选择“与原文件相同目录”或其他保存目录。输出文件名默认以“名称 加密.zip”作为输入框提示，也可以自行修改；省略 `.zip` 时应用会自动补齐。如果文件已存在，会自动追加数字而不覆盖。

新密码至少需要 8 个字符，不是只能输入 8 位，也不要求必须是数字。建议使用 12 个以上字符，并混合字母、数字和符号。

菜单栏只提供加密 ZIP 创建与 ZIP 解压。普通 ZIP 创建交给 macOS Finder 自带的“压缩”功能。
菜单栏保存位置已有同名 ZIP 时，由系统保存面板询问是否替换；确认后应用先完整生成新归档，再原子替换旧文件。Finder 右键入口仍始终生成唯一文件名，不覆盖已有文件。

最终创建的 ZIP 遵循应用进程的默认文件权限（通常由系统 `umask` 决定）；构建期间的工作目录和中间文件仅当前用户可访问。解压结果采用更保守的权限：根目录和子目录为 `0700`，文件为 `0600`，不恢复归档中的可执行位或特殊权限。

构建并运行 SwiftPM 开发程序：

```bash
swift run aulycZip
```

生成本地 Apple Silicon `.app`：

```bash
make bundle
open .cache/build/aulycZip.app
```

运行验证：

```bash
make check
```

共享工程规范是显式的外部依赖，不使用维护者机器上的默认路径。先检出
[`aulyc/codex-engineering-standards`](https://github.com/aulyc/codex-engineering-standards)，
并通过 `STANDARDS_ROOT` 指向该检出目录；采用的 Core、Profile 和 Release Policy
版本固定在 `.codex/standards.json`，中央扫描器会验证版本和项目登记：

```bash
STANDARDS_ROOT=/absolute/path/to/codex-engineering-standards make standards-check
```

正式版安装在 `/Applications/aulycZip.app` 时，可以直接在菜单栏完成在线升级。开发
构建和从其他目录运行的副本只检查新版本，不会自动覆盖应用；这种情况下可打开
GitHub 发布页手动下载。

CI 会安装 7-Zip 并运行双向兼容测试，包括 7-Zip 解压 aulycZip 生成的普通/AES
归档、aulycZip 解压 7-Zip AES 归档，以及 7-Zip 解压 aulycZip 强制生成的普通和
AES ZIP64 归档。本地未配置工具时会明确显示为 skipped；需要运行时显式提供路径：

```bash
AULYCZIP_7ZZ=/absolute/path/to/7zz swift test --filter ExternalCompatibilityTests
```

流式性能基准以 Release 配置运行，默认使用固定种子的 200 MiB 高熵输入，要求实际
归档大小不低于输入的 95%，从而覆盖完整的压缩、AES-CTR 和 HMAC 热路径。进程峰值
常驻内存限制为 192 MiB，创建、解压各自在 30 秒内完成；CI 每周及手动触发时运行。
输入大小和三个上限均可调整（大文件和 5 GiB ZIP64 验收应在具备足够临时磁盘空间的
专用环境运行）：

```bash
bash scripts/benchmark-zipcore.sh
AULYCZIP_BENCHMARK_BYTES=5368709120 bash scripts/benchmark-zipcore.sh
AULYCZIP_BENCHMARK_MAX_RSS_BYTES=268435456 bash scripts/benchmark-zipcore.sh
AULYCZIP_BENCHMARK_MAX_CREATE_SECONDS=60 AULYCZIP_BENCHMARK_MAX_EXTRACT_SECONDS=60 bash scripts/benchmark-zipcore.sh
```

## 加密说明

WinZip AES 会加密文件内容，但 ZIP 的文件名和目录名通常仍然可见。密码不会由应用保存；忘记密码后无法恢复。详细边界见 [docs/SECURITY.md](docs/SECURITY.md)。
