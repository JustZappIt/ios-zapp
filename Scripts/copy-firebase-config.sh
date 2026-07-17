#!/bin/sh

set -eu

# Firebase configuration is deliberately external to source control. A caller
# can provide one exact file, a root containing per-target directories, or use
# the deterministic repository-local convention:
#   FirebaseConfig/<target>/GoogleService-Info.plist
if [ -n "${ZAPP_FIREBASE_CONFIG_PATH:-}" ]; then
    source_plist="$ZAPP_FIREBASE_CONFIG_PATH"
elif [ -n "${ZAPP_FIREBASE_CONFIG_ROOT:-}" ]; then
    source_plist="$ZAPP_FIREBASE_CONFIG_ROOT/$TARGET_NAME/GoogleService-Info.plist"
else
    source_plist="$SRCROOT/FirebaseConfig/$TARGET_NAME/GoogleService-Info.plist"
fi

destination_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
destination_plist="$destination_dir/GoogleService-Info.plist"

# A missing file is a supported configuration for local development and CI.
# Remove an output left by an incremental build so a different target's config
# can never leak into this product.
if [ ! -f "$source_plist" ]; then
    rm -f "$destination_plist"
    echo "Firebase config absent for $TARGET_NAME; push notifications disabled"
    exit 0
fi

configured_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$source_plist" 2>/dev/null || true)
if [ "$configured_bundle_id" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
    echo "error: Firebase config BUNDLE_ID does not match $PRODUCT_BUNDLE_IDENTIFIER" >&2
    exit 1
fi

mkdir -p "$destination_dir"
/usr/bin/install -m 0644 "$source_plist" "$destination_plist"
echo "Injected Firebase config for $TARGET_NAME"
