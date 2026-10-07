#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"
SETUP_OFFLINE=0
SETUP_LAUNCH=1
SETUP_PYTHON="${PRESSTOWRITE_SETUP_PYTHON:-python3}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --offline) SETUP_OFFLINE=1; shift ;;
        --no-launch) SETUP_LAUNCH=0; shift ;;
        --python)
            [[ $# -ge 2 ]] || { echo "--python requires an executable path."; exit 1; }
            SETUP_PYTHON="$2"; shift 2 ;;
        --help)
            echo "Usage: scripts/setup_mac.sh [--offline] [--no-launch] [--python executable]"
            exit 0 ;;
        *) echo "Unknown setup option: $1"; exit 1 ;;
    esac
done

echo "Press To Write setup for macOS / Apple Silicon"
if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "Setup requires an Apple Silicon Mac, running the terminal natively (outside Rosetta)."
    exit 1
fi
SETUP_MACOS_MAJOR="$(sw_vers -productVersion | cut -d . -f 1)"
if [[ "$SETUP_MACOS_MAJOR" -lt 14 ]]; then
    echo "The pinned MLX runtime requires macOS 14 or later."
    exit 1
fi
if ! xcode-select -p >/dev/null 2>&1 || ! swift --version >/dev/null 2>&1; then
    echo "Install Xcode Command Line Tools with xcode-select --install, then run setup again."
    exit 1
fi
if ! command -v "$SETUP_PYTHON" >/dev/null 2>&1; then
    echo "Install an arm64 Python 3.10–3.13, then use --python with its executable."
    exit 1
fi
"$SETUP_PYTHON" - <<'PY'
import platform, sys
if platform.machine() != "arm64" or not (3, 10) <= sys.version_info[:2] <= (3, 13):
    raise SystemExit("Use a native arm64 Python 3.10–3.13 (Python 3.12 is recommended).")
PY

# Create the runtime in its final location. Copied venvs contain absolute paths
# and can stop working when the source checkout moves or Documents is protected.
APP_SUPPORT_DIR="$HOME/Library/Application Support/Press To Write"
APP_SUPPORT_VENV="$APP_SUPPORT_DIR/venv"
mkdir -p "$APP_SUPPORT_DIR"
if [[ ! -x "$APP_SUPPORT_VENV/bin/python3" ]]; then
    if [[ -e "$APP_SUPPORT_VENV" ]]; then
        echo "An incomplete runtime already exists. Preserve it and repair it before setup."
        exit 1
    fi
    if [[ "$SETUP_OFFLINE" == 1 ]]; then
        echo "Offline setup requires an existing runtime. Run make setup online once."
        exit 1
    fi
    "$SETUP_PYTHON" -m venv "$APP_SUPPORT_VENV"
fi
RUNTIME_PYTHON="$APP_SUPPORT_VENV/bin/python3"
"$RUNTIME_PYTHON" - <<'PY'
import platform, sys
if platform.machine() != "arm64" or not (3, 10) <= sys.version_info[:2] <= (3, 13):
    raise SystemExit("The existing runtime uses an unsupported Python; repair it before setup.")
PY

if [[ "$SETUP_OFFLINE" == 0 ]]; then
    echo "Installing pinned Python dependencies (one-time network setup)..."
    "$RUNTIME_PYTHON" -m pip install --disable-pip-version-check -r "$DIR/requirements.txt"
else
    echo "Verifying the existing offline runtime..."
fi
"$RUNTIME_PYTHON" - "$DIR/requirements.txt" <<'PY'
from importlib import metadata
from pathlib import Path
import sys
for line in Path(sys.argv[1]).read_text().splitlines():
    if not line or line.startswith("#"):
        continue
    name, expected = line.split("==")
    try:
        installed = metadata.version(name)
    except metadata.PackageNotFoundError:
        raise SystemExit(f"Missing dependency: {name}. Run online setup first.")
    if installed != expected:
        raise SystemExit(f"Dependency mismatch: {name}. Run online setup to install the pinned version.")
import mlx_whisper, numpy
PY

if [[ "$SETUP_OFFLINE" == 1 ]]; then
    "$RUNTIME_PYTHON" "$DIR/scripts/setup_model.py"
else
    echo "Checking the local model, downloading it only if missing..."
    "$RUNTIME_PYTHON" "$DIR/scripts/setup_model.py" --download
fi
"$DIR/scripts/build_app.sh"
echo "Setup complete. Grant Microphone and Accessibility permissions on this Mac."
if [[ "$SETUP_LAUNCH" == 1 ]]; then
    "$DIR/scripts/run.sh"
fi
