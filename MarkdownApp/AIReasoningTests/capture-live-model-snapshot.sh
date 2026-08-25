#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
if (( $# != 2 )); then
  print -u2 -- "usage: capture-live-model-snapshot.sh <provider> <output.json>"
  print -u2 -- "set AI_PROVIDER_API_KEY and optionally AI_PROVIDER_BASE_URL"
  exit 64
fi

output_dir=$(mktemp -d "${TMPDIR:-/tmp}/live-model-snapshot.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT
xcrun swiftc \
  "$app_dir/Models/AI/AIProvider.swift" \
  "$app_dir/Models/AI/ProviderCapabilities.swift" \
  "$app_dir/Models/AI/Manifest/AIModelManifest.swift" \
  "$app_dir/Models/AI/Discovery/AIModelDescriptor.swift" \
  "$app_dir/Models/AI/Discovery/AIModelCatalogScope.swift" \
  "$app_dir/Models/AI/Discovery/AIModelDiscoveryStrategy.swift" \
  "$app_dir/Models/AI/Discovery/OpenAIModelDiscovery.swift" \
  "$app_dir/Models/AI/Discovery/AnthropicModelDiscovery.swift" \
  "$app_dir/Models/AI/Discovery/GeminiModelDiscovery.swift" \
  "$app_dir/Models/AI/Discovery/KimiModelDiscovery.swift" \
  "$app_dir/Models/AI/Discovery/GLMModelDiscovery.swift" \
  "$app_dir/Models/AI/Kimi/KimiModelContract.swift" \
  "$app_dir/Models/AI/AIProviderCapabilityRules.swift" \
  "$app_dir/Models/AI/AIProviderManifest.swift" \
  "$app_dir/Models/AIConfig.swift" \
  "$app_dir/Models/AI/AIModelCatalogService.swift" \
  "$test_dir/LiveModelSnapshotCLI.swift" \
  -o "$output_dir/live-model-snapshot"

"$output_dir/live-model-snapshot" "$1" "$2"
