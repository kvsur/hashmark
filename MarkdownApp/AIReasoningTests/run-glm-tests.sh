#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/glm-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

cat > "$output_dir/AIPromptLocaleStub.swift" <<'SWIFT'
enum AIPromptLocale {
    static var uiLanguageName: String { "English" }
}
SWIFT

xcrun swiftc \
  "$output_dir/AIPromptLocaleStub.swift" \
  "$app_dir/Models/AIAttachment.swift" \
  "$app_dir/Models/AITool.swift" \
  "$app_dir/Models/AIDomain.swift" \
  "$app_dir/Models/AIReasoningBlock.swift" \
  "$app_dir/Models/AIStreamEvent.swift" \
  "$app_dir/Models/AIMessage.swift" \
  "$app_dir/Models/AI/AIProvider.swift" \
  "$app_dir/Models/AI/ProviderCapabilities.swift" \
  "$app_dir/Models/AI/Kimi/KimiModelContract.swift" \
  "$app_dir/Models/AI/Gemini/GeminiModelContract.swift" \
  "$app_dir/Models/AI/Qwen/QwenModelContract.swift" \
  "$app_dir/Models/AI/GLM/GLMModelContract.swift" \
  "$app_dir/Models/AI/AIProviderCapabilityRules.swift" \
  "$app_dir/Models/AI/AIProviderManifest.swift" \
  "$app_dir/Models/AIConfig.swift" \
  "$app_dir/Models/AI/SSEEventFramer.swift" \
  "$app_dir/Models/AI/GLM/GLMWire.swift" \
  "$app_dir/Models/AI/GLM/GLMWebSearchContract.swift" \
  "$app_dir/Models/AI/GLM/GLMRequestBuilder.swift" \
  "$app_dir/Models/AI/GLM/GLMStreamParser.swift" \
  "$test_dir/GLMContractTests.swift" \
  -o "$output_dir/GLMContractTests"

"$output_dir/GLMContractTests"
