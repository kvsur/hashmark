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
if [[ -n "$compatible_occurrences" ]]; then
  fail "Compatibility-mode routes remain in production sources"
fi

removed_provider_pattern='[Qq]''wen|[Dd]''ash[Ss]cope'
removed_provider_hits=$(rg -n "$removed_provider_pattern" "$app_dir" "$test_dir" || true)
if [[ -n "$removed_provider_hits" ]]; then
  fail "Retired provider content remains in current product or maintenance surfaces"
fi

hardcoded_model_pattern='gpt-5\\.|claude-(fable|mythos|opus|sonnet)|gemini-[0-9]|kimi-k[0-9]|glm-[0-9]'
if rg -n "$hardcoded_model_pattern" "$app_dir" --glob '*.swift' >/dev/null; then
  fail "Production Swift contains a maintenance model ID that belongs in the versioned Manifest"
fi

decision_bypass=$(rg -n \
  'effectiveCapabilities\\.(webSearch|imageInput|inlinePDF|directFileInput|displayableReasoning)' \
  "$app_dir/Models/AI/OpenAIResponses" \
  "$app_dir/Models/AI/Anthropic" \
  "$app_dir/Models/AI/Gemini" \
  "$app_dir/Models/AI/Kimi" \
  "$app_dir/Models/AI/GLM" || true)
if [[ -n "$decision_bypass" ]]; then
  fail "A Provider request path bypasses the layered capability decision"
fi

verification_sources=(
  "$app_dir/Models/AI/Capabilities/AICapabilityVerificationStore.swift"
  "$app_dir/Models/AI/Capabilities/AICapabilityVerificationRecorder.swift"
)
if rg -n 'apiKey|message\\.content|prompt|httpBody|attachment' $verification_sources >/dev/null; then
  fail "Capability verification may persist credentials or user content"
fi

diagnostics=$(sed -n '/enum AIDiagnostics/,/^}/p' "$app_dir/Models/AIClient.swift")
if print -r -- "$diagnostics" | rg -n 'apiKey|message\.content|prompt|attachmentData|arguments=' >/dev/null; then
  fail "AI diagnostics may expose credentials or user content"
fi
if print -r -- "$diagnostics" | rg -n 'httpBody(?!\?\.count)' --pcre2 >/dev/null; then
  fail "AI diagnostics may expose a raw request body"
fi

repo_dir=${test_dir:h:h}
privacy_page="$repo_dir/docs/privacy/index.html"
app_links="$app_dir/App/AppLinks.swift"
about_view="$app_dir/Features/Settings/AboutView.swift"
consent_store="$app_dir/Models/AI/Privacy/AIDataSharingConsent.swift"
writing_view="$app_dir/Features/AI/AIWritingView.swift"
settings_view="$app_dir/Features/Settings/AIConfigEditorView.swift"

[[ -f "$privacy_page" ]] || fail "Public privacy policy source is missing"
for required_policy_term in \
  'iCloud' \
  'OpenAI' \
  'Anthropic' \
  'Google Gemini' \
  'Moonshot Kimi' \
  'Zhipu GLM' \
  'API key' \
  'Retention and deletion'; do
  rg -q --fixed-strings "$required_policy_term" "$privacy_page" \
    || fail "Privacy policy is missing: $required_policy_term"
done

rg -q --fixed-strings 'https://kvsur.github.io/hashmark/privacy/' "$app_links" \
  || fail "App privacy URL does not match the GitHub Pages target"
rg -q --fixed-strings 'AppLinks.privacyPolicy' "$about_view" \
  || fail "About screen does not expose the privacy policy"
rg -q --fixed-strings 'AIDataSharingConsentStore().hasConsent' "$app_dir/Models/AIClient.swift" \
  || fail "AI client creation is not protected by the consent gate"
rg -q --fixed-strings 'AIDataSharingConsentStore' "$consent_store" \
  || fail "AI consent store is missing"
rg -q --fixed-strings 'showDataSharingConsent' "$writing_view" \
  || fail "AI writing start does not present the consent disclosure"
rg -q --fixed-strings 'Withdraw AI Data Sharing Consent' "$settings_view" \
  || fail "AI settings do not expose consent withdrawal"

if (( failures > 0 )); then
  exit 1
fi

print "RegressionAudit: PASS"
