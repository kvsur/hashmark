#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
catalog="$app_dir/Resources/Localizable.xcstrings"
failures=0

fail() {
  print -u2 -- "FAIL: $1"
  failures=$((failures + 1))
}

jq empty "$catalog" || fail "Localizable.xcstrings is not valid JSON"

missing_translations=$(jq -r '
  ["de", "ja", "ko", "ru", "zh-Hans", "zh-Hant"] as $languages
  | [.strings | to_entries[]
      | select(.value.shouldTranslate != false)
      | select(($languages - ((.value.localizations // {}) | keys)) | length > 0)
      | .key]
  | join(" | ")
' "$catalog")
[[ -z "$missing_translations" ]] || fail "Missing supported-language entries: $missing_translations"

legacy_files=(
  "$app_dir/Models/AI/APIProtocol.swift"
  "$app_dir/Models/AI/ProviderProfile.swift"
  "$app_dir/Models/AI/ProviderRegistry.swift"
  "$app_dir/Models/AI/OpenAIChat"
)
for legacy_path in $legacy_files; do
  [[ ! -e "$legacy_path" ]] || fail "Legacy production path remains: $legacy_path"
done

if rg -n '\b(APIProtocol|ProviderProfile|ChatGPTClient|ClaudeClient)\b' "$app_dir" --glob '*.swift' >/dev/null; then
  fail "Legacy compatibility type is still referenced by production Swift"
fi

legacy_labels=(
  "API Protocol"
  "Anthropic protocol"
  "OpenAI protocol"
  "Custom OpenAI-compatible"
  "The provider does not support the selected API protocol."
)
for label in $legacy_labels; do
  if jq -e --arg key "$label" '.strings | has($key)' "$catalog" >/dev/null; then
    fail "Legacy compatibility label remains in the string catalog: $label"
  fi
done

compatible_occurrences=$(rg -n '/compatible-mode/' "$app_dir" --glob '*.swift' || true)
if [[ $(print -r -- "$compatible_occurrences" | sed '/^$/d' | wc -l | tr -d ' ') != 1 ]] ||
   [[ "$compatible_occurrences" != *"QwenRequestBuilder.swift"* ]]; then
  fail "Qwen compatible-mode must exist only as one fail-closed rejection guard"
fi

diagnostics=$(sed -n '/enum AIDiagnostics/,/^}/p' "$app_dir/Models/AIClient.swift")
if print -r -- "$diagnostics" | rg -n 'apiKey|message\.content|prompt|attachmentData|arguments=' >/dev/null; then
  fail "AI diagnostics may expose credentials or user content"
fi
if print -r -- "$diagnostics" | rg -n 'httpBody(?!\?\.count)' --pcre2 >/dev/null; then
  fail "AI diagnostics may expose a raw request body"
fi

if (( failures > 0 )); then
  exit 1
fi

print "RegressionAudit: PASS"
