#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Kill any previous instance of Metatron or the daemon
pkill -f "Metatron.app/Contents/MacOS/Metatron" 2>/dev/null || true
pkill -f "whisper_daemon.py" 2>/dev/null || true
rm -f /tmp/metatron.sock 2>/dev/null || true

# Check if .app exists, if not build it
if [ ! -d "$DIR/Metatron.app" ]; then
    echo "Metatron.app not found. Building now..."
    "$DIR/scripts/build_app.sh"
fi

echo "Starting Metatron daemon in background..."
if [ -f "$DIR/.venv/bin/python3" ]; then
    "$DIR/.venv/bin/python3" "$DIR/daemon/whisper_daemon.py" > /tmp/metatron_daemon.log 2>&1 &
elif which uv >/dev/null 2>&1; then
    uv run --directory "$DIR" python3 "$DIR/daemon/whisper_daemon.py" > /tmp/metatron_daemon.log 2>&1 &
else
    python3 "$DIR/daemon/whisper_daemon.py" > /tmp/metatron_daemon.log 2>&1 &
fi

sleep 1

echo "Launching Metatron.app..."
open "$DIR/Metatron.app"

echo "Metatron is running!"
echo "Hold down the Function (Fn) key and speak, then release to transcribe and paste."
