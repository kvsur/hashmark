# Plan — Markdown App 迭代二期

> 承接已归档的 MVP 计划（`archive/ios-markdown-mvp-core/`）。代码结构与工程约定见 `CLAUDE.md`。

## Target architecture（现状回顾）
已落地的分层（本期在此基础上增量）：
```
MarkdownApp/MarkdownApp/
├── App/ ContentView（NavigationStack + onOpenURL 导入分流）
├── Models/ FileStore（CRUD/移动/导入/树/外部读取/isInsideStore）、DocumentNode、DocumentTreeNode
├── Features/
│   ├── Browser/ FileBrowserView、NameInputSheet
│   ├── Preview/ WebPreviewView（WKWebView 本地渲染）
│   ├── Editor/  EditorView（TextEditor 等宽）
│   ├── Document/ DocumentView（预览/编辑容器 + 分段切换 + 底部快速切换器）
│   ├── Import/  ImportPreviewButton、ReadOnlyPreviewView、ImportTargetPicker
│   └── Switcher/ DocumentSwitcherSheet
├── DesignSystem/ Theme、GlassBackground
└── Resources/WebPreview/ template.html + marked + github-markdown-css + highlight.js
```
关键接线：`DocumentView` 工具栏 = principal 分段器 + bottomBar 切换文档；topBarTrailing 目前空缺 → 本期按模式放「分享」(预览) / 「AI 辅助」(编辑)。

## Phases / Steps

### S1 — 最终定名与显示名
- Goal：把 App 品牌名定下来并落到显示名/文案。
- Sub-steps：
  - S1.1 定名（候选：Markdown Lite / Featherdown / Hashmark / MarkLite…；用户拍板）。
  - S1.2 改 `Info.plist` 的 `CFBundleDisplayName`；检查空状态等文案是否需要同步。
- Verify：桌面图标名、文件 App 目录名为新名。

### S2 — 预览外链改为 App 内 Safari 模态
- Goal：预览里点外部链接不再覆盖当前预览，改为 SFSafariViewController 弹出。
- Sub-steps：
  - S2.1 `WebPreviewView` 的 `WKNavigationDelegate.decidePolicyFor`：对 `http/https` 且 `navigationType == .linkActivated` 的外链 `.cancel`，把 URL 抛给 SwiftUI 层。
  - S2.2 用 `SFSafariViewController`（`UIViewControllerRepresentable`）经 `.sheet`/`.fullScreenCover` 弹出该链接；本地模板加载与锚点不受影响。
  - S2.3 边界：非 http(s)（mailto/tel 等）交系统 `openURL`；锚点内跳转仍在页面内。
- Verify：点文档外链 → App 内 Safari 模态打开 → 关闭回到原预览，预览未被覆盖；顶部/切换按钮不再被网页盖住。

### S3 — 选目录中间页支持「新建文件夹」
- Goal：`ImportTargetPicker` 里没有合适目录时可当场新建。
- Sub-steps：
  - S3.1 选目录页工具栏加「新建文件夹」，复用 `NameInputSheet` + `FileStore.createFolder(in: currentDir)`。
  - S3.2 新建后刷新当前层，可进入新目录或直接导入到它。
- Verify：导入/分享保存时，新建一个目录 → 导入进该新目录成功。

### S4 — 预览态「分享」按钮（三选一）
- Goal：预览右上角分享按钮，弹出三种分享模式。
- Sub-steps：
  - S4.1 入口：`DocumentView` 预览模式时 topBarTrailing 放分享按钮（`square.and.arrow.up`），点击弹 `confirmationDialog`/菜单三选一。
  - S4.2 长截图：把整篇渲染内容导出为长图分享（`WKWebView` 全内容快照，含超出屏幕部分）。
  - S4.3 分享源文件：`UIActivityViewController`/`ShareLink` 分享该 `.md` 文件 URL。
  - S4.4 分享源内容：分享纯文本正文。
- Verify：三种模式都能唤起系统分享面板；长截图完整（含滚动区外内容）。

### S5 — 编辑态「AI 辅助编辑」按钮（占位）
- Goal：编辑模式右上角放 AI 辅助编辑按钮，先占位。
- Sub-steps：
  - S5.1 `DocumentView` 编辑模式时 topBarTrailing 放按钮（`sparkles`），点击弹占位 sheet/提示（后续再接实际能力）。
- Verify：编辑态出现按钮，点击有占位反馈、不崩；预览态不显示它。

### S6 — App Store 上架准备（承接原 MVP S8）
- Goal：完成签名合规与提交，至少 TestFlight 可安装。
- Sub-steps：
  - S6.1 注册付费 Apple Developer Program（99 美元/年）。
  - S6.2 App ID / Bundle Identifier、证书与 provisioning（Xcode 自动签名优先）。
  - S6.3 隐私清单 `PrivacyInfo.xcprivacy`——本 App 不联网收集数据，如实声明。
  - S6.4 App Store Connect 建条目：名称（需全球唯一）、描述、分类、截图。
  - S6.5 Archive → 上传 → TestFlight 内测安装。
  - S6.6 提交审核。
- Verify：TestFlight 能装到真机（里程碑）；提交审核成功。
- 承接决策（自原计划）：大陆个人开发者建议注册中国区账号（全球发布与账号区无关）；大陆上架需 ICP 备案，MVP 发布范围可勾全球排除大陆以规避，日后再单独备案。

### S7 —（后续）iCloud 同步（承接原 MVP S9）
- Goal：文档改存 iCloud 容器，多设备自动同步。
- Sub-steps（占位，届时细化）：
  - S7.1 开启 iCloud Documents entitlement + ubiquity container。
  - S7.2 `FileStore` 迁移到 iCloud 容器路径，处理下载/冲突状态。
  - S7.3 本地已有文档的迁移策略。
- Verify：两台设备登录同一 iCloud，改动能同步。

---

## Notes / 风险
- S2 外链拦截要区分「本地模板首帧加载 / 锚点内跳 / 真外链」，只拦 `.linkActivated` 的 http(s)，避免误伤渲染。
- S4 长截图是本期技术难点：需要抓 WKWebView 完整内容高度再快照，注意大文档内存与分段拼接。
- S6 上架名全球唯一：拟定名可能被占，需备副名。
- 延续 CLAUDE.md：无 emoji 文案、SF Symbols 图标、单一职责、逻辑外移、版本差异收敛在封装层。
