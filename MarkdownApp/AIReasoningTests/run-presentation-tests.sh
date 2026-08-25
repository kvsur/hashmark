#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-presentation-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  -default-isolation MainActor \
  "$app_dir/Models/AITool.swift" \
  "$app_dir/Models/AIDomain.swift" \
  "$app_dir/Models/AI/AIProvider.swift" \
  "$app_dir/Features/AI/AIPresentationState.swift" \
  "$app_dir/Features/AI/AIStreamDeltaCoalescer.swift" \
  "$test_dir/PresentationStateTests.swift" \
  -o "$output_dir/PresentationStateTests"

"$output_dir/PresentationStateTests"
