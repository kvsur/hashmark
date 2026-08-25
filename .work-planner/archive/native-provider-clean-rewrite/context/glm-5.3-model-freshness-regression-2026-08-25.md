# GLM-5.3 model freshness regression — 2026-08-25

## User-observed behavior

- GLM-5.3 is already available, but the app still presents GLM-5.2 as the latest/default GLM model.
- The app presents GLM-5.2 as not supporting attachments, raising the question whether all attachment forms are actually unavailable.

## Read-only diagnosis

- The bundled GLM manifest is marked `verifiedAt: 2026-08-24` but still defaults to `glm-5.2`; GLM remote model refresh is explicitly disabled.
- The current official GLM-5.3 documentation says model ID `glm-5.3`, text-only input, always-on reasoning, and `low`/`high`/`max` reasoning effort.
- The current official GLM-5.2 documentation also identifies it as text-only.
- GLM-5V-Turbo is the separately documented multimodal model for image, file and PDF input.
- In the app, image/PDF/native file inputs are correctly gated to exact GLM visual models. Plain UTF-8 documents remain usable because their text is injected into the prompt as provider-neutral text context rather than sent as a native attachment.

## Sources

- https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3
- https://docs.bigmodel.cn/cn/guide/models/text/glm-5.2
- https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5v-turbo

## Implemented resolution

- The dated GLM manifest now defaults to `glm-5.3` and still lists `glm-5.2` as a supported text model.
- GLM-5.3 requests use its always-on thinking contract with `reasoning_effort: max`.
- Both GLM-5.3 and GLM-5.2 remain text-only in the capability matrix and reject image/PDF media before networking; GLM-5V models retain the separate native attachment path.
- GLM contract fixtures, the complete Provider regression suite, Debug simulator build and Release iPhoneOS build passed on 2026-08-25.
