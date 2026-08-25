#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-attachment-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  "$app_dir/Models/AIAttachment.swift" \
  "$app_dir/Models/AITool.swift" \
  "$app_dir/Models/AIDomain.swift" \
  "$app_dir/Models/AIReasoningBlock.swift" \
  "$app_dir/Models/AIMessage.swift" \
  "$app_dir/Models/AI/Attachments/AIAttachmentLifecycle.swift" \
  "$app_dir/Models/AI/Attachments/AIAttachmentPolicy.swift" \
  "$app_dir/Models/AI/Attachments/AIAttachmentOrchestrator.swift" \
  "$test_dir/AttachmentOrchestrationTests.swift" \
  -o "$output_dir/AttachmentOrchestrationTests"

"$output_dir/AttachmentOrchestrationTests"
