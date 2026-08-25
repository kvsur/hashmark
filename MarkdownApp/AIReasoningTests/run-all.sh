#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
"${test_dir:h}/AISettingsTests/run-tests.sh"
"$test_dir/run-provider-tests.sh"
"$test_dir/run-openai-responses-tests.sh"
"$test_dir/run-anthropic-tests.sh"
"$test_dir/run-gemini-tests.sh"
"$test_dir/run-qwen-tests.sh"
"$test_dir/run-kimi-tests.sh"
"$test_dir/run-glm-tests.sh"
zsh "$test_dir/run-attachment-tests.sh"
zsh "$test_dir/run-search-session-tests.sh"
zsh "$test_dir/run-presentation-tests.sh"
zsh "$test_dir/run-fixture-manifest-tests.sh"
zsh "$test_dir/run-regression-audit.sh"
