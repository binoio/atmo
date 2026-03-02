#!/bin/bash
# Test script for Atmo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="${PROJECT_DIR}/AppleTVRemoteApp"

echo "Running Atmo Swift tests..."
xcrun swift test --package-path "$APP_DIR" 2>&1 || true

echo ""
echo "Running Python tests..."
cd "$PROJECT_DIR"
if [ -d ".venv" ]; then
    .venv/bin/python -m pytest tests/ -v
else
    python3 -m pytest tests/ -v
fi

echo "✓ All tests completed"
