# 图片多模态请求体格式 — 两家 API 契约（实现 S3 图片序列化用）

本 App 的消息中立层 `AIMessage.content` 目前是纯 `String`。发图片必须把 user 消息的 content
从「字符串」升级为「内容块数组」。两家格式不同，是最容易只改一半的地方（见归档 i18n 计划 S6 教训）。

## OpenAI / ChatGPT 兼容（/chat/completions）

user 消息 content 变数组，文本块 + 图片块混排。图片用 data URI（base64）：

```json
{
  "role": "user",
  "content": [
    { "type": "text", "text": "<注入的文档参考 + 用户 prompt>" },
    { "type": "image_url",
      "image_url": { "url": "data:image/jpeg;base64,<BASE64>" } }
  ]
}
```

- 纯文本消息（无附件）应保持旧的 `"content": "<string>"` 形状不变（向后兼容、少动）。
- system / assistant / tool 消息不带图片，序列化不变。

## Anthropic / Claude 兼容（/messages）

user 消息 content 用 content blocks，图片块结构不同（source.base64）：

```json
{
  "role": "user",
  "content": [
    { "type": "text", "text": "<注入的文档参考 + 用户 prompt>" },
    { "type": "image",
      "source": { "type": "base64", "media_type": "image/jpeg", "data": "<BASE64>" } }
  ]
}
```

- 同样：无附件时保持 `"content": "<string>"`。
- `system` 仍是顶层字段（ClaudeClient 现有装配），不受影响。

## Provider 侧尺寸约束（决定本地压缩参数）

- 长边建议压到 ~1568px 内；单图体积控制在数 MB 内（base64 会膨胀 ~33%）。
- 张数上限本 App 自定为 4（前端硬限），避免请求体过大。
- 编码统一转 JPEG（HEIC/PNG 原图体积大、部分端点不认），media_type 固定 image/jpeg。

## 异常来源（S6 处理点）

1. 相册项加载失败 / 非图片数据 → 跳过该项并提示。
2. 压缩后仍超限 → 进一步降质或提示单张过大。
3. 模型不支持视觉 → 上游多为 400/404，需把「可能是所选模型不支持图片」翻译成可读提示，
   而非直接抛 provider 原始错误体（现有 AIError.http 已做截断，可在此之上补语义提示）。
4. tools 降级重试路径（SSEStream.streamWithToolFallback）与图片无耦合，但要确认带图请求
   在降级重试时仍带上图片块。
