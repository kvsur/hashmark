# 各大 LLM API Thinking 消息类型调研

---

## 1. OpenAI

### 模型

- `o1-preview`、`o1-mini`（已逐步被 `o3` 系列替代）
- `o3-mini`
- `o1`（满血版）
- GPT-4o with reasoning（通过 `store` / extended thinking 机制）

### API 实现方式

OpenAI 的 o 系列模型**原生将思维链作为内部推理过程输出**，并不暴露显式的 `thinking` 消息类型。2024 年底引入的 **Extended Thinking** 机制允许在响应中附带内部的推理摘要（通过 `store=true` 参数和 `thinking` 字段）。

```
// 请求示例（Extended Thinking）
{
  "model": "o3-mini",
  "store": false,
  "max_completion_tokens": 10000,
  "messages": [...]
}
```

### Thinking 结构

- **无显式 thinking block**。模型在生成最终答案前进行内部推理，用户不可直接控制思维步骤。
- 部分 API 响应中会返回 `completion_ms` 等元信息，但不以结构化消息块形式暴露。

### 特点

- 推理过程**封闭**，用户无法注入中间推理步骤。
- 不支持 `system` 消息中预设思考策略。
- 适用于需要强推理但无需过程可见性的场景。

---

## 2. Anthropic Claude

### 模型

- Claude 3.7 Sonnet（带有 Extended Thinking）
- Claude 3.5 Haiku / Sonnet（标准版本不支持 thinking block）
- Claude 4 系列（未来版本）

### API 实现方式

Anthropic 在 Messages API 中引入了 **`thinking` 块类型**，通过 `thinking` 参数启用：

```
// 请求示例
{
  "model": "claude-3-7-sonnet-20250220",
  "max_tokens": 8192,
  "thinking": {
    "type": "enabled",
    "budget_tokens": 10000
  },
  "messages": [
    { "role": "user", "content": "..." }
  ]
}
```

### Thinking 结构

响应中包含结构化的 `thinking` 块：

```json
{
  "type": "content_block",
  "thinking": "（模型的详细推理步骤，纯文本）"
}
```

随后才是最终的 `text` 块：

```json
{
  "type": "text",
  "text": "（最终回答）"
}
```

### 特点

- `thinking` 块内容**明文返回**，用户可完整读取推理过程。
- `budget_tokens` 控制 thinking 部分的最大 token 数，超出后模型停止思考并输出答案。
- 支持通过 `type: "disabled"` 关闭 thinking。
- 可以**配合 tools/use tools** 使用，thinking 内容不会传递给工具。
- Claude 的 thinking 块本质上是 `content` 数组中的一种 block 类型，结构与 `text`、`tool_use`、`tool_result` 并列。

---

## 3. Google Gemini

### 模型

- Gemini 2.0 Flash Thinking（实验性）
- Gemini 1.5 Pro / Flash（标准版本无显式 thinking block）
- Gemini 2.5 系列（部分版本支持）

### API 实现方式

Gemini 使用 **Thinking 模式（实验性）**，通过 `thinking_config` 参数开启：

```
// 请求示例（Google AI Studio / API）
{
  "contents": [...],
  "thinking_config": {
    "thinking_mode": "enabled"
  }
}
```

### Thinking 结构

Gemini 的 thinking 响应同样以结构化块形式出现，模型会先生成一段推理内容（可能被标记为 `thought` 或包含在内容序列中），然后输出最终回答。

### 特点

- 部分版本将 thinking 内容**作为响应的一部分**返回，但格式尚未完全标准化。
- 实验性功能，API 可能随时变更。
- 支持在 thinking 过程中使用工具（如 Google Search）。

---

## 4. DeepSeek

### 模型

- `deepseek-reasoner`（即 DeepSeek-R1）
- `deepseek-reasoner`（v2、v3 系列）

### API 实现方式

DeepSeek 在 Chat Completions API 中支持 `chat.completions` 格式，通过 **特殊的 user/assistant 消息序列** 来区分思考过程和最终答案：

```
// 请求示例
{
  "model": "deepseek-reasoner",
  "messages": [
    { "role": "user", "content": "问题" }
  ]
}
```

### Thinking 结构

DeepSeek-R1 的推理过程以 **assistant 消息的 `content` 字段中** 包含 `<think>...</think>` 标签的形式返回：

```json
{
  "role": "assistant",
  "content": "<think>\n模型在此进行详细推理...\n</think>\n\n这是最终答案。"
}
```

### 特点

- thinking 内容**明文嵌入在 assistant 消息中**，用 XML 风格标签包裹。
- 不需要特殊参数开关，模型天然输出结构化的思考内容。
- 可通过解析 `<think>` 标签来提取推理过程。
- 支持自定义 `max_tokens` 来限制总输出，间接控制思考长度。
- 早期版本 `deepseek-llm` 系列不支持此机制。

---

## 5. 阿里 Qwen（通义千问）

### 模型

- Qwen3 系列（Qwen3-8B、Qwen3-72B 等）
- Qwen2.5-Max / Qwen2.5 系列（标准版无显式 thinking）
- QwQ-32B（推理模型）

### API 实现方式

Qwen 通过 DashScope API 提供推理模型支持：

```
// 请求示例（OpenAI 兼容格式）
{
  "model": "qwq-32b",
  "messages": [...]
}
```

### Thinking 结构

与 DeepSeek 类似，Qwen 推理模型的 thinking 过程以 **assistant 消息的内容中** 包含特定分隔标记的形式返回：

```
<|think|>
模型在此进行推理步骤...
<|think|>

最终答案。
```

### 特点

- 使用 XML 风格的分隔标签 `<|think|>` 标记推理边界。
- 部分工具调用场景下，thinking 块会被截断或跳过。
- 通过 `extra_body` 可以传入 `thinking_depth` 等参数调控思考深度。

---

## 6. Zhipu AI（智谱 GLM）

### 模型

- GLM-Z1（推理模型）
- GLM-4 系列（标准版）

### API 实现方式

智谱 ChatGLM API 通过 `enable_thinking` 参数开启推理：

```
{
  "model": "glm-z1",
  "messages": [...],
  "extra_body": {
    "enable_thinking": true,
    "thinking_tokens": 4096
  }
}
```

### Thinking 结构

响应中 thinking 内容通过 **独立的 `thinking` 字段** 返回（部分 API 版本）：

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "thinking": "（推理过程）",
      "content": "（最终答案）"
    }
  }]
}
```

### 特点

- thinking 作为独立的顶层字段，而非嵌套在 content 中。
- `thinking_tokens` 参数显式控制思考 token 上限。
- 早期版本不支持 thinking 结构。

---

## 7. Moonshot AI（月之暗面 Kimi）

### 模型

- Kimi 1.5（标准版）
- Kimi 1.5 长思考版（实验性）

### API 实现方式

Moonbox API 支持 thinking 参数：

```
{
  "model": "moonshot-v1-32k",
  "messages": [...],
  "extra_body": {
    "thinking_type": "extended",
    "max_thinking_tokens": 8000
  }
}
```

### Thinking 结构

响应中 thinking 内容以 **单独的 content block** 形式出现，与最终答案分开展示。

### 特点

- `thinking_type` 参数区分思考模式类型。
- 仍在快速迭代中，API 结构可能变化。

---

## 8. 字节跳动 Doubao（豆包）

### 模型

- Doubao-1.5-pro（推理增强版）
- Doubao-1.5-lite

### API 实现方式

火山引擎 API 通过扩展参数控制：

```
{
  "model": "doubao-1.5-pro",
  "messages": [...],
  "extra_body": {
    "enable_thinking": true,
    "thinking_budget": 4096
  }
}
```

### Thinking 结构

Thinking 内容在响应中以 **独立的 thinking block** 存在，与标准 text content 并列。

### 特点

- `thinking_budget` 以 token 数控制思考消耗。
- 部分工具调用场景下 thinking 过程不暴露。

---

## 9. Step（阶跃星辰）

### 模型

- Step-2（推理模型）
- Step-1 系列

### API 实现方式

```
{
  "model": "step-2",
  "messages": [...],
  "extra_body": {
    "thinking": {
      "type": "enabled",
      "max_tokens": 8192
    }
  }
}
```

### Thinking 结构

响应中 thinking 内容嵌入在 assistant 消息的 thinking 字段中。

---

## 10. SiliconFlow / OpenRouter 等聚合平台

### 支持情况

- **OpenRouter**：对各模型的 thinking 支持做了统一封装，通过标准化的 `reasoning` 或 `thinking` 参数透传到底层模型。
- **SiliconFlow**：支持 DeepSeek、Qwen 等推理模型的 thinking 输出，格式与源平台一致。
- **One API**（开源）：在 `extra_info` 中携带 thinking 内容，格式因后端模型而异。

### 特点

- 聚合层通常**透传**而非转换 thinking 结构。
- 需注意不同底层模型的 thinking 格式差异（XML 标签 vs. 独立字段 vs. 嵌套 block）。

---

## 对比总览

| 平台 | 模型（推理类） | Thinking 结构形式 | 开启方式 | 可控参数 |
|---|---|---|---|---|
| **OpenAI** | o1 / o3 / o3-mini | 无显式 block（内部推理） | 默认 | `max_completion_tokens` |
| **Anthropic** | Claude 3.7 Sonnet | `content_block` 中的 `thinking` 字段 | `thinking.type=enabled` | `budget_tokens` |
| **Google** | Gemini 2.0 Flash Thinking | 响应序列中的 `thought` 块 | `thinking_config` | 模式选择 |
| **DeepSeek** | DeepSeek-R1/R2 | `<think>...</think>` 标签包裹 | 默认 | `max_tokens` |
| **Qwen** | QwQ-32B, Qwen3 | `<|think|>...</|think|>` 标签 | 默认 | `thinking_depth` |
| **智谱** | GLM-Z1 | 独立 `thinking` 字段 | `enable_thinking=true` | `thinking_tokens` |
| **Moonshot** | Kimi 1.5 思考版 | 独立 thinking block | `thinking_type=extended` | `max_thinking_tokens` |
| **字节** | Doubao 推理版 | 独立 thinking block | `enable_thinking=true` | `thinking_budget` |
| **Step** | Step-2 | thinking 字段 | `thinking.type=enabled` | `max_tokens` |

---

## 关键趋势

1. **结构多样**：Thinking 的承载形式尚未统一，主流方案包括 XML 标签包裹、独立 API 字段、content block 类型三种。
2. **参数命名差异**：Anthropic 用 `budget_tokens`，DeepSeek 用 `max_tokens`，智谱用 `thinking_tokens`，各厂商自定义。
3. **工具协同**：Claude 和 Gemini 的 thinking 支持与 tools/use tools 协同，但 thinking 内容默认不泄露给工具。
4. **聚合层标准化缺失**：通过 OpenRouter 等中间层调用时，需注意底层模型的实际格式。
5. **实验性特征**：多数平台的 thinking 功能仍标记为 Beta，API 随时可能变更。