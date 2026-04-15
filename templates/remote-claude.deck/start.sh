#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status reporting

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"
REMOTE_SCRIPT="/tmp/deck-remote-${DECK_SESSION_ID}.sh"
REMOTE_STATUS="/tmp/deck-${DECK_SESSION_ID}.status"
LOCAL_STATUS="/tmp/deck-${DECK_SESSION_ID}.status"

SSH_CTRL="/tmp/deck-ssh-ctrl-${DECK_SESSION_ID}"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CTRL -o ControlPersist=60"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Step 1: Write deck CLI + startup script to remote host
# The deck CLI is a simple shell script — embed it directly
ssh $SSH_OPTS "$SSH_DEST" "
mkdir -p /tmp/deck-bin-remote

# Create deck CLI on the remote host
cat > /tmp/deck-bin-remote/deck << 'DECK_CLI'
#!/bin/sh
_cmd=\"\$1\"; shift
_q='\"'
_json=\"\"
case \"\$_cmd\" in
  status)
    _state=\"\" _desc=\"\"
    while [ \$# -gt 0 ]; do
      case \"\$1\" in
        --state) _state=\"\$2\"; shift 2;;
        --desc) _desc=\"\$2\"; shift 2;;
        *) shift;;
      esac
    done
    _json=\"{\${_q}type\${_q}:\${_q}status\${_q}\"
    [ -n \"\$_state\" ] && _json=\"\${_json},\${_q}state\${_q}:\${_q}\${_state}\${_q}\"
    [ -n \"\$_desc\" ] && _json=\"\${_json},\${_q}desc\${_q}:\${_q}\${_desc}\${_q}\"
    _json=\"\${_json}}\"
    ;;
  title)
    _title=\"\$*\"
    _json=\"{\${_q}type\${_q}:\${_q}title\${_q},\${_q}text\${_q}:\${_q}\${_title}\${_q}}\"
    ;;
  notify)
    _text=\"\" _level=\"info\"
    while [ \$# -gt 0 ]; do
      case \"\$1\" in
        --text) _text=\"\$2\"; shift 2;;
        --level) _level=\"\$2\"; shift 2;;
        *) shift;;
      esac
    done
    _json=\"{\${_q}type\${_q}:\${_q}notify\${_q},\${_q}text\${_q}:\${_q}\${_text}\${_q},\${_q}level\${_q}:\${_q}\${_level}\${_q}}\"
    ;;
  exit)
    _json=\"{\${_q}type\${_q}:\${_q}exit\${_q}}\"
    ;;
  clear)
    _json=\"{\${_q}type\${_q}:\${_q}clear\${_q}}\"
    ;;
  *) exit 1;;
esac
/bin/echo \"\$_json\" >> \"$REMOTE_STATUS\"
DECK_CLI
chmod +x /tmp/deck-bin-remote/deck

# Create startup script
cat > $REMOTE_SCRIPT << 'STARTUP'
#!/bin/bash
export PATH=\"/tmp/deck-bin-remote:\$PATH\"
export DECK_SESSION_ID=\"$DECK_SESSION_ID\"

if ! command -v tmux &>/dev/null; then
    echo \"Error: tmux is not installed.\"
    exec bash -l
fi
if ! command -v claude &>/dev/null; then
    echo \"Error: claude is not installed.\"
    exec bash -l
fi

# Create on-prompt hook script
cat > /tmp/deck-on-prompt.sh << 'PROMPTHOOK'
#!/bin/bash
TITLE_FLAG="/tmp/deck-title-${DECK_SESSION_ID}"
INPUT=$(perl -e 'alarm 2; local $/; print <STDIN>' 2>/dev/null || true)
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
    [ -n "$PROMPT" ] && deck title "$PROMPT"
fi
deck status --state working --desc "Processing prompt"
PROMPTHOOK
chmod +x /tmp/deck-on-prompt.sh

HOOKS='{\"hooks\":{\"UserPromptSubmit\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"/tmp/deck-on-prompt.sh\"}]}],\"PostToolUse\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"deck status --state working --desc Working\"}]}],\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"deck status --state needs-input --desc Your_turn\"}]}],\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"deck status --state connected --desc Connected\"}]}]}}'

if tmux has-session -t \"\$DECK_TMUX\" 2>/dev/null; then
    tmux attach -t \"\$DECK_TMUX\"
else
    tmux new-session -s \"\$DECK_TMUX\" \"claude --settings '\$HOOKS'\"
fi
STARTUP
chmod +x $REMOTE_SCRIPT
"

# Step 2: Start background poller that syncs remote status file to local
(
    while true; do
        CONTENT=$(ssh $SSH_OPTS "$SSH_DEST" "cat '$REMOTE_STATUS' 2>/dev/null && rm -f '$REMOTE_STATUS'" 2>/dev/null)
        if [ -n "$CONTENT" ]; then
            echo "$CONTENT" >> "$LOCAL_STATUS"
        fi
        sleep 0.1
    done
) &
POLLER_PID=$!

# Step 3: Run the script interactively (reuses master connection)
ssh $SSH_OPTS -t "$SSH_DEST" \
    "export DECK_TMUX='$TMUX_SESSION' DECK_SESSION_ID='$DECK_SESSION_ID'; \
     cd '${REMOTE_DIR:-\$HOME}' 2>/dev/null; \
     $REMOTE_SCRIPT"

# Cleanup
kill $POLLER_PID 2>/dev/null
deck status --state idle --desc "Disconnected"
ssh $SSH_OPTS -O exit "$SSH_DEST" 2>/dev/null
deck exit
