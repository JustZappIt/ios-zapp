#!/usr/bin/env bash
#
# Verifies the libzcashlc the app will link. No build — this is the cheap check that any
# path shipping a binary can afford to run, and the release path MUST run: a local Swift
# package is consumed live off disk, so nothing else proves that what gets archived is the
# reviewed, slipstream-free artifact.
#
# Split out of bootstrap-zcash-sdk.sh so the gates have exactly one definition. Run it
# directly after any SDK rebuild you did by hand.
#
set -euo pipefail

fail() { echo "!! GATE FAILED: $1" >&2; exit 1; }

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIBLING="$(dirname "$APP_DIR")/zcash-swift-wallet-sdk"
# EXPECTED_PIN lets a caller name the revision it is actually releasing. The release
# lane sets it from `.zapp-deps` AS COMMITTED AT THE REF being built, because this
# script resolves $APP_DIR from its own location — the operator's checkout — which is
# the wrong file whenever the ref pins a different SDK revision than the branch the
# operator happens to be standing on. Unset (manual runs, CI) it falls back to the
# checkout, which is correct there.
if [ -n "${EXPECTED_PIN:-}" ]; then
  PINNED_REF="$EXPECTED_PIN"
  PIN_SOURCE="EXPECTED_PIN"
else
  PIN_SOURCE="$APP_DIR/.zapp-deps"
  PINNED_REF="$(grep '^zcashSwiftWalletSdk=' "$APP_DIR/.zapp-deps" | cut -d= -f2)" \
    || fail "no zcashSwiftWalletSdk= pin in $APP_DIR/.zapp-deps"
fi

[ -d "$SIBLING" ] || fail "sibling checkout not found at $SIBLING"

checked_out="$(git -C "$SIBLING" rev-parse HEAD)" || fail "$SIBLING is not a git checkout"
[ "$checked_out" = "$PINNED_REF" ] \
  || fail "$SIBLING is at $checked_out, but $PIN_SOURCE pins $PINNED_REF"

# A matching SHA says nothing about the working tree. Uncommitted edits to Cargo.toml, the
# Rust sources or Package.swift are compiled by init-local-ffi.sh just the same, so a dirty
# checkout means the artifact does not correspond to the reviewed commit — the symbol and
# string gates below cannot show that, they only speak to slipstream.
[ -z "$(git -C "$SIBLING" status --porcelain)" ] \
  || fail "$SIBLING has uncommitted changes — the artifact would not match $PINNED_REF"

cd "$SIBLING"

# Xcode's nm cannot read object files whose bitcode a NEWER LLVM produced: a Rust toolchain
# ahead of the one Xcode ships makes it exit with "Unknown attribute kind" rather than
# under-report, and these gates correctly refuse to read that as "no symbols found". Prefer
# the Rust toolchain's own llvm-nm, whose reader always matches the producer, and fall back
# to nm where the llvm-tools component is not installed.
NM="nm"
if rust_sysroot="$(rustc --print sysroot 2>/dev/null)" \
  && rust_host="$(rustc -vV 2>/dev/null | sed -n 's/^host: //p')"; then
  candidate="$rust_sysroot/lib/rustlib/$rust_host/bin/llvm-nm"
  if [ -x "$candidate" ]; then
    NM="$candidate"
  fi
fi

XCFRAMEWORK="LocalPackages/libzcashlc.xcframework"
[ -d "$XCFRAMEWORK" ] || fail "$XCFRAMEWORK is missing — run Scripts/bootstrap-zcash-sdk.sh"

# --arm-ios packages exactly these two, so the list doubles as a completeness check: a slice
# missing from disk is a partial install, not a pass.
SLICES=(
  "ios-arm64:aarch64-apple-ios"
  "ios-arm64_x86_64-simulator:aarch64-apple-ios-sim"
)

# One graph for the whole build, so this is not per-slice. Captured before grepping: a
# `cargo tree` that dies prints nothing, and a `grep -c` over nothing counts zero, which
# would read as a pass.
tree_output="$(cargo tree --edges normal --target aarch64-apple-ios)" \
  || fail "cargo tree failed — the build graph could not be read"
[ "$(printf '%s\n' "$tree_output" | grep -ic zodl)" = 0 ] \
  || fail "a zodl crate is in the build graph"

for entry in "${SLICES[@]}"; do
  slice="${entry%%:*}"
  rust_target="${entry##*:}"
  binary="$XCFRAMEWORK/$slice/libzcashlc.framework/libzcashlc"
  built="target/$rust_target/release/libzcashlc.a"

  [ -f "$binary" ] || fail "$binary was not produced"

  # init-local-ffi.sh installs each slice by copying the archive verbatim, so anything other
  # than byte equality means the framework predates this build and the gates below would be
  # reading a different artifact from the one the sources produce.
  [ -f "$built" ] || fail "$built is missing — the framework cannot be shown to match the source"
  cmp -s "$built" "$binary" || fail "$slice is stale — it does not match the built archive"

  # llvm-nm reports every symbol-less object on stderr, which buries a real reader error in
  # a wall of noise. Keep it, but only show it when the read actually fails.
  nm_err="$(mktemp)"
  if ! syms="$("$NM" -gU "$binary" 2>"$nm_err")"; then
    cat "$nm_err" >&2
    rm -f "$nm_err"
    fail "$NM could not read $binary"
  fi
  rm -f "$nm_err"
  [ "$(printf '%s\n' "$syms" | grep -c zcashlc_slipstream)" = 0 ] \
    || fail "slipstream FFI symbols are in $slice"

  blob="$(strings "$binary")" || fail "strings could not read $binary"
  [ "$(printf '%s\n' "$blob" | grep -ci slipstream)" = 0 ] \
    || fail "slipstream strings are in $slice"

  # Counterpart gate: an excision that also took Ironwood would pass all three above.
  migration_syms="$(printf '%s\n' "$syms" | grep -o '_zcashlc_migration_[a-z_]*' | sort -u | wc -l | tr -d ' ')"
  [ "$migration_syms" = 32 ] \
    || fail "expected 32 zcashlc_migration_* symbols in $slice, found $migration_syms"

  echo "    $slice: 0 slipstream symbols, 0 slipstream strings, $migration_syms/32 migration symbols"
done

echo "==> Verified: clean libzcashlc.xcframework at $PINNED_REF, both iOS slices gated"
