# Plan — iOS Markdown 预览/编辑 App

> 面向读者：一位资深 Web 前端、但**零 iOS 经验**的开发者。计划里对 iOS 特有概念会多给一句解释。
> 三份文件是唯一真相源。执行时以 `state.json` 为进度指针，本文件为蓝图。

## Target architecture

### 技术选型总览
- **语言/框架**：Swift + SwiftUI（声明式 UI，类似 React 的心智模型：`View` ≈ 组件，`@State`/`@Observable` ≈ 状态）。
- **最低部署**：iOS 18.0。液态玻璃走 `if #available(iOS 26, *)` 分支。
- **预览**：`WKWebView`（通过 `UIViewRepresentable` 包成 SwiftUI View）。加载本地 HTML 模板，注入 `marked`（或 `markdown-it`）+ `github-markdown-css`，把原始 Markdown 交给 JS 渲染。全部资源打包进 App bundle，**不联网**。
- **编辑器**：MVP 用 SwiftUI `TextEditor`（等宽字体）；若换行/光标体验不足，退回 `UITextView` 桥接。纯文本，无语法高亮。
- **存储**：`FileManager` 管理 App 沙盒内 `Documents/` 目录。文件树即真实目录结构（无限级 = 真实嵌套文件夹）。通过 Info.plist 的 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` 暴露给系统「文件」App。
- **导入**：Info.plist 注册 `.md`/`.markdown`/`text` 文档类型；实现 `.onOpenURL` 接收外部文件；中间页选目录后落盘。
- **分发**：付费 Apple Developer 账号 + App Store Connect。

### 目录/模块布局（目标形态，随实现微调）
```
MarkdownApp/
├── MarkdownApp.xcodeproj
├── MarkdownApp/
│   ├── App/
│   │   └── MarkdownAppApp.swift          # @main 入口，.onOpenURL 挂这里
│   ├── Models/
│   │   ├── DocumentNode.swift            # 文件/文件夹节点模型
│   │   └── FileStore.swift               # FileManager 封装：CRUD、遍历、移动
│   ├── Features/
│   │   ├── Browser/                      # 文件浏览器（列表 + 目录导航）
│   │   ├── Preview/                      # WKWebView 预览
│   │   ├── Editor/                       # 原生编辑器
│   │   └── Import/                       # 导入中间页（选目标目录）
│   ├── DesignSystem/
│   │   ├── GlassBackground.swift         # 液态玻璃/材质降级封装
│   │   └── Theme.swift                   # light/dark 颜色、字体
│   ├── Resources/
│   │   └── WebPreview/                   # 本地 web 资源
│   │       ├── template.html
│   │       ├── marked.min.js
│   │       └── github-markdown.css
│   └── Assets.xcassets                   # App 图标、颜色集
└── ...
```

### 关键抽象：液态玻璃降级层
一个 `GlassBackground` view modifier：
- `if #available(iOS 26, *)` → 使用系统原生 Liquid Glass API。
- else → `.background(.ultraThinMaterial)` / `.regularMaterial` 等材质模糊。
全 App 统一调用它，避免到处写可用性判断。

---

## Phases / Steps

### S0 — 开发环境搭建（从零到能跑起一个空 App）
- Goal：装好工具链，能把一个 SwiftUI 模板 App 跑在模拟器**和 iOS 26 真机**上。
- Sub-steps：
  - S0.1 从 App Store 安装 **Xcode**（最新正式版，支持 iOS 26 SDK），首次启动装好命令行组件。
  - S0.2 用个人 Apple ID 在 Xcode 登录（Settings → Accounts）。付费开发者账号留到 S8。
  - S0.3 `File → New → Project → iOS App`，Interface 选 **SwiftUI**，Language 选 **Swift**。项目名例如 `MarkdownApp`。
  - S0.4 理解「模拟器 vs 真机」：先在模拟器 Run 起模板；再用数据线连 iPhone，处理「信任此电脑」+ 开发者模式（Settings → Privacy & Security → Developer Mode）。
  - S0.5 把生成的 Xcode 工程纳入当前 git 仓库（补 `.gitignore` for Xcode/Swift）。
- Verify：模拟器与真机都能看到默认 "Hello World" 界面。

### S1 — 工程骨架与设计基座
- Goal：搭好导航结构、主题与液态玻璃降级层，作为后续所有功能的地基。
- Sub-steps：
  - S1.1 设置最低部署版本为 iOS 18.0（Project → Deployment Target）。
  - S1.2 建 `NavigationStack` 主界面骨架 + 空的「文件浏览器」占位页。
  - S1.3 `DesignSystem/Theme.swift`：定义 light/dark 颜色与等宽字体；确认系统深浅色自动切换生效。
  - S1.4 `GlassBackground` 封装（iOS 26 原生 / 低版本材质降级），先在一个 toolbar/卡片上验证。
  - S1.5 右上角放一个占位的 preview/edit 模式切换 button group（`Picker`/segmented）。
- Verify：App 有基本导航壳，深浅色自动适配，液态玻璃层在 26 真机与 18 模拟器都不崩。

### S2 — 文件存储层与目录管理（无限级目录）
- Goal：能在 App 内新建/管理多级目录与文档，落盘持久化，系统「文件」App 可见。
- Sub-steps：
  - S2.1 `FileStore`：基于 `FileManager` 读写 `Documents/`；列目录、建文件夹、建 `.md`、重命名、删除、移动。
  - S2.2 `DocumentNode` 模型 + 把真实目录映射成可展示的树。
  - S2.3 文件浏览器 UI：进入文件夹、返回、显示层级；新建目录/文档入口。
  - S2.4 Info.plist：`UIFileSharingEnabled=YES` + `LSSupportsOpeningDocumentsInPlace=YES`，让目录出现在系统「文件」App。
  - S2.5 删除/重命名的确认交互与边界（空目录、重名处理）。
- Verify：新建多级目录+文档，杀进程重开仍在；在「文件」App 里能看到同样结构。

### S3 — Markdown 预览（WebView + GitHub 主题）
- Goal：任选一个文档，WebView 渲染成 GitHub 风格，支持深浅色。
- Sub-steps：
  - S3.1 准备本地 web 资源：`template.html` + `marked.min.js` + `github-markdown.css`（放 `Resources/WebPreview/`，加入 bundle）。
  - S3.2 `WebPreviewView`（`UIViewRepresentable` 包 `WKWebView`），`loadHTMLString` 加载模板，baseURL 指向 bundle 以便引用本地 css/js。
  - S3.3 渲染管线：Swift 把原始 Markdown 传给 JS（`evaluateJavaScript` 或注入到模板占位符），JS 用 marked 转 HTML 塞进 `.markdown-body`。
  - S3.4 深浅色：根据 `colorScheme` 切换 github-markdown css 的 light/dark 变量（或加/去 `data-theme`）。
  - S3.5 验证 GFM：标题、列表、任务列表、表格、代码块高亮、引用、图片链接。
- Verify：一篇含表格/代码/任务列表的 md 渲染正确，深浅色都好看，全程离线。

### S4 — 原生编辑器与模式切换
- Goal：文档可在预览/编辑间切换，编辑纯文本并保存。
- Sub-steps：
  - S4.1 `EditorView`：`TextEditor` + 等宽字体；加载文档内容为可编辑文本。
  - S4.2 右上角 button group 真正驱动 preview/edit 切换（复用 S1.5 占位）。
  - S4.3 保存：编辑内容写回 `FileStore`（防抖/离开即存），预览端重新渲染。
  - S4.4 若 `TextEditor` 体验不足（光标/换行/性能），评估切换到 `UITextView` 桥接，记录在 notes。
- Verify：改一篇 md → 切到预览能看到变化 → 重启文档内容仍是新的。

### S5 — 本地文件导入预览
- Goal：从本地/「文件」App 选一个 `.md` 直接预览。
- Sub-steps：
  - S5.1 用 SwiftUI `.fileImporter` 选文件，限定 md/text UTType。
  - S5.2 处理 security-scoped resource（`startAccessingSecurityScopedResource`）读取外部文件内容。
  - S5.3 读到内容 → 进入预览（此路径可只读预览，不强制导入到目录）。
- Verify：从「文件」App 任选一个 md，能正确预览。

### S6 — 外部分享 / 打开方式导入
- Goal：其他 App 分享 `.md` 到本 App → 选目标目录（默认根）→ 导入并进入预览。
- Sub-steps：
  - S6.1 Info.plist 注册文档类型（`CFBundleDocumentTypes` + UTI：`net.daringfireball.markdown` / `public.text`），让本 App 出现在分享/「打开方式」里。
  - S6.2 入口 `MarkdownAppApp.swift` 的 `.onOpenURL` 接收传入文件 URL。
  - S6.3 中间页：展示目录树让用户选目标位置，默认选中根目录；确认后把文件拷进 `FileStore`。
  - S6.4 导入完成默认进入**预览模式**。
  - S6.5 边界：重名文件、非 md 内容、取消导入。
- Verify：从备忘录/浏览器等分享一个 md → 出现选目录中间页 → 确认 → 文件进目录并预览。

### S7 — 液态玻璃视觉打磨 & 主题适配
- Goal：把 Liquid Glass 与深浅色打磨到可交付观感，补齐图标/启动。
- Sub-steps：
  - S7.1 在导航栏、工具栏、卡片、模式切换器上统一应用 `GlassBackground`。
  - S7.2 iOS 26 真机走查原生液态玻璃；iOS 18 模拟器走查材质降级不违和。
  - S7.3 Light/Dark 全流程走查（浏览器/预览/编辑/导入页）。
  - S7.4 App 图标（Assets.xcassets）、启动屏、App 显示名。
- Verify：26 真机液态玻璃到位，18 降级可接受，深浅色一致，图标/名称就绪。

（注：原 S8 App Store 上架、S9 iCloud 同步已迁出本计划，作为后续新计划的 S6/S7，见 .work-planner/plan.md。）

### S10 — 文档快速切换器（编辑/预览页底部弹层）
- Goal：在编辑/预览某文档时，不离开 App 就能快速跳到另一篇继续预览/编辑。
- 背景：系统「文件」App 已有可折叠文档树，但要离开本 App；本功能主打「留在 App 内多篇之间无打断切换」。
- Sub-steps：
  - S10.1 `FileStore.tree(of:)` 递归读出整棵目录/文档树；`DocumentTreeNode`（含 `children`，文件为叶子）。
  - S10.2 `DocumentSwitcherSheet`：`OutlineGroup` 折叠/展开树（点文件夹收合、点文档选中），高亮当前文档，点文档回调并关闭。
  - S10.3 `DocumentView` 底部工具栏加入口按钮，`.sheet` + `.presentationDetents([.medium, .large])` + 拖拽指示，默认半屏可上拖。
  - S10.4 原地切换：`DocumentView` 的当前 node 改为可变状态；切换前保存当前脏内容，再载入新文档文本、更新标题，保持当前预览/编辑模式，不改导航栈。
- Verify：编辑一篇→底部弹层→选另一篇→原地切到新文档（标题/内容都变），当前修改已存；反复切换内容不串。

### S11 — 只读预览页「导入到 App」
- Goal：从「文件」App 打开外部文档只读预览（S5 路径）时，可一键导入进 App 目录（复用 S6 的选目录+拷入）；若该文件本就在 App 目录内，则不显示导入入口。
- Sub-steps：
  - S11.1 `FileStore.isInsideStore(url)`：解析符号链接后判断文件是否已在 App Documents 内。
  - S11.2 `ReadOnlyPreviewView` 传入 `store` + `sourceURL`，`canImport = !isInsideStore` 时在工具栏显示「导入」按钮。
  - S11.3 点导入 → 复用 `ImportTargetPicker` 选目录 → `FileStore.importFile` 拷入 → 关闭只读预览（返回浏览器可见新文件）。
- Verify：打开 iCloud/下载里的外部 md → 预览有「导入」→ 选目录导入 → 浏览器出现该文件；打开 Hashmark 自己目录里的 md → 预览无「导入」按钮。

---

## Milestones
- M1 = S0–S1：环境就绪 + App 骨架能跑（对零基础者是最大门槛，跨过即信心大增）。
- M2 = S2–S4：核心闭环——建目录/文档、预览、编辑保存。
- M3 = S5–S6：两条导入路径打通。
- M4 = S7–S8：视觉打磨 + 上架。
- M5 = S9：iCloud 同步（MVP 之后）。

## Notes / 风险
- 零基础者最容易卡 S0（真机开发者模式、签名）——预留耐心，遇错记录到 state。
- WebView 引本地资源的 baseURL 与沙盒路径是常见坑，S3 重点验证。
- `TextEditor` 在长文档/中文输入下可能有体验问题，备选 `UITextView`。
- 液态玻璃 API 以实机 iOS 26 SDK 为准，实现时以 Xcode 文档/自动补全为准，不臆造 API 名。
