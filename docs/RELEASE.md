# 发布流程

## 身份与边界

- Release Profile：`macos-arm64-app` 2.0.0
- 可选 Release Policy：`aulyc-dual-mirror-v1` 1.7.0
- 权威版本与构建号：`Config/Info.plist`
- 正式分支与标签：`main`，稳定 SemVer annotated tag，不带 `v`
- 正式安装包：`aulycZip-<version>-build.<build>-formal-macos-arm64.dmg`
- 正式发布只发布并回读产物，不写入 `/Applications`
- 只有用户明确要求安装时才运行 `make install-release` 和 `make verify-installed`

测试发布目前为 `N/A`。本地 ad-hoc bundle、候选构建和正式产物不能互相改名替代。

## 中央规范依赖

正式发布命令依赖公开的
[`aulyc/codex-engineering-standards`](https://github.com/aulyc/codex-engineering-standards)
检出目录。仓库不提供个人机器路径或隐式回退；运行发布门禁前必须显式设置：

```bash
export STANDARDS_ROOT=/absolute/path/to/codex-engineering-standards
```

`.codex/standards.json` 固定本项目采用的 Core、`macos-arm64-app` Profile 和
`aulyc-dual-mirror-v1` Policy 版本。每个入口会先验证 `STANDARDS_ROOT` 及所需
中央脚本，中央扫描器再验证采用版本、项目登记和发布渠道映射；依赖缺失或不匹配
时发布流程会在改动版本、标签或远端之前失败。

## 正式发布命令

先提交全部功能、测试、文档和治理改动，并保持工作区干净。中央登记和两个公开
渠道必须已经存在，随后准备独立发布元数据提交：

```bash
make prepare-formal-release TARGET_VERSION=1.1.0 TARGET_BUILD=4
git add Config/Info.plist CHANGELOG.md CHANGELOG.zh-CN.md
git commit -m "chore: release 1.1.0"
```

运行标签前同配置候选门禁并创建不可移动标签：

```bash
make release-check \
  DEVELOPER_ID_APPLICATION='Developer ID Application: nan ma (M9M7M2ARFD)'
make release-tag
```

从精确 annotated tag 的隔离干净 worktree 重建、Developer ID 签名、提交 Apple
公证、staple 并验证真实 DMG：

```bash
make release-formal \
  DEVELOPER_ID_APPLICATION='Developer ID Application: nan ma (M9M7M2ARFD)' \
  NOTARY_PROFILE=aulyc-notary
```

正式产物先在本地完成 DMG、挂载 App、SHA-256、签名、公证、Gatekeeper 和
provenance 交叉验证。随后原子推送 `main` 与 annotated tag 到中央绑定的 GitHub
仓库，补齐远端 provenance，再执行 GitHub/Gitee 双镜像发布：

```bash
make publish-release \
  RELEASE_PROVENANCE=/absolute/path/to/dist/<file>.release-provenance.json
```

发布失败只能复用同一份不可变计划安全继续；禁止移动标签、覆盖附件、删除冲突
Release 或降低验证门禁。

## 显式安装

以下命令不属于纯发版，只能在用户明确授权安装后运行：

```bash
make install-release \
  RELEASE_PROVENANCE=/absolute/path/to/dist/<file>.release-provenance.json
make verify-installed \
  RELEASE_PROVENANCE=/absolute/path/to/dist/<file>.release-provenance.json
```

安装入口只接受已经补齐 GitHub 远端身份并完成独立验证的正式 provenance，安装前
要求退出 aulycZip；替换失败时恢复原应用。
