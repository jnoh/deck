#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"
REMOTE_HOOKS="/tmp/deck-hooks-${DECK_SESSION_ID}.json"
REMOTE_START="/tmp/deck-start-remote-${DECK_SESSION_ID}.sh"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Write a startup script to the remote host — avoids all quoting issues
ssh "$SSH_DEST" "cat > $REMOTE_START && chmod +x $REMOTE_START" <<SCRIPT
#!/bin/bash
export PATH="/tmp/deck-bin-remote:\$PATH"
export DECK_SESSION_ID="$DECK_SESSION_ID"
cd "${REMOTE_DIR:-\$HOME}"

# Check dependencies
if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is not installed on this host."
    echo "Install it: sudo apt install tmux / brew install tmux"
    exec bash -l
fi

if ! command -v claude &>/dev/null; then
    echo "Error: claude is not installed on this host."
    echo "Install it: https://docs.anthropic.com/en/docs/claude-code"
    exec bash -l
fi

HOOKS='{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}],"Stop":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc Your_turn"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"deck status --state connected --desc Connected"}]}]}}'

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux attach -t "$TMUX_SESSION"
else
    tmux new-session -s "$TMUX_SESSION" "claude --settings '\$HOOKS'"
fi
SCRIPT

# Copy deck CLI to remote host
DECK_CLI=$(which deck 2>/dev/null)
if [ -n "$DECK_CLI" ]; then
    ssh "$SSH_DEST" "mkdir -p /tmp/deck-bin-remote" 2>/dev/null
    scp -q "$DECK_CLI" "$SSH_DEST:/tmp/deck-bin-remote/deck" 2>/dev/null
fi

# Run the remote script
ssh -t "$SSH_DEST" "$REMOTE_START"

deck exit
