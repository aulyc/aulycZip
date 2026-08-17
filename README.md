# aulycZip

aulycZip 是一个原生 macOS 菜单栏 ZIP 工具，界面使用 AppKit 编写，不依赖 `7zz`、Keka 或其他外部压缩进程。

当前功能：

- 创建 WinZip AES-256（AE-2）加密 ZIP
- 在 Finder 右键菜单中加密压缩所选文件或文件夹
- 解压普通 ZIP 和 WinZip AES-128/192/256 ZIP
- 与 WinZip、7-Zip、Keka 使用的 WinZip AES ZIP 格式互操作
- 在写出文件前验证密码与认证码
- 阻止路径穿越、符号链接逃逸和超限解压
- 在“关于 aulycZip”中查看版本、系统要求、产品说明、官网与致谢

## 使用

Finder 中选中文件或文件夹后，右键选择“使用 aulycZip 加密压缩”。密码窗口会显示本次选中的名称和源文件目录，并允许选择“与原文件相同目录”或其他保存目录。输出文件名默认以“名称 加密.zip”作为输入框提示，也可以自行修改；省略 `.zip` 时应用会自动补齐。如果文件已存在，会自动追加数字而不覆盖。

新密码至少需要 8 个字符，不是只能输入 8 位，也不要求必须是数字。建议使用 12 个以上字符，并混合字母、数字和符号。

菜单栏只提供加密 ZIP 创建与 ZIP 解压。普通 ZIP 创建交给 macOS Finder 自带的“压缩”功能。

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

外部 7-Zip 双向兼容测试默认不依赖本机安装。需要运行时显式提供测试工具路径：

```bash
AULYCZIP_7ZZ=/absolute/path/to/7zz swift test --filter ExternalCompatibilityTests
```

## 加密说明

WinZip AES 会加密文件内容，但 ZIP 的文件名和目录名通常仍然可见。密码不会由应用保存；忘记密码后无法恢复。详细边界见 [docs/SECURITY.md](docs/SECURITY.md)。
