#!/usr/bin/env bash
#
# Rebuilds the Kotlin Multiplatform P2P engine and installs the resulting iOS
# XCFramework. The symbol and UTF-16 gates prevent a stale pre-onramp binary
# from being committed again.
#
set -euo pipefail

fail() { echo "!! GATE FAILED: $1" >&2; exit 1; }

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ZAPP_ANDROID_DIR:-$(dirname "$APP_DIR")/zapp-android}"
BUILD_OUTPUT="$ANDROID_DIR/offramp-lib/build/XCFrameworks/release/ZappOfframp.xcframework"
DESTINATION="$APP_DIR/Vendor/ZappOfframp.xcframework"

[ -d "$ANDROID_DIR" ] || fail "Android sibling checkout not found at $ANDROID_DIR"

if [ "${1:-}" != "--use-existing" ]; then
  if [ -x /usr/libexec/java_home ]; then
    export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
  fi
  echo "==> Building ZappOfframp.xcframework from $ANDROID_DIR"
  ( cd "$ANDROID_DIR" && ./gradlew :offramp-lib:assembleZappOfframpReleaseXCFramework )
fi

[ -d "$BUILD_OUTPUT" ] || fail "$BUILD_OUTPUT is missing"

verify_slice() {
  local slice="$1"
  local framework="$2/$slice/ZappOfframp.framework"
  local header="$framework/Headers/ZappOfframp.h"
  local binary="$framework/ZappOfframp"

  [ -f "$header" ] || fail "$slice header is missing"
  [ -f "$binary" ] || fail "$slice binary is missing"

  local symbols
  symbols="$(grep -aci onramp "$header")"
  [ "$symbols" -gt 0 ] || fail "$slice exports no on-ramp symbols"

  python3 - "$binary" <<'PY'
import sys

data = open(sys.argv[1], "rb").read()
for value in ("usdcRecipientAddress", "orders_collection"):
    if not data.count(value.encode("utf-16-le")):
        raise SystemExit(f"missing UTF-16 protocol literal: {value}")
PY

  echo "    $slice: $symbols on-ramp header matches; protocol literals present"
}

echo "==> Verifying built framework"
verify_slice ios-arm64 "$BUILD_OUTPUT"
verify_slice ios-arm64-simulator "$BUILD_OUTPUT"

staging="$(mktemp -d "${TMPDIR:-/tmp}/zapp-offramp.XXXXXX")"
backup="$APP_DIR/Vendor/.ZappOfframp.xcframework.backup"
trap 'rm -rf "$staging" "$backup"' EXIT
cp -R "$BUILD_OUTPUT" "$staging/ZappOfframp.xcframework"

[ ! -L "$DESTINATION" ] || fail "refusing to replace symlink at $DESTINATION"
rm -rf "$backup"
if [ -e "$DESTINATION" ]; then
  mv "$DESTINATION" "$backup"
fi
mv "$staging/ZappOfframp.xcframework" "$DESTINATION"

echo "==> Verifying installed framework"
verify_slice ios-arm64 "$DESTINATION"
verify_slice ios-arm64-simulator "$DESTINATION"
rm -rf "$backup"

echo "==> Ready: $DESTINATION"
