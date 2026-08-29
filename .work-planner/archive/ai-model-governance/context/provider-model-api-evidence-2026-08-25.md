# Provider models API 第一方证据摘要（2026-08-25）

本文件只记录 bootstrap 阶段确认到的 models API 结构和规划含义；S1 仍需逐家冻结完整契约、分页、错误和可用字段映射。

## OpenAI

- 官方 Models API：<https://developers.openai.com/api/reference/resources/models>
- `GET /models` 返回 `id`、`created`、`owned_by` 和可选 `shutdown_date`。
- 规划含义：可用于账号可见性、发布时间/下线提示和差异发现，不能单凭该响应推断图片、PDF、reasoning 或 web search。

## Anthropic

- 官方 List Models：<https://platform.claude.com/docs/en/api/models/list>
- `GET /v1/models` 支持 cursor 分页，返回 `capabilities`，当前包含 `image_input`、`pdf_input`、`thinking`、`effort`、citations 等字段。
- 规划含义：对应能力应优先使用 Provider 元数据；缺失/null 不能被误当成明确 false。

## Google Gemini

- 官方 Models API：<https://ai.google.dev/api/models>
- `GET /v1beta/models` 使用 `nextPageToken`，返回 `baseModelId`、version、token limits、`supportedGenerationMethods` 和 `thinking`。
- 规划含义：可验证生成方法和 thinking；图片/PDF/search/file search 仍需结合第一方能力文档、精确例外、家族规则或运行时证据。

## Alibaba Cloud Qwen

- 官方 List models：<https://help.aliyun.com/en/model-studio/list-models>
- `GET /api/v1/models` 支持 region/workspace 和页码分页；返回 `capabilities`、`features`（含 `web-search`）、`inference_metadata.request_modality`、发布时间和 token limits。
- 规划含义：文本生成、reasoning、视觉输入、web search 可优先读取元数据；原生 text/multimodal endpoint 路由仍需由受版本控制的协议策略约束。

## Moonshot Kimi

- 当前代码调用 `GET /v1/models`，但 bootstrap 搜索未得到可冻结的官方字段级 List Models 文档。
- 规划含义：S1 必须重新核验官方文档/真实响应；在此之前只把返回 ID 当发现证据，能力依赖声明式家族、精确例外和运行时验证。

## Zhipu GLM

- 官方模型概览：<https://docs.bigmodel.cn/cn/guide/start/model-overview>
- bootstrap 未发现可依赖的统一模型目录 API；官方对话、视觉、文件和搜索契约分散在各 API 文档/枚举中。
- 规划含义：不猜测 `/models`；使用 App 内置 Manifest、官方文档差异检查和运行时验证，直到官方提供稳定列表契约。

