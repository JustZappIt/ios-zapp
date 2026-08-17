#!/usr/bin/env bash
#
# secant.xcodeproj references ../zappMessaging/ios as a LOCAL Swift package, and
# that package's binary artifacts are generated, not committed. Without them
# Xcode fails to resolve with:
#
#     error: ... sodium-native.5.1.0.xcframework does not contain binary artifact
#
# which is correct but says nothing about what to do. This script is what to do.
#
# Run it after a fresh clone, and again whenever you pull JS changes in
# zappMessaging — an ios-zapp build will otherwise link a STALE worklet.bundle
# with no warning at all. (Android has the same coupling; see its AGENTS.md.)
#
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIBLING="$(dirname "$APP_DIR")/zappMessaging"
PINNED_REF="$(grep '^zappMessaging=' "$APP_DIR/.zapp-deps" | cut -d= -f2)"

if [ ! -d "$SIBLING" ]; then
  echo "==> Cloning zappMessaging beside the app ($SIBLING)"
  git clone https://github.com/JustZappIt/zappmessaging-sdk.git "$SIBLING"
  git -C "$SIBLING" checkout "$PINNED_REF"
else
  echo "==> Found $SIBLING"
  echo "    Pinned ref in .zapp-deps: $PINNED_REF"
  echo "    Currently checked out:    $(git -C "$SIBLING" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  echo "    Not switching branches for you — check out the pin yourself if they differ."
fi

# `link` + `build` = `npm run setup` minus its leading `npm install`. Both halves
# are required: worklet.bundle names every addon by exact version, so `link` alone
# fails at RUNTIME with "No addon registered", never at build time.
#
# `npm install` is skipped on purpose. `npm ci` already installed exactly the
# lockfile, and the SDK's committed package-lock.json is missing an `engines` block
# that `npm install` writes back, dirtying the checkout and tripping
# Scripts/validate-zappmessaging-artifacts.sh. Drop this once the SDK repins its lock.
echo "==> assembling the 15 addon xcframeworks + packing worklet.bundle"
( cd "$SIBLING" && npm ci && npm run link && npm run build )

COUNT=$(ls -d "$SIBLING"/ios/Addons/*.xcframework 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" != "15" ]; then
  echo "!! expected 15 addon xcframeworks, found $COUNT" >&2
  exit 1
fi
if [ ! -f "$SIBLING/ios/Resources/worklet.bundle" ]; then
  echo "!! worklet.bundle was not generated" >&2
  exit 1
fi

echo "==> Ready: $COUNT addons + worklet.bundle ($(wc -c < "$SIBLING/ios/Resources/worklet.bundle" | tr -d ' ') bytes)"
"$APP_DIR/Scripts/validate-zappmessaging-artifacts.sh"
