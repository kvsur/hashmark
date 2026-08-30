# Native Provider support and handoff

Contract review date: 2026-08-25

This document records the shipped local contract, not a promise that newly announced model IDs automatically receive advanced features.

## Support matrix

| Provider | Default model | Native generation route | Search | Reasoning | Image/PDF/file | Account model refresh |
|---|---|---|---|---|---|---|
| OpenAI | `gpt-5.6-terra` | `/v1/responses` | Hosted `web_search` | Displayable summary events | Direct input, upload reference, File Search | `/v1/models` |
| Anthropic | `claude-fable-5` | `/v1/messages` | `web_search_20250305` server tool; MiniMax official compatibility hosts use Coding Plan search followed by `tool_result` | Thinking blocks; opaque signature retained | Direct input and Files reference | `/v1/models` |
| Gemini | `gemini-3.7-flash` | `/v1beta/interactions` | Google Search grounding | Thought summary; signature retained | Direct input, Files and File Search | `/v1beta/models` |
| Kimi | `kimi-k2.6` | `/v1/chat/completions` | Formula `moonshot/web-search:latest` | Verified; Formula tool definition and Fiber result are replayed opaquely, and displayable thinking is disabled while search is on | Vision, Files references and extraction | `/v1/models` |
| GLM | `glm-5.3` | `/api/paas/v4/chat/completions` | Standalone `/api/paas/v4/web_search` evidence on exact text models | GLM-5.3 always-on reasoning with `reasoning_effort=max` | GLM-5.3/5.2 are text-only; only exact GLM-5V models receive image/PDF/file capabilities | Not exposed in settings until a first-party list contract is verified |

Exact models, families, lifecycle and safe strategy IDs live in `Resources/AIProviders/manifest-v1.json`; Swift contains only the native protocol boundary. Unknown models remain selectable and usable for text. Image/PDF/file/reasoning fields remain conservative until supported by metadata, Manifest or scoped evidence; Web Search can make an explicit user-requested trial and records the result.

## Regional and account prerequisites

- OpenAI, Anthropic and Gemini use their global first-party endpoints.
- Kimi and GLM use their China first-party endpoints.
- A custom Base URL is an advanced override for the already-selected Provider and does not change Provider identity. The only endpoint-owned extension is MiniMax Coding Plan search on the exact `api.minimaxi.com` and `api.minimax.io` hosts; generation remains Anthropic Messages wire format.
- Model refresh requires a saved or entered API key. Explicit capability fields returned by Anthropic or Gemini are higher-priority evidence; missing fields remain unknown. OpenAI and Kimi directory rows are not treated as advanced-capability proof, and GLM has no invented list endpoint.

## Troubleshooting

| Symptom | Check |
|---|---|
| Authentication failed | Confirm the key belongs to the selected Provider and endpoint region. |
| Model appears after refresh but a capability is unverified | The Provider did not return an explicit value and no Manifest or usable local evidence covers it. Review the decision source before changing the Manifest. |
| Kimi Thinking becomes unavailable | Built-in Web Search requires displayable thinking to be off. Turn off search for a thinking turn. |
| MiniMax on the Anthropic endpoint does not search | Confirm the endpoint is `api.minimaxi.com/anthropic` or `api.minimax.io/anthropic` and the key has Coding Plan search access. Search is a separate `/v1/coding_plan/search` request, not an Anthropic server tool. |
| Image or file is rejected before sending | Check the exact model capability, MIME type, count, byte limit and whether that Provider requires upload or extraction. |
| Generation stops after backgrounding or a weak connection | The partial answer is intentionally non-accepting. Retry or regenerate from the explicit interrupted state. |
| Search has no source link | The Provider returned no valid URL. The result remains visible as activity but no fabricated citation is created. |
| A gateway returns a foreign generation schema | The override must preserve the selected Provider's request and stream contract. MiniMax's explicit search extension does not permit a cross-Provider generation serializer. |

## Validation record

Completed on 2026-08-25:

- Offline core, five Adapter, attachment, session/search, presentation, settings/profile, Manifest/source governance, fixture-manifest, synthetic drift, localization, privacy, retired-Provider and legacy-path regression suites.
- Debug and Release simulator builds.
- iPhone 17 Pro launch/resume and visual checks in light appearance at Accessibility Extra Large, plus iPad Pro 13-inch launch and visual checks in dark appearance. The checked-in generation snapshots cover light, dark and accessibility-sized Thinking/streaming surfaces.
- Deterministic presentation tests for cancellation, background interruption, weak-network interruption, scroll ownership, retry and final-answer-only acceptance.

Not live-tested in this environment:

- OpenAI, Anthropic, Gemini, Kimi and GLM real-account smoke tests. No Provider credential environment variables were available, so no paid or externally mutating request was attempted.
- Physical-device rotation, network conditioning and hands-on VoiceOver gesture navigation remain release-candidate checks; automated state transitions, accessibility semantics and portrait simulator surfaces are covered offline.

## Future model refresh procedure

1. Review the Provider's first-party generation, search, reasoning and file documentation and record the review date.
2. Capture sanitized native request, stream/source, typed error, image and file evidence for each capability being claimed.
3. Update exact model IDs, families and safe strategy IDs in `Resources/AIProviders/manifest-v1.json`; tool versions and wire changes remain Swift release work. Never replace them with broad substring inference.
4. Update `Fixtures/manifest.json` and the support matrix, then run `run-all.sh`, Debug/Release builds and iPhone/iPad QA. Use `run-model-drift-audit.sh` before accepting a changed snapshot.
5. With an authorized test account, smoke-test only the newly changed Provider capabilities and record region/account differences without logging keys, prompts, bodies or attachment contents.

The complete maintenance decision tree and command reference are in `AI_MODEL_MAINTENANCE_RUNBOOK.md`.
