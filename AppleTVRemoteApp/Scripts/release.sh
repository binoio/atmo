#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ARTIFACT_NAME="Atmo"
ARTIFACT_DISPLAY_NAME="Atmo"
APP_BUNDLE="${DIST_DIR}/${ARTIFACT_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${DIST_DIR}"
rm -rf "${APP_BUNDLE}"
rm -f "${DIST_DIR}/${ARTIFACT_NAME}.zip"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

bash "${ROOT_DIR}/Scripts/package_python.sh"

xcrun swift build -c release --package-path "${ROOT_DIR}"
BIN_DIR="$(xcrun swift build -c release --package-path "${ROOT_DIR}" --show-bin-path)"

cp "${BIN_DIR}/${ARTIFACT_NAME}" "${MACOS_DIR}/${ARTIFACT_NAME}"
chmod +x "${MACOS_DIR}/${ARTIFACT_NAME}"

rsync -a --delete "${ROOT_DIR}/Sources/Atmo/Resources/" "${RESOURCES_DIR}/"

if [[ -f "${ROOT_DIR}/Support/Info.plist" ]]; then
	cp "${ROOT_DIR}/Support/Info.plist" "${CONTENTS_DIR}/Info.plist"
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
	<string>${ARTIFACT_DISPLAY_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleSignature</key>
	<string>ATMO</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF
fi

echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

pushd "${DIST_DIR}" >/dev/null
zip -r "${ARTIFACT_NAME}.zip" "${ARTIFACT_NAME}.app" >/dev/null
popd >/dev/null

echo "Release package created at ${DIST_DIR}/${ARTIFACT_NAME}.zip"
echo "App bundle layout:"
find "${APP_BUNDLE}" -maxdepth 2 -mindepth 1 -type d -o -type f
