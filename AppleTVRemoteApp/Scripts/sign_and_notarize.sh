#!/usr/bin/env bash
set -euo pipefail

# sign_and_notarize.sh
# Signs and notarizes the Atmo.app bundle for distribution

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/Atmo.app"
ZIP_FILE="${DIST_DIR}/Atmo.zip"

# Required environment variables
: "${APPLE_DEVELOPER_ID:?Error: APPLE_DEVELOPER_ID not set}"
: "${APPLE_TEAM_ID:?Error: APPLE_TEAM_ID not set}"
: "${APPLE_ID:?Error: APPLE_ID not set}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Error: APPLE_APP_SPECIFIC_PASSWORD not set}"

SIGNING_IDENTITY="Developer ID Application: ${APPLE_DEVELOPER_ID} (${APPLE_TEAM_ID})"
ENTITLEMENTS="${ROOT_DIR}/Support/Atmo.entitlements"

echo "==> Signing app bundle with identity: ${SIGNING_IDENTITY}"

# Sign all executables and frameworks within the bundle
find "${APP_BUNDLE}/Contents" -type f \( -name "*.dylib" -o -name "*.so" -o -perm +111 \) -print0 | while IFS= read -r -d '' file; do
    if file "${file}" | grep -q "Mach-O"; then
        echo "Signing: ${file}"
        codesign --force --sign "${SIGNING_IDENTITY}" \
            --options runtime \
            --timestamp \
            "${file}" 2>&1 | grep -v "signed Mach-O" || true
    fi
done

# Sign the main app bundle with entitlements
echo "Signing main app bundle..."
codesign --force --sign "${SIGNING_IDENTITY}" \
    --entitlements "${ENTITLEMENTS}" \
    --options runtime \
    --timestamp \
    --deep \
    "${APP_BUNDLE}"

# Verify signature
echo "==> Verifying signature..."
codesign --verify --verbose=2 "${APP_BUNDLE}"
spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"

# Create ZIP for notarization
echo "==> Creating ZIP for notarization..."
rm -f "${ZIP_FILE}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_FILE}"

# Submit for notarization
echo "==> Submitting for notarization..."
xcrun notarytool submit "${ZIP_FILE}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --wait

# Staple notarization ticket
echo "==> Stapling notarization ticket..."
xcrun stapler staple "${APP_BUNDLE}"

# Verify notarization
echo "==> Verifying notarization..."
spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"

# Recreate final ZIP with stapled app
echo "==> Creating final distribution ZIP..."
rm -f "${ZIP_FILE}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_FILE}"

echo "✓ Successfully signed and notarized ${APP_BUNDLE}"
echo "✓ Distribution package: ${ZIP_FILE}"
