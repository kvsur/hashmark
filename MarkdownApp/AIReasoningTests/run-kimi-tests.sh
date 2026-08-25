#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/kimi-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

cat > "$output_dir/AIPromptLocaleStub.swift" <<'SWIFT'
import Foundation

enum AIPromptLocale {
    static var uiLanguageName: String { "English" }
}

enum LocalizationController {
    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value)
    }
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
  "$app_dir/Models/AI/Manifest/AIModelManifest.swift" \
  "$app_dir/Models/AI/Discovery/AIModelDescriptor.swift" \
  "$app_dir/Models/AI/Discovery/AIModelCatalogScope.swift" \
  "$app_dir/Models/AI/Capabilities/AICapabilityDecision.swift" \
  "$app_dir/Models/AI/Capabilities/AICapabilityResolver.swift" \
  "$app_dir/Models/AI/Capabilities/AICapabilityVerificationStore.swift" \
  "$app_dir/Models/AI/Kimi/KimiModelContract.swift" \
  "$app_dir/Models/AI/Gemini/GeminiModelContract.swift" \
  "$app_dir/Models/AI/GLM/GLMModelContract.swift" \
  "$app_dir/Models/AI/AIProviderCapabilityRules.swift" \
  "$app_dir/Models/AI/AIProviderManifest.swift" \
  "$app_dir/Models/AIConfig.swift" \
  "$app_dir/Models/AI/SSEEventFramer.swift" \
  "$app_dir/Models/AI/Kimi/KimiWire.swift" \
  "$app_dir/Models/AI/Kimi/KimiFormulaService.swift" \
  "$app_dir/Models/AI/Kimi/KimiRequestBuilder.swift" \
  "$app_dir/Models/AI/Kimi/KimiStreamParser.swift" \
  "$test_dir/KimiContractTests.swift" \
  -o "$output_dir/KimiContractTests"

"$output_dir/KimiContractTests"
