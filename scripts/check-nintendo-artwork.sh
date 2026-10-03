#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/hourcade-nintendo-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$check_dir/modules" \
  -o "$check_dir/check" \
  "$repo_root/Hourcade/App/NintendoArtworkStore.swift" \
  "$repo_root/tests/NintendoArtworkScenarios.swift"
"$check_dir/check" "$@"
