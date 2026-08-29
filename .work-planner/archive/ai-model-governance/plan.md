# Plan

## Target architecture

```text
MarkdownApp/MarkdownApp/
├── Models/AI/
│   ├── Manifest/             # Codable schema、loader、semantic validator、版本/迁移
│   ├── Discovery/            # 归一目录模型、五家 client/parser、分页与 diff
│   ├── Capabilities/         # 分层 resolver、逐项 decision、运行时证据 store
│   ├── Configuration/        # versioned profiles、旧 AIConfig 迁移、active config 投影
│   ├── Attachments/          # 消费逐项 capability decision（保留现有职责）
│   └── <Provider>/           # 继续拥有强类型 wire、request、stream、tool/file 协议
└── Resources/AIProviders/
    ├── manifest-v1.json      # Provider defaults、model families、exact overrides、lifecycle
    └── manifest-v1.schema.json
```

核心数据流：

```text
Provider models API ──> normalized catalog ──> versioned profile cache ──┐
App bundled Manifest ──> validated rules/defaults/lifecycle ─────────────┼─> capability resolver
runtime success/explicit unsupported ──> expiring local evidence ────────┘
                                                                        │
saved provider profile <── Settings/UI <── source-aware decisions <─────┘
                                                                        │
                                                               native Provider adapter
```

`CapabilityDecision` 必须保留 capability、state（supported/unsupported/unverified）、source、confidence、reason、evidence timestamp/version；Provider Adapter 只消费已经解析好的决定，不自行重复型号判断。Manifest 只能选择代码中已注册的安全策略枚举，不能声明任意 endpoint 字段或执行逻辑。

## Non-regression gate

- S1 首先冻结五家保留 Provider 的 capability matrix，以及 request、stream、attachment、search、citation/continuation、settings golden fixtures；Qwen 单独进入完整退役清单。
- S2-S6 每个迁移单元先保留旧结果作为测试 oracle，执行新旧 shadow comparison；已支持模型只能保持同等能力或增加证据，不能从 supported 退为 unverified/unsupported。
- 旧 Swift 型号清单只在对应 Manifest/Resolver parity 测试通过后删除；目录/cache 改造在 resolver 切换前不得改变生产能力结果。
- 已保存配置必须通过 lossless migration；刷新、空响应、stale、missing 或新默认值都不能覆盖用户已有 model/endpoint/preferences。
- 五家原生 request/stream fixtures、搜索执行 gate、附件生命周期和全量 `run-all.sh` 是每阶段硬门槛，不只留到最终回归；Qwen fixture 从 runner 和支持矩阵中删除。
- 如果官方上游真实下线能力或改变协议，当前步骤停止并记录为外部破坏性变化；不得通过伪造支持、静默降级或删除能力来让测试通过。

## Dependency graph

```text
S1 → S1a → S2 → S3 → S4 ──┬──> S5 ──┐
                            └──> S6 ──┴──> S7
```

## Phases / Steps

### S1 — Current-state audit and contract freeze

- Goal: 把 bootstrap 审计升级为逐文件、逐 Provider、逐 capability 的冻结契约，关闭会影响 schema、缓存和运行时验证的开放项。
- Depends on: none
- Refs: C1 — 用户优先级与验收；C2 — 当前差距；C3 — 第一方 API 起点；C4-C8 — 实现/测试基线；C9 — 历史 native 契约；C10 — 工程约束。
- Resolves: Kimi models API 元数据、GLM list-models 边界、cache profile key、runtime validation 触发和 unknown-search trial 语义。
- Sub-steps:
  - S1.1 冻结五家保留 Provider capability/request/settings golden baseline，并生成 Qwen 完整 demolition map 及其他型号硬编码、默认值、路由、能力消费和持久化的 retain/move/rewrite 清单。
  - S1.2 逐家冻结五家 models API endpoint/auth/pagination/metadata/error；无官方接口时记录证据和 fail-closed 路径。
  - S1.3 冻结逐项 capability state/source/confidence、五层优先级、trial-eligible 与明确 unsupported 语义。
  - S1.4 冻结 Provider profile、目录 cache key、TTL、last-good、空响应、missing/deprecated 和迁移规则。
  - S1.5 形成“本地/运行时可适配 vs 必须发版”的 change-classification matrix 与目标文件图。
- Verify: 五家保留 Provider 的文本/流式/推理/搜索/附件/引用续传/设置能力进入 golden baseline；Qwen 所有生产/测试/文档表面有完整拆除清单；五类 capability 的开放项关闭。

### S1a — Complete Qwen Provider removal

- Goal: 从当前产品与维护表面完整退役 Qwen，保证无可达路由、无残余配置入口、无测试/文档继续宣称支持，同时不破坏五家保留 Provider。
- Depends on: S1
- Refs: C1 — 最新范围决定；C2/C4-C8 — Qwen 代码、设置、测试和文档现状；C9 — 只读历史归档边界；C10 — i18n/拆分约束；C12 — 冻结 demolition map。
- Sub-steps:
  - S1a.1 按 demolition map 定位 `Qwen/qwen/DashScope/dashscope` 的生产、测试、fixture、文案和当前文档表面。
  - S1a.2 移除 Provider enum/factory、endpoint presets、Manifest/model discovery/cache/capability/settings 分支及 Qwen 本地数据身份。
  - S1a.3 删除 Qwen Adapter、request/stream/wire、file、search、route 与附件路径，并收口五家 exhaustive switch。
  - S1a.4 删除 Qwen 测试、fixture、runner、支持矩阵与七语言文案，更新五家 baseline/文档。
  - S1a.5 增加排除 `.work-planner/archive/` 的全局残留审计，运行五家全回归和 Debug/Release 构建。
- Verify: 除历史归档与本计划的退役说明外，产品、测试、fixture、用户文案和当前支持文档无 Qwen/DashScope 内容或可达路由；五家 frozen baseline 全部通过。

### S2 — Versioned declarative Manifest and core domain

- Goal: 建立可解码、可验证、可演进的 App Bundle Manifest 和 source-aware capability/catalog 领域模型，替换 Swift 逐型号数组。
- Depends on: S1a
- Refs: C1 — 声明式/版本化要求；C4 — 旧 Manifest/规则替换边界；C7 — Adapter 所需稳定投影；C10 — 模块拆分；C11 — 冻结领域契约与文件图。
- Sub-steps:
  - S2.1 定义 manifest schemaVersion/contentVersion、Provider defaults、family、exact override、alias、lifecycle 和 safe strategy IDs。
  - S2.2 实现 loader、schema migration、semantic validator、冲突/重复/default/unknown strategy fail-fast。
  - S2.3 定义 normalized model descriptor、capability decision/evidence、lifecycle 与 discovery provenance。
  - S2.4 将五家型号/家族/默认/弃用数据迁入 JSON，删除 Swift 逐型号清单和重复能力装配。
  - S2.5 改造 Registry/Provider Contract 只保留协议策略与强类型 wire 分支，并用 validated Manifest 注入数据。
  - S2.6 增加 schema/semantic/golden decoding、新旧 resolver shadow parity、旧能力等价和生产源无逐型号数组审计。
- Verify: Manifest 缺失/损坏/冲突会安全失败；所有既有已支持模型的能力决定与请求策略同等或更强；生产 Swift 不再包含维护型逐型号能力数组。

### S3 — Provider discovery, normalized metadata, cache and diff

- Goal: 充分利用各 models API 的真实字段，形成可分页、可缓存、可比较且不破坏 last-good 的本地目录。
- Depends on: S2
- Refs: C3 — 五家保留 Provider 的 API 字段差异；C5 — 旧 ID-only 服务/store；C6 — Settings 消费边界；C8 — fixture/test harness；C11 — 冻结发现/cache/diff 契约。
- Sub-steps:
  - S3.1 拆分五家 discovery strategy/client/parser，共享安全 transport/pagination 骨架但不共享 Provider wire schema。
  - S3.2 实现 OpenAI shutdown、Anthropic capabilities/cursor、Gemini methods/thinking/pageToken 的元数据映射。
  - S3.3 为 Kimi/GLM 落地 S1 冻结的 ID-only 或 unavailable 策略，不猜测 endpoint/字段。
  - S3.4 实现 versioned profile+endpoint scoped cache、TTL/stale/last-good、元数据与 manifest/protocol 版本失效。
  - S3.5 实现新增、missing、rename candidate、deprecated/shutdown、metadata change 和 manifest gap diff engine。
  - S3.6 增加分页、重复、未知字段、空成功、部分页失败、鉴权/限流、cache migration 与 diff fixture 测试。
- Verify: 五家 fixture 不漏页、不丢已知元数据；错误/空响应保留 last-good；新 ID 即使不匹配旧家族也进入可选择目录并产生 Manifest gap；仅发现/cache 改造不改变现有 capability baseline。

### S4 — Layered capability resolver and runtime verification

- Goal: 对每项能力按固定五层证据独立解析，并将真实请求结果安全沉淀为可失效的本地验证记录。
- Depends on: S3
- Refs: C1 — 固定优先级与未知模型政策；C2 — 当前全局 modelNotVerified 缺陷；C3 — metadata 可用字段；C4/C7 — resolver/Adapter 边界；C11 — 冻结 capability/evidence 语义。
- Sub-steps:
  - S4.1 实现 metadata > exact > family > local verification > conservative fallback 的 deterministic resolver 和解释链。
  - S4.2 分离 image、PDF、generic attachment、reasoning、native web search，并保留 streaming/function/file-service 等内部能力。
  - S4.3 实现 versioned verification store、TTL、profile/endpoint/model/capability/protocol identity 和清理/失效。
  - S4.4 定义 user-request/explicit-verify recorder：成功、明确 unsupported、inconclusive 的错误分类与去敏诊断。
  - S4.5 实现未知模型 text baseline、advanced unverified、trial-eligible search 和明确负例的保守行为。
  - S4.6 增加优先级冲突表、逐能力独立性、过期/切 endpoint、临时错误不降级、source explanation 和所有既有模型新旧 parity 测试。
- Verify: 表驱动测试覆盖五层每种冲突；未知模型不再得到一组伪造的 unsupported；所有既有已支持模型保持同等或更强能力且不会因模糊错误错误改变结果。

### S5 — Versioned Provider profiles and stable Settings UX

- Goal: 刷新、选择、保存、重进设置和 Provider 往返均恢复用户自己的配置，并清楚展示模型来源、生命周期和逐项能力状态。
- Depends on: S4
- Refs: C1 — 稳定保存/未知模型 UX；C5 — cache；C6 — 当前单配置 UI；C10 — 七语言/无障碍；C11 — profile/lifecycle/migration 契约。
- Sub-steps:
  - S5.1 定义 versioned settings document：activeProvider + per-Provider profile，并迁移旧单 `AIConfig.json`。
  - S5.2 让 profile ID 稳定绑定 endpoint/model/key/preferences/catalog；默认值只用于首次建档或显式重置。
  - S5.3 重构表单状态和 Provider 切换，恢复各自 profile，刷新/失败/重开均保留选中模型。
  - S5.4 展示 recommended/discovered/selected 模型、verified/unverified/stale/missing/deprecated 状态，不隐藏未知新模型。
  - S5.5 分别展示 image/PDF/files/reasoning/search 的 state、source/reason，并保持非技术化主界面。
  - S5.6 补齐旧配置迁移、原子写入失败、Provider 往返、缓存缺失、下架保留、七语言、Dynamic Type 与 VoiceOver 测试。
- Verify: 任意 Provider 的动态模型在刷新选择保存后，重建 Store/View、切换往返和离线启动均不回退；旧配置 lossless migration，现有设置行为与能力入口无回归。

### S6 — Adapter integration for attachments and native Web Search

- Goal: 五家 request/preflight 统一消费逐项 decision，移除残余型号分支；搜索开关确定性触发原生协议并反馈运行时证据。
- Depends on: S4
- Refs: C1 — 搜索无关键词、能力分离；C7 — 五家 Adapter/附件/搜索执行门；C8/C9 — native contract fixtures；C11 — trial/unsupported 与发版边界。
- Sub-steps:
  - S6.1 让附件 policy/request builder 分别消费 image/PDF/generic-file decision，明确 supported/unverified/unsupported 用户路径。
  - S6.2 Web Search 开启时，对 supported/trial-eligible 直接发送五家现有原生配置/第一方搜索请求；关闭时完全不发送。
  - S6.3 以搜索执行证据/明确 API capability error 更新 verification store，禁止关键词、模型回答文本或一般 HTTP 错误充当证据。
  - S6.4 把 Anthropic adaptive thinking、GLM reasoning 参数等残余型号分支迁移为受验证 strategy/capability input。
  - S6.5 保持协议未知/字段变化 fail closed，并为用户提供可理解的未验证、明确不支持和协议需更新错误。
  - S6.6 更新五家 request/stream/error fixture，覆盖未知新模型文本、搜索 trial、图片/PDF/files 独立决策和关闭搜索，并逐项对照现有 golden request/stream/attachment/search baseline。
- Verify: 生产源无搜索关键词门控；五家现有原生请求、流式、搜索执行证据、附件、引用与续传 fixture 零回归；未知模型可文本调用，高级请求只按可解释 decision 发送。

### S7 — Automated drift checks, regression, build and maintenance handoff

- Goal: 建立后续不依赖服务端的可重复维护闭环，并完成全套回归与发布边界文档。
- Depends on: S5, S6
- Refs: C1 — 自动差异和发版边界；C3 — 官方来源；C8 — 现有测试入口；C10 — i18n/隐私/构建；C11 — change classification matrix。
- Sub-steps:
  - S7.1 增加离线 fixture diff 命令和可选凭据 live snapshot 命令，输出新增/missing/rename/deprecation/metadata/schema drift。
  - S7.2 将 Manifest validator、fixture freshness、source audit 和 diff 纳入 `run-all.sh`，结果可在本地/CI 直接失败定位。
  - S7.3 运行设置、core、五家 Adapter、附件、搜索会话、展示、i18n、隐私、Qwen 残留、旧硬编码审计和 frozen capability baseline 全回归。
  - S7.4 完成 Debug/Release simulator/device build、设置关键状态 QA 和可用凭据 smoke test；缺失项明确记录。
  - S7.5 发布 AI model maintenance runbook、Provider metadata matrix、cache/verification troubleshooting 和 change-classification matrix。
- Verify: frozen baseline、离线完整回归和双配置构建全部通过且现有能力零回归；差异工具对合成新增/改名/下架准确报警；维护者能判断本地适配、运行时验证或必须发版。
