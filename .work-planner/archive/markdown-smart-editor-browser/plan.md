# Plan — iOS/iPad Markdown 智能编辑与首页目录体验

## Target architecture

```text
Features/Editor/
├── EditorView.swift                  # SwiftUI 入口，保持轻量
├── MarkdownTextView.swift            # UITextView/Coordinator 桥接
├── Editing/
│   ├── MarkdownEditingEngine.swift   # 提议输入 → TextMutation，纯逻辑
│   ├── MarkdownEditingContext.swift  # UTF-16 行/选区/marked-text 上下文
│   ├── MarkdownEditorCommand.swift   # 格式、缩进、移动等统一命令
│   ├── MarkdownTextMutation.swift    # replacement + selection + undo 语义
│   ├── MarkdownListRule.swift        # 列表/任务续写与退出
│   └── MarkdownFormatRule.swift      # 行内/块级格式切换
├── Highlighting/
│   ├── MarkdownSyntaxHighlighter.swift
│   └── MarkdownParagraphStyler.swift
├── Commands/
│   ├── EditorKeyboardBar.swift       # iPhone/iPad 软件键盘入口
│   └── EditorKeyCommands.swift       # iPad 硬件键盘命令
├── Outline/
│   └── MarkdownOutline.swift         # 标题层级与跳转模型
└── EditorBlockScanner.swift          # 现有块选择扫描器，按需复用/收敛

Features/Browser/
├── FileBrowserView.swift             # 列表与导航入口，保持轻量
└── BrowserNodeLabel.swift            # 原生 List 行的纯展示内容

Models/
├── FileStore.swift                   # 目录枚举与磁盘移动
└── DocumentActivityResolver.swift    # 文件夹递归有效更新时间与稳定排序键
```

核心数据流：

```text
用户输入/格式命令
    → MarkdownEditingContext（raw text + UTF-16 range）
    → MarkdownEditingEngine / MarkdownEditorCommand
    → MarkdownTextMutation（替换范围、替换文本、新选区）
    → UITextView 单次 undo transaction
    → Binding<String> / DocumentView 保存
```

语法着色和段落样式只写 `textStorage` 属性，不改变 raw Markdown；IME 存在 `markedTextRange` 时跳过会改变组合文本的智能规则。

首页目录数据流：

```text
FileStore 枚举直接子项
    → DocumentActivityResolver 单次递归计算后代 Markdown 最新修改时间
    → 文件夹/文件分组 + 组内时间降序 + 名称稳定兜底
    → FileBrowserView

用户从左滑菜单打开移动面板
    → FileStore.move（沿用重名策略）
    → 刷新目录与有效更新时间排序
```

## Dependency graph

```text
S1 → S2 → S3 → S4 ─┐
  └────────→ S5 ────┼→ S6 → S7
                     └→ S8 → S9 → S10
```

## Milestones

- M1（S1–S2）：手动输入不再机械——列表/任务/引用/代码缩进自然续写与退出。
- M2（S3–S4）：触屏与键盘都能高效格式化——统一命令、移动端工具栏和硬件快捷键。
- M3（S5）：raw Markdown 仍然清晰可读——增量语法着色和悬挂缩进。
- M4（S6–S7）：专业导航与 iPad 工作区完成，经过性能、i18n 和回归验收。
- M5（S8–S10）：首页目录按真实活动时间组织，支持符合系统规范的文件拖放移动并完成回归验收。

## Phases / Steps

### S1 — 可测试的编辑引擎与 UIKit 安全应用层

- Goal: 建立与 UI 解耦、按 UTF-16 工作的编辑规则基础，让后续能力不继续堆进 Coordinator。
- Depends on: none
- Refs: C1（目标）、C2（现有桥接）、C5（语法范围）、C7/C8（UIKit/TextKit 边界）
- Resolves: 第三方内核是否必要；测试目标与性能基线。
- Sub-steps:
  - S1.1 定义 `MarkdownEditingContext`、`MarkdownTextMutation`、`MarkdownEditorCommand`，明确 range/selection 契约。
  - S1.2 实现 UTF-16 安全的当前行、相邻行、缩进、前缀和多行选区工具，不依赖 UIKit。
  - S1.3 在 `MarkdownTextView` 建立 mutation applier：单次 undo、光标/选区/滚动稳定、Binding 回写一次。
  - S1.4 增加可独立运行的纯逻辑测试 harness 与基线用例，覆盖 emoji、组合字符、CRLF、文首/文末、空文档和 marked-text 门控。
- Verify: Debug 构建通过；纯逻辑测试全绿；一次 mutation 可单步撤销/重做；IME 组合输入不被规则改写。

### S2 — 智能 Return、列表层级与结构续写

- Goal: 优先解决用户示例及同类编辑器最高频的“输入下一项/退出结构”摩擦。
- Depends on: S1
- Refs: C1（`1.` 示例）、C2（接入点）、C5/C6（列表语义）、C10/C11/C12（产品行为参考）
- Sub-steps:
  - S2.1 Return 续写 `-/*/+` 无序列表、`N.`/`N)` 有序列表并递增实际编号，保留当前缩进。
  - S2.2 续写 `- [ ]`/`* [ ]` 等任务项，新项始终为未完成；已完成项不复制 `x`。
  - S2.3 空项 Return：嵌套层先 outdent，顶层移除 marker 退出；连续两次 Return 不残留空 marker。
  - S2.4 续写多层 blockquote；围栏代码块内只保留合理行缩进，不触发列表/引用误判。
  - S2.5 Tab/Shift-Tab（以及统一命令）支持当前行和多行选区 indent/outdent；必要时重编号受影响的有序列表。
- Verify: 自动化矩阵覆盖普通/嵌套/任务/引用/围栏/混合/空项；用户示例输入 Return 得到 `2. `；撤销一次恢复 Return 前状态。

### S3 — 统一格式命令、配对输入与智能粘贴

- Goal: 让触屏按钮、菜单和硬件快捷键共用可预测、幂等的 Markdown 变换。
- Depends on: S2
- Refs: C2（选区/菜单）、C5/C6（合法语法）、C10/C12（命令集合与交互）
- Sub-steps:
  - S3.1 行内 toggle：bold、italic、strikethrough、inline code、link；有选区包裹，无选区插入 pair 并置中光标。
  - S3.2 块级 toggle：H1–H6、blockquote、bullet/ordered/task list、fenced code；多行选区逐行或整体处理正确。
  - S3.3 明确的自动配对与跳过闭合符规则，避让转义、代码上下文、粘贴和 marked text。
  - S3.4 选中文本粘贴 http(s) URL → `[selection](url)`；非 URL、空选区和多行选区保持系统粘贴语义。
  - S3.5 统一命令的幂等、选区恢复和单步 undo/redo 测试；AI 定制 edit menu 继续可用。
- Verify: 每个命令在空选区/单行/多行/已格式化/Unicode 下均有测试；toggle 两次恢复原文；粘贴和 AI 菜单无回归。

### S4 — iPhone/iPad 命令入口与硬件键盘

- Goal: 根据设备和输入方式暴露同一套编辑命令，不让用户必须手敲所有 Markdown 标记。
- Depends on: S3
- Refs: C2（当前仅收键盘按钮）、C9（iPad 系统栏）、C10/C11/C12（主流入口与快捷键）
- Sub-steps:
  - S4.1 把现有单按钮 `UIToolbar` 拆为独立 `EditorKeyboardBar`，提供常用结构/格式、撤销重做和收键盘入口，支持横向/分组布局。
  - S4.2 iPad 使用 `UITextInputAssistantItem` 或等价系统接入，避免与系统建议、分屏和硬件键盘状态冲突。
  - S4.3 增加 `UIKeyCommand`/系统命令：bold、italic、link、code、标题、列表、任务、indent/outdent、移动行、查找和预览切换，并提供 discoverability title。
  - S4.4 所有新标签/辅助功能名称进入七语言 xcstrings；仅用 SF Symbols，完成 VoiceOver、Dynamic Type 和 44pt 命中区检查。
- Verify: iPhone 软件键盘、iPad 软件/浮动/硬件键盘矩阵通过；按住 Command 可发现快捷键；所有入口触发同一命令结果。

### S5 — raw Markdown 语法视觉与排版辅助

- Goal: 保留源码字符，但让结构和长行更易扫读，接近专业 Markdown 写作 App 的清晰度。
- Depends on: S1
- Refs: C2/C3（当前文本与块扫描）、C5（结构边界）、C8（TextKit 属性/性能）、C12（源码写作体验参考）
- Sub-steps:
  - S5.1 独立增量 `MarkdownSyntaxHighlighter`：标题、marker、强调、链接、代码、引用、任务和表格采用语义色/字重，raw 字符始终可见。
  - S5.2 `MarkdownParagraphStyler` 为列表/引用换行提供悬挂缩进；不插入空格、不改变文件内容。
  - S5.3 对高频输入做 50ms 合帧刷新；外部全文替换、AI 回填、深浅色/字号变化时安全重建视觉属性。
  - S5.4 保证着色不破坏 selectedRange、marked text、拼写/系统菜单、undo、滚动和现有光标行 AI 按钮。
- Verify: 100k 字符文档局部输入无可感停顿；属性与 raw text 分离；七类结构视觉正确，切主题/切文档/AI 回填后不 stale。

### S6 — 查找、大纲与 iPad 编辑工作区

- Goal: 补齐长文档导航，并让 iPad 宽屏同时承担源码编辑与结果确认。
- Depends on: S4, S5
- Refs: C2（编辑器）、C3（标题扫描基础）、C4（预览入口）、C13（大纲/并排预览参考）
- Sub-steps:
  - S6.1 接入系统查找/替换与硬件快捷键，匹配结果可见且不破坏当前选区/滚动。
  - S6.2 建立标题层级模型与 Preview/Edit 共用的大纲 UI；编辑态按 UTF-16 range 聚焦源码，预览态定位渲染标题。
  - S6.3 regular horizontal size class 提供可调整的编辑/预览并排布局；compact 保留现有 Preview/Edit 切换和滑动手势。
  - S6.4 并排模式实现编辑/预览双向比例滚动同步，并以大纲提供精确标题定位；单栏 Preview 也保留同一大纲入口，横滚表格/代码时不误触发页面切换。
- Verify: 10k+ 行文档可查找并由大纲跳转；iPad 横竖屏/分屏尺寸切换稳定；并排位置同步可预测且 iPhone 体验不变。

### S7 — 性能、回归、i18n 与发布验收

- Goal: 用自动化与设备矩阵证明新编辑器可靠，而非只覆盖演示路径。
- Depends on: S6
- Refs: C1（最终体验目标）、C5/C6（语法基线）
- Sub-steps:
  - S7.1 完成规则测试矩阵和 100k 字符性能基准，修复主线程长任务、重复全文扫描和 undo 分裂。
  - S7.2 七语言/无 emoji/stale key 审计；VoiceOver、Dynamic Type、Reduce Motion、深浅色检查。
  - S7.3 iPhone/iPad 走查：输入法、软件/硬件键盘、旋转/分屏、保存、切文档、Preview、分享、AI 选区与回填。
  - S7.4 逐条核对 summary Definition of Done，记录明确的已知限制与后续候选项。
- Verify: DoD 十项全部满足；Debug/Release 构建与测试通过；验收矩阵无阻断回归。

### S8 — 目录活动时间与稳定分组排序

- Goal: 让首页和所有子目录始终优先展示文件夹，并在每个分组中突出最近实际编辑的内容。
- Depends on: S6（可与仍由用户验收的 S7 并行实施）
- Refs: C14（排序语义）、C15（列表入口）、C16（枚举与节点模型）
- Sub-steps:
  - S8.1 定义可测试的活动时间/排序契约：文件用自身 `contentModificationDate`；文件夹递归取全部后代可见 Markdown 文件的最大值，无文件时回退目录时间。
  - S8.2 把递归元信息计算从 `FileBrowserView` 外移到独立模型服务；一次遍历排除隐藏项、Inbox、非 Markdown 与潜在目录循环，避免按每个文件夹重复扫描整棵子树。
  - S8.3 `FileStore.contents` 输出固定的文件夹组和文件组；组内按有效时间降序，时间相同时以本地化自然名称升序稳定兜底，并让行元数据显示同一有效时间。
  - S8.4 增加空目录、深层嵌套、同时间戳、不可读目录、大量节点和文件保存后刷新排序的纯逻辑/存储夹具测试。
- Verify: 目录夹具中分组与递归时间结果完全确定；最近编辑深层文件会把祖先文件夹提升到文件夹组顶部；大目录加载无明显主线程卡顿且现有过滤规则不回归。

### S9 — 取消拖放移动并恢复原生列表

- Goal: 根据用户的多轮真机失败反馈，完整移除文件拖放功能，保留目录排序与现有移动面板。
- Depends on: S8
- Refs: C14（用户取消决定）、C15（NavigationLink/滑动操作）、C16（移动面板语义）
- Sub-steps:
  - S9.1 删除拖动载荷、拖动源与预览。
  - S9.2 删除 List/子行放置目标、坐标测量与 targeted 反馈。
  - S9.3 删除 FileStore 中仅供拖放使用的校验 API 与专用测试。
  - S9.4 恢复 `BrowserNodeLabel` 纯展示和原生 List/swipe 样式。
  - S9.5 确认左滑移动面板、目录排序与刷新仍可用。
- Verify: Browser 不再包含拖放 API/状态/视觉层；目录与 FileStore 回归测试通过；Debug/Release 构建成功。

### S10 — 首页目录性能、回归与设备验收

- Goal: 证明递归排序与拖放移除不会破坏文件浏览、移动面板或现有跨设备交互。
- Depends on: S9（与仍由用户验收的编辑器 S7 无技术依赖）
- Refs: C14（最终验收矩阵）、C15/C16（现有行为）、C17（替代操作与辅助功能）
- Sub-steps:
  - S10.1 完成排序/递归时间/移动校验/重名/失败恢复测试，并对大目录递归扫描建立性能基线。
  - S10.2 回归新建、保存、导入、AI 新建、重命名、删除、移动面板、目录下钻与外部刷新，确认每次磁盘变化后顺序和元数据及时更新。
  - S10.3 完成 iPhone/iPad 全屏与分屏、触控/指针/VoiceOver、深浅色和七语言设备矩阵；核对轻点、滚动、左滑和移动面板。
  - S10.4 核对扩展后的 DoD 11–14，记录已知限制并完成 Debug/Release 构建与发布前收口。
- Verify: 扩展 DoD 全部满足；磁盘操作无数据丢失或越界移动；性能、自动化测试、Debug/Release 构建与设备验收均通过。

## Verification strategy

- Pure logic: XCTest/Swift Testing 表驱动用例，以 input + UTF-16 range + command → text + selection 对比。
- UIKit integration: mutation/undo/marked-text/selection 的小范围集成测试，避免只测正则。
- Performance: 10k/100k 字符夹具，分别测局部换行规则、命令变换和增量高亮。
- Manual matrix: iPhone 紧凑宽度、iPad 全屏/二分之一/三分之一、软件键盘/浮动键盘/硬件键盘、七种语言输入。
- Regression: 保存与切换、横向滑动、Web Preview、AI 选区 range 回填、外部文件导入和分享。
- Browser pure logic: 临时目录夹具验证递归有效时间、文件夹/文件分组、稳定次级排序、过滤和移动合法性。
- Browser interaction: 系统按住拖动、NavigationLink 轻点、List 滚动/滑动操作、放置 targeted 状态与取消/失败路径组合验收。
- Browser performance: 深层/宽层目录夹具记录单次枚举耗时，防止为每个文件夹重复递归导致平方级扫描。
