#!/bin/bash
# Build script for Atmo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="${PROJECT_DIR}/AppleTVRemoteApp"
BUILD_DIR="${PROJECT_DIR}/build"

# Default configuration
CONFIGURATION="${1:-Release}"

echo "Building Atmo ($CONFIGURATION)..."

# Clean and create build directory
mkdir -p "$BUILD_DIR"

# Build the project using Swift Package Manager
if [ "$CONFIGURATION" = "Release" ]; then
    xcrun swift build -c release --package-path "$APP_DIR"
    BIN_PATH="$(xcrun swift build -c release --package-path "$APP_DIR" --show-bin-path)/Atmo"
else
    xcrun swift build --package-path "$APP_DIR"
    BIN_PATH="$(xcrun swift build --package-path "$APP_DIR" --show-bin-path)/Atmo"
fi

# Copy the binary to build directory
if [ -f "$BIN_PATH" ]; then
    cp "$BIN_PATH" "$BUILD_DIR/"
    echo "✓ Build complete: $BUILD_DIR/Atmo"
else
    echo "✗ Build failed: Binary not found at $BIN_PATH"
    exit 1
fi
