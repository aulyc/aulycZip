# 图标资产

`design/iconMark.svg` 是唯一几何源，包含四角框与单笔手写 `z`。不要直接编辑下列生成文件：

- `design/menuBarIcon.svg`
- `design/appIcon.svg`
- `design/appIcon-preview.png`
- `design/icon-manifest.json`
- `Sources/aulycZip/Resources/MenuBarIcon.svg`
- `Resources/AppIcon.icns`

修改几何后执行：

```bash
make icons
make icon-check
```

菜单栏 SVG 使用黑色模板图；应用图标使用深灰背景和浅灰图形。生成器负责颜色、渲染尺寸、ICNS 与哈希清单，保证两类图标保持同一造型。
