# Plan Summary

## Goal

先完整退役 Qwen，再把当前“Provider models API 只保存 ID + Swift 分散型号白名单 + 单配置文件”的实现，演进为无自建 CDN/Server 依赖的五家本地模型治理体系：尽可能消费 OpenAI、Anthropic、Gemini、Kimi、GLM 第一方 models API 元数据，以版本化 App Manifest 表达型号家族、例外、默认值和弃用状态，以分层 resolver 和本地运行时证据逐项判断能力，并让新模型可以稳定发现、选择、保存和文本调用。

## Scope

- In: OpenAI、Anthropic、Gemini、Kimi、GLM 五家保留原生 Provider。
- In: 完整移除 Qwen Provider：枚举/工厂、endpoint/Manifest/discovery/capability、Adapter/wire/file/search、设置/缓存/验证数据、七语言文案、测试/fixture、支持矩阵和当前维护文档。
- In: 逐家 models API client/parser、分页、元数据归一化、错误语义和无官方目录时的显式 unavailable 路径。
- In: App Bundle 内版本化、可验证的声明式模型 Manifest；收敛默认模型、精确例外、家族规则、能力、别名与弃用状态。
- In: 图片、PDF、通用附件、推理、原生 Web Search 等独立 capability result、证据来源、置信度和解释。
- In: Provider metadata > exact exception > family rule > verified local result > conservative unverified fallback 的固定优先级。
- In: 版本化目录缓存、差异历史、stale/last-good、下架候选和 profile/endpoint 作用域。
- In: 版本化设置文档和旧 `AIConfig.json` 迁移；每个 Provider 恢复自己的 model/endpoint/key/preferences，已保存动态模型不被默认值覆盖。
- In: 未知新模型显示、选择、保存、文本调用与“能力未验证”状态。
- In: Web Search 开启即直接走该 Provider 已实现的原生协议/第一方搜索服务，不做正文关键词判断；成功或明确不支持结果进入本地验证证据。
- In: models API fixture、Manifest schema/semantic validation、目录差异检查、迁移/缓存/能力/Adapter 回归、七语言和构建验证。
- In: 发布维护手册，明确数据/运行时可适配变化与必须发版的 wire/protocol 变化。
- Out: 自建 CDN、远端 Manifest、Server API、远程 feature flag 或第三方模型聚合服务。
- Out: Qwen 支持、Qwen 配置兼容迁移、Qwen 目录缓存保留或任何 DashScope 路由；Qwen 历史只保留在 `.work-planner/archive/` 审计材料中。
- Out: 新增其他 Provider、恢复 OpenAI-compatible/custom Provider 或重写现有五家 wire adapter。
- Out: 自动静默执行会产生费用的后台 capability probe；优先复用用户真实操作或显式验证动作。
- Out: 本任务不扩展到 API Key 的 Keychain 迁移；继续遵守现有本地隐私和日志约束。

## Constraints / Coexistence

- 遵守 `AGENTS.md`：按职责拆分、避免重复、业务逻辑外移；所有 UI 文案同步简中/英/繁中/日/韩/德/俄，无 emoji，优先 SF Symbols。
- 保留五家 native-only adapter、附件生命周期、搜索执行证据和统一设置页；Qwen 是明确退役例外，不恢复兼容协议。
- 不清理、回滚或覆盖用户已有修改；不提交。审计期间出现的外部提交 `0575bfe` 视为新的只读基线。
- 本任务对五家保留 Provider 执行零能力回归：其已验证的文本、流式、推理、搜索、图片、PDF、普通文件、上传/提取/检索、引用/续传和设置恢复都属于兼容性基线；Qwen 退役不计作回归，其他任何回退都会阻止阶段完成。
- models API 的字段缺失代表 unknown，不自动解释为 false；鉴权、限流、网络和服务错误不产生“不支持”证据。
- 缓存不能让已保存模型消失；目录成功空响应、暂时缺项或一次未出现不能立刻判定下架。
- 强类型 Swift 继续拥有 auth、endpoint/wire schema、stream parser、tool/file protocol；声明式 Manifest 不执行任意代码或拼装未知协议字段。

## Definition of Done

1. 除 `.work-planner/archive/` 历史材料外，生产代码、测试、fixture、用户文案和当前支持文档不存在 `Qwen/qwen/DashScope/dashscope` Provider 内容或可达路由。
2. Swift 生产代码不再维护逐型号能力数组；五家模型 ID、家族、例外、默认值、别名和弃用状态来自通过 schema 与 semantic validation 的版本化 Manifest。
3. 五家发现策略均有明确实现或明确 unavailable；支持分页的 API 不漏页，Provider 元数据被归一并持久化，而不是只留下 ID。
4. 目录缓存按配置 profile/endpoint 隔离，保留 fetchedAt、lastSeen、来源、元数据、manifest/protocol 版本、stale 和差异；失败/空响应不破坏 last-good。
5. 能力 resolver 对 image、PDF、generic file、reasoning、native web search 分别按规定五层优先级返回 supported/unsupported/unverified、来源和理由。
6. 运行时只记录明确成功、明确不支持或 inconclusive；证据有 TTL/失效条件，切换 endpoint/model/protocol/Manifest 后不会错误复用。
7. 未知模型可显示、选择、保存和文本调用；重新打开设置、切换 Provider 往返或刷新失败后都不会回到旧默认模型。
8. Web Search 开启时，所有已实现该协议且非明确 unsupported 的路径直接发送原生搜索配置/第一方搜索请求，不包含关键词门控；关闭时不发送。
9. 图片、PDF、普通附件的 preflight 与请求构建消费逐项能力结果；未知不再被错误描述成“确定不支持”。
10. 自动化差异检查能从 fixture/可选真实 models API 快照报告新增、消失、改名候选、元数据/弃用变化和 Manifest 覆盖缺口。
11. 设置/迁移/目录/能力/五家 Adapter/搜索/附件/i18n/隐私回归和 Debug/Release 构建通过；无凭据的在线项明确标记未验证。
12. 维护文档明确列出无需发版可适配的目录/元数据/家族/本地证据变化，以及 endpoint/auth/request/stream/tool/file schema 等必须发版的协议变化。
13. 当前已支持的五家能力矩阵与 golden request/stream/settings fixtures 在新实现下保持同等或更强；任何已验证能力、请求字段、附件路径、搜索执行证据、引用/续传或保存恢复回退都会使对应阶段失败。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 用户原始模型治理要求 | context/ai-model-governance-requirements-2026-08-25.md | 全计划范围、证据优先级、未知模型与无远端基础设施约束 |
| C2 | 当前实现审计 | context/current-ai-model-governance-audit-2026-08-25.md | S1 差距基线、工作树事实、现有回归结果 |
| C3 | 第一方 models API 证据摘要 | context/provider-model-api-evidence-2026-08-25.md | S1/S3 五家保留 Provider 的发现能力；Qwen 条目仅作退役前历史对照 |
| C4 | 当前 Manifest 与能力规则 | MarkdownApp/MarkdownApp/Models/AI/AIProviderManifest.swift; MarkdownApp/MarkdownApp/Models/AI/AIProviderCapabilityRules.swift; MarkdownApp/MarkdownApp/Models/AI/ProviderCapabilities.swift | S1/S2/S4 替换边界 |
| C5 | 当前目录服务与缓存 | MarkdownApp/MarkdownApp/Models/AI/AIModelCatalogService.swift; MarkdownApp/MarkdownApp/Models/AI/AIModelCatalogStore.swift | S1/S3 发现、分页、缓存和 diff 基线 |
| C6 | 当前设置与持久化 | MarkdownApp/MarkdownApp/Models/AIConfig.swift; MarkdownApp/MarkdownApp/Models/AIConfigStore.swift; MarkdownApp/MarkdownApp/Features/Settings/AIConfigFormState.swift; MarkdownApp/MarkdownApp/Features/Settings/AIConfigEditorView.swift | S1/S5 迁移与稳定选择基线 |
| C7 | 当前 Provider Adapter、附件与搜索门 | MarkdownApp/MarkdownApp/Models/AI/; MarkdownApp/MarkdownApp/Models/AIClient.swift | S1a Qwen 拆除范围与 S4/S6 五家能力接入 |
| C8 | 当前离线测试与构建脚本 | MarkdownApp/AISettingsTests/; MarkdownApp/AIReasoningTests/ | S1/S2-S7 验收和差异自动化基线 |
| C9 | 已归档六家 native-only 计划 | archive/native-provider-clean-rewrite/summary.md; archive/native-provider-clean-rewrite/state.json; archive/native-provider-clean-rewrite/context/ | 历史契约与已知真实账户缺口，只作审计参考 |
| C10 | 工程约定 | AGENTS.md | 所有阶段的目录、i18n、隐私、UI 与不提交约束 |
| C11 | 冻结的五家治理契约 | context/ai-model-governance-contract-freeze-2026-08-25.md | S2-S7 的 baseline、models API、capability、cache/profile 和发版边界 |
| C12 | Qwen demolition map | context/qwen-demolition-map-2026-08-25.md | S1a 的生产、测试、fixture、文档拆除清单与硬编码处置 |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| 目录缓存作用域 | assumed：以持久化 Provider profile ID + normalized endpoint 为主键，不从 API Key 派生身份 | 避免不同 region/account 目录互相污染，同时不保存 Key 指纹 | S1.4 |
| 运行时验证触发 | assumed：优先复用用户真实 capability 请求；额外 probe 只由用户显式触发，且显示可能产生请求/费用 | 防止后台静默计费或上传测试数据 | S1.3/S4.4 |
| 未知模型的原生搜索 | assumed：Provider 协议已实现且无更高层明确 unsupported 时为 trial-eligible；用户开关触发真实原生请求，结果写入证据 | 满足“未知不等于不支持”和“开启即原生发送”，同时保留明确例外 | S1.3/S6.2 |
| Kimi models API 元数据 | open：当前只确认代码使用 `/v1/models`，未冻结字段级官方文档 | 决定 Kimi 是 metadata source 还是 ID-only discovery | S1.2 |
| GLM 统一模型目录 | open：当前未发现稳定官方 list-models 契约 | 决定是否保持 manifest-only discovery | S1.2 |
| API Key 存储 | assumed out of scope：本轮只迁移配置结构，不改 Keychain | 避免把模型治理扩张为凭据安全项目 | S5.1 前可纠正 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| 远端依赖 | 不使用自建 CDN/Server API；只使用 Provider 官方 API、App Manifest、本地缓存与运行时证据 | 符合产品部署前提 |
| 能力优先级 | Provider metadata > exact exception > family rule > verified local result > conservative unverified fallback | 用户指定；所有 capability 共用同一 resolver 规则 |
| 能力粒度 | image、PDF、generic attachment、reasoning、native web search 独立解析 | 避免一个未知结果关闭全部高级能力 |
| 未知模型 | 始终可显示、选择、保存和文本调用；高级能力显示 unverified 而非伪装 unsupported | 新模型无需先等 App 清单更新才能基础使用 |
| 声明式/代码边界 | 模型数据进入版本化 Manifest；auth、wire、stream、tool/file protocol 留在强类型 Swift | 数据变化可维护，协议变化仍 fail closed |
| 默认值语义 | 默认模型只用于首次建 profile 或明确重置，不覆盖非空已保存选择 | 根治重新进入设置回退 |
| 下架语义 | 目录缺失先成为 missing candidate；保留已保存选择并提示，只有明确 shutdown/deprecated 或连续差异策略才升级状态 | 防止账号/区域/临时 API 波动误删模型 |
| 搜索触发 | 只由用户 Web Search 开关和 capability decision 驱动，禁止正文关键词判断 | 行为确定、可测试、与提示语言无关 |
| 零回归门槛 | 先冻结五家保留 Provider 的 capability/request/settings golden baseline；新旧 resolver 对已支持模型必须同等或更强，五家 contract fixture 必须保持通过 | 保证治理重构不牺牲保留能力；Qwen 是明确退役例外 |
| 上游破坏性变化 | 若 Provider 真正下线能力或改变协议，阻断交付并报告，不用错误 fallback 伪装兼容，也不把能力删除静默混入重构 | 区分 App 回归与无法由客户端控制的上游变化 |
| Qwen 退役 | 从产品、测试、fixture、文案和当前维护文档完整移除，不做 Qwen 配置兼容或其他 Provider 映射；历史归档保留 | 用户最新范围决定，并避免旧凭据被错误路由 |
