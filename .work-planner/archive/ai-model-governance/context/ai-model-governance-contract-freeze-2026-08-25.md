# AI 模型治理冻结契约（2026-08-25）

## 五家零回归 baseline

`zsh MarkdownApp/AIReasoningTests/run-all.sh` 在 2026-08-25 15:47 重新运行并通过 13 组离线测试。Qwen 是明确退役例外；以下五家为后续 shadow parity oracle。

| Provider | 生成路由 | 必须保留的能力与 fixture |
|---|---|---|
| OpenAI | `/v1/responses` | text/stream、reasoning、hosted `web_search`、function tool、previous response continuation、image、PDF/direct file、upload reference、File Search |
| Anthropic | `/v1/messages` | text/stream、thinking/signature replay、versioned server Web Search/citation、function tool、image、PDF/direct file、Files reference |
| Gemini | `/v1beta/interactions` | text/stream、thought signature、Google Search grounding/citation、function tool、stateful continuation、image、PDF/direct file、Files、File Search |
| Kimi | `/v1/chat/completions` + Formula | text/stream、reasoning continuation、Formula Web Search/Fiber、image、PDF/file extraction、Files upload/reference |
| GLM | `/api/paas/v4/chat/completions` + `/api/paas/v4/web_search` | text/stream、reasoning replay、search sources、function tool、exact visual-model image/PDF/file path |

每个迁移单元必须通过现有五家 contract tests、附件、search/session、settings、fixture manifest 和 regression audit。新 resolver 对 baseline 模型的逐项结果不得从 supported 退为 unsupported/unverified。

## Models API contract

| Provider | endpoint / auth | pagination | normalized fields | error / fallback |
|---|---|---|---|---|
| OpenAI | `GET /v1/models`, Bearer | 当前契约无 cursor | `id`, `created`, `owned_by`, optional `shutdown_date` | 非 2xx、解码失败和空列表保留 last-good；目录不能独立证明高级能力 |
| Anthropic | `GET /v1/models`, `x-api-key`, `anthropic-version` | `has_more` + `last_id` → `after_id`; page limit | `id`, display name, created time, capabilities including image/PDF/thinking/effort/citations | capability 缺失/null 为 unknown；只把显式布尔值作为 Provider evidence |
| Gemini | `GET /v1beta/models`, `x-goog-api-key` | `nextPageToken` → `pageToken` | `name/baseModelId`, version, display name, description, token limits, `supportedGenerationMethods`, thinking | 不可生成的资源可保留 descriptor 但不进入 writing picker；空/失败保留 last-good |
| Kimi | `GET /v1/models`, Bearer | 当前第一方文档未冻结分页字段 | 至少 `id`, `created`, `owned_by`; 未知字段保留为 metadata | 仅作 account-visible discovery；能力来自 Manifest/运行时证据，未知分页标记 unavailable 而非猜测 |
| GLM | unavailable | none | none | 不发明 `/models`；使用 Bundle Manifest、可选手工 snapshot 和运行时证据 |

API 级 auth、rate-limit、network、5xx、schema mismatch 都是 inconclusive，不会写入 unsupported evidence。一次成功空列表同样不替换 last-good。

## Capability contract

独立 capability：`imageInput`、`pdfInput`、`genericFileInput`、`reasoning`、`nativeWebSearch`。每项返回：

- state: `supported | unsupported | unverified`
- source: `providerMetadata | exactManifest | familyManifest | runtimeVerification | conservativeFallback`
- confidence: `high | medium | low`
- reason、`observedAt`、manifest/protocol version（适用时）

固定优先级为 Provider metadata > exact exception > family rule > verified local result > conservative fallback。字段缺失不是 false；exact/family 可以补充缺失元数据，但不能覆盖 Provider 的显式 unsupported。未知模型文本调用允许；高级能力为 unverified，其中已实现固定原生协议的 Web Search 为 trial-eligible，用户开关可触发真实请求。只有明确 capability 成功或明确 unsupported 错误写证据；auth、限流、网络、取消、5xx 和不明确 4xx 记录 inconclusive。

## Profile / cache / lifecycle contract

- Settings 文档版本化；每个 Provider 至少一个稳定 profile，profile 保存 id、Provider、base URL、model、API key 和 preferences。
- cache scope key 为 `profileID + provider + normalizedEndpoint`；不从 API key 生成或持久化指纹。
- catalog schema、manifest content version、protocol evidence version 都进入缓存；默认 TTL 24 小时，last-good 保留 30 天供离线恢复。
- 非 2xx、解码失败、网络失败或成功空列表不覆盖 last-good。刷新成功产生 added/missing/metadataChanged/lifecycleChanged/renameCandidate diff。
- 一次 missing 只标记 candidate 并保留选择；连续三次成功目录缺失或 Provider 显式 shutdown/deprecated 才升级 lifecycle。已保存 model 永远进入 picker。
- runtime evidence 默认 TTL 30 天；切换 Provider、normalized endpoint、model、manifest content version 或 protocol evidence version 后不会复用旧证据。
- 旧 `AIConfig.json` lossless 迁移为一个稳定 active profile；默认模型只用于首次建 profile或明确 reset。

## Change classification matrix

| Change | local/runtime adaptable | App release required |
|---|---|---|
| 新增/消失 model ID、created/owner/token limit 等目录元数据 | yes | no |
| 已声明 family 下的新 snapshot、runtime capability evidence | yes | no |
| exact exception、family、alias、default、deprecated/shutdown 数据 | Bundle Manifest 更新 | yes（无远端控制面） |
| endpoint path、auth/header、request/stream schema | no | yes |
| search tool name/version/continuation/citation wire | no | yes |
| file upload/reference/extract/retrieval protocol | no | yes |
| Provider 移除或设置 schema 破坏性变化 | no | yes + migration/product decision |

## Target file map

- `Models/AI/Manifest/`: versioned schema、loader、validator、safe strategy IDs。
- `Models/AI/Discovery/`: normalized descriptor、五家 strategy/parser、pagination、cache、diff。
- `Models/AI/Capabilities/`: source-aware resolver、verification store/recorder。
- `Models/AI/Configuration/`: versioned settings document、profiles、legacy migration。
- `Resources/AIProviders/`: JSON Manifest 与 JSON Schema。
- Provider directories retain auth、wire request/stream、search/file protocol only；附件 policy 与 Settings consume resolved decisions，不再维护型号清单。

