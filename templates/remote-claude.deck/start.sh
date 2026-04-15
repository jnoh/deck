#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Read the deck CLI binary to embed in the setup
DECK_CLI=$(which deck 2>/dev/null)
DECK_SCRIPT=""
if [ -n "$DECK_CLI" ]; then
    DECK_SCRIPT="mkdir -p /tmp/deck-bin-remote"
fi

# Single SSH connection: set up everything and start tmux
ssh -t "$SSH_DEST" "
    # Set up deck CLI
    $DECK_SCRIPT
    export PATH='/tmp/deck-bin-remote:\$PATH'
    export DECK_SESSION_ID='$DECK_SESSION_ID'
    cd '${REMOTE_DIR:-\$HOME}'

    # Check dependencies
    if ! command -v tmux &>/dev/null; then
        echo 'Error: tmux is not installed on this host.'
        exec bash -l
    fi
    if ! command -v claude &>/dev/null; then
        echo 'Error: claude is not installed on this host.'
        exec bash -l
    fi

    HOOKS='{\"hooks\":{\"PostToolUse\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"deck status --state working --desc Working\"}]}],\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"deck status --state needs-input --desc Your_turn\"}]}],\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"deck status --state connected --desc Connected\"}]}]}}'

    if tmux has-session -t '$TMUX_SESSION' 2>/dev/null; then
        tmux attach -t '$TMUX_SESSION'
    else
        tmux new-session -s '$TMUX_SESSION' \"claude --settings \\\"\\\$HOOKS\\\"\"
    fi
"

deck exit
