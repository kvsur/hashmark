# AI Provider Architecture — User Requirements

Captured from the planning conversation on 2026-08-19.

## Product direction

- The settings UI should expose exactly two API protocol choices: `OpenAI` and `Anthropic`.
- `OpenAI` means the OpenAI SDK-compatible Chat Completions form (`/chat/completions`). `OpenAI Responses` is not a third protocol and is not an internal Provider sub-dialect in this plan.
- Put the `OpenAI` / `Anthropic` protocol choice at the very top of the AI endpoint configuration page.
- The settings UI must explicitly tell users that the app officially supports exactly these ten providers: OpenAI, Anthropic, Google Gemini, xAI, DeepSeek, Alibaba Cloud Qwen, Mistral AI, Moonshot Kimi, Zhipu GLM, and MiniMax. This must be visible guidance, not only implicit URL detection.
- The notice should distinguish the ten officially supported providers from unknown custom OpenAI-compatible endpoints, which may be attempted on a best-effort basis but are not part of the official support promise.
- Only Anthropic's official service is supported through the Anthropic protocol path.
- OpenAI and these eight additional providers are supported through their OpenAI-compatible interfaces:
  - Google Gemini
  - xAI
  - DeepSeek
  - Alibaba Cloud Qwen / DashScope
  - Mistral AI
  - Moonshot Kimi
  - Zhipu GLM
  - MiniMax
- Custom third-party endpoints use OpenAI compatibility; the app does not promise support for third-party Anthropic-compatible proxies.
- The app has not shipped, so the redesign does not need saved-configuration migration or backward compatibility.
- User correction recorded on 2026-08-19: do not decide which Providers use Responses versus Chat Completions. All nine Providers on the OpenAI side use the OpenAI SDK-compatible Chat Completions family; Provider differences are limited to verified endpoint/auth/search/tool/attachment extensions within that family.

## Capabilities

- Keep a user-facing Web Search switch, default on.
- Whether Web Search is actually sent must depend on both the switch and the detected provider/model capability.
- Explore and handle the different server-side search contracts used by OpenAI and Anthropic, plus the eight supported OpenAI-compatible providers.
- Account for file, image, and PDF input support in the same provider-capability design instead of assuming all compatible endpoints implement identical shapes.
- Do not treat ordinary function calling, server-side web search, file upload, and inline attachment input as the same capability.

## Reliability and diagnostics

- MiniMax's Anthropic-compatible stream was observed returning a `plugin_web_search` tool call during reasoning, followed by the user-visible error “AI returned unrecognized content”.
- The relevant debug sample was:

  ```text
  [AI-Debug] session-tool-call tool=plugin_web_search argumentBytes=85 phase=reasoning reasoningChars=290 textChars=0
  [AI-Debug] unrecognized-tool tool=plugin_web_search reason=unsupported-tool-name
  [AI-Debug] anthropic-event type=message_delta index=-1 block=- delta=- tool=- stopReason=tool_use
  [AI-Debug] anthropic-event type=message_stop index=-1 block=- delta=- tool=- stopReason=-
  [AI-Debug] stream-finished path=/anthropic/v1/messages
  ```

- Debug logging should make request protocol/provider, capability decisions, stream structure, tool continuations, and terminal failure reasons diagnosable without logging API keys, prompts, generated text, attachments, or raw tool arguments.

## Existing small requirements already applied but still subject to regression coverage

- API Key is shown as a normal text field rather than a password field.
- Every LLM request gets the current local date and time in `yyyy-MM-dd HH:mm:ss` form in its system context.
