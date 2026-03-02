#!/usr/bin/env bash
# verify_setup.sh - Verify signed release setup is complete

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_file() {
    if [[ -f "$1" ]]; then
        echo -e "${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "${RED}✗${NC} $1 (missing)"
        return 1
    fi
}

check_executable() {
    if [[ -x "$1" ]]; then
        echo -e "${GREEN}✓${NC} $1 (executable)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $1 (not executable, fixing...)"
        chmod +x "$1"
        return 1
    fi
}

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $1 command available"
        return 0
    else
        echo -e "${RED}✗${NC} $1 command not found"
        return 1
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Verifying Signed Release Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

errors=0

echo "📁 Checking Required Files..."
check_file "AppleTVRemoteApp/Support/Atmo.entitlements" || ((errors++))
check_file "AppleTVRemoteApp/Scripts/sign_and_notarize.sh" || ((errors++))
check_file "AppleTVRemoteApp/Scripts/signing_helper.sh" || ((errors++))
check_file "AppleTVRemoteApp/Scripts/notarize_and_release.sh" || ((errors++))
check_file ".github/workflows/notarize-release.yml" || ((errors++))
check_file "docs/SIGNING.md" || ((errors++))
check_file "SIGNED_RELEASE_SETUP.md" || ((errors++))
check_file "QUICK_START_CHECKLIST.md" || ((errors++))
echo ""

echo "🔧 Checking Script Permissions..."
check_executable "AppleTVRemoteApp/Scripts/sign_and_notarize.sh" || ((errors++))
check_executable "AppleTVRemoteApp/Scripts/signing_helper.sh" || ((errors++))
check_executable "AppleTVRemoteApp/Scripts/notarize_and_release.sh" || ((errors++))
check_executable "AppleTVRemoteApp/Scripts/release.sh" || ((errors++))
check_executable "AppleTVRemoteApp/Scripts/package_python.sh" || ((errors++))
echo ""

echo "🛠️  Checking System Requirements..."
check_command "xcrun" || ((errors++))
check_command "codesign" || ((errors++))
check_command "security" || ((errors++))
check_command "plutil" || ((errors++))
check_command "swift" || ((errors++))
check_command "python3" || ((errors++))
echo ""

echo "📝 Validating Configuration Files..."
if plutil -lint "AppleTVRemoteApp/Support/Atmo.entitlements" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Atmo.entitlements is valid"
else
    echo -e "${RED}✗${NC} Atmo.entitlements is invalid"
    ((errors++))
fi

if plutil -lint "AppleTVRemoteApp/Support/Info.plist" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Info.plist is valid"
else
    echo -e "${RED}✗${NC} Info.plist is invalid"
    ((errors++))
fi
echo ""

echo "🔐 Checking Signing Environment..."
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo -e "${GREEN}✓${NC} DEVELOPER_ID_APPLICATION is set"
else
    echo -e "${YELLOW}⚠${NC} DEVELOPER_ID_APPLICATION not set (optional for now)"
fi

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo -e "${GREEN}✓${NC} Developer ID certificate found in keychain"
else
    echo -e "${YELLOW}⚠${NC} No Developer ID certificate in keychain (required for signing)"
fi
echo ""

echo "📊 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $errors -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Review docs/SIGNING.md for setup instructions"
    echo "2. Set environment variables or GitHub secrets"
    echo "3. Run: ./AppleTVRemoteApp/Scripts/signing_helper.sh list-identities"
    echo "4. Test: ./AppleTVRemoteApp/Scripts/signing_helper.sh test-sign"
    exit 0
else
    echo -e "${RED}✗ Found $errors issue(s)${NC}"
    echo ""
    echo "Please fix the issues above and run this script again."
    exit 1
fi
