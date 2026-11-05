#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
task_tmp="$(mktemp -d)"
trap 'rm -rf "${task_tmp}"' EXIT
xcrun --sdk macosx clang -fobjc-arc -framework Foundation \
    -I "${project_dir}/Sources/CPowerUIBridge/include" \
    "${project_dir}/Tests/CPowerUIBridgeTests/BridgeTests.m" \
    -o "${task_tmp}/bridge-tests"
"${task_tmp}/bridge-tests"
