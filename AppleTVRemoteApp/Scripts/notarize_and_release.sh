#!/usr/bin/env bash
set -euo pipefail

# notarize_and_release.sh
# Build, sign, notarize, and optionally upload to GitHub

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ZIP_NAME="Atmo.zip"
NOTARIZE_ZIP="Atmo-notarize.zip"
STAPLED_ZIP="Atmo-stapled.zip"

# Parse options
SKIP_UPLOAD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-upload)
            SKIP_UPLOAD=true
            shift
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Build, sign, and notarize Atmo for release.

Options:
  --no-upload       Skip GitHub release creation (default for local builds)
  --help            Show this help message

Environment variables (required):
  DEVELOPER_ID_APPLICATION    Your Developer ID signing identity

Notarization (required - choose one method):
  Method 1 - API Key (recommended):
    NOTARY_KEY_PATH             Path to .p8 API key file
    NOTARY_KEY_ID               Key ID
    NOTARY_ISSUER_ID            Issuer ID

  Method 2 - App-Specific Password:
    APPLEID                     Your Apple ID
    APP_SPECIFIC_PASSWORD       App-specific password

After building, upload to GitHub with:
  ./Scripts/upload_release.sh v1.0.0

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

command -v xcrun >/dev/null || { echo "xcrun required" >&2; exit 1; }
command -v codesign >/dev/null || { echo "codesign required" >&2; exit 1; }

: "# Required env vars"
: "# DEVELOPER_ID_APPLICATION - exact codesign identity (e.g. 'Developer ID Application: Name (TEAMID)')"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "DEVELOPER_ID_APPLICATION environment variable must be set to a Developer ID Application identity." >&2
  exit 1
fi

# Build unsigned app bundle + zip
bash "${ROOT_DIR}/Scripts/release.sh"

mkdir -p "${ROOT_DIR}/_notarize_tmp"
TMPDIR="${ROOT_DIR}/_notarize_tmp"
rm -rf "${TMPDIR:?}/*"

unzip -o "${DIST_DIR}/${ZIP_NAME}" -d "${TMPDIR}"
APP_BUNDLE="${TMPDIR}/Atmo.app"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "App bundle not found at ${APP_BUNDLE}" >&2
  exit 1
fi

echo "Signing ${APP_BUNDLE} with '${DEVELOPER_ID_APPLICATION}'"
# Sign the bundle (deep, runtime enabled)
codesign --force --options runtime --deep --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${APP_BUNDLE}"

# Repack the signed app for notarization
pushd "${TMPDIR}" >/dev/null
rm -f "${DIST_DIR}/${NOTARIZE_ZIP}"
zip -r "${DIST_DIR}/${NOTARIZE_ZIP}" "Atmo.app" >/dev/null
popd >/dev/null

# Notarize using notarytool (preferred) or altool fallback
if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  echo "Submitting with notarytool using API key"
  xcrun notarytool submit "${DIST_DIR}/${NOTARIZE_ZIP}" \
    --key "${NOTARY_KEY_PATH}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID}" --wait || { echo "Notarization failed" >&2; exit 1; }
else
  if [[ -n "${APPLEID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "Submitting with altool (Apple ID)"
    xcrun altool --notarize-app -f "${DIST_DIR}/${NOTARIZE_ZIP}" -u "${APPLEID}" -p "${APP_SPECIFIC_PASSWORD}" --primary-bundle-id "io.bino.atmo" || { echo "Notarization submission failed" >&2; exit 1; }
    echo "Waiting for notarization to complete. Use altool --notarization-info <REQUEST-UUID> to poll status." >&2
    echo "(Consider using NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID for automated runs.)" >&2
    exit 0
  else
    echo "No notarization credentials provided. Set NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER_ID or APPLEID/APP_SPECIFIC_PASSWORD." >&2
    exit 1
  fi
fi

# Staple the notarization ticket
echo "Stapling the app bundle"
# Stapler expects the app path present, so staple the copy in TMPDIR
xcrun stapler staple "${APP_BUNDLE}" || { echo "Stapling failed" >&2; exit 1; }

# Recreate a stapled distribution zip
pushd "${TMPDIR}" >/dev/null
rm -f "${DIST_DIR}/${STAPLED_ZIP}"
zip -r "${DIST_DIR}/${STAPLED_ZIP}" "Atmo.app" >/dev/null
popd >/dev/null

# Extract version for release tag
PLIST="${APP_BUNDLE}/Contents/Info.plist"
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PLIST}")
else
  VERSION=$(defaults read "${PLIST}" CFBundleShortVersionString 2>/dev/null || echo "0.0")
fi

RELEASE_TAG="v${VERSION}"

echo "Notarized release artifact: ${DIST_DIR}/${STAPLED_ZIP}"
echo ""

# GitHub release creation (skipped by default for local builds)
if [[ "$SKIP_UPLOAD" == "true" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✓ Build and notarization complete!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Release package: ${DIST_DIR}/${STAPLED_ZIP}"
  echo ""
  echo "To create a GitHub release, run:"
  echo "  ./Scripts/upload_release.sh ${RELEASE_TAG}"
  echo ""
else
  if command -v gh >/dev/null 2>&1; then
    echo "Creating GitHub release ${RELEASE_TAG} and uploading ${STAPLED_ZIP}"
    gh release create "${RELEASE_TAG}" "${DIST_DIR}/${STAPLED_ZIP}" \
      --title "Atmo ${VERSION}" \
      --notes "Notarized and stapled macOS release." || { 
        echo "gh release failed" >&2
        echo ""
        echo "You can manually upload with:"
        echo "  ./Scripts/upload_release.sh ${RELEASE_TAG}"
        exit 1
      }
  else
    echo "gh CLI not available; skipping GitHub release step."
    echo ""
    echo "To upload to GitHub, install gh CLI or run:"
    echo "  ./Scripts/upload_release.sh ${RELEASE_TAG}"
  fi
fi

# Cleanup
rm -rf "${TMPDIR}"

echo "Done."
