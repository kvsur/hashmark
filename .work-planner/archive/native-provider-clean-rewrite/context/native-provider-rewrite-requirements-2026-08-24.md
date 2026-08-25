# Native Provider Rewrite Requirements

Captured: 2026-08-24

## User direction

- Final supported providers: OpenAI, Anthropic, Gemini, Qwen, Kimi, GLM.
- Every provider must use its own first-party API contract. Do not route one provider through another provider's compatibility protocol.
- OpenAI must move to the current Responses API rather than Chat Completions.
- The existing provider integration implementation may be removed and rebuilt as a clean break.
- Keep one unified, non-technical configuration experience for users rather than exposing six API consoles.
- A coarse code-level Adapter abstraction is desirable, but it must not flatten provider-specific wire contracts.
- The plan must account for each provider's latest Web Search-capable models and current tool invocation mechanism.

## Interpretation used by this plan

- "Native API" means the first-party endpoint, authentication, request schema, stream/event schema, tool lifecycle, file lifecycle, and model constraints documented by that provider.
- Similar-looking JSON is not treated as compatibility. Kimi and GLM, for example, still receive independent serializers and parsers even where fields resemble another provider.
- The shared Adapter boundary normalizes app-domain requests and events only. Provider request/response payloads remain private to each provider module.
- "Configuration page unchanged" means preserving a single shared page, its non-technical interaction style, and its common key/model/endpoint fields. Necessary provider-list and wording updates may be made so the page does not expose obsolete protocol concepts.
- A Base URL override, if retained, selects an endpoint for the already-selected provider and never infers or changes the provider or wire contract.

