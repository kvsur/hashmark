# Plan Summary

## Goal

把当前“OpenAI Chat Completions/Anthropic Messages 两条协议 + 十家兼容 Provider Adapter”的实现整体替换为六家原生 API 架构：OpenAI Responses、Anthropic Messages、Gemini 原生 API、Qwen DashScope、Kimi 官方 API、GLM BigModel API。用户仍通过一个统一、非技术化的配置页面使用 AI，但代码不再通过兼容协议、host 猜测或共享 wire serializer 伪装不同 Provider。

## Scope

- In: 仅正式支持 OpenAI、Anthropic、Gemini、Qwen、Kimi、GLM 六家 Provider。
- In: OpenAI 全面迁移到当前 Responses API，包括流式事件、会话状态、Web Search、图片和文件输入。
- In: 六家分别实现第一方 endpoint、auth、request、stream/parser、reasoning、tool/search、image、PDF/file 生命周期。
- In: 建立粗粒度 `AIProviderAdapter`，只统一 App 领域请求、能力查询和事件输出；Provider wire 类型不跨模块共享。
- In: 建立带复核日期的模型/能力 manifest，记录最新 Web Search 模型、tool 类型、版本、限制和引用结构；未知模型默认关闭高级能力。
- In: 保留一个统一配置页面及当前非技术化体验；必要时把旧协议语义改成明确 Provider 语义，但不拆成六套技术表单。
- In: 统一图片、PDF、普通文件、上传引用、提取和检索状态，并在 Provider Adapter 内完成各自映射。
- In: 统一 Web Search 用户意图、搜索状态和引用展示，但不统一 Provider 工具执行协议。
- In: Web Search 开启即代表每个新用户回合必须真实执行搜索；禁止关键词表、`auto` 静默跳过和无证据降级。
- In: 建立端到端 AIGC 展示状态机，覆盖附件准备、连接、thinking、search/tool、正文流式生成、完成、取消、失败和恢复。
- In: 删除旧兼容层、十家 Provider Registry、custom fallback、host 方言识别和不再成立的 fixture。
- In: 更新七语言、本地诊断、契约 fixture、会话/UI 回归、构建和真实 Provider smoke test。
- Out: 不支持 xAI、DeepSeek、Mistral、MiniMax 或任意 custom OpenAI-compatible Provider。
- Out: 不支持第三方 Anthropic-compatible、OpenAI-compatible、Gemini-compatible 等代理协议。
- Out: 不自建搜索引擎、网页抓取服务、通用向量库或跨 Provider 文件托管层。
- Out: 不为了复用而引入一个覆盖六家 wire payload 的万能请求/响应模型。

## Constraints / Coexistence

- App 尚未发布，采用 clean break；不保留旧十家配置迁移、旧协议 raw value 或兼容客户端回退。
- 当前工作区可能包含用户未提交改动；执行计划时只能增量处理 AI 相关文件，不清理或回滚无关改动。
- 原生 API 使用第一方 REST 契约与 `URLSession` 实现；官方 SDK 仅作契约参考，除非 S1 证明某 SDK 对 iOS 有不可替代且可接受的收益。
- 统一配置页保留常用字段与交互。若保留 Base URL，它只是所选 Provider 的 endpoint override，不能用于识别 Provider 或改变 wire contract。
- API Key、prompt、正文、附件数据、搜索原文和原始工具参数不得进入 Debug 日志。
- 所有新增或修改的 UI 文案及 AI prompt 必须同步简中、英、繁中、日、韩、德、俄，并遵守 SF Symbols、无 emoji、Dynamic Type 和 VoiceOver 约定。
- Provider 模型和工具会变化；任何“最新”结论都必须标注官方资料复核日期，不能用宽泛 substring 自动开启能力。

## Definition of Done

1. 运行时只存在六家 Provider；旧 `APIProtocol` 路由、OpenAI Chat 兼容 serializer、十家 Registry、custom fallback 和 host 猜测均从生产代码移除。
2. `AIProviderAdapter` 只暴露稳定领域边界；六家各自拥有独立 request/response/stream/file/search wire 类型和契约 fixture。
3. OpenAI 只发送 Responses API 请求，并正确处理 response items、流式事件、状态续传、`web_search`、图片、文件和 File Search。
4. Anthropic、Gemini、Qwen、Kimi、GLM 分别只发送其第一方文档定义的请求，不借用 OpenAI/Anthropic 兼容 endpoint 或 serializer。
5. 六家均有日期化 Web Search 模型/tool 矩阵；支持、模型条件、工具版本条件、思考冲突和不支持路径都有 fixture。
6. Web Search 来源被归一为可展示引用，且 Provider 原始 source/call identity 在 Adapter 下层保真；停止、重试和多轮继续不会重复或丢失搜索状态。
7. 图片、PDF、文件上传、文件引用、提取和检索分别建模；任何不支持或超限附件在请求前给出明确反馈，不静默丢弃。
8. 配置仍是一个统一页面，六家切换、Key/model/endpoint、搜索偏好和能力解释一致；不向用户展示兼容协议或六套 SDK 参数面板。
9. 最终 UI 有完整生成阶段、Thinking 面板、search/tool 进度、稳定 Markdown 增量渲染、尊重用户阅读位置的自动滚动，以及一致的取消/中断/恢复体验；只有最终正文可写回 Markdown。
10. 每家 Provider 的文本、推理、普通工具、搜索、图片和文件路径都有去敏 golden request/stream fixture；错误、取消、重试和续传均有会话回归。
11. 隐私日志审计、七语言、无障碍、Debug/Release 构建、iPhone/iPad QA 和可用凭据的真实 smoke test 完成；缺少凭据的项目明确标记未实测。
12. Web Search 开启时六家均通过 Provider 原生强制机制或 App 预检搜索获得执行证据；不支持组合在联网前失败，关闭时不产生搜索请求。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 本轮六家原生 API 重写要求 | context/native-provider-rewrite-requirements-2026-08-24.md | Provider 范围、native-only、OpenAI Responses、统一配置页与 clean break 边界 |
| C2 | 2026-08-24 第一方 API/Web Search 快照 | context/native-provider-api-research-2026-08-24.md | S1 日期化契约、最新搜索模型/tool 与高风险差异的起始基线 |
| C3 | 用户补充探索资料 | ../WEB_SEARCH_EXPLORE.md | 交叉核对六家 search/image/file 资料与历史误判 |
| C4 | 当前 AI 配置和兼容 Registry | MarkdownApp/MarkdownApp/Models/AIConfig.swift; MarkdownApp/MarkdownApp/Models/AI/ProviderRegistry.swift; MarkdownApp/MarkdownApp/Models/AI/ProviderCapabilities.swift | S1 删除清单、S2 配置/领域模型重建边界 |
| C5 | 当前 OpenAI/Anthropic 客户端目录 | MarkdownApp/MarkdownApp/Models/AI/OpenAIChat/; MarkdownApp/MarkdownApp/Models/AI/Anthropic/ | S1 可复用审计和 S3/S4 clean rewrite 边界 |
| C6 | 当前统一配置页面 | MarkdownApp/MarkdownApp/Features/Settings/AIConfigEditorView.swift; MarkdownApp/MarkdownApp/Features/Settings/AIConfigFormState.swift; MarkdownApp/MarkdownApp/Features/Settings/AICapabilitiesSection.swift | S2/S11 保持单页体验并删除协议误导 |
| C7 | 当前会话与附件入口 | MarkdownApp/MarkdownApp/Features/AI/AIWritingSession.swift; MarkdownApp/MarkdownApp/Features/AI/AIAttachmentBar.swift | S9/S10 附件、搜索、续传和错误状态重建 |
| C8 | 当前 AI 契约测试 | MarkdownApp/AIReasoningTests/ | S1 fixture 删除/保留清单和 S3-S12 验收基线 |
| C9 | 工程与国际化约定 | AGENTS.md; MarkdownApp/MarkdownApp/Resources/Localizable.xcstrings | 模块拆分、七语言、无障碍、隐私和无 emoji 约束 |
| C10 | Xcode 工程 | MarkdownApp/MarkdownApp.xcodeproj/project.pbxproj | 测试 target 与 Debug/Release/设备构建入口 |
| C11 | 已归档十家兼容层计划 | archive/ten-provider-compatibility/summary.md; archive/ten-provider-compatibility/state.json | 历史决策与已实现兼容层的审计来源，不作为新架构约束 |
| C12 | AIGC thinking/streaming UI 补充要求 | context/aigc-streaming-ui-requirements-2026-08-24.md | S2-S11 typed event、完整展示状态机、Thinking 面板、流式性能和中断恢复基线 |
| C13 | 2026-08-24 六家原生契约冻结矩阵 | context/native-provider-contract-freeze-2026-08-24.md | 六家 endpoint/auth/model/search tool/image/file 的 S2-S13 实施事实源 |
| C14 | 旧兼容实现拆除图 | context/native-provider-demolition-map-2026-08-24.md | S2 删除/保留/重写边界与 S13 最终旧路径审计 |
| C15 | Kimi 真机搜索回归证据 | context/kimi-search-offline-response-2026-08-25.png; context/kimi-invalid-native-search-continuation-2026-08-25.png; context/kimi-search-missing-tool-log-2026-08-25.txt | S14 重现“工具未注入、模型谎称离线、continuation 被会话门控拒绝”三类失败 |
| C16 | 2026-08-25 六家强制搜索契约复核 | context/forced-web-search-contract-research-2026-08-25.md | S14 各 Provider 强制方式、thinking 冲突、执行证据和失败语义 |
| C17 | 刷新模型与动态选择丢失回归 | context/dynamic-model-persistence-regression-2026-08-25.md | S14.6 区分 Kimi 列表新鲜度与所有 Provider 共用的设置初始化/缓存缺陷 |
| C18 | GLM-5.3 清单新鲜度与附件能力回归 | context/glm-5.3-model-freshness-regression-2026-08-25.md | 记录 GLM 默认模型过期、5.2/5.3 文本模态和 5V-Turbo 原生附件边界 |
| C19 | Qwen 3.6–3.8 清单与刷新回归 | context/qwen-model-catalog-refresh-regression-2026-08-25.md | 记录 Qwen 静态清单过期、地域/Workspace 列表端点缺口及新系列原生路由差异 |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| 统一配置页的“不变”边界 | confirmed：保持单页、主字段和非技术化体验；允许把协议语义改成 Provider 语义并更新六家名单 | 不能继续向用户展示与 native-only 冲突的协议概念 | S2.4 形成状态模型，S11 落地 |
| Base URL 高级覆盖 | assumed：可保留，但必须先选择 Provider，且覆盖值仍按该 Provider 原生契约发送 | 兼顾网关/地区 endpoint，同时杜绝 host 猜测和兼容承诺 | S1.4 复核六家地区/代理约束，S2.4 锁定 |
| 原生 SDK 依赖 | assumed：不用六套 SDK，继续使用 `URLSession` + 独立 wire types | 控制包体、并发模型和供应链复杂度 | S1.5 仅在官方 SDK 有不可替代能力时重新评估 |
| Gemini 主路由 | confirmed：使用 Interactions + `google_search`，Files/File Search 保持独立第一方生命周期 | 已由原生 request/stream/source/file fixture 锁定 | S5/S13 完成 |
| Kimi 搜索主路由 | superseded：真机证明 builtin/模型自主 continuation 不满足确定性语义；改为 App 预执行 Formula 并注入受保护结果 | 避免模型跳过搜索与 `invalid_native_search_continuation` | S14 收口 |
| 六家真实凭据 | unavailable：执行环境未提供六家凭据；离线契约全部通过，真实账户 smoke test 明确列入发布候选清单 | 不阻塞计划完成，不能冒充在线验证 | S13.4 已记录 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| Provider 范围 | 仅 OpenAI、Anthropic、Gemini、Qwen、Kimi、GLM | 用户最终范围；减少不可验证兼容面 |
| API 路由 | 每家只使用第一方原生 API；OpenAI 使用 Responses | Provider 能力以自家契约为准，不再被兼容协议截断 |
| 抽象边界 | 粗粒度 `AIProviderAdapter` + 中立领域事件；wire 类型完全归 Provider 私有 | 复用上层会话/UI，同时避免万能协议泄漏 |
| 配置体验 | 一个统一页面，不做六套技术表单；Provider 显式选择，旧协议不参与路由 | 保持用户体验并让 native 路由可解释 |
| 兼容策略 | clean break；无 custom、无 OpenAI-compatible、无第三方 Anthropic、无 host 自动识别 | App 未发布，避免永久维护错误抽象 |
| 模型能力策略 | 日期化精确 manifest；未知模型高级能力关闭；模型列表只辅助发现 | 防止“latest”漂移导致非法 tool/file 请求 |
| 搜索策略 | 每家保留原生 wire 生命周期，但统一保证“开关开启即每个新回合真实执行并有证据”；禁止关键词判断和 `auto` 静默跳过 | 用户开启的是执行承诺，不只是向模型提供可选工具 |
| 文件策略 | direct input、upload/reference、extract、retrieval 分开建模 | 六家文件能力不是同一种机制 |
| Thinking 展示 | 只显示 Provider 明确返回的可展示 reasoning；流式时展开、正文开始后默认收起并尊重用户手动选择；opaque/signature 永不展示 | 兼顾过程感、阅读空间、隐私和 Provider 差异，不伪造思维链 |
| 流式体验 | typed generation phases + delta 合并渲染；用户离开底部后停止强制自动滚动；中断进入显式可恢复状态 | 防止逐 token 重排、页面跳动、重复续传和不可解释的半完成状态 |
| 传输实现 | 默认 `URLSession` 直接调用第一方 REST API | 避免六套 SDK 依赖并保持 Swift 并发/诊断一致 |
| 安全默认 | 不支持、未知、模型不匹配或 tool 版本不匹配时不发送高级字段 | 请求正确性与数据安全优先于“尽力尝试” |
