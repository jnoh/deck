#!/bin/bash
# Called on UserPromptSubmit — sets title from first prompt, marks working

TITLE_FLAG="/tmp/deck-title-${DECK_SESSION_ID}"
INPUT=$(cat)

# Generate a title from the first prompt only
if [ ! -f "$TITLE_FLAG" ]; then
    touch "$TITLE_FLAG"

    PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('prompt', '')[:200])
except:
    pass
" 2>/dev/null)

    if [ -n "$PROMPT" ]; then
        # Ask Claude to generate a short title in the background
        (
            TITLE=$(echo "Summarize this task in 3-5 words for a sidebar label. Output ONLY the label, nothing else: $PROMPT" \
                | claude -p --model haiku 2>/dev/null \
                | head -1 \
                | cut -c1-50)
            if [ -n "$TITLE" ]; then
                deck title "$TITLE"
            else
                # Fallback: use first 50 chars of prompt
                deck title "$(echo "$PROMPT" | cut -c1-50)"
            fi
        ) &
    fi
fi

deck status --state working --desc "Processing prompt"
