#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
SOURCE_VENV="${REPO_ROOT}/.venv"
LOCKFILE="${REPO_ROOT}/pybridge/requirements.lock"
PYTHON_VERSION_FILE="${REPO_ROOT}/pybridge/python-version.txt"
BUNDLE_DIR="${ROOT_DIR}/Sources/Atmo/Resources/Python"
TARGET_VENV="${BUNDLE_DIR}/.venv"

if [[ ! -x "${SOURCE_VENV}/bin/python" ]]; then
  echo "Virtual environment not found at ${SOURCE_VENV}" >&2
  echo "Run 'python3 -m venv .venv' and install dependencies before packaging." >&2
  exit 1
fi

if [[ ! -f "${LOCKFILE}" ]]; then
  echo "Lockfile missing at ${LOCKFILE}" >&2
  exit 1
fi

if [[ ! -f "${PYTHON_VERSION_FILE}" ]]; then
  echo "Python version file missing at ${PYTHON_VERSION_FILE}" >&2
  exit 1
fi

EXPECTED_PYTHON_VERSION="$(tr -d '[:space:]' < "${PYTHON_VERSION_FILE}")"

ACTUAL_PYTHON_VERSION="$(${SOURCE_VENV}/bin/python - <<'PY'
import platform
print(platform.python_version())
PY
)"

if [[ "${ACTUAL_PYTHON_VERSION}" != "${EXPECTED_PYTHON_VERSION}" ]]; then
  echo "Python version mismatch: expected ${EXPECTED_PYTHON_VERSION}, found ${ACTUAL_PYTHON_VERSION}" >&2
  echo "Recreate .venv with the correct interpreter before packaging." >&2
  exit 1
fi

rm -rf "${BUNDLE_DIR}"
mkdir -p "${TARGET_VENV}"

rsync -a --delete --copy-links "${SOURCE_VENV}/" "${TARGET_VENV}/"

TARGET_PYTHON="${TARGET_VENV}/bin/python"
TARGET_PIP="${TARGET_VENV}/bin/pip"

FRAMEWORK_SRC="$(${SOURCE_VENV}/bin/python - <<'PY'
import pathlib
import sys
print(pathlib.Path(sys.executable).resolve().parents[3])
PY
)"

FRAMEWORK_DEST="${BUNDLE_DIR}/Python3.framework"

if [[ ! -d "${FRAMEWORK_SRC}" ]]; then
  echo "Could not resolve Python framework directory from ${SOURCE_VENV} (expected ${FRAMEWORK_SRC})." >&2
  exit 1
fi

rsync -a --delete "${FRAMEWORK_SRC}/" "${FRAMEWORK_DEST}/"
ln -sf "../Python3.framework/Python3" "${TARGET_VENV}/Python3"


PY_MAJOR_MINOR="${ACTUAL_PYTHON_VERSION%.*}"

# Normalise pyvenv.cfg to avoid leaking developer-specific paths while keeping the
# interpreter aware of the bundled framework.
cat > "${TARGET_VENV}/pyvenv.cfg" <<EOF
home = ../Python3.framework/Versions/${PY_MAJOR_MINOR}/bin
include-system-site-packages = false
version = ${ACTUAL_PYTHON_VERSION}
EOF

# Reinstall dependencies from the lockfile and remove extras.
"${TARGET_PIP}" install --no-cache-dir --upgrade pip

"${TARGET_PYTHON}" - <<PY
import pathlib
import subprocess
import sys

lock_path = pathlib.Path(r"${LOCKFILE}")
required = {"pip", "setuptools", "wheel"}
for line in lock_path.read_text().splitlines():
  line = line.strip()
  if not line or line.startswith("#"):
    continue
  name = line.split("==", 1)[0].strip().lower().replace("-", "_")
  required.add(name)

try:
  import importlib.metadata as metadata
except ImportError:  # pragma: no cover - Python < 3.8 fallback
  import importlib_metadata as metadata  # type: ignore

installed = {
  dist.metadata["Name"].strip().lower().replace("-", "_")
  for dist in metadata.distributions()
}

extras = sorted(installed - required)
if extras:
  subprocess.check_call([
    sys.executable,
    "-m",
    "pip",
    "uninstall",
    "-y",
    *extras,
  ])

subprocess.check_call([
  sys.executable,
  "-m",
  "pip",
  "install",
  "--no-cache-dir",
  "--requirement",
  str(lock_path),
])
PY

PYTHON_TAG="$(${TARGET_PYTHON} - <<'PY'
import sys
print(f"python{sys.version_info.major}.{sys.version_info.minor}")
PY
)"

SITE_PACKAGES="${TARGET_VENV}/lib/${PYTHON_TAG}/site-packages"

rsync -a --delete \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "${REPO_ROOT}/pybridge/" "${BUNDLE_DIR}/pybridge/"

find "${BUNDLE_DIR}" -type d -name '__pycache__' -prune -exec rm -rf {} +

echo "Embedded Python environment created at ${TARGET_VENV}" 
echo "Python executable: ${TARGET_PYTHON}"
echo "Site-packages root: ${SITE_PACKAGES}"
