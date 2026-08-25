#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-capability-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  "$app_dir/Models/AI/AIProvider.swift" \
  "$app_dir/Models/AI/ProviderCapabilities.swift" \
  "$app_dir/Models/AI/Manifest/AIModelManifest.swift" \
  "$app_dir/Models/AI/Kimi/KimiModelContract.swift" \
  "$app_dir/Models/AI/AIProviderCapabilityRules.swift" \
  "$app_dir/Models/AI/AIProviderManifest.swift" \
  "$app_dir/Models/AIConfig.swift" \
  "$app_dir/Models/AI/Discovery/AIModelDescriptor.swift" \
  "$app_dir/Models/AI/Discovery/AIModelCatalogScope.swift" \
  "$app_dir/Models/AI/Capabilities/AICapabilityDecision.swift" \
  "$app_dir/Models/AI/Capabilities/AICapabilityResolver.swift" \
  "$app_dir/Models/AI/Capabilities/AICapabilityVerificationStore.swift" \
  "$test_dir/CapabilityResolverTests.swift" \
  -o "$output_dir/CapabilityResolverTests"

"$output_dir/CapabilityResolverTests"

