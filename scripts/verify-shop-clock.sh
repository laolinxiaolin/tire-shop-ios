#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/tire-shop-clock.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT

xcrun swiftc \
  "$repo_dir/TireShop/ShopClock.swift" \
  "$repo_dir/scripts/ShopClockChecks.swift" \
  -o "$check_dir/shop-clock-checks"

"$check_dir/shop-clock-checks"
