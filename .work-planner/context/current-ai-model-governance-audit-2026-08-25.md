# 当前 AI 模型治理审计（2026-08-25）

## 工作树与基线

- 首次检查时工作树包含大量尚未提交的 AI 原生 Provider、设置、测试与其他功能改动，旧计划为 99% 完成、S14.5 仍待实体机/真实凭据验证。
- 旧计划已原样归档至 `.work-planner/archive/native-provider-clean-rewrite/`。
- 审计期间外部环境在 2026-08-25 14:04:14 生成根提交 `0575bfed14475ccb17ff3f6742c29efa4070adf7`；Codex 未执行提交命令。该提交出现后工作树变为干净，不做回退。
- `zsh MarkdownApp/AIReasoningTests/run-all.sh` 全部通过：Settings、Native Core、六家 Adapter、附件、搜索会话、展示、fixture 和 regression audit 共 13 组。

## 当前实现链路

### 模型发现

- `AIModelCatalogService` 支持 OpenAI、Anthropic、Gemini、Qwen、Kimi；GLM 明确返回 unavailable。
- 解析结果被压缩为 `[String]` 模型 ID；Provider 返回的能力、输入模态、发布时间、下线时间、上下文和分页元数据大多被丢弃。
- Gemini 没有跟随 `nextPageToken`；Anthropic 没有跟随 `has_more/after_id`；Qwen 有页码分页；其他 Provider 只取单页。
- `isUsefulModelID` 以 Swift 前缀和 Gemini Contract 过滤，新的非既有命名家族可能被列表接口返回后再次丢弃。

### 缓存与差异

- `AIModelCatalogStore` 使用 `UserDefaults` 的 `AIModelCatalog.v1`，只按 Provider 保存模型 ID 数组。
- 缓存没有 schema 迁移、profile/endpoint/account 作用域、fetchedAt、lastSeen、来源、元数据、过期、下架或差异历史。
- 成功空列表会覆盖最后一次有效目录；刷新失败只显示消息，没有 stale 状态或可诊断差异。

### 能力判断

- `AIProviderManifest.swift`、`AIProviderCapabilityRules.swift`、`GeminiModelContract.swift`、`QwenModelContract.swift`、`KimiModelContract.swift`、`GLMModelContract.swift` 包含型号、前缀、默认模型与能力白名单。
- `AnthropicRequestBuilder` 另有 adaptive thinking 型号集合；`GLMRequestBuilder` 另有 `glm-5.3` 精确分支。
- 当前只有 `supported / unsupported / conditional(rule)`，解析结果只有 available/unavailable；没有 provider metadata、exact override、family、runtime evidence 的来源与优先级模型。
- 未识别模型可保存并文本调用，但高级能力统一成为 `modelNotVerified`。图片、PDF、通用文件、推理和搜索无法各自保持“未知/待验证”。
- 设置页把多种文件能力合并成一个展示结果，无法解释图片、PDF、普通附件的不同证据。

### 配置持久化与设置

- `AIConfigStore` 将单个 `AIConfig` 原子写入 Application Support 的 `AIConfig.json`；非空已保存模型在打开设置时不会被默认值覆盖。
- 当前回归测试已防止旧的 `onAppear` 初始化竞态，并确保刷新目录与当前选中模型进入选项。
- 配置仍只有“当前 Provider 的一份值”；切换 Provider 会立即套用该 Provider 默认 endpoint/model，再切回不会恢复该 Provider 先前草稿/配置。
- 目录缓存仅按 Provider，无法隔离同一 Provider 的不同 region、endpoint 或配置 profile。

### Web Search 与附件

- 六家请求构建器当前都由 `preferences.webSearchEnabled` 和 effective capability 驱动，没有基于“搜索/最新/股价/行情”等正文关键词的启用逻辑。
- OpenAI、Anthropic、Gemini、Qwen 会直接写入各自原生搜索字段，并使用执行证据 gate；Kimi/GLM 采用各自第一方预执行搜索服务。
- 问题在于未知模型会在工厂层因 `modelNotVerified` 被拒绝，无法通过真实请求验证新模型是否支持搜索。
- `AIAttachmentPolicy` 已区分 image、PDF 和本地文本引用，但前两者仍依赖白名单布尔结果；普通文件能力在设置 UI 中被合并。

## 结构性结论

1. 现有保存回归已修复一个具体竞态，但没有建立 per-Provider/profile 的长期持久化模型。
2. 当前“models API 只发现 ID，manifest 才是唯一能力权威”的假设已经落后于 Anthropic、Qwen 等会返回能力元数据的 API。
3. 需要把声明式数据与 Swift 协议实现分开：型号、家族、例外、弃用、默认值进版本化 Manifest；auth、endpoint 语义、wire schema、stream parser 和工具协议继续保持强类型代码。
4. 能力必须成为逐项、带来源与置信度的决策，而不是一个未知模型触发的全局高级能力关闭。
5. runtime verification 需要只把明确的 Provider 成功或“能力不支持”错误写入证据；网络、鉴权、限流和临时服务错误必须保持 inconclusive。

