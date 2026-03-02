#!/bin/bash
# Run script for Atmo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="${PROJECT_DIR}/AppleTVRemoteApp"
DIST_DIR="${APP_DIR}/dist"

# Check if app bundle exists, build if not
if [ ! -d "${DIST_DIR}/Atmo.app" ]; then
    echo "App bundle not found. Building first..."
    bash "${APP_DIR}/Scripts/release.sh"
fi

echo "Launching Atmo..."
open "${DIST_DIR}/Atmo.app"
