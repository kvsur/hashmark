#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/fixture-manifest-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  -parse-as-library \
  "$test_dir/FixtureManifestTests.swift" \
  -o "$output_dir/FixtureManifestTests"

"$output_dir/FixtureManifestTests"
