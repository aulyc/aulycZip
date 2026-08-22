# Finder 右键压缩与解压

## 用户流程

### 加密压缩

1. 在 Finder 选择一个或多个文件、文件夹。
2. 右键选择“使用 aulycZip 加密压缩”。
3. 在密码窗口确认选中的文件或文件夹名称及源文件目录。
4. 保存位置默认选择“与原文件相同目录”，也可以选择其他文件夹。
5. 输出文件名输入框以自动名称作为 placeholder；可以留空使用默认名称，也可以输入自定义名称，`.zip` 扩展名可以省略。
6. 输入并确认至少 8 个字符的密码后创建 WinZip AES-256 ZIP。界面会同时提示建议使用 12 个以上字符并混合字母、数字和符号。

单项默认命名为“原名称 加密.zip”，多项默认命名为“加密归档.zip”。无论使用默认名称还是自定义名称、原目录还是其他目录，若名称已存在，都会追加数字后缀，不会覆盖旧文件或源文件。

### 解压

1. 在 Finder 只选择一个 ZIP 文件。
2. 右键选择“使用 aulycZip 解压”。
3. 应用读取并校验归档，然后显示与菜单栏入口相同的保存位置和密码设置。
4. 普通 ZIP 不需要密码；WinZip AES 归档需要输入正确密码。

右键解压一次只处理一个 ZIP，不会解压非 ZIP 文件。

## macOS 集成

`Config/Info.plist` 的 `NSServices` 声明两个服务：

- 加密压缩：`使用 aulycZip 加密压缩` / `createEncryptedZip:userData:error:` / `public.item`
- ZIP 解压：`使用 aulycZip 解压` / `extractZip:userData:error:` / `public.zip-archive`
- 上下文：仅 `com.apple.finder`
- `NSRestricted`：不声明（系统默认 `false`），右键后直接进入对应的应用操作流程

应用启动后把 `FinderServiceProvider` 设置为 `NSApplication.servicesProvider`。Finder 将所选项目作为文件 URL 写入服务粘贴板；提供者不接收普通字符串或网络 URL。加密压缩与右键解压分别复用各自的菜单栏工作流。

这里有一项明确的体验与安全取舍：不把服务标记为受限制服务，因此 macOS 不会在应用操作框之前再显示“确认服务”。服务仍限定为 Finder 上下文、只读取文件 URL；实际创建必须经过 aulycZip 的密码确认，而且不会覆盖已有 ZIP。解压仍执行归档格式、路径、认证码、大小和条目数限制。

macOS 可能把服务直接显示在右键菜单底部，也可能收进“服务”子菜单。若用户在“系统设置 → 键盘 → 键盘快捷键 → 服务”中禁用了该项目，应用不能绕过用户设置强制显示。
