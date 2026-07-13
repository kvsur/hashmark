# Plan Summary — 设置页（主题 / 语言 / AI 配置 / 关于）

## Goal
在主页新增设置入口与设置页，让用户可配置外观主题、（占位）语言、AI API 参数与查看开发者信息。
从（From）：App 无任何用户偏好设置，主题固定跟随系统，无 AI 配置存储。
到（To）：主页左上角设置按钮进入设置页；可切换 System/Light/Dark 主题并全局生效且持久化；有语言切换占位入口；可编辑并本地保存 AI API 配置（BaseURL/Model/APIKey/响应格式）；可查看开发者联系方式。

## Scope
- In（本期）：
  - 主页左上角设置按钮 → 设置页
  - 主题：System / Light / Dark（默认跟随系统；本地有存储则优先用存储），全局即时生效 + 持久化
  - 语言：仅占位按钮（具体多语言以后迭代）
  - AI API 配置（独立 modal，关闭不保存，保存按钮落本地）：BaseURL、Model、APIKey、API Response Format（ChatGPT | Claude）
  - 关于 Me：弹出显示开发者 email（hello1024lc@gmail.com）
- Out / 后续：
  - 真正的多语言（本地化字符串、语言切换生效）
  - AI 功能本身的调用（本期只存配置，不发请求；对接 S5 占位的 AI 辅助编辑按钮以后再做）

## Constraints / Coexistence
- 遵循 CLAUDE.md：单一职责、按功能分层（新代码进 `Features/Settings/` 与 `Models/`）、文案禁用 emoji、图标用 SF Symbols、版本差异收敛封装层。
- 最低 iOS 18；沿用现有 SwiftUI + NavigationStack 结构。
- 存储位置：**均不放文档存储目录（Documents，Files App 可见）**。
  - 主题 / 语言等偏好 → UserDefaults（Library/Preferences）。
  - AI 配置（含 APIKey）→ JSON 落 Library/Application Support（用户选定方案，Files App 不可见）。

## Definition of Done
- 主页左上角有设置按钮，点击进入设置页。
- 主题三选一即时全局生效，重启后保持；未存储时跟随系统。
- 语言按钮存在、点击有占位反馈、不崩。
- AI 配置 modal：取消不落盘；保存后重开仍在；数据文件位于 Application Support 而非 Documents。
- 关于弹出显示 email 且可点发邮件。

## Key Decisions (locked)
| Decision | Choice | Why |
|---|---|---|
| 偏好存储 | 主题/语言用 UserDefaults | 系统标准、不进 Documents，@Observable 封装 |
| AI 配置存储 | 全量 JSON 存 Library/Application Support | 用户选定；不进 Documents、Files App 不可见；实现简单 |
| 主题模型 | enum system/light/dark，默认 system | 有本地存储则覆盖，UserDefaults 天然满足「有则优先」 |
| 主题生效 | 根视图 .preferredColorScheme(store.colorScheme) | 可用性/差异收敛一处，全局统一 |
| AI 配置编辑 | 独立 modal + 草稿副本 + 取消/保存 | 满足「关闭不保存、保存才落本地」 |
| 语言 | 仅占位按钮 | 用户明确本期不做具体逻辑 |
| 开发者邮箱 | hello1024lc@gmail.com | 用户本次指定（区别于账号 icloud 邮箱） |
