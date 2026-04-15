#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"
REMOTE_HOOKS_FILE="/tmp/deck-hooks-${DECK_SESSION_ID}.json"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Write hooks JSON to remote host first (avoids quoting hell)
ssh "$SSH_DEST" "cat > $REMOTE_HOOKS_FILE" <<'HOOKS_EOF'
{"hooks":{
  "PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}],
  "Stop":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc 'Your turn'"}]}],
  "SessionStart":[{"hooks":[{"type":"command","command":"deck status --state connected --desc Connected"}]}]
}}
HOOKS_EOF

# Copy deck CLI to remote host
DECK_CLI=$(which deck 2>/dev/null)
if [ -n "$DECK_CLI" ]; then
    ssh "$SSH_DEST" "mkdir -p /tmp/deck-bin-remote" 2>/dev/null
    scp -q "$DECK_CLI" "$SSH_DEST:/tmp/deck-bin-remote/deck" 2>/dev/null
fi

# Connect: attach to existing tmux session or create new one with Claude
ssh -t "$SSH_DEST" \
    "export PATH='/tmp/deck-bin-remote:\$PATH' DECK_SESSION_ID='$DECK_SESSION_ID'; \
     cd '${REMOTE_DIR:-~}'; \
     if tmux has-session -t '$TMUX_SESSION' 2>/dev/null; then \
         tmux attach -t '$TMUX_SESSION'; \
     else \
         tmux new-session -s '$TMUX_SESSION' \
             \"claude --settings \\\"\$(cat $REMOTE_HOOKS_FILE)\\\"\"; \
     fi"

deck exit
