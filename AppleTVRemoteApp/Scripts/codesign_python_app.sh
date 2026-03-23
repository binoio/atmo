#!/usr/bin/env bash
set -euo pipefail

# codesign_python_app.sh
#
# Signs a macOS app bundle containing an embedded Python environment
# in the correct inner-to-outer order required by Apple's codesign tool.
#
# Usage: codesign_python_app.sh <app_bundle> <signing_identity>

APP_BUNDLE="${1:?Usage: codesign_python_app.sh <app_bundle> <signing_identity>}"
IDENTITY="${2:?Missing signing identity}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="${SCRIPT_DIR}/../Support/Atmo.entitlements"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: App bundle not found: $APP_BUNDLE" >&2
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "Error: Entitlements file not found: $ENTITLEMENTS" >&2
    exit 1
fi

CODESIGN_FLAGS=(--force --options runtime --timestamp --sign "$IDENTITY")

sign_files() {
    local pattern="$1"
    local label="$2"
    local count=0

    while IFS= read -r -d '' file; do
        codesign "${CODESIGN_FLAGS[@]}" "$file"
        ((count++))
    done < <(find "$APP_BUNDLE" -name "$pattern" -print0 2>/dev/null)

    if [[ $count -gt 0 ]]; then
        echo "  Signed $count $label file(s)"
    fi
}

# ── Step 1: Python shared-object modules ──────────────────────────────
echo "Step 1/4: Signing Python modules (.so)..."
sign_files "*.so" ".so"

# ── Step 2: Dynamic libraries ─────────────────────────────────────────
echo "Step 2/4: Signing dynamic libraries (.dylib)..."
sign_files "*.dylib" ".dylib"

# ── Step 3: All remaining Mach-O executables ──────────────────────────
echo "Step 3/4: Signing Mach-O executables..."
MACHO_COUNT=0

# Find all regular files under the Python directories and sign any Mach-O binary.
# This covers python-framework/bin/*, .venv/bin/python*, and any other executables.
while IFS= read -r -d '' file; do
    if [[ -L "$file" ]]; then
        continue
    fi
    if file "$file" | grep -q "Mach-O"; then
        codesign "${CODESIGN_FLAGS[@]}" "$file"
        ((MACHO_COUNT++))
    fi
done < <(find "$APP_BUNDLE" -type f \
    \( -path "*/bin/*" -o -path "*/python-framework/*" \) \
    -not -name "*.so" -not -name "*.dylib" \
    -print0 2>/dev/null)

if [[ $MACHO_COUNT -gt 0 ]]; then
    echo "  Signed $MACHO_COUNT Mach-O executable(s)"
fi

# ── Step 4: App bundle ────────────────────────────────────────────────
echo "Step 4/4: Signing app bundle with entitlements..."
codesign "${CODESIGN_FLAGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "Code signing complete (inner-to-outer)."
