#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Restart this app. The client verifies and replaces its own resident daemon;
# removing the socket or broadly killing Python processes can race that handoff.
APP_NAME="Press To Write"
APP_EXECUTABLE="$DIR/$APP_NAME.app/Contents/MacOS/PressToWrite"
pkill -f "$APP_EXECUTABLE" 2>/dev/null || true
pkill -f "$DIR/Metatron.app/Contents/MacOS/Metatron" 2>/dev/null || true
for _ in {1..50}; do
    if ! pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
if pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
    echo "Press To Write is still running; close it before relaunching."
    exit 1
fi

# Check if .app exists, if not build it
if [ ! -d "$DIR/$APP_NAME.app" ]; then
    echo "$APP_NAME.app not found. Building now..."
    "$DIR/scripts/build_app.sh"
fi

echo "Launching $APP_NAME.app..."
open "$DIR/$APP_NAME.app"

echo "Press To Write is running!"
echo "Its local speech engine will load automatically and show Ready when available."
echo "Hold down the Function (Fn) key and speak, then release to transcribe and paste."
