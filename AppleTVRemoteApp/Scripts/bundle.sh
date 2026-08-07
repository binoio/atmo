#!/usr/bin/env bash
set -euo pipefail

# bundle.sh: Package the built Atmo binary into a macOS .app bundle

PROJECT_ROOT="$(pwd)"
BUILD_DIR="${PROJECT_ROOT}/AppleTVRemoteApp/build"
DIST_DIR="${PROJECT_ROOT}/dist"
ARTIFACT_NAME="Atmo"
APP_BUNDLE="${DIST_DIR}/${ARTIFACT_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Creating bundle layout..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp "${BUILD_DIR}/${ARTIFACT_NAME}" "${MACOS_DIR}/${ARTIFACT_NAME}"
chmod +x "${MACOS_DIR}/${ARTIFACT_NAME}"

# Embed Sparkle.framework (the executable links it via @rpath/../Frameworks)
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
SPARKLE_FRAMEWORK=$(find "${PROJECT_ROOT}/AppleTVRemoteApp/.build" "${PROJECT_ROOT}/AppleTVRemoteApp/build" -type d -name "Sparkle.framework" -path "*artifacts*" -not -path "*dSYM*" 2>/dev/null | head -1)
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: Sparkle.framework not found under AppleTVRemoteApp/.build; run 'swift build --package-path AppleTVRemoteApp' first" >&2
    exit 1
fi
mkdir -p "${FRAMEWORKS_DIR}"
rm -rf "${FRAMEWORKS_DIR}/Sparkle.framework"
# ditto preserves the framework's Versions symlink structure; cp -R would not
ditto "$SPARKLE_FRAMEWORK" "${FRAMEWORKS_DIR}/Sparkle.framework"

# Copy resources
rsync -a --delete "${PROJECT_ROOT}/AppleTVRemoteApp/Sources/Atmo/Resources/" "${RESOURCES_DIR}/"

# Info.plist
if [[ -f "${PROJECT_ROOT}/AppleTVRemoteApp/Support/Info.plist" ]]; then
    cp "${PROJECT_ROOT}/AppleTVRemoteApp/Support/Info.plist" "${CONTENTS_DIR}/Info.plist"
else
    cat >"${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${ARTIFACT_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>io.bino.atmo</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${ARTIFACT_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF
fi

# Determine version
VERSION="${APP_VERSION:-1.0.0}"
if [[ -z "${APP_VERSION:-}" && -f "${PROJECT_ROOT}/VERSION" ]]; then
    VERSION=$(tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION")
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "${CONTENTS_DIR}/Info.plist"

# Sparkle update feed and EdDSA public key (env-overridable for testing)
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://binoio.github.io/atmo/appcast.xml}"
SPARKLE_ED_PUBLIC_KEY="${SPARKLE_ED_PUBLIC_KEY:-nDAE5HXFYg6pBQbAFtyEObXbHu9N7TM+7zUivRcRqNA=}"
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_ED_PUBLIC_KEY" "${CONTENTS_DIR}/Info.plist"
# Sandboxed app: Sparkle must install updates through its InstallerLauncher
# XPC service (paired with the mach-lookup exception in Atmo.entitlements)
/usr/libexec/PlistBuddy -c "Delete :SUEnableInstallerLauncherService" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUEnableInstallerLauncherService bool true" "${CONTENTS_DIR}/Info.plist"

echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"
echo "✓ Bundle created at ${APP_BUNDLE} (version $VERSION)"
