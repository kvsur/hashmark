#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_dir=${test_dir:h}/MarkdownApp
manifest="$app_dir/Resources/AIProviders/manifest-v1.json"
schema="$app_dir/Resources/AIProviders/manifest-v1.schema.json"
fixtures="$test_dir/Fixtures/manifest.json"
sources="$test_dir/Fixtures/official-sources.json"
expected='["anthropic","gemini","glm","kimi","openAI"]'

jq empty "$manifest" "$schema" "$fixtures" "$sources"

jq -e --argjson expected "$expected" '
  .schemaVersion == 1
  and (.contentVersion | test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}\\.[0-9]+$"))
  and (.protocolEvidenceVersion | length > 0)
  and ([.providers[].provider] | sort == $expected)
  and all(.providers[]; . as $provider |
    (.models | length > 0)
    and ([.models[].id] | length == (unique | length))
    and ([.models[].id] | index($provider.defaultModel) != null)
    and (.verifiedAt >= "2026-08-24")
  )
' "$manifest" >/dev/null

jq -e --argjson expected "$expected" '
  .version == 2 and .verifiedAt == "2026-08-25"
  and ([.providers[].id] | sort == $expected)
  and all(.providers[];
    (["request","stream","source","error","image","file","decision"]
      - (.cases | keys) | length) == 0
  )
' "$fixtures" >/dev/null

jq -e --argjson expected "$expected" '
  .version == 1 and .reviewedAt == "2026-08-25"
  and ([.providers[].id] | sort == $expected)
  and all(.providers[];
    (.modelsAPI == null or (.modelsAPI | test("^https://(platform\\.openai\\.com|platform\\.claude\\.com|ai\\.google\\.dev|platform\\.kimi\\.ai)/")))
    and (.contractSources | length > 0)
    and all(.contractSources[];
      test("^https://(platform\\.openai\\.com|platform\\.claude\\.com|ai\\.google\\.dev|platform\\.kimi\\.ai|docs\\.bigmodel\\.cn)/")
    )
  )
  and (.providers[] | select(.id == "glm") | .modelsAPI) == null
' "$sources" >/dev/null

manifest_glm_strategy=$(jq -r '.providers[] | select(.provider == "glm") | .discoveryStrategy' "$manifest")
[[ "$manifest_glm_strategy" == "unavailable" ]] || {
  print -u2 -- "FAIL: GLM discovery must remain unavailable until an official Models API is frozen"
  exit 1
}

print "GovernanceAudit: PASS"
