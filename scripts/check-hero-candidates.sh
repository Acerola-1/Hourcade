#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/hourcade-hero-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$check_dir/modules" \
  -o "$check_dir/check" \
  "$repo_root/Hourcade/Shared/GameSnapshot.swift" \
  "$repo_root/Hourcade/Shared/PlatformSnapshots.swift" \
  "$repo_root/tests/HeroCandidateScenarios.swift"
"$check_dir/check"
