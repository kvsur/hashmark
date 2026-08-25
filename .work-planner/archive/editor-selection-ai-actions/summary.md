# Plan Summary — 编辑器选区 AI 快捷入口 + 块级快速选中

## Goal
提升 Editor「编辑模式」的选区易用性，做两件事：

1. **选区 AI 润色快捷入口**：选中 Markdown 文本后，系统气泡菜单里多一个「AI」项，
   点它直接对选中内容走现有 `.polish`（润色）链路，结果只回填选中的那段。
2. **块级快速选中（方案 A：左侧极简 gutter）**：滚动到结构块（标题/代码块/表格/引用）时，
   左缘对齐一个不显眼的小标记，点它一键选中整块并弹出（已带 AI 的）气泡菜单。

From → To：
- From：`EditorView` 是裸 `TextEditor(text:)`，无法自定义选区菜单、拿不到布局 rect；
  选区润色只能手动进 AI 面板且只支持整篇；块选中只能手动拖选。
- To：`EditorView` 内部换成 `UITextView` 封装（对外接口不变）；选区菜单含 AI 项、按 range 回填；
  左侧 gutter 一键选块并复用同一菜单。

## Scope
- **In**：
  - `EditorView` 内部 `TextEditor` → `UIViewRepresentable(UITextView)`，行为对齐现状（等宽字体、
    无自动更正/大写、隐藏背景、左右 padding、双向绑定、切换/保存不回归）。
  - 选区气泡菜单加「AI」项（`editMenuForTextIn`），接现有 `AILaunch`+`AIWritingView`（`.polish`），
    context=选中文本，接受后**按 range 替换**并落盘。
  - 左侧极简 gutter：Markdown 源码 → 结构块+行范围扫描器；行范围 → UITextView 布局 rect 定位；
    淡标记覆盖层随滚动/编辑同步；点标记选中整块 + 弹菜单 + 触觉反馈。
  - 新文案 i18n 补齐七语言，无 emoji，图标用 SF Symbols。
- **Out（留 TODO 或后续迭代）**：
  - 预览模式的块级操作（本次只做编辑模式）。
  - 选区 AI 的续写/整理/自定义动作入口（本次只接 `.polish`；结构上可扩展）。
  - 富文本渲染式编辑器 / 语法高亮（仍是纯源码等宽编辑，不改这一定位）。
  - 查找替换、大文档虚拟化等 UITextView 才有意义的能力（本次不做，仅打好底座）。

## Constraints / Coexistence
- 遵循 CLAUDE.md：单一职责、DRY、feature 分层、视图轻逻辑外移、版本差异收敛在封装层、
  **文案禁 emoji、图标用 SF Symbols**、UI 文案与 prompt 一律走 i18n。
- **对外接口硬约束**：`EditorView` 对外仍是 `EditorView(text: $text)`，`DocumentView` 不改结构
  （除新增「选区 AI 回填」这条应用路径）。切换/保存/滑动切换/键盘行为不得回归。
- 复用现有 AI 链路，不新造第二套会话/配置门槛流程（`AILaunch`/`AIConfigGate`/`AIWritingView`）。
- 最低 iOS 18；`editMenuForTextIn`（iOS 16+）与 TextKit 布局在 iOS 18 稳定可用。
- 无 Swift 侧现成 Markdown 块解析（预览走 web）；块扫描器新写，保持轻量、行级、可单测。

## Definition of Done
1. 编辑模式改用 UITextView 封装后，输入/光标/滚动/切换预览/保存/滑动切换/键盘全部与原 TextEditor 观感一致，无可感回归。
2. 选中文本后气泡菜单出现「AI」项（无 emoji、用 SF Symbol）；点它进入现有润色会话，context 为选中文本。
3. 接受润色结果后，**只替换选中的那段 range**、其余正文不动，并正确落盘；选区在流程中变动有兜底。
4. 左侧 gutter 在标题/代码块/表格/引用的起始处显示不显眼标记，随滚动/编辑保持对齐；不遮挡主内容、不干扰正常点按/选择/编辑手势。
5. 点 gutter 标记选中对应整块并弹出含 AI 的气泡菜单；有触觉反馈。
6. 新增文案进 `Localizable.xcstrings` 七语言（简中/英/繁中/日/韩/德/俄），无 emoji、无 stale key。
7. 大文档与频繁编辑下 gutter 重算不卡顿（有节流），深浅色适配正常。

## Context & References
| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 本次需求原文 + 已定方向（用户 2026-07-21） | context/feature-requirements.md | 两点诉求、方案 A 决策、复用约束的权威出处；贯穿 S1–S4 |
| C2 | 现 EditorView（裸 TextEditor，含演进注释） | MarkdownApp/MarkdownApp/Features/Editor/EditorView.swift | S1 要对齐/替换的现状 |
| C3 | DocumentView（承载编辑/预览、AI 接线、applyAI） | MarkdownApp/MarkdownApp/Features/Document/DocumentView.swift | S2 回填路径、AI 链路接线点 |
| C4 | AIAction（.polish 角色/输出纪律/refine） | MarkdownApp/MarkdownApp/Models/AIAction.swift | S2 复用润色动作与 context 语义 |
| C5 | AILaunch + AIWritingView（会话 UI 与门槛） | MarkdownApp/MarkdownApp/Features/AI/AILaunch.swift, Features/AI/AIWritingView.swift | S2 复用的现成会话链路 |
| C6 | WebPreviewView（UIViewRepresentable 包 WKWebView 参照） | MarkdownApp/MarkdownApp/Features/Preview/WebPreviewView.swift | S1 Representable 模式参照 |
| C7 | Theme / Haptics（设计常量与触觉） | MarkdownApp/MarkdownApp/DesignSystem/Theme.swift, DesignSystem/Haptics.swift | S3 gutter 样式与反馈 |
| C8 | Localizable.xcstrings（本地化目录，七语言） | MarkdownApp/MarkdownApp/Resources/Localizable.xcstrings | S2/S3 新文案补齐 |

## Assumptions and Open Questions
| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| UITextView 能完全复刻现 TextEditor 的观感（字体/内边距/背景/滚动/键盘） | assumed | 决定 S1 是否零回归 | S1.3 回归走查 |
| 结构块只覆盖 标题/代码块(fenced)/表格/引用 四类即够用 | assumed | 决定块扫描器范围与 gutter 密度 | S3.1 实现时，若列表/分割线也需要再扩 |
| 选区 AI 本次只接 `.polish`（不做续写/整理/自定义入口） | confirmed | 控制范围，避免菜单过载 | 见 Scope Out |
| gutter 标记的视觉形态（短竖条 vs 小图标）与位置（贴最左 vs 行号位） | open | 影响「不显眼」的达成度 | S3.3 出首版后与用户对样式定稿 |

## Key Decisions (locked)
| Decision | Choice | Why |
|---|---|---|
| 编辑器底层 | TextEditor → UIViewRepresentable(UITextView) | 选区菜单与布局 rect 都需 UITextView；注释早已预留 |
| 第二点交互 | 方案 A：左侧极简 gutter 标记 | 最不显眼、且与第一点的气泡菜单合流 |
| 选区润色回填 | 只替换选中 range，非整篇替换 | 选区语义要求；整篇替换会破坏未选中内容 |
| AI 会话链路 | 复用 AILaunch/AIWritingView/.polish | DRY，不造第二套 |
