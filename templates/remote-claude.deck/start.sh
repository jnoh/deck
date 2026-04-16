#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status reporting

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"
REMOTE_STATUS="/tmp/deck-${DECK_SESSION_ID}.status"
LOCAL_STATUS="/tmp/deck-${DECK_SESSION_ID}.status"

SSH_CTRL="/tmp/deck-ssh-ctrl-${DECK_SESSION_ID}"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CTRL -o ControlPersist=60"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Step 1a: Write deck CLI to remote (establishes ControlMaster, prompts password)
ssh $SSH_OPTS "$SSH_DEST" "mkdir -p /tmp/deck-bin-remote && cat > /tmp/deck-bin-remote/deck && chmod +x /tmp/deck-bin-remote/deck" <<DECK_CLI
#!/bin/sh
_q='"'
_cmd="\$1"; shift
_json=""
case "\$_cmd" in
  status)
    _s="" _d=""
    while [ \$# -gt 0 ]; do case "\$1" in --state) _s="\$2"; shift 2;; --desc) _d="\$2"; shift 2;; *) shift;; esac; done
    _json="{\${_q}type\${_q}:\${_q}status\${_q}"
    [ -n "\$_s" ] && _json="\$_json,\${_q}state\${_q}:\${_q}\$_s\${_q}"
    [ -n "\$_d" ] && _json="\$_json,\${_q}desc\${_q}:\${_q}\$_d\${_q}"
    _json="\$_json}";;
  title) _json="{\${_q}type\${_q}:\${_q}title\${_q},\${_q}text\${_q}:\${_q}\$*\${_q}}";;
  notify) _json="{\${_q}type\${_q}:\${_q}notify\${_q}}";;
  exit) _json="{\${_q}type\${_q}:\${_q}exit\${_q}}";;
  clear) _json="{\${_q}type\${_q}:\${_q}clear\${_q}}";;
  *) exit 1;;
esac
/bin/echo "\$_json" >> "$REMOTE_STATUS"
DECK_CLI

# Step 1b: Write update-status hook
ssh $SSH_OPTS "$SSH_DEST" "cat > /tmp/deck-update-status.sh && chmod +x /tmp/deck-update-status.sh" <<UPDATE_STATUS
#!/bin/bash
STATE="\$1"
INPUT=\$(cat)

TRANSCRIPT=\$(echo "\$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', ''))
except: pass
" 2>/dev/null)

TOKENS=""
if [ -n "\$TRANSCRIPT" ] && [ -f "\$TRANSCRIPT" ]; then
    TOKENS=\$(python3 -c "
import json, sys
total = 0
for line in open(sys.argv[1]):
    try:
        d = json.loads(line)
        u = d.get('message', {}).get('usage', {})
        if u:
            total += u.get('input_tokens', 0)
            total += u.get('output_tokens', 0)
    except: pass
if total >= 1000000: print(f'{total/1000000:.1f}M tokens')
elif total >= 1000: print(f'{total//1000}k tokens')
elif total > 0: print(f'{total} tokens')
" "\$TRANSCRIPT" 2>/dev/null)
fi

DESC="${SSH_HOST}"
[ -n "\$TOKENS" ] && DESC="\$DESC · \$TOKENS"

deck status --state "\$STATE" --desc "\$DESC"
UPDATE_STATUS

# Step 1c: Write on-prompt hook
ssh $SSH_OPTS "$SSH_DEST" "cat > /tmp/deck-on-prompt.sh && chmod +x /tmp/deck-on-prompt.sh" <<ON_PROMPT
#!/bin/bash
TITLE_FLAG="/tmp/deck-title-${DECK_SESSION_ID}"
INPUT=\$(cat)
if [ ! -f "\$TITLE_FLAG" ] && [ -n "\$INPUT" ]; then
    touch "\$TITLE_FLAG"
    PROMPT=\$(echo "\$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    p = d.get('prompt', '')
    if p:
        print(p[:50])
except: pass
" 2>/dev/null)
    [ -n "\$PROMPT" ] && deck title "\$PROMPT"
fi
echo "\$INPUT" | /tmp/deck-update-status.sh working
ON_PROMPT

# Step 1d: Write startup script
ssh $SSH_OPTS "$SSH_DEST" "cat > /tmp/deck-start.sh && chmod +x /tmp/deck-start.sh" <<STARTUP
#!/bin/bash
export PATH="/tmp/deck-bin-remote:\$PATH"
export DECK_SESSION_ID="$DECK_SESSION_ID"
export DECK_STATUS_FILE="$REMOTE_STATUS"

if ! command -v tmux &>/dev/null; then echo "Error: tmux not installed."; exec bash -l; fi
if ! command -v claude &>/dev/null; then echo "Error: claude not installed."; exec bash -l; fi

cat > /tmp/deck-hooks.json << 'HOOKSJSON'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/tmp/deck-update-status.sh needs-input"}]}],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/tmp/deck-on-prompt.sh"}]}],"PostToolUse":[{"hooks":[{"type":"command","command":"/tmp/deck-update-status.sh working"}]}],"Stop":[{"hooks":[{"type":"command","command":"/tmp/deck-update-status.sh needs-input"}]}],"StopFailure":[{"hooks":[{"type":"command","command":"/tmp/deck-update-status.sh needs-input"}]}],"PermissionRequest":[{"hooks":[{"type":"command","command":"/tmp/deck-update-status.sh needs-approval"}]}]}}
HOOKSJSON

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux attach -t "$TMUX_SESSION"
else
    tmux new-session -s "$TMUX_SESSION" \
        "export PATH=/tmp/deck-bin-remote:\$PATH; cd ${REMOTE_DIR:-\$HOME}; claude --settings /tmp/deck-hooks.json"
fi
STARTUP

# Step 2: Background poller — syncs remote status to local
(
    while true; do
        CONTENT=$(ssh $SSH_OPTS "$SSH_DEST" "cat '$REMOTE_STATUS' 2>/dev/null && rm -f '$REMOTE_STATUS'" 2>/dev/null)
        if [ $? -ne 0 ]; then
            sleep 5
            continue
        fi
        [ -n "$CONTENT" ] && echo "$CONTENT" >> "$LOCAL_STATUS"
        sleep 0.1
    done
) &
POLLER_PID=$!

# Step 3: Run interactively
ssh $SSH_OPTS -t "$SSH_DEST" \
    "cd ${REMOTE_DIR:-\$HOME} 2>/dev/null; \
     /tmp/deck-start.sh"

# Cleanup
kill $POLLER_PID 2>/dev/null
deck status --state idle --desc "Disconnected"
ssh $SSH_OPTS -O exit "$SSH_DEST" 2>/dev/null
deck exit
