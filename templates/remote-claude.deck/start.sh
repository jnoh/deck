#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"
REMOTE_SCRIPT="/tmp/deck-remote-${DECK_SESSION_ID}.sh"

SSH_CTRL="/tmp/deck-ssh-ctrl-${DECK_SESSION_ID}"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CTRL -o ControlPersist=30"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Step 1: Write startup script to remote host
ssh $SSH_OPTS "$SSH_DEST" "cat > $REMOTE_SCRIPT && chmod +x $REMOTE_SCRIPT" <<'REMOTE_EOF'
#!/bin/bash
if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is not installed."
    exec bash -l
fi
if ! command -v claude &>/dev/null; then
    echo "Error: claude is not installed."
    exec bash -l
fi

if tmux has-session -t "$DECK_TMUX" 2>/dev/null; then
    tmux attach -t "$DECK_TMUX"
else
    tmux new-session -s "$DECK_TMUX" "claude"
fi
REMOTE_EOF

# Step 2: Run the script
ssh $SSH_OPTS -t "$SSH_DEST" \
    "export DECK_TMUX='$TMUX_SESSION'; \
     cd '${REMOTE_DIR:-\$HOME}' 2>/dev/null; \
     $REMOTE_SCRIPT"

# Update local status
deck status --state idle --desc "Disconnected"
ssh $SSH_OPTS -O exit "$SSH_DEST" 2>/dev/null
deck exit
