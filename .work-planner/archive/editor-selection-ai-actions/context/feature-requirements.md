# 原始需求（用户 2026-07-21 提出）

## 背景
Editor 页面「编辑模式」目前是纯 SwiftUI `TextEditor`
（`Features/Editor/EditorView.swift`，仅 26 行，受控组件只接 `@Binding var text`）。
本次要在编辑模式上加两个提升选区易用性的能力。

## 第一点：选中文字 → 系统气泡菜单加「AI」按钮
- 选中 Markdown 文本后，系统弹出的选区气泡菜单（复制/剪切/粘贴那一排）里加一个「AI」项。
- 点它对**选中的内容**做润色/修改/调整——相当于现有 AI 入口的「润色」功能的快捷入口。
- 说白了就是把现有 `.polish` 动作接到选区上，省去手动进 AI 面板。

## 第二点：块级快速选中（用户明确说「没想好怎么提升」，让我给方案）
- 现状：要选中某个独立块（`##` / `###` section、代码块、table、引用 等）只能手动拖选。
- 诉求：滚动到某个块时，出现一个**不太显眼**的操作，能**一键选中整块**，
  但**不影响编辑器现在的主内容查看与编辑**。

## 已定方向（本次会话拍板）
1. 两个功能的共同前提：把 `EditorView` 内部从 `TextEditor` 换成 `UIViewRepresentable`
   包 `UITextView`（对外接口不变，仍是 `@Binding var text`；`DocumentView` 不动）。
   —— 这也是 EditorView 注释里早就预留的演进方向。
   原因：SwiftUI `TextEditor` 无法自定义选区气泡菜单，也拿不到文本布局 rect。
2. 第二点交互采用**方案 A**：左侧极简 gutter 标记——结构块起始行对齐一个很淡的小标记，
   点它选中整块并弹出（已带 AI 的）气泡菜单。第一点第二点在此合流。
3. 用 phased-work-planner 分阶段推进（本计划）。

## 复用与约束
- 复用现有 AI 链路：`AILaunch` + `AIWritingView`，`AIAction.polish`，把选中文本当 `context`。
- 现 `DocumentView.applyAI` 对 `.polish` 是整篇替换（`text = result`）；
  选区润色必须**只替换选中的 range**，需新增按 range 回填路径。
- 遵循 CLAUDE.md：单一职责/DRY/feature 分层/视图轻逻辑外移/版本差异收敛；
  **文案禁 emoji、图标用 SF Symbols**；新文案走 i18n（简中/英/繁中/日/韩/德/俄）。
- 最低 iOS 18；`editMenuForTextIn`（iOS 16+）可用。
- 无 Swift 侧现成 Markdown 块解析（预览走 web/markdown-it），块扫描器需新写（轻量、行级）。

## 参照实现（仓库内已有）
- `Features/Preview/WebPreviewView.swift`：`UIViewRepresentable` 包 WKWebView 的模式参照。
- `Features/AI/CameraPicker.swift`：`UIViewControllerRepresentable` 模式参照。
- `DesignSystem/Theme.swift`：spacing/cornerRadius/aiGradient 等设计常量。
- `DesignSystem/Haptics.swift`：触觉反馈。
