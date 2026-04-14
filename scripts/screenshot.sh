#!/bin/bash
# Launch Deck, wait for window, screenshot, kill.
# Usage: ./scripts/screenshot.sh [output_path]

set -e

OUTPUT="${1:-/tmp/deck-screenshot.png}"
APP=".build/debug/Deck"

if [ ! -f "$APP" ]; then
    echo "Build first: swift build"
    exit 1
fi

# Kill any existing Deck instance
pkill -f ".build/debug/Deck" 2>/dev/null || true
sleep 0.5

# Launch in background
"$APP" &
APP_PID=$!

# Wait for the window to appear
for i in $(seq 1 20); do
    WINDOW_ID=$(osascript -e '
        tell application "System Events"
            set deckProcs to (processes whose unix id is '"$APP_PID"')
            if (count of deckProcs) > 0 then
                set deckProc to item 1 of deckProcs
                if (count of windows of deckProc) > 0 then
                    return id of window 1 of deckProc
                end if
            end if
        end tell
    ' 2>/dev/null || true)

    if [ -n "$WINDOW_ID" ]; then
        break
    fi
    sleep 0.5
done

sleep 1  # Let the UI fully render

# Take screenshot of the whole screen (window capture needs CGWindowID which is harder)
screencapture -x "$OUTPUT"

# Kill the app
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

echo "$OUTPUT"
