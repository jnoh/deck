#!/bin/bash
# Reusable UI interaction helpers for Deck.
# Source this, or run individual functions.
#
# Usage:
#   ./scripts/ui-test.sh screenshot          # Take a screenshot
#   ./scripts/ui-test.sh launch              # Launch the app
#   ./scripts/ui-test.sh kill                # Kill the app
#   ./scripts/ui-test.sh click-add           # Click the + button
#   ./scripts/ui-test.sh select-blueprint N  # Select Nth blueprint from menu
#   ./scripts/ui-test.sh list-ui             # Dump UI element tree

set -e

APP=".build/debug/Deck"

case "${1:-help}" in
    launch)
        pkill -f ".build/debug/Deck" 2>/dev/null || true
        sleep 0.3
        "$APP" &
        echo "Launched PID: $!"
        sleep 2
        osascript -e 'tell application "System Events" to set frontmost of process "Deck" to true'
        ;;

    kill)
        pkill -f ".build/debug/Deck" 2>/dev/null || true
        ;;

    screenshot)
        OUTPUT="${2:-/tmp/deck-screenshot.png}"
        osascript -e 'tell application "System Events" to set frontmost of process "Deck" to true' 2>/dev/null
        sleep 0.3
        screencapture -x "$OUTPUT"
        echo "$OUTPUT"
        ;;

    click-add)
        osascript -e '
        tell application "System Events"
            tell process "Deck"
                set frontmost to true
                delay 0.3
                click menu button "Add" of group 1 of toolbar 1 of window 1
            end tell
        end tell'
        ;;

    select-blueprint)
        N="${2:-1}"
        osascript -e '
        tell application "System Events"
            tell process "Deck"
                set frontmost to true
                delay 0.2
                click menu button "Add" of group 1 of toolbar 1 of window 1
                delay 0.4
                click menu item '"$N"' of menu 1 of menu button "Add" of group 1 of toolbar 1 of window 1
            end tell
        end tell'
        ;;

    right-click)
        # Right-click the Nth row in the sidebar
        N="${2:-1}"
        osascript -e '
        tell application "System Events"
            tell process "Deck"
                set frontmost to true
                delay 0.2
                -- Find rows in the outline (sidebar list)
                set sidebarRows to every row of outline 1 of scroll area 1 of group 1 of splitter group 1 of window 1
                if (count of sidebarRows) >= '"$N"' then
                    perform action "AXShowMenu" of row '"$N"' of outline 1 of scroll area 1 of group 1 of splitter group 1 of window 1
                end if
            end tell
        end tell'
        ;;

    list-ui)
        osascript -e '
        tell application "System Events"
            tell process "Deck"
                set output to ""
                set allElements to entire contents of window 1
                repeat with elem in allElements
                    try
                        set output to output & (class of elem as string) & ": \"" & (name of elem as string) & "\"" & return
                    end try
                end repeat
                return output
            end tell
        end tell' 2>&1
        ;;

    type)
        TEXT="${2}"
        osascript -e '
        tell application "System Events"
            tell process "Deck"
                set frontmost to true
                delay 0.2
                keystroke "'"$TEXT"'"
            end tell
        end tell'
        ;;

    help|*)
        echo "Usage: $0 {launch|kill|screenshot|click-add|select-blueprint N|right-click N|list-ui|type TEXT}"
        ;;
esac
