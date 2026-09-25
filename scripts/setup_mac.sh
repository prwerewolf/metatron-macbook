#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=========================================="
echo "  Metatron Setup for macOS (Apple Silicon)"
echo "=========================================="

# 1. Architecture Check
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "Error: Metatron requires an Apple Silicon Mac (M1/M2/M3/M4, arm64). Detected: $ARCH"
    exit 1
fi

# 2. Python 3 Check
if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required. Please install Python 3 (e.g. brew install python3)."
    exit 1
fi

# 3. Create or verify Python virtual environment
echo "[1/4] Configuring Python environment (.venv)..."
if [ ! -d "$DIR/.venv" ] || [ ! -f "$DIR/.venv/bin/python3" ]; then
    echo "Creating virtual environment at $DIR/.venv..."
    python3 -m venv "$DIR/.venv"
fi

# 4. Install MLX Whisper & dependencies
echo "[2/4] Installing MLX Whisper dependencies..."
if ! "$DIR/.venv/bin/python3" -m pip --version >/dev/null 2>&1; then
    echo "Bootstrapping pip in virtual environment..."
    "$DIR/.venv/bin/python3" -m ensurepip --default-pip >/dev/null 2>&1 || true
fi
"$DIR/.venv/bin/python3" -m pip install --upgrade pip --quiet
"$DIR/.venv/bin/python3" -m pip install mlx-whisper huggingface_hub --quiet

# Sync runtime environment to Application Support (avoids macOS TCC Documents folder restrictions)
APP_SUPPORT_DIR="$HOME/Library/Application Support/Metatron"
APP_SUPPORT_VENV="$APP_SUPPORT_DIR/venv"
mkdir -p "$APP_SUPPORT_DIR"
if [ ! -d "$APP_SUPPORT_VENV" ] || [ ! -f "$APP_SUPPORT_VENV/bin/python3" ]; then
    echo "Syncing runtime virtual environment to Application Support..."
    cp -R "$DIR/.venv" "$APP_SUPPORT_VENV"
fi

# 5. Check / Download Offline Model
echo "[3/4] Checking offline speech model..."
MODEL_ID="mlx-community/whisper-large-v3-turbo"
MODEL_STATUS=$("$DIR/.venv/bin/python3" -c '
import os
from pathlib import Path
cache_dir = Path(os.environ.get("HF_HUB_CACHE", os.path.expanduser("~/.cache/huggingface/hub")))
repo_dir = cache_dir / "models--mlx-community--whisper-large-v3-turbo"
snapshots = repo_dir / "snapshots"
found = False
if snapshots.is_dir():
    for snap in snapshots.iterdir():
        if (snap / "config.json").is_file() and any((snap / w).is_file() for w in ("weights.safetensors", "weights.npz")):
            found = True
            break
print("EXISTS" if found else "MISSING")
')

if [ "$MODEL_STATUS" = "EXISTS" ]; then
    echo "✓ Found local speech model in cache."
else
    echo "Model not found in cache. Downloading $MODEL_ID (one-time setup)..."
    "$DIR/.venv/bin/python3" -m huggingface_hub.cli.core download "$MODEL_ID"
fi

# 6. Build application
echo "[4/4] Building Metatron.app..."
"$DIR/scripts/build_app.sh"

echo ""
echo "=========================================="
echo "  Setup complete! Starting Metatron..."
echo "=========================================="
"$DIR/scripts/run.sh"
