#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/model-drift-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT
xcrun swiftc -parse-as-library \
  "$test_dir/ModelCatalogDriftCLI.swift" \
  -o "$output_dir/model-catalog-drift"

"$output_dir/model-catalog-drift" \
  "$test_dir/DriftFixtures/baseline.json" \
  "$test_dir/DriftFixtures/baseline.json" > "$output_dir/unchanged.json"
jq -e '
  (.schemaDrift | length) == 0 and (.added | length) == 0
  and (.missing | length) == 0 and (.renameCandidates | length) == 0
  and (.lifecycleChanged | length) == 0 and (.metadataChanged | length) == 0
' "$output_dir/unchanged.json" >/dev/null

set +e
"$output_dir/model-catalog-drift" \
  "$test_dir/DriftFixtures/baseline.json" \
  "$test_dir/DriftFixtures/candidate.json" > "$output_dir/drift.json"
drift_status=$?
set -e
(( drift_status == 2 )) || { print -u2 -- "FAIL: drift command did not return exit 2"; exit 1; }
jq -e '
  .schemaDrift == ["protocolEvidenceVersion", "schemaVersion"]
  and .added == ["gpt-new"] and .missing == ["gpt-old"]
  and .renameCandidates == [{"addedID":"gpt-new","missingID":"gpt-old"}]
  and .lifecycleChanged == ["gpt-retiring"]
  and .metadataChanged == ["gpt-stable"]
' "$output_dir/drift.json" >/dev/null

print "ModelDriftTests: PASS"
