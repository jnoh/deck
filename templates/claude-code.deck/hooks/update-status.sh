#!/bin/bash
# Updates deck status with state + project/token description
# Usage: update-status.sh <state>

STATE="$1"
INPUT=$(cat)

# Get project name
PROJECT_NAME=""
if [ -n "$PROJECT" ]; then
    PROJECT_NAME="$(basename "$PROJECT")"
fi

# Get transcript path from hook stdin
TRANSCRIPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', ''))
except:
    pass
" 2>/dev/null)

# Sum tokens from transcript
TOKENS=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TOKENS=$(python3 -c "
import json, sys
total = 0
for line in open(sys.argv[1]):
    try:
        d = json.loads(line)
        u = d.get('message', {}).get('usage', {})
        if u:
            total += u.get('input_tokens', 0)
            total += u.get('output_tokens', 0)
            total += u.get('cache_read_input_tokens', 0)
            total += u.get('cache_creation_input_tokens', 0)
    except:
        pass
if total >= 1000000:
    print(f'{total/1000000:.1f}M tokens')
elif total >= 1000:
    print(f'{total//1000}k tokens')
elif total > 0:
    print(f'{total} tokens')
" "$TRANSCRIPT" 2>/dev/null)
fi

# Build description: "project · 84k tokens"
DESC=""
if [ -n "$PROJECT_NAME" ] && [ -n "$TOKENS" ]; then
    DESC="$PROJECT_NAME · $TOKENS"
elif [ -n "$PROJECT_NAME" ]; then
    DESC="$PROJECT_NAME"
elif [ -n "$TOKENS" ]; then
    DESC="$TOKENS"
fi

deck status --state "$STATE" --desc "$DESC"
