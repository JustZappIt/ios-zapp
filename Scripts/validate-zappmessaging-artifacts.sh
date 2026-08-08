#!/usr/bin/env bash

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="$(dirname "$APP_DIR")/zappMessaging"
PINNED_REF="$(grep '^zappMessaging=' "$APP_DIR/.zapp-deps" | cut -d= -f2)"
MANIFEST="$SDK_DIR/ios/Resources/worklet-manifest.json"
BUNDLE="$SDK_DIR/ios/Resources/worklet.bundle"
REPAIR="cd $SDK_DIR && npm run setup"

fail() {
  echo "error: zappMessaging iOS artifacts are stale or missing: $1" >&2
  echo "error: Repair with: $REPAIR" >&2
  exit 1
}

[ -d "$SDK_DIR/.git" ] || fail "sibling checkout not found at $SDK_DIR"
[ -f "$MANIFEST" ] || fail "worklet-manifest.json is missing"
[ -f "$BUNDLE" ] || fail "worklet.bundle is missing"

checked_out="$(git -C "$SDK_DIR" rev-parse HEAD)"
[ "$checked_out" = "$PINNED_REF" ] || fail "checkout $checked_out does not match pin $PINNED_REF"

manifest_commit="$(plutil -extract sourceCommit raw -o - "$MANIFEST")"
[ "$manifest_commit" = "$PINNED_REF" ] || fail "bundle was built from $manifest_commit, expected $PINNED_REF"

manifest_tree="$(plutil -extract sourceTree raw -o - "$MANIFEST")"
checked_out_tree="$(git -C "$SDK_DIR" rev-parse 'HEAD^{tree}')"
[ "$manifest_tree" = "$checked_out_tree" ] || fail "bundle source tree does not match the checkout"
manifest_dirty="$(plutil -extract sourceDirty raw -o - "$MANIFEST")"
[ "$manifest_dirty" = "false" ] || fail "bundle was generated from uncommitted SDK sources"

manifest_bundle_hash="$(plutil -extract bundleSHA256 raw -o - "$MANIFEST")"
actual_bundle_hash="$(shasum -a 256 "$BUNDLE" | awk '{print $1}')"
[ "$manifest_bundle_hash" = "$actual_bundle_hash" ] || fail "worklet.bundle hash does not match its manifest"

manifest_lock_hash="$(plutil -extract packageLockSHA256 raw -o - "$MANIFEST")"
actual_lock_hash="$(shasum -a 256 "$SDK_DIR/package-lock.json" | awk '{print $1}')"
[ "$manifest_lock_hash" = "$actual_lock_hash" ] || fail "package-lock.json does not match the generated artifacts"

# Expected set is the SDK's own SPM link list, so a repin needs no edit here. bare-link never prunes
# ios/Addons and the manifest is just a listing of it, so only Package.swift catches a stale framework.
expected_addons="$(
  sed -n '/^let addons = \[/,/^]/p' "$SDK_DIR/ios/Package.swift" 2>/dev/null |
    grep -oE '"[^"]+"' | tr -d '"' | sed 's/$/.xcframework/' | sort || true
)"
[ -n "$expected_addons" ] || fail "could not read the addon list from ios/Package.swift"
expected_count="$(printf '%s\n' "$expected_addons" | wc -l | tr -d ' ')"

manifest_addons=""
index=0
while addon="$(plutil -extract "addons.$index" raw -o - "$MANIFEST" 2>/dev/null)"; do
  [ -d "$SDK_DIR/ios/Addons/$addon" ] || fail "addon $addon is missing"
  manifest_addons="${manifest_addons}${addon}
"
  index=$((index + 1))
done
[ "$(printf '%s' "$manifest_addons" | sort)" = "$expected_addons" ] ||
  fail "manifest lists $index addons, ios/Package.swift links $expected_count, and they differ"

disk_addons="$(find "$SDK_DIR/ios/Addons" -maxdepth 1 -name '*.xcframework' -type d -exec basename {} \; | sort)"
[ "$disk_addons" = "$expected_addons" ] ||
  fail "ios/Addons does not match ios/Package.swift; it has stale or missing frameworks"

echo "zappMessaging artifacts verified: source=$PINNED_REF bundle=$actual_bundle_hash addons=$index"
