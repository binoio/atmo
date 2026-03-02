#!/bin/bash
# Interactive Notarization Wrapper for Atmo
# Delegates to AppleTVRemoteApp/Scripts/notarize_and_release.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="${PROJECT_DIR}/AppleTVRemoteApp"

exec bash "${APP_DIR}/Scripts/notarize_and_release.sh" "$@"
