# Plan Summary — Markdown App 迭代二期（体验增强 + 上架 + iCloud）

## Goal
在已交付的 MVP（原生 SwiftUI iOS Markdown 预览/编辑 App，见 `archive/ios-markdown-mvp-core/`）之上，做一轮**交互体验增强**，并完成**App Store 上架**与后续 **iCloud 同步**。
从（From）：MVP 核心闭环已跑通（目录管理、WebView 预览、原生编辑、两条导入路径、快速切换器、液态玻璃、图标/显示名）。
到（To）：更顺手的预览/分享/导入体验 + 最终品牌命名 + 上架 TestFlight/审核 +（后续）多设备 iCloud 同步。

## Scope
- In（本期）：
  - 最终定名并改显示名（拟 "Markdown Lite" / 或备选）
  - 预览里点外部链接：不覆盖当前预览，改为 **App 内 Safari 模态**（SFSafariViewController）
  - 导入选目录中间页支持**当场新建文件夹**
  - 预览态右上角**分享**：长截图 / 源文件 .md / 源内容 三选一
  - 编辑态右上角 **AI 辅助编辑** 按钮（先占位，交互待定）
  - App Store 上架准备（原 MVP 计划 S8）
- Out / 后续：
  - iCloud 多设备同步（S7，MVP 后再做）
  - AI 辅助编辑的实际能力（本期仅占位）
  - 编辑器语法高亮、数学公式、mermaid

## Constraints / Coexistence
- 延续 MVP 技术栈与约定：SwiftUI 为主，WKWebView/编辑器用 Representable 桥接；最低 iOS 18，液态玻璃 iOS 26+ 渐进增强。
- 预览仍**离线**（本地打包 marked + github-markdown-css）；外链走 SFSafariViewController（用户点击才联网，不影响离线渲染与审核）。
- 存储仍为本地 Documents（Files 可见）；iCloud 留到 S7。
- 遵循 CLAUDE.md：文案无 emoji、图标用 SF Symbols、单一职责、可复用封装。

## Definition of Done（本期完成信号）
1. 桌面图标名 / 文件 App 目录名为最终品牌名。
2. 预览点外链 → App 内 Safari 模态打开，当前预览不被覆盖，关闭后回到原预览。
3. 导入/分享保存的选目录页可新建文件夹并导入进去。
4. 预览分享按钮三种模式都能唤起系统分享面板；长截图含超出屏幕的完整内容。
5. 编辑态有 AI 辅助编辑占位按钮，点击有反馈、不崩。
6. 成功提交 App Store 审核（TestFlight 可安装即里程碑）。

## Key Decisions (locked)
| Decision | Choice | Why |
|---|---|---|
| 外链打开方式 | SFSafariViewController（App 内 Safari 模态） | 原生、带地址栏/前进后退/完成，不覆盖预览、不离开 App |
| 归档 | 原 MVP 计划归档到 archive/ios-markdown-mvp-core | 保留已交付记录，本期为其续作 |
| 上架/iCloud | 承接自原计划 S8/S9，本期作为 S6/S7 | 顺延未完成的收尾与后续 |
| App 名称 | 待定（Markdown Lite / Featherdown / Hashmark…） | 用户拍板；商店主名需全球唯一，S6 处理 |
