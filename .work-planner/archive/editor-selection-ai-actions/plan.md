# Plan — 编辑器选区 AI 快捷入口 + 块级快速选中

## Target architecture
```
Features/Editor/
├── EditorView.swift            # 对外壳不变（EditorView(text:)），内部改用下面的封装
├── MarkdownTextView.swift      # 新：UIViewRepresentable 包 UITextView（双向绑定、选区回调、gutter 宿主）
├── EditorBlockScanner.swift    # 新：Markdown 源码 → 结构块+行范围（纯逻辑，可单测）
└── EditorGutterOverlay.swift   # 新：左侧极简 gutter 覆盖层（块标记 + 点选）

Features/Document/
└── DocumentView.swift          # 改：新增「选区 AI 润色」应用路径（按 range 回填）

Models/  复用 AIAction / AILaunch；AI 会话复用 AIWritingView（均不改核心）
```

设计要点：
- `MarkdownTextView` 是唯一「怎么显示/如何拿选区与布局」的地方；`EditorView` 退化为薄封装，
  `DocumentView` 只多接一条 AI 回填闭包。版本差异（若有）收敛在 `MarkdownTextView`。
- 选区 AI 与 gutter 选块**共用同一个气泡菜单**：AI 项在菜单里加一次，两条入口都能触达。
- 块扫描器纯函数、无 UIKit 依赖，便于单测；布局定位（行范围→rect）单独一层，隔离 TextKit 细节。

## Dependency graph
```
S1 ──┬──> S2 ──┐
     └──> S3 ──┴──> S4
```
（S2 选区 AI 与 S3 gutter 都依赖 S1 的 UITextView 底座；二者可并行，但 S3.4「点标记弹含 AI 的菜单」
需要 S2 已把 AI 项加进菜单——故 S4 验收依赖 S2、S3 皆完成。）

## Phases / Steps

### S1 — 编辑器底层：TextEditor → UITextView 封装
- Goal: `EditorView` 内部换成 `UIViewRepresentable(UITextView)`，行为与现 `TextEditor` 逐点对齐，对外接口不变。
- Depends on: none
- Refs: C2（现状与演进注释）、C6（Representable 参照）、C7（字体/常量）
- Resolves: 「UITextView 能否复刻现观感」假设
- Sub-steps:
  - S1.1 新建 `MarkdownTextView`：`UITextView` + Coordinator；配置等宽字体（Theme.mono 对应 UIFont）、
    `autocorrectionType=.no`、`autocapitalizationType=.none`、透明背景、左右 padding（`textContainerInset`/
    `lineFragmentPadding` 对齐现 12pt 观感）、`smartQuotes/Dashes` 关闭（Markdown 源码）。
  - S1.2 双向绑定：`textViewDidChange` 回写 `@Binding`；`updateUIView` 仅在外部 text 与内部不一致时赋值，
    保护 `selectedRange`/滚动位置，避免更新回环与光标跳动。
  - S1.3 `EditorView` 内部改用 `MarkdownTextView`；回归走查：输入、光标、滚动、切换预览/编辑、保存脏检查、
    左右滑动切换（`horizontalSwitch` 不被 UITextView 手势吞掉）、键盘弹出/收起观感与原一致。
- Verify: 编辑模式日常使用与原 TextEditor 无可感差异；DocumentView 未改仍编译通过、切换与保存正常。

### S2 — 选区 AI 润色快捷入口
- Goal: 选区气泡菜单加「AI」项，接现有润色链路，结果只回填选中 range。
- Depends on: S1
- Refs: C3（DocumentView 接线/回填）、C4（.polish 语义）、C5（AILaunch/AIWritingView）、C8（i18n）
- Sub-steps:
  - S2.1 在 `MarkdownTextView` 实现 `editMenuForTextIn`（iOS 16+）：向 suggestedActions 追加一个「AI」
    `UIAction`（`title` 本地化、`image = UIImage(systemName: "wand.and.stars")`，无 emoji）；仅在有非空选区时出现。
  - S2.2 上抛选区意图：`MarkdownTextView` 暴露 `onRequestAIRefine(selectedText, selectedRange)` 闭包；
    `EditorView` 透传；`DocumentView` 收到后走 `AILaunch(config, .polish)` + `aiConfigGate` + `AIWritingView`，
    `context = selectedText`。复用现有 sheet 流程，不新造门槛。
  - S2.3 按 range 回填：新增 `applyAIToSelection(range:result:)`——用 `result` 替换 `text` 中该 range 段
    （其余不动），落盘；对「流程期间文本已变/range 越界」做兜底（失败则回退整段追加或提示，不覆盖错内容）。
  - S2.4 i18n：菜单标题等新文案进 `Localizable.xcstrings` 七语言，无 emoji；自查无 stale key。
- Verify: 选中一段 → 菜单出现 AI → 润色会话 context 是选中文本 → 接受后仅该段被替换、落盘正确。

### S3 — 块级快速选中（方案 A：左侧极简 gutter）
- Goal: 左缘对齐结构块起始的不显眼标记，点它选中整块并弹出含 AI 的菜单，不干扰主内容与编辑。
- Depends on: S1
- Refs: C1（方案 A 定义/「不显眼」诉求）、C7（Theme/Haptics）
- Sub-steps:
  - S3.1 `EditorBlockScanner`：纯函数，输入源码文本，输出结构块列表（type: heading/codeFence/table/blockquote，
    起止字符/行范围）。行级扫描，正确处理 fenced code（``` 内不误判）。附最小单测思路。
  - S3.2 行范围 → 屏幕 rect：在 `MarkdownTextView` 用 TextKit（`layoutManager.boundingRect(forGlyphRange:)`
    或 TextKit2 等价）把每个块首行换算成 gutter 对齐的 y。随 `scrollViewDidScroll`/内容变化更新。
  - S3.3 `EditorGutterOverlay`：左缘窄覆盖层，块首处画很淡的小标记（短竖条/小图标，样式用 Theme，
    深浅色适配）。命中区略大于视觉、但**只在 gutter 窄带内**，不吃正文点按/选择/滑动切换手势。
  - S3.4 点标记 → `textView.selectedRange = 块范围` 并 `becomeFirstResponder` 弹出气泡菜单（已含 S2 的 AI）；
    `Haptics` 反馈。
  - S3.5 性能与边界：块扫描与 rect 重算在编辑/滚动时节流（防抖，避免每字符重算全文）；空文档/超大文档
    不卡顿；标记不与选区放大镜/系统把手打架。
- Verify: 滚动时标记稳定对齐各结构块首；点标记整块被选中并弹菜单；正常编辑/选择/滑动切换不受影响。

### S4 — 验收 + 收尾
- Goal: 两功能端到端走查、i18n 复核、对照 DoD。
- Depends on: S2, S3
- Refs: C1（DoD 出处）、C8（i18n）
- Sub-steps:
  - S4.1 真机/模拟器走查：S1 回归 + 选区 AI 全链路 + gutter 选块全链路。
  - S4.2 i18n 复核：新文案七语言齐、无 emoji、无 stale。
  - S4.3 逐条对照 summary 的 Definition of Done。
- Verify: DoD 七项全部满足；无回归。
