# Plan Summary

## Goal

把当前由 `ResponseFormat.chatGPT/.claude`、Base URL 猜测和零散 host 判断组成的 AI 接入，重构为清晰的“协议 → 提供商 → 能力/适配器”体系：设置页只向用户展示置顶的 `OpenAI` 与 `Anthropic` 两种 API Protocol，并明确列出 App 正式支持的十家 Provider；Anthropic 模式仅连接 Anthropic 官方服务；OpenAI、Gemini、xAI、DeepSeek、Qwen、Mistral、Kimi、GLM、MiniMax 及自定义端点统一从 OpenAI 兼容入口接入，并按已验证的提供商契约安全启用 Web Search、工具续传、图片/PDF/文件能力。

## Scope

- In:
  - 将设置概念从 Response Format 改为置顶的 API Protocol，只保留 `OpenAI` / `Anthropic` 两项，默认 OpenAI。
  - 在设置页以常驻、清晰的 UI 提示列出十家正式支持的 Provider：OpenAI、Anthropic、Gemini、xAI、DeepSeek、Qwen、Mistral、Kimi、GLM、MiniMax；自定义 OpenAI-compatible 明确标为尽力兼容而非正式支持。
  - Anthropic 协议只支持官方 Anthropic；其他八家第三方统一走 OpenAI 兼容接口；未知自定义端点按保守的 OpenAI 基线处理。
  - 分离传输协议、提供商身份、Provider 适配器和能力配置；OpenAI 侧统一保持 OpenAI SDK-compatible Chat Completions，只对 endpoint、鉴权、Web Search、工具续传及附件做有证据的 Provider 差异适配。
  - 对 OpenAI、Anthropic、Gemini、xAI、DeepSeek、Qwen、Mistral、Kimi、GLM、MiniMax 建立可追溯的能力矩阵和请求契约。
  - Web Search 用户开关默认开启，但只有“用户开启且 Provider Profile 明确支持”时才发送；不向未知端点猜测专有工具。
  - 区分普通 function calling、服务端搜索、内置工具往返、图片/PDF 内联输入、文件上传引用和检索型 file search。
  - 收口 reasoning/tool continuation、无法识别内容错误和隐私安全的 Debug 日志。
  - 更新单元/契约/fixture/UI 状态测试、七语言本地化、Debug/Release 构建和真机验收矩阵。
- Out:
  - 不实现或内部切换到 OpenAI Responses API；OpenAI 侧统一使用 OpenAI SDK-compatible Chat Completions (`/chat/completions`)。
  - 不支持第三方 Anthropic-compatible 代理，也不为未上线版本保留旧配置迁移或兼容 raw value。
  - 不在第一轮接入 Mistral Agents、MiniMax MCP、供应商知识库等独立产品形态来伪装普通 Chat API 能力。
  - 不自建搜索后端、网页抓取器、向量库或跨供应商文件托管服务。
  - 不承诺任意自定义 Base URL 的模型能力；未知端点仅保证保守的 OpenAI-compatible 文本/普通工具基线。

## Constraints / Coexistence

- App 尚未发布，可执行破坏性内部重命名并删除旧配置迁移分支，但不得清理或回滚工作区内其他未提交改动。
- 用户界面保持非技术化；实现层可以存在 Provider Adapter，但不能把协议细节堆给普通用户。
- OpenAI compatibility 在本产品中明确指 Chat Completions 家族的基础消息/鉴权/流式/普通 function calling；搜索、文件和 reasoning 不做跨厂商统一假设，Responses 不进入实现范围。
- API Key 保持普通文本输入；动态 system context 继续在每次请求时注入本地 `yyyy-MM-dd HH:mm:ss`，两项均需回归。
- Debug 日志不得输出 API Key、prompt、生成正文、附件内容或原始工具参数。
- 按仓库长期约定，所有新增/修改 UI 文案和 prompt 必须补齐简中、英、繁中、日、韩、德、俄，且 App 文案不使用 emoji。

## Definition of Done

1. 设置页第一组即为 `OpenAI / Anthropic`；不存在 `ChatGPT`、`Claude` 或 `OpenAI Responses` 的用户可见协议选项，默认值为 OpenAI；页面无需用户猜测即可看到完整的十家正式支持名单。
2. Anthropic 协议只能形成官方 Anthropic 请求；八家第三方与自定义端点只能进入 OpenAI 路径，保存校验和界面说明一致。
3. 传输协议、Provider、Provider Adapter 和能力 Profile 是独立模型；OpenAI 侧所有 Provider 均落到 Chat Completions，请求差异不演变成新的 API 家族。
4. 十家 Provider 均有官方文档或去敏 fixture 支撑的契约记录；未知/未验证能力默认关闭，不发送猜测字段。
5. Web Search 开关默认开，但实际请求严格满足用户开关、Provider 能力、模型/端点方言三重条件；支持、需工具续传和不支持三类路径均有测试。
6. 图片、PDF、上传文件引用和 file search 被分别建模与门控；文本文件作为上下文的既有降级能力不回归。
7. OpenAI/Anthropic 流式 reasoning、正文、普通工具和服务端工具事件保持隔离；已知 provider 工具可继续，未知工具产生可诊断错误而非笼统丢失上下文。
8. Debug 日志可从 request → provider/adapter/capability decision → stream/tool → terminal outcome 串联排障，并通过隐私字段审计。
9. API Key 文本展示、动态日期时间注入、停止/重试/精修/重新生成、反问工具、附件和接受正文行为全部通过回归。
10. Provider 契约 fixture、模型/会话/UI 测试、七语言 catalog、Debug/Release 构建及 iPhone/iPad 深浅色与辅助功能验收通过；真实凭据不可得的 Provider 被明确记录而不虚报实测。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 本轮产品要求与 MiniMax 错误日志 | context/ai-provider-architecture-requirements.md | 目标边界、UI 顺序、Provider 清单、能力与诊断要求 |
| C2 | 2026-08 Provider 兼容性快照 | context/llm-provider-compatibility-2026-08.md | 十家协议/search/file 差异与官方文档目录；实施前复核 |
| C3 | 当前 AI 配置模型 | MarkdownApp/MarkdownApp/Models/AIConfig.swift | 旧 ResponseFormat、迁移、能力开关和 URL 推断的替换点 |
| C4 | 当前 AI 配置页面 | MarkdownApp/MarkdownApp/Features/Settings/AIConfigEditorView.swift | 协议置顶、表单状态、校验和能力提示的 UI 边界 |
| C5 | 当前共享客户端与诊断层 | MarkdownApp/MarkdownApp/Models/AIClient.swift | 工厂、endpoint、SSE、日期时间和 Debug logging 边界 |
| C6 | 当前 OpenAI-compatible 客户端 | MarkdownApp/MarkdownApp/Models/AI/OpenAIChat/ | Chat Completions 传输、请求序列化、Provider 扩展、附件与流解析现状 |
| C7 | 当前官方 Anthropic 客户端 | MarkdownApp/MarkdownApp/Models/AI/Anthropic/ | Messages 传输、请求序列化、thinking/tool/search 流解析与附件门控现状 |
| C8 | 当前 AI 会话状态机 | MarkdownApp/MarkdownApp/Features/AI/AIWritingSession.swift | 工具续传、错误、重试和 reasoning/正文隔离边界 |
| C9 | 当前 AI 契约/fixture 测试 | MarkdownApp/AIReasoningTests/ | 请求、解析、会话及旧配置断言的更新基线 |
| C10 | 工程与 i18n 约定 | AGENTS.md；MarkdownApp/MarkdownApp/Resources/Localizable.xcstrings | 模块拆分、七语言、无障碍和无 emoji 要求 |
| C11 | Xcode 工程 | MarkdownApp/MarkdownApp.xcodeproj/project.pbxproj | 测试 target、Debug/Release 与设备构建入口 |
| C12 | 2026-08-19 当前 AI 契约与测试分支审计 | context/current-ai-contract-inventory-2026-08-19.md | S1.1 现状清单；标记可复用、需重构、冲突、删除与缺口 |
| C13 | 2026-08-20 Provider 契约矩阵与决策冻结 | context/provider-contract-matrix-2026-08-20.md | S1.2–S1.4 官方契约、Chat adapter、能力门控和 UX 决策的实施基线 |
| C14 | 2026-08-20 Provider fixture 统一清单 | context/provider-contract-fixture-manifest-2026-08-20.md | S9.1 建立 Provider 文档日期/request/response/event fixture 索引 |
| C15 | 2026-08-23 Web Search / Image 补充探索与纠偏矩阵 | ../WEB_SEARCH_EXPLORE.md | 区分 Chat 直连、替代 API 路径与模型条件；作为 S10A 契约复核和实现审计的新基线 |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| Provider 识别只靠 URL，还是允许高级手动覆盖 | resolved：官方域名自动识别；未知/网关默认 custom，并允许高级手选九家 OpenAI-side Provider；官方域名冲突禁止保存 | 兼顾网关透传与防误判；专有字段只由显式 Provider adapter 注入 | S1.4 已锁定，S3 落地 |
| Anthropic Base URL 是否隐藏/锁定为官方值 | resolved：隐藏或只读为 `https://api.anthropic.com`，保存与运行时双重校验 | 使“只支持官方 Anthropic”成为可执行约束 | S1.4 已锁定，S3/S5 实现 |
| 默认开启但 Provider 不支持搜索时的 UI | resolved：保留默认开启的用户偏好，显示当前不可用原因，请求不发送 | 偏好不等于能力，切换 Provider 时不丢用户意图 | S1.4 已锁定，S3/S6 实现 |
| 模型级能力可否由 model name 静态判断 | resolved：只采用官方确认的精确 ID/系列和明确版本边界；未知即关闭，禁止宽泛 substring 猜测 | Provider 能力只是上限，模型迭代不能导致错误字段外发 | S1.2/S1.4 已锁定，S2.3 实现 |
| 十家真实 API 凭据是否都可用于验收 | open | 决定 S10 能否完成在线 smoke test；不影响 fixture 契约验收 | S10 开始前确认 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| 用户可见协议 | 仅 `OpenAI` 与 `Anthropic`，并置顶；OpenAI 为默认 | 与主流 SDK 心智一致，去掉 Response Format/Responses 混淆 |
| Provider 支持提示 | 设置页明确列出 OpenAI、Anthropic、Gemini、xAI、DeepSeek、Qwen、Mistral、Kimi、GLM、MiniMax；custom OpenAI-compatible 标为尽力兼容 | 让正式支持边界对用户可见，不把自动检测当作产品说明 |
| Provider 路由 | 仅 Anthropic 官方走 Anthropic；其余八家、OpenAI 和 custom 全走 OpenAI | 用户已明确产品边界，避免维护两套第三方兼容矩阵 |
| OpenAI 请求形态 | 九家 OpenAI 路径统一使用 OpenAI SDK-compatible Chat Completions；不实现 Responses | 与当前代码和用户前次更正一致，避免把同一 UI 协议拆成隐藏 API 家族 |
| 内部抽象 | Protocol、Provider、Provider Adapter、Capabilities 四层分离 | Provider 高级能力差异需要适配，但不改变两类 API 主协议 |
| 兼容策略 | 未发布版本不保留旧配置迁移和第三方 Anthropic 特例 | 减少永久历史包袱和不可测试分支 |
| 能力安全默认 | 未验证/未知能力不发送；用户开关不能强行越过 Provider Profile | 防止“默认开启”变成对任意端点注入猜测工具 |
| Provider 识别与网关 | 官方域名确定性识别；未知域名为 custom，可高级手选九家 OpenAI-side Provider；官方域名与手选冲突时禁止保存 | 网关可显式启用目标 adapter，同时避免 URL 猜测和身份伪装 |
| Anthropic endpoint | Anthropic 协议固定官方 `https://api.anthropic.com/v1/messages`，不提供自定义 endpoint | 将官方-only 产品边界落实到 UI、保存校验与运行时 |
| 能力偏好 UX | Web Search 偏好默认开启且跨 Provider 保留；有效能力由偏好、Provider、模型和 endpoint 共同决定，不可用时解释但不发送 | 分离用户意图与线协议事实，避免自动篡改和非法请求 |
| 模型能力规则 | 只使用官方确认的精确 ID/系列和版本边界；未知模型能力关闭，图片/PDF 可用性派生且不可手工声明 | 防止快速迭代的模型名导致过度启用 |
| 其他 API 家族 | Responses、Agents、MCP 与 native-SDK-only 服务不在本计划实现范围 | 保持两条明确请求路径，并诚实表达 Chat API 的能力边界 |
| 能力路径判定 | Provider “具备能力”不等于本 App 的 Chat adapter “可用”；必须区分 Chat 直连、替代 API 路径、模型条件和未确认 | 防止把 MiniMax/xAI/Gemini 的其他 API 能力误判为本地缺陷，也防止遗漏 Kimi/Qwen/GLM 的直接 Chat 契约 |
| 可观测性 | 结构化 Debug 日志只记录元数据，不记录内容与凭据 | 能定位无法识别流/工具问题，同时保护隐私 |
