# Native Provider support and handoff

Contract review date: 2026-08-25

This document records the shipped local contract, not a promise that newly announced model IDs automatically receive advanced features.

## Support matrix

| Provider | Default model | Native generation route | Search | Reasoning | Image/PDF/file | Account model refresh |
|---|---|---|---|---|---|---|
| OpenAI | `gpt-5.6-terra` | `/v1/responses` | Hosted `web_search` | Displayable summary events | Direct input, upload reference, File Search | `/v1/models` |
| Anthropic | `claude-fable-5` | `/v1/messages` | `web_search_20260318` server tool | Thinking blocks; opaque signature retained | Direct input and Files reference | `/v1/models` |
| Gemini | `gemini-3.7-flash` | `/v1beta/interactions` | Google Search grounding | Thought summary; signature retained | Direct input, Files and File Search | `/v1beta/models` |
| Qwen | `qwen3.7-plus` | DashScope text generation; exact multimodal models use multimodal generation | `enable_search`, forced `search_options`, native `search_info` | Native reasoning content on verified models | Exact visual models; native PDF/file remains limited to fixture-verified models | China account permissions; regional/workspace `/api/v1/models` |
| Kimi | `kimi-k2.6` | `/v1/chat/completions` | Formula `moonshot/web-search:latest` | Verified; Formula tool definition and Fiber result are replayed opaquely, and displayable thinking is disabled while search is on | Vision, Files references and extraction | `/v1/models` |
| GLM | `glm-5.3` | `/api/paas/v4/chat/completions` | Standalone `/api/paas/v4/web_search` evidence on exact text models | GLM-5.3 always-on reasoning with `reasoning_effort=max` | GLM-5.3/5.2 are text-only; only exact GLM-5V models receive image/PDF/file capabilities | Not exposed in settings until a first-party list contract is verified |

The exact model allowlists live in `AIProviderManifest.swift`. Unknown or merely discovered models keep advanced capabilities disabled.

## Regional and account prerequisites

- OpenAI, Anthropic and Gemini use their global first-party endpoints.
- Kimi and GLM use their China first-party endpoints.
- Qwen exposes explicit China, Singapore, Hong Kong and United States endpoint presets. The API key, model availability and region must belong together. China legacy hosts refresh authorized inference models through `/api/v1/models/permissions`; regional and workspace hosts use the paginated `/api/v1/models` catalog.
- A custom Base URL is an advanced override for the already-selected Provider. It does not enable a compatible protocol or change Provider identity.
- Model refresh requires a saved or entered API key. A successful refresh lists account-visible model IDs but does not update capability rules.

## Troubleshooting

| Symptom | Check |
|---|---|
| Authentication failed | Confirm the key belongs to the selected Provider and, for Qwen, the selected region. |
| Model appears after refresh but capabilities are unavailable | The model is account-visible but not in the dated capability manifest. Review official contracts and add fixtures before enabling it. |
| Kimi Thinking becomes unavailable | Built-in Web Search requires displayable thinking to be off. Turn off search for a thinking turn. |
| Image or file is rejected before sending | Check the exact model capability, MIME type, count, byte limit and whether that Provider requires upload or extraction. |
| Generation stops after backgrounding or a weak connection | The partial answer is intentionally non-accepting. Retry or regenerate from the explicit interrupted state. |
| Search has no source link | The Provider returned no valid URL. The result remains visible as activity but no fabricated citation is created. |
| A gateway returns a foreign schema | The override must preserve the selected Provider's native request and stream contract; compatibility gateways are unsupported. |

## Validation record

Completed on 2026-08-24:

- Offline core, six Adapter, attachment, session/search, presentation, settings, fixture-manifest, localization, privacy and legacy-path regression suites.
- Debug and Release simulator builds.
- iPhone 17 Pro launch/resume and visual checks in light appearance at Accessibility Extra Large, plus iPad Pro 13-inch launch and visual checks in dark appearance. The checked-in generation snapshots cover light, dark and accessibility-sized Thinking/streaming surfaces.
- Deterministic presentation tests for cancellation, background interruption, weak-network interruption, scroll ownership, retry and final-answer-only acceptance.

Not live-tested in this environment:

- OpenAI, Anthropic, Gemini, Qwen, Kimi and GLM real-account smoke tests. No Provider credential environment variables were available, so no paid or externally mutating request was attempted.
- Physical-device rotation, network conditioning and hands-on VoiceOver gesture navigation remain release-candidate checks; automated state transitions, accessibility semantics and portrait simulator surfaces are covered offline.

## Future model refresh procedure

1. Review the Provider's first-party generation, search, reasoning and file documentation and record the review date.
2. Capture sanitized native request, stream/source, typed error, image and file evidence for each capability being claimed.
3. Update exact model IDs and tool versions in `AIProviderManifest`; never replace them with broad substring inference.
4. Update `Fixtures/manifest.json` and the support matrix, then run `run-all.sh`, Debug/Release builds and iPhone/iPad QA.
5. With an authorized test account, smoke-test only the newly changed Provider capabilities and record region/account differences without logging keys, prompts, bodies or attachment contents.
