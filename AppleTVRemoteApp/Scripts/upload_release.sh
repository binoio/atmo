#!/usr/bin/env bash
set -euo pipefail

# upload_release.sh
# Creates a GitHub release and uploads locally built and notarized app

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
STAPLED_ZIP="${DIST_DIR}/Atmo-stapled.zip"
RELEASE_ZIP="${DIST_DIR}/Atmo.zip"
RELEASE_DMG="${DIST_DIR}/Atmo.dmg"
PLIST="${DIST_DIR}/Atmo.app/Contents/Info.plist"

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS] <version>

Creates a GitHub release with git tag and uploads the locally built notarized app.

Arguments:
  version           Version tag (e.g., v1.0.0)

Options:
  --draft           Create as draft release
  --prerelease      Mark as pre-release
  --notes FILE      Use custom release notes from file
  --no-tag          Skip git tag creation (use if tag already exists)
  --help            Show this help message

Environment variables:
  GH_TOKEN or GITHUB_TOKEN    GitHub personal access token (required)

Examples:
  # Create a release with auto-generated notes
  $0 v1.0.0

  # Create a draft release
  $0 --draft v1.0.1

  # Use custom release notes
  $0 --notes CHANGELOG.md v1.0.2

Prerequisites:
  1. Build and notarize the app first:
     ./Scripts/notarize_and_release.sh

  2. Install GitHub CLI (gh) or set GITHUB_TOKEN
     brew install gh
     gh auth login

EOF
}

# Parse options
DRAFT=""
PRERELEASE=""
NOTES_FILE=""
SKIP_TAG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --draft)
            DRAFT="--draft"
            shift
            ;;
        --prerelease)
            PRERELEASE="--prerelease"
            shift
            ;;
        --notes)
            NOTES_FILE="$2"
            shift 2
            ;;
        --no-tag)
            SKIP_TAG=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

if [[ -z "${VERSION:-}" ]]; then
    echo "Error: Version argument is required" >&2
    echo "" >&2
    show_help
    exit 1
fi

# Normalize version tag
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v${VERSION}"
fi

echo "==> Creating GitHub Release: ${VERSION}"
echo ""

# Check for gh CLI or token
if command -v gh >/dev/null 2>&1; then
    USE_GH_CLI=true
    echo "✓ Using GitHub CLI (gh)"
elif [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    USE_GH_CLI=false
    echo "✓ Using GITHUB_TOKEN for authentication"
    GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN}}"
else
    echo "Error: GitHub CLI not found and no GITHUB_TOKEN set" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "1. Install GitHub CLI: brew install gh && gh auth login" >&2
    echo "2. Set GITHUB_TOKEN environment variable" >&2
    exit 1
fi

# Check for release assets (prefer release ZIP over stapled ZIP)
if [[ -f "${RELEASE_ZIP}" ]]; then
    PRIMARY_ASSET="${RELEASE_ZIP}"
    echo "✓ Found release package: Atmo.zip"
elif [[ -f "${STAPLED_ZIP}" ]]; then
    PRIMARY_ASSET="${STAPLED_ZIP}"
    echo "✓ Found stapled package: Atmo-stapled.zip"
else
    echo "Error: No release package found at ${RELEASE_ZIP} or ${STAPLED_ZIP}" >&2
    echo "" >&2
    echo "Build and notarize the app first:" >&2
    echo "  cd ${ROOT_DIR}" >&2
    echo "  ./Scripts/notarize_and_release.sh" >&2
    exit 1
fi

# Check for DMG
ASSETS="${PRIMARY_ASSET}"
if [[ -f "${RELEASE_DMG}" ]]; then
    ASSETS="${ASSETS} ${RELEASE_DMG}"
    echo "✓ Found DMG package: Atmo.dmg"
fi

# Verify the zip is actually notarized
echo "==> Verifying notarization..."
TMPDIR="${ROOT_DIR}/_verify_tmp"
rm -rf "${TMPDIR}"
mkdir -p "${TMPDIR}"

unzip -q "${PRIMARY_ASSET}" -d "${TMPDIR}"
APP_BUNDLE="${TMPDIR}/Atmo.app"

if ! xcrun stapler validate "${APP_BUNDLE}" >/dev/null 2>&1; then
    echo "Warning: App bundle does not have a valid stapled ticket" >&2
    echo "The notarization may have failed. Continue anyway? (y/N) " >&2
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        rm -rf "${TMPDIR}"
        exit 1
    fi
else
    echo "✓ App bundle is properly notarized and stapled"
fi

# Extract version from Info.plist if available
if [[ -f "${PLIST}" ]]; then
    if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
        BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PLIST}" 2>/dev/null || echo "")
        if [[ -n "${BUNDLE_VERSION}" ]]; then
            echo "✓ Bundle version: ${BUNDLE_VERSION}"
        fi
    fi
fi

# Get file size
FILE_SIZE=$(du -h "${PRIMARY_ASSET}" | awk '{print $1}')
echo "✓ Package size: ${FILE_SIZE}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Git Tag
# ══════════════════════════════════════════════════════════════════════════════

if [[ "$SKIP_TAG" != "true" ]]; then
    echo "==> Creating git tag ${VERSION}..."
    
    # Check if tag already exists
    if git rev-parse "${VERSION}" >/dev/null 2>&1; then
        echo "Warning: Tag ${VERSION} already exists" >&2
        echo "Use --no-tag to skip tag creation, or delete the existing tag first." >&2
        echo "Continue without creating tag? (y/N) " >&2
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            rm -rf "${TMPDIR}"
            exit 1
        fi
    else
        # Create annotated tag
        git tag -a "${VERSION}" -m "Release ${VERSION}"
        echo "✓ Created git tag: ${VERSION}"
        
        # Push tag to remote
        echo "==> Pushing tag to remote..."
        git push origin "${VERSION}"
        echo "✓ Pushed tag to origin"
    fi
    echo ""
fi

# Generate or use custom release notes
if [[ -n "${NOTES_FILE}" ]]; then
    if [[ ! -f "${NOTES_FILE}" ]]; then
        echo "Error: Release notes file not found: ${NOTES_FILE}" >&2
        exit 1
    fi
    RELEASE_NOTES=$(cat "${NOTES_FILE}")
else
    RELEASE_NOTES=$(cat <<NOTES
## Atmo ${VERSION}

### Installation

**Option 1: ZIP** (Recommended)
1. Download \`Atmo.zip\`
2. Unzip and drag Atmo.app to your Applications folder
3. Launch Atmo

**Option 2: DMG**
1. Download \`Atmo.dmg\`
2. Open the DMG and drag Atmo to the Applications folder
3. Launch Atmo

This release is **signed and notarized** with Apple Developer ID.

### Package Details
- Version: ${BUNDLE_VERSION:-${VERSION}}
- Size: ${FILE_SIZE}
- macOS: 13.0+

### What's Changed
See the commit history for details.
NOTES
)
fi

# Create release using gh CLI or API
if [[ "$USE_GH_CLI" == "true" ]]; then
    echo "==> Creating release with GitHub CLI..."
    # shellcheck disable=SC2086
    gh release create "${VERSION}" \
        ${ASSETS} \
        --title "Atmo ${VERSION}" \
        --notes "${RELEASE_NOTES}" \
        ${DRAFT} \
        ${PRERELEASE}
else
    echo "==> Creating release with GitHub API..."
    
    # Get repo info
    REPO_URL=$(git remote get-url origin | sed -E 's|^.*github\.com[:/]||' | sed 's|\.git$||')
    
    # Create release
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${REPO_URL}/releases" \
        -d @- <<JSON
{
  "tag_name": "${VERSION}",
  "name": "Atmo ${VERSION}",
  "body": $(echo "${RELEASE_NOTES}" | jq -Rs .),
  "draft": $([ -n "${DRAFT}" ] && echo "true" || echo "false"),
  "prerelease": $([ -n "${PRERELEASE}" ] && echo "true" || echo "false")
}
JSON
)
    
    UPLOAD_URL=$(echo "${RESPONSE}" | jq -r '.upload_url' | sed 's/{?name,label}//')
    
    if [[ "$UPLOAD_URL" == "null" || -z "$UPLOAD_URL" ]]; then
        echo "Error: Failed to create release" >&2
        echo "${RESPONSE}" | jq . >&2
        exit 1
    fi
    
    echo "✓ Release created"
    echo "==> Uploading assets..."
    
    # Upload ZIP
    curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-Type: application/zip" \
        --data-binary "@${PRIMARY_ASSET}" \
        "${UPLOAD_URL}?name=Atmo.zip" > /dev/null
    echo "✓ Uploaded Atmo.zip"
    
    # Upload DMG if available
    if [[ -f "${RELEASE_DMG}" ]]; then
        curl -s -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "@${RELEASE_DMG}" \
            "${UPLOAD_URL}?name=Atmo.dmg" > /dev/null
        echo "✓ Uploaded Atmo.dmg"
    fi
fi

# Cleanup
rm -rf "${TMPDIR}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Release ${VERSION} created successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "View release:"
if [[ "$USE_GH_CLI" == "true" ]]; then
    gh release view "${VERSION}" --web
else
    echo "https://github.com/${REPO_URL}/releases/tag/${VERSION}"
fi
echo ""
