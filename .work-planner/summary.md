# Plan Summary — iOS Markdown 预览/编辑 App

## Goal
从零构建一款**原生 SwiftUI iOS/iPadOS App**，用于 Markdown 文档的预览与编辑。
从（From）：完全空目录，开发者是资深 Web 前端但**零 iOS 开发经验**，机器上连 Xcode 都没装。
到（To）：一个能在自己 iOS 26 真机上跑、支持本地/分享导入、目录管理、WebView 预览（GitHub 主题）、原生编辑、液态玻璃视觉，并**上架 App Store** 的应用。

## Scope
- In（MVP 范围内）：
  - 本地文件系统选择 `.md` 文档预览（`.fileImporter`）
  - 其他 App 通过分享/「打开方式」把 `.md` 导入本 App（含选择目标目录的中间步骤，默认根目录）
  - App 内文档的**无限级目录**管理（新建/重命名/删除/移动 文件夹与文档）
  - 新建 Markdown 文档，存储在 App 本地目录（通过「文件」App 可见）
  - WebView 预览，GitHub Markdown 主题，标准 GFM
  - 原生编辑器（纯文本 + 等宽字体），预览/编辑模式切换（右上角 button group）
  - Light/Dark 主题适配
  - 液态玻璃：iOS 26+ 用系统原生 Liquid Glass，iOS 17–25 降级为材质模糊
  - App Store 上架（签名、证书、隐私清单、审核提交）
- Out（本期不做，已规划为后续阶段）：
  - iCloud 多设备同步（S9，MVP 后再加）
  - 编辑器语法高亮 / 工具栏
  - 数学公式（LaTeX）、mermaid 图表
  - macOS / iPad 专属分栏布局的深度优化（iPad 先保证可用）

## Constraints / Coexistence
- 平台：仅 iPhone/iPad（iOS/iPadOS），暂不做 macOS。
- 最低部署版本：**iOS 17.0**。液态玻璃通过 `if #available(iOS 26, *)` 分支，低版本优雅降级，不因新 API 崩溃。
- 技术栈：原生 Swift + **SwiftUI**（非 UIKit 主体，必要处用 `UIViewRepresentable` 桥接 WKWebView / UITextView）。
- 预览渲染：WebView 内 **本地打包** 的 JS（marked/markdown-it）+ github-markdown-css，**不联网**（离线可用、便于 App Store 审核、无隐私风险）。
- 存储：MVP 用 App 本地 Documents 目录，通过 Info.plist 暴露给系统「文件」App；iCloud 容器留到 S9。
- 分发：需要**付费 Apple Developer 账号**（99 美元/年），S8 处理。
- 测试真机为 iOS 26，可直接验证原生液态玻璃。

## Definition of Done（MVP 完成信号，可验证）
1. App 能在 iOS 26 真机安装运行，不崩溃。
2. 能新建目录（多级嵌套）与文档，重启后仍在，且在系统「文件」App 中可见。
3. 从「文件」App 或其他 App 选一个 `.md` → 能在本 App 预览为 GitHub 风格。
4. 其他 App 分享 `.md` → 出现选择目标目录的中间页 → 确认后导入并进入预览。
5. 任一文档可在右上角切换到编辑模式，改动能保存并在预览端反映。
6. Light/Dark 切换下预览与界面均正确适配。
7. iOS 26 上呈现液态玻璃；模拟器降级到 iOS 17 不崩溃、观感可接受。
8. 成功提交 App Store 审核（TestFlight 可安装即视为里程碑达成）。

## Key Decisions (locked)
| Decision | Choice | Why |
|---|---|---|
| UI 框架 | SwiftUI 为主 | 现代、代码少、对 Liquid Glass 支持最好；WebView/编辑器处用 Representable 桥接 |
| 最低系统 | iOS 17.0 | 兼顾旧设备；Liquid Glass 用可用性分支渐进增强 |
| 预览方案 | WKWebView + 本地 marked + github-markdown-css | 满足「GitHub 主题 + WebView」诉求，离线、审核友好 |
| Markdown 范围 | 标准 GFM | 覆盖日常笔记；数学/图表列为后续 |
| 编辑器 | 原生纯文本 + 等宽字体 | 先跑通、可靠；语法高亮作为增强阶段 |
| 存储 | 本地 Documents 目录（Files 可见） | MVP 最简；iCloud 同步延后到 S9 |
| 导入方式 | 注册文档类型(UTI) + `.onOpenURL` | 比 Share Extension 简单，`.md` 会出现在分享/打开方式里 |
| 分发 | App Store | 用户明确要上架 |
