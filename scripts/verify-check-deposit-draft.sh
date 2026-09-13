#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/tire-shop-check-deposit.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT

xcrun swiftc \
  "$repo_dir/TireShop/ShopClock.swift" \
  "$repo_dir/TireShop/CheckDates.swift" \
  "$repo_dir/TireShop/CheckDepositDraft.swift" \
  "$repo_dir/scripts/CheckDepositDraftChecks.swift" \
  -module-cache-path "$check_dir/module-cache" \
  -o "$check_dir/check-deposit-draft-checks"

"$check_dir/check-deposit-draft-checks"
