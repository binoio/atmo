#!/usr/bin/env bash
set -euo pipefail

# notarize_and_release.sh
# Build, sign, notarize, and optionally upload to GitHub

# ══════════════════════════════════════════════════════════════════════════════
# Colors and Formatting
# ══════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

CHECK="✓"
CROSS="✗"
ARROW="→"
STAR="★"
LOCK="🔐"
PACKAGE="📦"
ROCKET="🚀"
HOURGLASS="⏳"
SPARKLES="✨"

# ══════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ══════════════════════════════════════════════════════════════════════════════

print_banner() {
    echo ""
    echo -e "${CYAN}    ╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}    ║${RESET}                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}   ${BOLD}${WHITE} █████╗ ${BLUE}████████╗${GREEN}███╗   ███╗${YELLOW} ██████╗${RESET}                   ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}   ${BOLD}${WHITE}██╔══██╗${BLUE}╚══██╔══╝${GREEN}████╗ ████║${YELLOW}██╔═══██╗${RESET}                  ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}   ${BOLD}${WHITE}███████║${BLUE}   ██║   ${GREEN}██╔████╔██║${YELLOW}██║   ██║${RESET}                  ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}   ${BOLD}${WHITE}██╔══██║${BLUE}   ██║   ${GREEN}██║╚██╔╝██║${YELLOW}██║   ██║${RESET}                  ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}   ${BOLD}${WHITE}██║  ██║${BLUE}   ██║   ${GREEN}██║ ╚═╝ ██║${YELLOW}╚██████╔╝${RESET}                  ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}   ${BOLD}${WHITE}╚═╝  ╚═╝${BLUE}   ╚═╝   ${GREEN}╚═╝     ╚═╝${YELLOW} ╚═════╝${RESET}                   ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}         ${LOCK} ${BOLD}Notarization & Code Signing Tool${RESET}  ${LOCK}            ${CYAN}║${RESET}"
    echo -e "${CYAN}    ║${RESET}                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}    ╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_header() {
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${MAGENTA}║${RESET}  ${CYAN}${BOLD}$1${RESET}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local message=$3
    echo -e "${BLUE}${BOLD}[${step}/${total}]${RESET} ${CYAN}${ARROW}${RESET} ${message}"
}

print_success() {
    echo -e "     ${GREEN}${CHECK} $1${RESET}"
}

print_error() {
    echo -e "     ${RED}${CROSS} $1${RESET}"
}

print_warning() {
    echo -e "     ${YELLOW}! $1${RESET}"
}

print_info() {
    echo -e "     ${DIM}$1${RESET}"
}

prompt_input() {
    local prompt=$1
    local var_name=$2
    local is_secret=${3:-false}
    
    echo -ne "${YELLOW}${ARROW}${RESET} ${WHITE}${prompt}${RESET}: "
    if [ "$is_secret" = true ]; then
        read -s input
        echo ""
    else
        read input
    fi
    eval "$var_name='$input'"
}

prompt_confirm() {
    local prompt=$1
    echo -ne "${YELLOW}?${RESET} ${WHITE}${prompt}${RESET} ${DIM}[y/N]${RESET}: "
    read -n 1 reply
    echo ""
    [[ "$reply" =~ ^[Yy]$ ]]
}

spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r     ${CYAN}${spin:$i:1}${RESET} ${message}"
        sleep 0.1
    done
    printf "\r"
}

# ══════════════════════════════════════════════════════════════════════════════
# Configuration
# ══════════════════════════════════════════════════════════════════════════════

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ZIP_NAME="Atmo.zip"
NOTARIZE_ZIP="Atmo-notarize.zip"
STAPLED_ZIP="Atmo-stapled.zip"
RELEASE_ZIP="Atmo.zip"
RELEASE_DMG="Atmo.dmg"

# Parse options
SKIP_UPLOAD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-upload)
            SKIP_UPLOAD=true
            shift
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Build, sign, and notarize Atmo for release.

Options:
  --no-upload       Skip GitHub release creation (default for local builds)
  --help            Show this help message

Environment variables (optional - will prompt if not set):
  DEVELOPER_ID_APPLICATION    Your Developer ID signing identity
  APPLEID                     Your Apple ID email
  APP_SPECIFIC_PASSWORD       App-specific password from appleid.apple.com
  TEAM_ID                     Your Apple Team ID

After building, upload to GitHub with:
  ./Scripts/upload_release.sh v1.0.0

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

command -v xcrun >/dev/null || { echo "xcrun required" >&2; exit 1; }
command -v codesign >/dev/null || { echo "codesign required" >&2; exit 1; }

# ══════════════════════════════════════════════════════════════════════════════
# Interactive Credential Gathering
# ══════════════════════════════════════════════════════════════════════════════

print_banner

echo -e "${DIM}This script will build, sign, and notarize Atmo for distribution.${RESET}"
echo -e "${DIM}You'll need an Apple Developer account and app-specific password.${RESET}"
echo ""

print_header "${LOCK} Configuration"

# Get signing identity
if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo -e "${DIM}Available signing identities:${RESET}"
    security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -5 || true
    echo ""
    prompt_input "Signing identity (full string or press Enter to search)" DEVELOPER_ID_APPLICATION
    
    if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
        # Try to find one automatically
        DEVELOPER_ID_APPLICATION=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
        if [[ -n "$DEVELOPER_ID_APPLICATION" ]]; then
            echo -e "     ${GREEN}${CHECK}${RESET} Found: ${CYAN}$DEVELOPER_ID_APPLICATION${RESET}"
        else
            print_error "No Developer ID Application identity found in keychain"
            exit 1
        fi
    fi
fi
echo -e "     ${GREEN}${CHECK}${RESET} Signing Identity: ${CYAN}${DEVELOPER_ID_APPLICATION}${RESET}"

# Get Apple ID
if [[ -z "${APPLEID:-}" ]]; then
    prompt_input "Apple ID (email)" APPLEID
fi
echo -e "     ${GREEN}${CHECK}${RESET} Apple ID: ${CYAN}$APPLEID${RESET}"

# Get Team ID (extract from signing identity or prompt)
if [[ -z "${TEAM_ID:-}" ]]; then
    # Try to extract from signing identity
    TEAM_ID=$(echo "$DEVELOPER_ID_APPLICATION" | grep -oE '\([A-Z0-9]+\)$' | tr -d '()' || echo "")
    if [[ -z "$TEAM_ID" ]]; then
        prompt_input "Team ID" TEAM_ID
    else
        echo -e "     ${GREEN}${CHECK}${RESET} Team ID: ${CYAN}$TEAM_ID${RESET} (extracted from identity)"
    fi
fi
if [[ -z "$TEAM_ID" ]]; then
    echo -e "     ${GREEN}${CHECK}${RESET} Team ID: ${CYAN}$TEAM_ID${RESET}"
fi

# Get app-specific password
if [[ -z "${APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo ""
    echo -e "     ${DIM}App-specific passwords can be generated at:${RESET}"
    echo -e "     ${BLUE}https://appleid.apple.com/account/manage${RESET}"
    echo ""
    prompt_input "App-Specific Password" APP_SPECIFIC_PASSWORD true
fi
echo -e "     ${GREEN}${CHECK}${RESET} App Password: ${CYAN}••••••••••••${RESET}"

# Validate
if [[ -z "$DEVELOPER_ID_APPLICATION" ]] || [[ -z "$APPLEID" ]] || [[ -z "$APP_SPECIFIC_PASSWORD" ]]; then
    print_error "Missing required credentials. Cannot proceed."
    exit 1
fi

echo ""
if ! prompt_confirm "Proceed with build and notarization?"; then
    echo -e "${YELLOW}Aborted.${RESET}"
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# Build
# ══════════════════════════════════════════════════════════════════════════════

print_header "${PACKAGE} Building Release"

print_step 1 5 "Building release version..."

if [[ -f "${DIST_DIR}/${ZIP_NAME}" ]]; then
    print_warning "Existing build found"
    if prompt_confirm "Rebuild the app?"; then
        rm -rf "${DIST_DIR}"
        bash "${ROOT_DIR}/Scripts/release.sh" > /dev/null 2>&1 &
        spinner $! "Compiling..."
        wait $!
        print_success "Build complete"
    else
        print_info "Using existing build"
    fi
else
    bash "${ROOT_DIR}/Scripts/release.sh" > /dev/null 2>&1 &
    spinner $! "Compiling..."
    wait $!
    print_success "Build complete"
fi

mkdir -p "${ROOT_DIR}/_notarize_tmp"
TMPDIR="${ROOT_DIR}/_notarize_tmp"
rm -rf "${TMPDIR:?}"/*

unzip -o "${DIST_DIR}/${ZIP_NAME}" -d "${TMPDIR}" > /dev/null
APP_BUNDLE="${TMPDIR}/Atmo.app"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    print_error "App bundle not found at ${APP_BUNDLE}"
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# Code Sign
# ══════════════════════════════════════════════════════════════════════════════

print_header "${LOCK} Code Signing"

print_step 2 5 "Signing app with Developer ID..."

# First, sign all embedded binaries (Python framework, .so files, dylibs)
# These must be signed with hardened runtime before the app bundle
print_info "Signing embedded binaries with hardened runtime..."

SIGN_COUNT=0
PYTHON_RESOURCES="${APP_BUNDLE}/Contents/Resources/Python"
PYTHON_DIR="${PYTHON_RESOURCES}/python-framework"

# Sign all .so and .dylib files first
while IFS= read -r -d '' binary; do
    if file "$binary" | grep -qE "Mach-O|bundle"; then
        codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "$binary" 2>/dev/null && ((SIGN_COUNT++)) || true
    fi
done < <(find "${PYTHON_RESOURCES}" -type f \( -name "*.so" -o -name "*.dylib" \) -print0 2>/dev/null)

# Sign venv python executables
while IFS= read -r -d '' binary; do
    if file "$binary" | grep -qE "Mach-O"; then
        codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "$binary" 2>/dev/null && ((SIGN_COUNT++)) || true
    fi
done < <(find "${PYTHON_RESOURCES}/.venv/bin" -type f -print0 2>/dev/null)

# Sign python-framework binaries (not a bundle, just individual files)
if [[ -d "${PYTHON_DIR}" ]]; then
    print_info "Signing python-framework binaries..."
    
    # Sign all Mach-O binaries inside
    while IFS= read -r -d '' binary; do
        if file "$binary" | grep -qE "Mach-O"; then
            codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "$binary" 2>/dev/null && ((SIGN_COUNT++)) || true
        fi
    done < <(find "${PYTHON_DIR}" -type f \( -perm +111 -o -name "*.dylib" \) -print0 2>/dev/null)
    
    # Sign Python.app inside if it exists
    PYTHON_APP="${PYTHON_DIR}/Resources/Python.app"
    if [[ -d "${PYTHON_APP}" ]]; then
        print_info "Signing Python.app..."
        codesign --force --options runtime --deep --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${PYTHON_APP}"
        ((SIGN_COUNT++))
    fi
fi

print_success "Signed ${SIGN_COUNT} embedded binaries"

# Now sign the main app bundle
print_info "Signing main app bundle..."
codesign --force --options runtime --deep --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${APP_BUNDLE}" 2>&1 | while read line; do
    print_info "$line"
done

if codesign --verify --verbose "${APP_BUNDLE}" 2>&1 | grep -q "valid on disk"; then
    print_success "Code signature verified"
else
    print_warning "Verifying signature..."
    codesign --verify --verbose "${APP_BUNDLE}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Create Archive
# ══════════════════════════════════════════════════════════════════════════════

print_header "${PACKAGE} Creating Archive"

print_step 3 5 "Creating ZIP archive for notarization..."

pushd "${TMPDIR}" >/dev/null
rm -f "${DIST_DIR}/${NOTARIZE_ZIP}"
zip -r -y "${DIST_DIR}/${NOTARIZE_ZIP}" "Atmo.app" >/dev/null
popd >/dev/null

ZIP_SIZE=$(du -h "${DIST_DIR}/${NOTARIZE_ZIP}" | cut -f1)
print_success "Archive created: ${ZIP_SIZE}"

# ══════════════════════════════════════════════════════════════════════════════
# Notarize
# ══════════════════════════════════════════════════════════════════════════════

print_header "${ROCKET} Notarization"

print_step 4 5 "Submitting to Apple notary service..."
echo ""
echo -e "     ${HOURGLASS} ${DIM}This may take several minutes...${RESET}"
echo ""

xcrun notarytool submit "${DIST_DIR}/${NOTARIZE_ZIP}" \
    --apple-id "$APPLEID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"status: Accepted"* ]]; then
        echo -e "     ${GREEN}${SPARKLES} $line${RESET}"
    elif [[ "$line" == *"status:"* ]]; then
        echo -e "     ${CYAN}$line${RESET}"
    elif [[ "$line" == *"id:"* ]]; then
        echo -e "     ${DIM}$line${RESET}"
    else
        echo -e "     $line"
    fi
done

print_success "Notarization complete"

# ══════════════════════════════════════════════════════════════════════════════
# Staple
# ══════════════════════════════════════════════════════════════════════════════

print_header "${STAR} Finalizing"

print_step 5 5 "Stapling notarization ticket to app..."

xcrun stapler staple "${APP_BUNDLE}" 2>&1 | while read line; do
    if [[ "$line" == *"action worked"* ]]; then
        print_success "Ticket stapled successfully"
    else
        print_info "$line"
    fi
done

# Recreate a stapled distribution zip
pushd "${TMPDIR}" >/dev/null
rm -f "${DIST_DIR}/${STAPLED_ZIP}"
zip -r "${DIST_DIR}/${STAPLED_ZIP}" "Atmo.app" >/dev/null
popd >/dev/null

# Also copy stapled app to dist
rm -rf "${DIST_DIR}/Atmo.app"
cp -R "${APP_BUNDLE}" "${DIST_DIR}/"

# Create final release ZIP (cleaner name for distribution)
print_info "Creating release package ${RELEASE_ZIP}..."
rm -f "${DIST_DIR}/${RELEASE_ZIP}"
cp "${DIST_DIR}/${STAPLED_ZIP}" "${DIST_DIR}/${RELEASE_ZIP}"
print_success "Created ${RELEASE_ZIP}"

# Create DMG for release
print_info "Creating DMG package ${RELEASE_DMG}..."
rm -f "${DIST_DIR}/${RELEASE_DMG}"
if command -v hdiutil >/dev/null 2>&1; then
    # Create a temporary DMG staging folder
    DMG_STAGING="${ROOT_DIR}/_dmg_staging"
    rm -rf "${DMG_STAGING}"
    mkdir -p "${DMG_STAGING}"
    cp -R "${DIST_DIR}/Atmo.app" "${DMG_STAGING}/"
    
    # Create symbolic link to /Applications for drag-and-drop install
    ln -s /Applications "${DMG_STAGING}/Applications"
    
    # Create DMG
    hdiutil create -volname "Atmo" -srcfolder "${DMG_STAGING}" \
        -ov -format UDZO "${DIST_DIR}/${RELEASE_DMG}" >/dev/null 2>&1
    
    rm -rf "${DMG_STAGING}"
    print_success "Created ${RELEASE_DMG}"
else
    print_warning "hdiutil not found, skipping DMG creation"
fi

# Extract version for release tag
PLIST="${APP_BUNDLE}/Contents/Info.plist"
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PLIST}")
else
    VERSION=$(defaults read "${PLIST}" CFBundleShortVersionString 2>/dev/null || echo "1.0")
fi

RELEASE_TAG="v${VERSION}"

# ══════════════════════════════════════════════════════════════════════════════
# Complete
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║${RESET}                                                                  ${GREEN}║${RESET}"
echo -e "${GREEN}║${RESET}   ${SPARKLES}  ${BOLD}${WHITE}NOTARIZATION COMPLETE!${RESET}  ${SPARKLES}                              ${GREEN}║${RESET}"
echo -e "${GREEN}║${RESET}                                                                  ${GREEN}║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${CYAN}${ARROW}${RESET} Notarized app: ${WHITE}${DIST_DIR}/Atmo.app${RESET}"
echo -e "  ${CYAN}${ARROW}${RESET} Release ZIP:   ${WHITE}${DIST_DIR}/${RELEASE_ZIP}${RESET}"
echo -e "  ${CYAN}${ARROW}${RESET} Release DMG:   ${WHITE}${DIST_DIR}/${RELEASE_DMG}${RESET}"
echo ""
echo -e "  ${DIM}The app is ready for distribution outside the Mac App Store.${RESET}"
echo -e "  ${DIM}Users will not see Gatekeeper warnings when opening Atmo.${RESET}"
echo ""

# GitHub release
if [[ "$SKIP_UPLOAD" != "true" ]]; then
    if prompt_confirm "Upload to GitHub Releases?"; then
        prompt_input "Version tag (default: ${RELEASE_TAG})" INPUT_VERSION
        RELEASE_TAG="${INPUT_VERSION:-$RELEASE_TAG}"
        
        if [[ -f "${ROOT_DIR}/Scripts/upload_release.sh" ]]; then
            bash "${ROOT_DIR}/Scripts/upload_release.sh" "${RELEASE_TAG}"
        elif command -v gh >/dev/null 2>&1; then
            echo -e "${CYAN}Creating GitHub release ${RELEASE_TAG}...${RESET}"
            gh release create "${RELEASE_TAG}" "${DIST_DIR}/${STAPLED_ZIP}" \
                --title "Atmo ${VERSION}" \
                --notes "Notarized and stapled macOS release."
            print_success "Release created!"
        else
            echo -e "${YELLOW}gh CLI not available. Upload manually:${RESET}"
            echo -e "  gh release create ${RELEASE_TAG} ${DIST_DIR}/${STAPLED_ZIP}"
        fi
    fi
else
    echo -e "To create a GitHub release, run:"
    echo -e "  ${CYAN}./Scripts/upload_release.sh ${RELEASE_TAG}${RESET}"
fi

# Cleanup
rm -rf "${TMPDIR}"

echo ""
echo -e "${CYAN}Thanks for using Atmo! ${RESET}${SPARKLES}"
echo ""
