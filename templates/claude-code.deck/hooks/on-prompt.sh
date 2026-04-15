#!/bin/bash
# Called on UserPromptSubmit — sets title from first prompt, marks working

TITLE_FLAG="/tmp/deck-title-${DECK_SESSION_ID}"

# Read stdin with timeout (Claude sends hook data as JSON)
INPUT=$(timeout 2 cat 2>/dev/null || true)

# Set title from first prompt only
if [ ! -f "$TITLE_FLAG" ] && [ -n "$INPUT" ]; then
    touch "$TITLE_FLAG"

    PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('prompt', '')[:50])
except:
    pass
" 2>/dev/null)

    if [ -n "$PROMPT" ]; then
        deck title "$PROMPT"
    fi
fi

deck status --state working --desc "Processing prompt"
