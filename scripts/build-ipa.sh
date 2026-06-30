#!/usr/bin/env bash
#
# Local unsigned iOS .ipa build for the standalone iOS app. This is the same
# recipe the manual GitHub Actions workflow uses, but on this Mac:
#
#   1. expo prebuild   → (re)generates the native ios/ project
#   2. pod install     → installs CocoaPods deps (Stripe Terminal, etc.)
#   3. xcodebuild       → Release archive with signing turned OFF
#   4. zip Payload/     → wraps the .app into tire-shop.ipa
#
# The result is UNSIGNED, so iOS won't install it as-is. Re-sign it on the way
# to the device with Sideloadly or AltStore (free Apple ID), or install on a
# jailbroken device — same as the CI .ipa.
#
# Requires macOS with Xcode + command line tools + CocoaPods (brew install
# cocoapods) + Node 20 / pnpm.
#
# Usage:  pnpm build:ipa
#
#   Override the output folder (default ~/ipa-share):
#     IPA_SHARE_DIR=/some/path pnpm build:ipa
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="$REPO_ROOT"
IOS="$MOBILE/ios"
SHARE_DIR="${IPA_SHARE_DIR:-$HOME/ipa-share}"

SCHEME="TireShop"
WORKSPACE="$IOS/$SCHEME.xcworkspace"

[ "$(uname)" = "Darwin" ] || { echo "This builds iOS — run it on macOS."; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild not found — install Xcode."; exit 1; }
command -v pod        >/dev/null || { echo "CocoaPods not found — brew install cocoapods."; exit 1; }

echo "==> expo prebuild (regenerating native ios/ project)"
( cd "$MOBILE" && npx expo prebuild -p ios --clean )

echo "==> pod install"
( cd "$IOS" && pod install )

echo "==> xcodebuild archive (unsigned)"
ARCHIVE="$IOS/build/$SCHEME.xcarchive"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

APP="$ARCHIVE/Products/Applications/$SCHEME.app"
[ -d "$APP" ] || { echo "No .app at $APP"; exit 1; }

echo "==> packaging .ipa"
STAGE="$IOS/build/payload-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

mkdir -p "$SHARE_DIR"
OUT="$SHARE_DIR/tire-shop.ipa"
rm -f "$OUT"
( cd "$STAGE" && zip -qry "$OUT" Payload )
rm -rf "$STAGE"

echo
echo "==> Done: $OUT ($(du -h "$OUT" | cut -f1))"
echo "    UNSIGNED — re-sign before installing:"
echo "      Sideloadly (https://sideloadly.io/) or AltStore (https://altstore.io/),"
echo "      both re-sign with a free Apple ID."
