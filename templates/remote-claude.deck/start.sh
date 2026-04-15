#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"

# SSH connection multiplexing — one password prompt, all subsequent commands reuse it
SSH_CTRL="/tmp/deck-ssh-${DECK_SESSION_ID}"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CTRL -o ControlPersist=30"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Establish the master connection (this is where the password prompt happens)
ssh $SSH_OPTS -O check "$SSH_DEST" 2>/dev/null || \
    ssh $SSH_OPTS -fN "$SSH_DEST"

if [ $? -ne 0 ]; then
    deck status --state error --desc "Connection failed"
    deck exit
    exit 1
fi

# Copy deck CLI to remote host (reuses master connection, no password)
REMOTE_DECK_DIR="/tmp/deck-bin-remote"
DECK_CLI=$(which deck 2>/dev/null)
if [ -n "$DECK_CLI" ]; then
    ssh $SSH_OPTS "$SSH_DEST" "mkdir -p $REMOTE_DECK_DIR" 2>/dev/null
    scp -o "ControlPath=$SSH_CTRL" -q "$DECK_CLI" "$SSH_DEST:$REMOTE_DECK_DIR/deck" 2>/dev/null
fi

# Claude hooks
HOOKS=$(cat <<'HOOKS_EOF'
{"hooks":{
  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"deck status --state working --desc 'Processing prompt'"}]}],
  "PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}],
  "Stop":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc 'Your turn'"}]}],
  "SessionStart":[{"hooks":[{"type":"command","command":"deck status --state connected --desc Connected"}]}]
}}
HOOKS_EOF
)

# Create or attach to remote tmux session
if ssh $SSH_OPTS "$SSH_DEST" "tmux has-session -t $TMUX_SESSION 2>/dev/null"; then
    deck status --state starting --desc "Reattaching to $SSH_HOST"
    ssh $SSH_OPTS -t "$SSH_DEST" "tmux attach -t $TMUX_SESSION"
else
    deck status --state starting --desc "Starting Claude on $SSH_HOST"
    ssh $SSH_OPTS -t "$SSH_DEST" \
        "export PATH='$REMOTE_DECK_DIR:\$PATH' DECK_SESSION_ID='$DECK_SESSION_ID'; \
         cd '${REMOTE_DIR:-~}'; \
         tmux new-session -s '$TMUX_SESSION' 'claude --settings '\"'\"'$HOOKS'\"'\"''"
fi

# Clean up master connection
ssh $SSH_OPTS -O exit "$SSH_DEST" 2>/dev/null

deck exit
