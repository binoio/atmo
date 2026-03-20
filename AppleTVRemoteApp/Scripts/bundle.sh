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

echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"
echo "✓ Bundle created at ${APP_BUNDLE}"
