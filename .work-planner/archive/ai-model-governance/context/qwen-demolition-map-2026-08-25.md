# Qwen demolition map（2026-08-25）

历史归档 `.work-planner/archive/` 原样保留；本文件与活动计划中的退役说明允许继续出现名称。其他当前产品与维护表面必须清零。

## Production

- 删除 `MarkdownApp/MarkdownApp/Models/AI/Qwen/` 全目录：Adapter、RequestBuilder、StreamParser、Wire、FileService、ModelContract。
- `AIProvider`: 删除 Provider case/display name；五家 exhaustive switch 成为编译期残留门。
- `AIProviderManifest` / `AIProviderCapabilityRules`: 删除 endpoint、auth、search/file mechanism 与 capability rules。
- `AIEndpointPreset`: 删除四个 regional preset。
- `AIModelCatalogService`: 删除 permissions/list route、分页/parser/filter。
- `AIProviderAdapter`: 删除 factory branch；`AIAttachmentPolicy`: 删除 Provider-specific limits；任何 file-reference identity 不再接受被移除 Provider。
- 设置与支持列表由 `AIProvider.allCases` / Manifest 驱动，确认无隐藏入口或缓存 identity。

## Tests / fixtures / docs

- 删除 `QwenContractTests.swift`、`run-qwen-tests.sh`、三个 Qwen fixtures，并从 `run-all.sh` 与 fixture manifest 移除。
- 更新 Native Core、Settings、Attachment、Search/session tests 中的六家 stub enum、数组、route 与 endpoint assertions。
- 更新其他 Provider runner 的显式编译源列表，移除 Qwen ModelContract。
- 更新 `CONTRACT.md`、`NATIVE_PROVIDER_SUPPORT.md`、README 当前支持描述和 regression audit；新增排除 `.work-planner/archive/` 与活动退役计划/context 的 residual audit。
- 审计七语言 string catalog；若没有 Provider-specific 用户文案则记录为 no-op，不新增退役提示或配置迁移。

## Disposition of other hardcoding

| Surface | disposition |
|---|---|
| Swift model ID / prefix arrays | move to `Resources/AIProviders/manifest-v1.json` |
| endpoint/auth/request/stream/tool/file protocol constants | retain in strongly typed Swift strategy/Provider modules |
| Provider defaults | move to JSON Manifest; Swift registry consumes validated projection |
| model-list parser/filter logic | rewrite as Provider discovery strategies yielding normalized metadata |
| `AIModelCatalog.v1` Provider-only cache | migrate/rewrite as profile+endpoint scoped versioned cache |
| single `AIConfig.json` | migrate/rewrite as versioned profile document |
| Settings availability booleans | rewrite to consume independent source-aware decisions |
| request-builder model gates | rewrite to consume decision/validated protocol strategy; retain wire-only constraints |

