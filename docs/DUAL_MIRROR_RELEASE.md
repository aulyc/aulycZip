# GitHub / Gitee 双镜像发布

本项目显式采用中央可选策略 `aulyc-dual-mirror-v1` 1.7.0，Release Profile 仍为
`macos-arm64-app` 2.0.0。

## 渠道拓扑

- GitHub `aulyc/aulycZip` 是公共源码权威、正式标签权威和 GitHub Release 仓库
- Gitee `aulyc/aulycZip` 只承载 Release、安装包和更新元数据，不推送业务源码
- 两端 Release 只包含同一份已验证正式 DMG
- 最终 provenance 写入两端不可覆盖的
  `updates/<version>/<file>.release-provenance.json`
- Schema v2 `latest.json` 是允许前移的稳定版本指针
- DMG 与 provenance 的 checksum sidecar 只作为本地验证证据，不公开为附件

GitHub 发布说明为中文在前、英文在后；Gitee 只使用简体中文，并指向 GitHub
公共源码权威。

## 更新器合同

应用内更新固定执行：

```text
GitHub latest.json
-> 失败时读取 Gitee latest.json
-> 按 GitHub、Gitee 顺序下载同一份版本化 provenance
-> 按 GitHub、Gitee 顺序下载同一份 DMG
-> 验证 provenance、SHA-256、DMG 签名、公证与 Gatekeeper
-> 挂载 DMG 并验证版本、build、Commit、标签、Bundle ID、Team ID、arm64 和 App 签名
-> 仅在当前应用为 /Applications/aulycZip.app 时退出后安全替换并重新启动
```

回退只改变传输源，不降低任何身份、信任或完整性校验。开发 bundle 或其他位置的
副本可以检查更新，但不会自动覆盖 `/Applications`。

## 中央工具阶段

项目包装 `scripts/dual-mirror-release.sh` 只绑定 `aulyczip`，真实发布由中央工具
按 `prepare`、`preflight`、`publish`、`verify` 四阶段执行。只有 `publish` 可写
远端。任一端失败时状态为 `partial` 或 `failed`，使用原 immutable plan 继续，
不得覆盖同版本内容。
