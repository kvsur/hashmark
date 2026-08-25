#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-settings-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  "$app_dir/Models/AI/AIProvider.swift" \
  "$app_dir/Models/AI/ProviderCapabilities.swift" \
  "$app_dir/Models/AI/Kimi/KimiModelContract.swift" \
  "$app_dir/Models/AI/Gemini/GeminiModelContract.swift" \
  "$app_dir/Models/AI/Qwen/QwenModelContract.swift" \
  "$app_dir/Models/AI/GLM/GLMModelContract.swift" \
  "$app_dir/Models/AI/AIProviderCapabilityRules.swift" \
  "$app_dir/Models/AI/AIProviderManifest.swift" \
  "$app_dir/Models/AI/AIEndpointPreset.swift" \
  "$app_dir/Models/AI/AIModelCatalogService.swift" \
  "$app_dir/Models/AI/AIModelCatalogStore.swift" \
  "$app_dir/Models/AIConfig.swift" \
  "$app_dir/Features/Settings/AIConfigFormState.swift" \
  "$test_dir/AIConfigFormStateTests.swift" \
  -o "$output_dir/AIConfigFormStateTests"

"$output_dir/AIConfigFormStateTests" \
  "$app_dir/Features/Settings/AIConfigEditorView.swift" \
  "$app_dir/Features/Settings/AISupportedProvidersSection.swift" \
  "$app_dir/Features/Settings/AICapabilitiesSection.swift"
