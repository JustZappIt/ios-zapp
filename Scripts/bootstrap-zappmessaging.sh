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
# with no warning at all. (Android has the same coupling; see its CLAUDE.md.)
#
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIBLING="$(dirname "$APP_DIR")/zappMessaging"
PINNED_REF="$(grep '^zappMessaging=' "$APP_DIR/.zapp-deps" | cut -d= -f2)"

if [ ! -d "$SIBLING" ]; then
  echo "==> Cloning zappMessaging beside the app ($SIBLING)"
  git clone https://github.com/JustZappIt/zappMessaging.git "$SIBLING"
  git -C "$SIBLING" checkout "$PINNED_REF"
else
  echo "==> Found $SIBLING"
  echo "    Pinned ref in .zapp-deps: $PINNED_REF"
  echo "    Currently checked out:    $(git -C "$SIBLING" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  echo "    Not switching branches for you — check out the pin yourself if they differ."
fi

# `setup` = install + bare-link + bare-pack. It must NOT be `npm run link` alone:
# worklet.bundle names every addon by exact version, so a bundle/addon mismatch
# fails at RUNTIME with "No addon registered", never at build time.
echo "==> npm run setup (assembles the 15 addon xcframeworks + packs worklet.bundle)"
( cd "$SIBLING" && npm ci && npm run setup )

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
