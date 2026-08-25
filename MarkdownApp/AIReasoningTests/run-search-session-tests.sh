#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-search-session-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  -default-isolation MainActor \
  "$app_dir/Models/AIAttachment.swift" \
  "$app_dir/Models/AITool.swift" \
  "$app_dir/Models/AIDomain.swift" \
  "$app_dir/Models/AIReasoningBlock.swift" \
  "$app_dir/Models/AIStreamEvent.swift" \
  "$app_dir/Models/AI/AIWebSearchExecutionGate.swift" \
  "$app_dir/Models/AIMessage.swift" \
  "$app_dir/Models/AI/SystemPromptContext.swift" \
  "$app_dir/Models/AI/Attachments/AIAttachmentLifecycle.swift" \
  "$app_dir/Models/AI/Attachments/AIAttachmentPolicy.swift" \
  "$app_dir/Models/AI/Attachments/AIAttachmentOrchestrator.swift" \
  "$app_dir/Features/AI/AIPresentationState.swift" \
  "$app_dir/Features/AI/AIStreamDeltaCoalescer.swift" \
  "$app_dir/Features/AI/AIWritingSession.swift" \
  "$app_dir/Features/AI/AIWritingSession+Attachments.swift" \
  "$app_dir/Features/AI/AIWritingSession+Continuation.swift" \
  "$test_dir/SearchAndSessionStateTests.swift" \
  -o "$output_dir/SearchAndSessionStateTests"

"$output_dir/SearchAndSessionStateTests"
