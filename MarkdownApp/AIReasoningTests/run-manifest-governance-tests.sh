#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-manifest-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  "$app_dir/Models/AI/AIProvider.swift" \
  "$app_dir/Models/AI/ProviderCapabilities.swift" \
  "$app_dir/Models/AI/Manifest/AIModelManifest.swift" \
  "$test_dir/ManifestGovernanceTests.swift" \
  -o "$output_dir/ManifestGovernanceTests"

"$output_dir/ManifestGovernanceTests"

