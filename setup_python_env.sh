#!/usr/bin/env bash
# setup_python_env.sh - Set up Python environment with correct version

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_VERSION_FILE="${REPO_ROOT}/pybridge/python-version.txt"
REQUIREMENTS_LOCK="${REPO_ROOT}/pybridge/requirements.lock"
VENV_DIR="${REPO_ROOT}/.venv"

if [[ ! -f "${PYTHON_VERSION_FILE}" ]]; then
    echo "Error: ${PYTHON_VERSION_FILE} not found" >&2
    exit 1
fi

EXPECTED_VERSION="$(tr -d '[:space:]' < "${PYTHON_VERSION_FILE}")"
EXPECTED_MAJOR_MINOR="${EXPECTED_VERSION%.*}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setting up Python Environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Required Python version: ${EXPECTED_VERSION}"
echo ""

# Find compatible Python
PYTHON_CMD=""

# Check common locations for the exact version
for cmd in \
    "/usr/bin/python${EXPECTED_MAJOR_MINOR}" \
    "/usr/bin/python3" \
    "python${EXPECTED_MAJOR_MINOR}" \
    "/opt/homebrew/bin/python${EXPECTED_MAJOR_MINOR}" \
    "${HOME}/homebrew/bin/python${EXPECTED_MAJOR_MINOR}" \
    "/usr/local/bin/python${EXPECTED_MAJOR_MINOR}"; do
    
    if command -v "$cmd" >/dev/null 2>&1; then
        VERSION=$("$cmd" --version 2>&1 | awk '{print $2}')
        if [[ "$VERSION" == "$EXPECTED_VERSION" ]]; then
            PYTHON_CMD="$cmd"
            echo "✓ Found Python ${VERSION} at: ${cmd}"
            break
        fi
    fi
done

# If exact match not found, find any compatible version
if [[ -z "$PYTHON_CMD" ]]; then
    echo "Exact version not found, looking for Python ${EXPECTED_MAJOR_MINOR}.x..."
    for cmd in \
        "/usr/bin/python3" \
        "python3" \
        "/opt/homebrew/bin/python3" \
        "${HOME}/homebrew/bin/python3" \
        "/usr/local/bin/python3"; do
        
        if command -v "$cmd" >/dev/null 2>&1; then
            VERSION=$("$cmd" --version 2>&1 | awk '{print $2}')
            VERSION_MAJOR_MINOR="${VERSION%.*}"
            if [[ "$VERSION_MAJOR_MINOR" == "$EXPECTED_MAJOR_MINOR" ]]; then
                PYTHON_CMD="$cmd"
                echo "✓ Found compatible Python ${VERSION} at: ${cmd}"
                break
            fi
        fi
    done
fi

if [[ -z "$PYTHON_CMD" ]]; then
    echo "✗ Error: Could not find Python ${EXPECTED_MAJOR_MINOR}.x" >&2
    echo "" >&2
    echo "Available Python versions:" >&2
    which -a python3 python3.* 2>/dev/null || echo "  (none found)" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "1. Install Python ${EXPECTED_MAJOR_MINOR} (recommended)" >&2
    echo "2. Update pybridge/python-version.txt to match your Python version" >&2
    exit 1
fi

# Check if venv exists with wrong version
if [[ -d "$VENV_DIR" ]]; then
    CURRENT_VERSION=$("${VENV_DIR}/bin/python" --version 2>&1 | awk '{print $2}' || echo "unknown")
    if [[ "$CURRENT_VERSION" != "$EXPECTED_VERSION" ]]; then
        echo ""
        echo "⚠ Existing venv uses Python ${CURRENT_VERSION} (expected ${EXPECTED_VERSION})"
        echo "  Removing old venv..."
        rm -rf "$VENV_DIR"
    fi
fi

# Create or verify venv
if [[ ! -d "$VENV_DIR" ]]; then
    echo ""
    echo "==> Creating virtual environment..."
    "$PYTHON_CMD" -m venv "$VENV_DIR"
    echo "✓ Virtual environment created"
fi

# Install dependencies
echo ""
echo "==> Installing dependencies..."
"${VENV_DIR}/bin/pip" install --quiet --upgrade pip setuptools wheel

if [[ -f "$REQUIREMENTS_LOCK" ]]; then
    "${VENV_DIR}/bin/pip" install --quiet -r "$REQUIREMENTS_LOCK"
    echo "✓ Dependencies installed from requirements.lock"
else
    echo "⚠ No requirements.lock found, skipping dependency installation"
fi

# Verify
FINAL_VERSION=$("${VENV_DIR}/bin/python" --version 2>&1 | awk '{print $2}')
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Python version: ${FINAL_VERSION}"
echo "Virtual environment: ${VENV_DIR}"
echo ""
echo "To activate the virtual environment:"
echo "  source .venv/bin/activate"
echo ""
echo "To build and test signing:"
echo "  export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAM_ID)\""
echo "  ./AppleTVRemoteApp/Scripts/signing_helper.sh test-sign"
echo ""
