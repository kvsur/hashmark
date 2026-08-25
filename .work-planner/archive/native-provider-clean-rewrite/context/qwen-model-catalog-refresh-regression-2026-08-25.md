# Qwen model catalog and refresh regression — 2026-08-25

## User-observed behavior

- Qwen 3.6, 3.7 and 3.8 model families are available upstream but do not appear in the app's bundled model list.
- Refreshing available Qwen models does not populate those models.

## Read-only diagnosis

- The bundled Qwen capability manifest stops at Qwen 3.5 plus the legacy `qwen-plus`, `qwen-max` and `qwen-flash` aliases.
- Current first-party Model Studio documentation lists `qwen3.8-max`, Qwen 3.7 max/plus/flash variants, and Qwen 3.6 max-preview/plus/flash variants.
- The current List Models contract is `GET /api/v1/models`; its response uses `output.models[].model`, which the local parser already accepts.
- Model Studio API keys, endpoints and available model lists are region-specific and cannot be mixed. The official list endpoint requires a region-appropriate host; several regions require a Workspace ID hostname. The app derives the list URL from a simplified generation preset and does not model Workspace ID, so refresh is not reliable across current keys/regions.
- Refresh failures collapse HTTP status and region/account causes into a generic UI message and emit no safe request/status/model-count diagnostics, preventing the observed failure from being distinguished as 401/403/404 versus a successful empty result.
- Adding IDs alone is unsafe: current Qwen 3.6/3.7/3.8 variants have model-specific native text-versus-multimodal endpoint requirements, and advanced search strategies differ by exact model.

## Sources

- https://help.aliyun.com/zh/model-studio/text-generation-model/
- https://help.aliyun.com/zh/model-studio/vision-model
- https://help.aliyun.com/zh/model-studio/list-models
- https://help.aliyun.com/zh/model-studio/regions/
- https://help.aliyun.com/zh/model-studio/qwen-api-via-dashscope

## Implemented resolution

- The dated Qwen manifest now defaults to `qwen3.7-plus` and contains the verified Qwen 3.6, 3.7 and 3.8 model IDs, including snapshots and the current 3.8 open-source variants.
- A dedicated exact-model contract owns reasoning, built-in search, native text/multimodal routing and conservative document capability; unknown discovered models remain text-only and advanced features stay disabled.
- The China legacy host now refreshes authorized inference models through `/api/v1/models/permissions`. International and custom Workspace hosts use `/api/v1/models` with `providers=qwen`, `capabilities=TG`, `supports=inference` and automatic pagination.
- Debug diagnostics record only Provider, host/path, status, page and parsed model count; API keys and response bodies are not logged.
- Current `output.models[].model`, China `output.permissions[].model`, multi-page refresh, Qwen request routes/search options, the complete Provider regression suite, Debug simulator build and Release iPhoneOS build passed on 2026-08-25.
