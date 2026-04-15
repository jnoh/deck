#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"
REMOTE_SCRIPT="/tmp/deck-remote-${DECK_SESSION_ID}.sh"

# SSH multiplexing — first command prompts password, second reuses it
SSH_CTRL="/tmp/deck-ssh-ctrl-${DECK_SESSION_ID}"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CTRL -o ControlPersist=30"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Step 1: Write startup script to remote host (prompts for password, creates master)
ssh $SSH_OPTS "$SSH_DEST" "cat > $REMOTE_SCRIPT && chmod +x $REMOTE_SCRIPT" <<'REMOTE_EOF'
#!/bin/bash
export PATH="/tmp/deck-bin-remote:$PATH"

if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is not installed."
    exec bash -l
fi
if ! command -v claude &>/dev/null; then
    echo "Error: claude is not installed."
    exec bash -l
fi

HOOKS='{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}],"Stop":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc Your_turn"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"deck status --state connected --desc Connected"}]}]}}'

if tmux has-session -t "$DECK_TMUX" 2>/dev/null; then
    tmux attach -t "$DECK_TMUX"
else
    tmux new-session -s "$DECK_TMUX" "claude --settings '$HOOKS'"
fi
REMOTE_EOF

# Step 2: Run the script (reuses master connection — no password prompt)
ssh $SSH_OPTS -t "$SSH_DEST" \
    "export DECK_TMUX='$TMUX_SESSION' DECK_SESSION_ID='$DECK_SESSION_ID'; \
     cd '${REMOTE_DIR:-\$HOME}' 2>/dev/null; \
     $REMOTE_SCRIPT"

# Cleanup
ssh $SSH_OPTS -O exit "$SSH_DEST" 2>/dev/null
deck exit
