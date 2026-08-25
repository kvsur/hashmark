#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
if (( $# != 2 )); then
  print -u2 -- "usage: run-model-drift-audit.sh <baseline.json> <candidate.json>"
  exit 64
fi

output_dir=$(mktemp -d "${TMPDIR:-/tmp}/model-drift-audit.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT
xcrun swiftc -parse-as-library \
  "$test_dir/ModelCatalogDriftCLI.swift" \
  -o "$output_dir/model-catalog-drift"
"$output_dir/model-catalog-drift" "$1" "$2"
