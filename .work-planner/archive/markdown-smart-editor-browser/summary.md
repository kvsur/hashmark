# Plan Summary

## Goal

把当前仅提供基础 `UITextView` 输入能力的 Markdown 源码编辑器，升级为适合 iPhone/iPad 的“源码优先智能编辑器”：保持 `.md` 原文、文件兼容性和 Preview/Edit 双模式，同时补齐主流编辑器中降低机械输入成本的智能续写、结构化编辑、格式命令、键盘入口、源码视觉辅助与导航能力。

在编辑体验完成后，继续优化首页文件目录：以“文件夹优先、组内按最近活动排序”提升可扫读性，并保留现有稳定的移动面板。文件拖入文件夹经多轮真机验证仍失败，已按用户决定完整移除。

## Scope

- In:
  - 列表、任务列表、引用和代码块等结构的智能换行、退出、缩进与反缩进。
  - 行内/块级 Markdown 格式切换、配对符号、选中文本粘贴 URL 转链接。
  - iPhone 软件键盘工具栏、iPad 键盘快捷栏与硬件键盘命令。
  - 保留 raw Markdown 的增量语法着色、列表悬挂缩进、当前结构反馈。
  - 文档内查找、标题大纲跳转，以及 iPad 宽屏编辑/预览协作布局。
  - UTF-16 选区、中文/日文/韩文输入法 marked text、撤销栈、大文档性能和七语言 i18n。
  - 首页文件夹/文件分组，以及基于文件实际修改时间的稳定降序排序。
- Out:
  - Notion 式 WYSIWYG/块数据库编辑器和 Markdown AST 双向序列化重写。
  - 实时协作、评论、插件系统、云同步或底层文件存储架构替换。
  - 文件夹拖动、任意列表拖放排序、自定义排序模式或跨 App 拖放导出。
  - 单文件拖入文件夹；该功能因真机可用性不达标已取消，文件移动继续使用现有移动面板。
  - GFM/CommonMark 之外的私有 Markdown 方言和富媒体块模型。
  - AI 会话能力扩展；本计划只保证现有 AI 选区入口不回归。

## Constraints / Coexistence

- 最低 iOS/iPadOS 18；iOS 26+ 液态玻璃仍通过现有封装启用。
- `DocumentView.text` 与磁盘中的纯 Markdown 始终是唯一内容源；视觉属性不得污染保存文本。
- 延续 `EditorView → MarkdownTextView(UITextView)` 架构，先基于 TextKit 2 增强，不引入第三方编辑器内核。
- 编辑规则必须收敛到纯逻辑类型，`UIViewRepresentable`/Coordinator 只桥接 UIKit 事件和应用变更。
- 所有变更以 UTF-16 `NSRange` 对齐 UIKit；输入法处于 marked-text 组合阶段时不得擅自改写内容。
- 新 UI 文案进入 `Localizable.xcstrings`，补齐简中/英/繁中/日/韩/德/俄；图标使用 SF Symbols，不使用 emoji。
- 每个智能变更应形成单次可撤销事务，并尽量保持选区、光标和滚动位置稳定。

## Definition of Done

1. 输入有序、无序、任务列表后按 Return，会保持缩进并生成正确的下一项；有序列表从当前数字递增。
2. 空列表项按 Return 能自然退出；嵌套列表先降级再退出；引用和围栏代码块换行符合上下文，代码块内不误触发列表规则。
3. Tab/Shift-Tab 或对应移动端按钮可对当前行/多行选区缩进、反缩进，并正确处理嵌套列表与后续编号。
4. 加粗、斜体、删除线、行内代码、链接、标题、引用、列表、任务和代码围栏均可通过统一命令切换；重复执行可撤销格式而非叠加标记。
5. 选中文本后粘贴 URL 可生成 Markdown 链接；配对标记和闭合符行为不干扰 IME、已有闭合符或普通粘贴。
6. iPhone 软件键盘、iPad 键盘快捷栏与硬件键盘均有适配入口；硬件快捷键可被系统发现，所有标签完成七语言本地化。
7. 源码标记始终可见但具备增量语法着色与列表悬挂缩进；编辑、选区、AI 回填和切文档后样式能正确恢复。
8. 支持系统查找/替换和标题大纲跳转；iPad 常规宽度可并排编辑与预览，紧凑宽度保留现有切换方式。
9. 每条纯编辑规则有自动化测试，覆盖 Unicode/UTF-16、嵌套结构、撤销和边界；100k 字符基准文档中局部键入无明显主线程卡顿。
10. 现有保存、滑动切换、预览、分享、AI 选区/回填链路无回归，并完成 iPhone/iPad 真机或模拟器验收矩阵。
11. 首页始终先显示文件夹、后显示文件；两组分别按有效更新时间降序排列，同时间戳以自然名称稳定排序。
12. 文件夹有效更新时间取全部后代 Markdown 文件的最新修改时间；无后代 Markdown 文件时回退到目录自身时间，隐藏项、Inbox 和非 Markdown 文件不参与计算。
13. 浏览器不包含文件拖动源、放置目标、目标高亮或隐式几何测量；轻点导航、List 滚动和左滑操作保持原生行为与样式。
14. 现有移动面板仍支持文件/文件夹移动、重名自动编号和失败提示；导航、删除、重命名与辅助功能操作无回归。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 用户原始需求与方向确认 | context/editor-experience-requirements.md | 产品目标、示例与源码优先决策 |
| C2 | 当前 UITextView 编辑器桥 | MarkdownApp/MarkdownApp/Features/Editor/MarkdownTextView.swift | UIKit 接入点、选区与 AI 现状 |
| C3 | 当前 Markdown 结构扫描器 | MarkdownApp/MarkdownApp/Features/Editor/EditorBlockScanner.swift | 标题/块边界复用与后续职责拆分 |
| C4 | 当前 Markdown 预览 | MarkdownApp/MarkdownApp/Features/Preview/MarkdownPreviewView.swift | iPad 并排预览与滚动协作入口 |
| C5 | CommonMark 规范 | https://spec.commonmark.org/current/ | 列表标记、缩进和块结构基线 |
| C6 | GitHub Flavored Markdown 规范 | https://github.github.com/gfm/ | 任务列表、表格、删除线与 autolink 基线 |
| C7 | Apple `UITextViewDelegate` | https://developer.apple.com/documentation/uikit/uitextviewdelegate | 输入拦截、变化与选区回调边界 |
| C8 | Apple TextKit 2 | https://developer.apple.com/videos/play/wwdc2022/10090/ | iOS 文本布局、属性与性能依据 |
| C9 | Apple `UITextInputAssistantItem` | https://developer.apple.com/documentation/uikit/uitextinputassistantitem | iPad 键盘快捷栏的系统接入方式 |
| C10 | Notion keyboard/Markdown shortcuts | https://www.notion.com/help/keyboard-shortcuts | Markdown 快捷输入、Tab 层级和格式命令参考 |
| C11 | Bear lists and todos | https://bear.app/faq/lists-and-todos-in-bear/ | iOS 格式栏、列表续写/退出/重排参考 |
| C12 | iA Writer shortcuts/settings | https://ia.net/writer/support/basics/shortcuts?tab=keyboard-shortcuts-iphone | iOS/iPad 源码编辑、硬件快捷键和工具栏参考 |
| C13 | VS Code Markdown editing | https://code.visualstudio.com/docs/languages/markdown | 大纲、片段、并排预览与专业源码编辑参考 |
| C14 | 首页文件目录交互需求 | context/home-file-browser-requirements.md | 分组排序、文件夹有效更新时间、拖放边界与验收标准 |
| C15 | 当前首页文件浏览器 | MarkdownApp/MarkdownApp/Features/Browser/FileBrowserView.swift | 列表、NavigationLink、滑动操作、移动面板与拖放接入点 |
| C16 | 当前文件存储与节点模型 | MarkdownApp/MarkdownApp/Models/FileStore.swift；MarkdownApp/MarkdownApp/Models/DocumentNode.swift | 目录枚举、修改时间、稳定排序和磁盘移动语义 |
| C17 | Apple Human Interface Guidelines：Drag and drop | https://developer.apple.com/design/human-interface-guidelines/drag-and-drop | 系统拖放手势、移动/复制预期与替代操作入口 |
| C18 | Apple SwiftUI：Adopting drag and drop / `onDrop` | https://developer.apple.com/documentation/swiftui/adopting-drag-and-drop-using-swiftui | 拖动源位置与基于 `NSItemProvider` / `DropDelegate` 的系统放置实现基线 |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| 智能换行与列表行为默认开启 | assumed | 它们是基础编辑预期；过早增加设置会扩大 UI/i18n | S2 真机验收；若出现强争议再增加开关 |
| 自动配对标记默认仅处理明确选择或空选区 | assumed | 降低“编辑器自作主张”的干扰 | S3.3 交互测试 |
| GFM/CommonMark 为唯一规则基线 | confirmed | 与当前 marked GFM 预览和可移植 `.md` 一致 | 已锁定 |
| 源码标记继续可见，不做隐藏语法字符 | confirmed | 用户接受“源码优先”建议，避免 WYSIWYG 双模型 | 已锁定 |
| iPad 宽屏提供并排编辑/预览，iPhone 保持切换 | assumed | 利用 iPad 空间，同时避免压缩 iPhone 编辑区 | S6 原型验收 |
| 暂不引入第三方编辑器内核 | assumed | 当前 UITextView/TextKit 2 足以覆盖首轮目标，风险更低 | S5 性能基准后复核 |
| 文件夹活动时间递归查看全部后代 Markdown 文件 | assumed | “根据其中的文件决定”应反映嵌套目录中的真实最近编辑活动 | S8.1 数据夹具验收；若用户只希望直接子项则调整 |
| 文件拖入文件夹 | cancelled | 多轮真机验收均回弹且未移动文件，用户明确要求移除 | S9 已删除实现与测试 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| 编辑模型 | 源码优先的智能纯文本编辑器 | 保留 Markdown 可移植性与现有文件/AI/预览链路 |
| 内容真相源 | `String` raw Markdown | 属性与 UI 状态不得写回文件 |
| 规则实现 | 纯逻辑 Editing Engine + UIKit 薄桥接 | 可单测、可复用、避免 Coordinator 膨胀 |
| 标准 | CommonMark + 当前 GFM 能力 | 与预览一致并覆盖任务列表等主流语法 |
| 发布方式 | 按阶段增量交付，每阶段均可独立验收 | 先解决高频输入摩擦，再增加视觉与 iPad 能力 |
| 首页排序 | 文件夹、文件分组固定；组内按有效更新时间降序、名称稳定兜底 | 保留目录层次感，同时突出最近活动内容且避免同时间戳抖动 |
| 文件移动 | 仅保留现有移动面板；拖放功能已移除 | 真机可用性不达标，优先恢复稳定且可预测的浏览体验 |
