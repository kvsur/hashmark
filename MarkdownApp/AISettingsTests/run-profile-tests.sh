#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-profile-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  "$app_dir/Models/AI/AIProvider.swift" \
  "$app_dir/Models/AI/ProviderCapabilities.swift" \
  "$app_dir/Models/AI/Manifest/AIModelManifest.swift" \
  "$app_dir/Models/AI/Discovery/AIModelCatalogScope.swift" \
  "$app_dir/Models/AI/Kimi/KimiModelContract.swift" \
  "$app_dir/Models/AI/AIProviderCapabilityRules.swift" \
  "$app_dir/Models/AI/AIProviderManifest.swift" \
  "$app_dir/Models/AIConfig.swift" \
  "$app_dir/Models/AI/Privacy/AIDataSharingConsent.swift" \
  "$app_dir/Models/AI/Configuration/AISettingsDocument.swift" \
  "$app_dir/Models/AIConfigStore.swift" \
  "$test_dir/AISettingsProfileTests.swift" \
  -o "$output_dir/AISettingsProfileTests"

"$output_dir/AISettingsProfileTests"
