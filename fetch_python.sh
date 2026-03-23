#!/usr/bin/env bash
set -euo pipefail

# fetch_python.sh
#
# Downloads a standalone relocatable Python into .python/ so that
# package_python.sh and setup_python_env.sh can create a venv without
# requiring a matching system Python.  Nothing is added to PATH.
#
# Uses python-build-standalone (astral-sh) install_only builds.
# https://github.com/astral-sh/python-build-standalone

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_VERSION_FILE="${REPO_ROOT}/pybridge/python-version.txt"

if [[ ! -f "$PYTHON_VERSION_FILE" ]]; then
    echo "Error: ${PYTHON_VERSION_FILE} not found" >&2
    exit 1
fi

FULL_VERSION="$(tr -d '[:space:]' < "$PYTHON_VERSION_FILE")"
MAJOR_MINOR="${FULL_VERSION%.*}"           # e.g. 3.11

ARCH="$(uname -m)"                         # arm64 or x86_64
case "$ARCH" in
    arm64)  TARGET="aarch64-apple-darwin" ;;
    x86_64) TARGET="x86_64-apple-darwin"  ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

INSTALL_DIR="${REPO_ROOT}/.python"

# If already present and matching, skip download
if [[ -x "${INSTALL_DIR}/bin/python3" ]]; then
    EXISTING="$("${INSTALL_DIR}/bin/python3" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [[ "$EXISTING" == "$MAJOR_MINOR" ]]; then
        echo "✓ Standalone Python ${MAJOR_MINOR} already present at ${INSTALL_DIR}"
        exit 0
    fi
    echo "Removing stale standalone Python (found ${EXISTING}, need ${MAJOR_MINOR})..."
    rm -rf "$INSTALL_DIR"
fi

echo "Fetching standalone Python ${MAJOR_MINOR} for ${TARGET}..."

# Resolve the latest release tag
RELEASE_JSON="$(curl -fsSL \
    "https://raw.githubusercontent.com/astral-sh/python-build-standalone/latest-release/latest-release.json")"
TAG="$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag'])" 2>/dev/null \
    || echo "$RELEASE_JSON" | grep -o '"tag":"[^"]*"' | cut -d'"' -f4)"
ASSET_PREFIX="$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['asset_url_prefix'])" 2>/dev/null \
    || echo "$RELEASE_JSON" | grep -o '"asset_url_prefix":"[^"]*"' | cut -d'"' -f4)"

# Find the exact asset via the GitHub API
ASSET_URL="$(curl -fsSL \
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/tags/${TAG}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
mm = '${MAJOR_MINOR}'
target = '${TARGET}'
for a in data.get('assets', []):
    n = a['name']
    # Match cpython-3.11.X+DATE-TARGET-install_only.tar.gz (not stripped)
    if n.startswith('cpython-') and mm in n and target in n \
       and 'install_only.tar.gz' in n and 'stripped' not in n:
        print(a['browser_download_url'])
        break
" 2>/dev/null)"

if [[ -z "${ASSET_URL:-}" ]]; then
    echo "Error: Could not find a Python ${MAJOR_MINOR} ${TARGET} install_only asset in release ${TAG}" >&2
    exit 1
fi

TMPDIR_DL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_DL"' EXIT

TARBALL="${TMPDIR_DL}/python.tar.gz"
echo "Downloading ${ASSET_URL}..."
curl -fSL --progress-bar -o "$TARBALL" "$ASSET_URL"

echo "Extracting to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
tar xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1

ACTUAL="$("${INSTALL_DIR}/bin/python3" --version 2>&1)"
echo "✓ Installed ${ACTUAL} → ${INSTALL_DIR}"
echo ""
echo "This directory is git-ignored.  setup_python_env.sh will find it automatically."
