#!/usr/bin/env bash
# Quick reference script for common signing and notarization tasks

set -euo pipefail

show_help() {
    cat <<EOF
Atmo Signing Helper

Usage: $0 <command>

Commands:
    list-identities    List available code signing identities
    verify-app         Verify signature of Atmo.app in dist/
    check-notarize     Check notarization status of Atmo.app
    show-entitlements  Show app entitlements
    export-cert        Guide for exporting Developer ID certificate
    test-sign          Quick sign test (without notarization)
    full-release       Build, sign, and notarize complete release
    upload             Upload notarized release to GitHub

Environment variables for signing:
    DEVELOPER_ID_APPLICATION    Your Developer ID signing identity
    APPLEID                    Your Apple ID email
    APP_SPECIFIC_PASSWORD      App-specific password for notarization

Or use API key:
    NOTARY_KEY_PATH            Path to .p8 API key file
    NOTARY_KEY_ID              Key ID
    NOTARY_ISSUER_ID           Issuer ID

For upload:
    GH_TOKEN or GITHUB_TOKEN   GitHub personal access token

EOF
}

list_identities() {
    echo "==> Available code signing identities:"
    security find-identity -v -p codesigning
}

verify_app() {
    APP="${1:-dist/Atmo.app}"
    if [[ ! -d "$APP" ]]; then
        echo "Error: $APP not found" >&2
        exit 1
    fi
    
    echo "==> Verifying signature of $APP"
    codesign -vvv --deep --strict "$APP"
    echo ""
    echo "==> Checking Gatekeeper assessment"
    spctl -a -vvv -t install "$APP"
}

check_notarize() {
    APP="${1:-dist/Atmo.app}"
    if [[ ! -d "$APP" ]]; then
        echo "Error: $APP not found" >&2
        exit 1
    fi
    
    echo "==> Checking notarization status of $APP"
    spctl -a -vvv -t install "$APP"
    echo ""
    echo "==> Checking for stapled ticket"
    xcrun stapler validate "$APP"
}

show_entitlements() {
    APP="${1:-dist/Atmo.app}"
    if [[ ! -d "$APP" ]]; then
        echo "Error: $APP not found" >&2
        exit 1
    fi
    
    echo "==> Entitlements for $APP"
    codesign -d --entitlements - "$APP"
}

export_cert_guide() {
    cat <<EOF
==> How to export your Developer ID certificate:

1. Open Keychain Access
2. Select "login" keychain
3. Select "My Certificates" category
4. Find "Developer ID Application: Your Name (TEAM_ID)"
5. Right-click → Export "Developer ID Application..."
6. Save as: certificate.p12
7. Set a strong password

Then for GitHub Actions:
    base64 -i certificate.p12 | pbcopy
    # Paste into GitHub Secrets as APPLE_CERTIFICATE_BASE64

Your signing identity string (for DEVELOPER_ID_APPLICATION):
EOF
    security find-identity -v -p codesigning | grep "Developer ID Application"
}

test_sign() {
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
        echo "Error: DEVELOPER_ID_APPLICATION environment variable is not set." >&2
        echo "" >&2
        echo "Please set it to your Developer ID signing identity:" >&2
        echo "" >&2
        echo "  export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAM_ID)\"" >&2
        echo "" >&2
        echo "To find your signing identity, run:" >&2
        echo "  $0 list-identities" >&2
        echo "" >&2
        exit 1
    fi
    
    echo "==> Building unsigned app..."
    bash "${ROOT_DIR}/Scripts/release.sh"
    
    APP="${ROOT_DIR}/dist/Atmo.app"
    
    echo "==> Test signing $APP"
    codesign --force --options runtime --deep --timestamp \
        --sign "${DEVELOPER_ID_APPLICATION}" \
        "${APP}"
    
    echo "==> Verifying signature"
    codesign -vvv --deep --strict "${APP}"
    
    echo "✓ Test sign successful"
}

full_release() {
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    echo "==> Running full notarization workflow"
    bash "${ROOT_DIR}/Scripts/notarize_and_release.sh" --no-upload
}

upload_release() {
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    if [[ -z "${1:-}" ]]; then
        echo "Error: Version tag required" >&2
        echo "" >&2
        echo "Usage: $0 upload <version>" >&2
        echo "Example: $0 upload v1.0.0" >&2
        exit 1
    fi
    
    bash "${ROOT_DIR}/Scripts/upload_release.sh" "$@"
}

case "${1:-help}" in
    list-identities)
        list_identities
        ;;
    verify-app)
        verify_app "${2:-dist/Atmo.app}"
        ;;
    check-notarize)
        check_notarize "${2:-dist/Atmo.app}"
        ;;
    show-entitlements)
        show_entitlements "${2:-dist/Atmo.app}"
        ;;
    export-cert)
        export_cert_guide
        ;;
    test-sign)
        test_sign
        ;;
    full-release)
        full_release
        ;;
    upload)
        shift
        upload_release "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo ""
        show_help
        exit 1
        ;;
esac
