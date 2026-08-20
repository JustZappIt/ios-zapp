#!/usr/bin/env bash
#
# secant.xcodeproj references ../zcash-swift-wallet-sdk as a LOCAL Swift package whose
# binary artifact is generated from Rust, not committed. It also has to be generated the
# right way: upstream's default build links zodl-slipstream (AGPL-3.0-only), which we may
# not convey through the App Store. Not passing --slipstream is the whole difference; the
# gates at the bottom are what make that a checked fact.
#
set -euo pipefail

fail() { echo "!! GATE FAILED: $1" >&2; exit 1; }

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIBLING="$(dirname "$APP_DIR")/zcash-swift-wallet-sdk"
# Explicit, because errexit would otherwise kill the assignment with no message at all.
PINNED_REF="$(grep '^zcashSwiftWalletSdk=' "$APP_DIR/.zapp-deps" | cut -d= -f2)" \
  || fail "no zcashSwiftWalletSdk= pin in $APP_DIR/.zapp-deps"

# The pin is on an unmerged branch that only our fork carries; upstream cannot resolve it.
SDK_REMOTE="${ZAPP_SDK_REMOTE:-https://github.com/JustZappIt/zcash-swift-wallet-sdk.git}"
PINNED_BRANCH="${ZAPP_SDK_BRANCH:-zapp/sdk-mit-on-main}"

if [ ! -d "$SIBLING" ]; then
  echo "==> Cloning zcash-swift-wallet-sdk beside the app ($SIBLING)"
  git clone "$SDK_REMOTE" "$SIBLING"
  git -C "$SIBLING" fetch "$SDK_REMOTE" "$PINNED_BRANCH" || true
  if ! git -C "$SIBLING" cat-file -e "$PINNED_REF^{commit}" 2>/dev/null; then
    echo "!! $PINNED_REF is not reachable from $SDK_REMOTE ($PINNED_BRANCH)." >&2
    echo "   The branch was probably force-pushed. Re-pin .zapp-deps to its current head," >&2
    echo "   or point ZAPP_SDK_REMOTE / ZAPP_SDK_BRANCH at wherever the commit now lives." >&2
    exit 1
  fi
  git -C "$SIBLING" checkout "$PINNED_REF"
else
  echo "==> Found $SIBLING"
  # Refuse to build a checkout that is not the pin. Same standard as
  # Scripts/validate-zappmessaging-artifacts.sh applies to the other sibling: an advisory
  # notice here would mean the SHA pin binds on a fresh clone only, and every returning
  # developer builds whatever they happen to have out — including a pre-pin revision where
  # zodl-slipstream is still a MANDATORY dependency rather than an optional feature.
  checked_out="$(git -C "$SIBLING" rev-parse HEAD)" || fail "$SIBLING is not a git checkout"
  if [ "$checked_out" != "$PINNED_REF" ]; then
    echo "!! $SIBLING is at $checked_out, but .zapp-deps pins $PINNED_REF." >&2
    echo "   Recover with:" >&2
    echo "     git -C $SIBLING fetch $SDK_REMOTE $PINNED_BRANCH" >&2
    echo "     git -C $SIBLING checkout $PINNED_REF" >&2
    exit 1
  fi
  # A matching SHA says nothing about the working tree, and init-local-ffi.sh compiles
  # whatever is on disk. Catch it here rather than after a multi-minute build.
  [ -z "$(git -C "$SIBLING" status --porcelain)" ] \
    || fail "$SIBLING has uncommitted changes — commit, stash or discard them first"
  echo "    At the pin: $PINNED_REF, clean"
fi

command -v rustup >/dev/null \
  || fail "rustup is not installed, and the FFI is compiled from Rust — see https://rustup.rs"

for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  if ! rustup target list --installed 2>/dev/null | grep -qx "$target"; then
    echo "!! Rust target $target is not installed. Run:" >&2
    echo "     rustup target add aarch64-apple-ios aarch64-apple-ios-sim" >&2
    exit 1
  fi
done

# --slipstream leaves this marker; Package.swift treats the checkout as the AGPL variant.
if [ -f "$SIBLING/.zodl-slipstream-variant" ]; then
  echo "!! $SIBLING was last built as the ZODL Slipstream (AGPL) variant." >&2
  echo "   Remove .zodl-slipstream-variant and re-run to get the clean artifact." >&2
  exit 1
fi

# --arm-ios, never --arm-all: the app consumes only the two iOS slices.
echo "==> Building the clean (slipstream-free) FFI — a few minutes from cold"
( cd "$SIBLING" && ./Scripts/init-local-ffi.sh --arm-ios )

echo "==> Purity gates"
# One definition of the gates, shared with the release path — see the header of the
# verifier for why a build-free check has to exist separately from this script.
"$APP_DIR/Scripts/verify-zcash-sdk-artifact.sh"

echo "==> Ready: clean libzcashlc.xcframework, 0 AGPL crates, both iOS slices gated"
