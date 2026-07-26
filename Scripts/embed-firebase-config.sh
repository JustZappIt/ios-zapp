#!/bin/bash

set -euo pipefail

# Firebase configuration is intentionally ignored by Git. Prefer a
# bundle-specific file when multiple variants are configured, and keep the
# conventional filename as the production/mainnet fallback.
bundle_specific="${SRCROOT}/GoogleService-Info.${PRODUCT_BUNDLE_IDENTIFIER}.plist"
fallback="${SRCROOT}/GoogleService-Info.plist"

if [[ -f "${bundle_specific}" ]]; then
    config="${bundle_specific}"
elif [[ -f "${fallback}" ]]; then
    config="${fallback}"
else
    echo "warning: Firebase Messaging disabled: no GoogleService-Info plist for ${PRODUCT_BUNDLE_IDENTIFIER}"
    exit 0
fi

configured_bundle_id=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "${config}" 2>/dev/null || true)
if [[ "${configured_bundle_id}" != "${PRODUCT_BUNDLE_IDENTIFIER}" ]]; then
    echo "warning: Firebase Messaging disabled: ${config##*/} is for ${configured_bundle_id}, not ${PRODUCT_BUNDLE_IDENTIFIER}"
    exit 0
fi

destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
/bin/mkdir -p "$(dirname "${destination}")"
/bin/cp "${config}" "${destination}"
/bin/chmod 0644 "${destination}"
