#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Encode the remote script as base64 so we can pass it as an argument
# (stdin must stay free for the SSH terminal)
REMOTE_SCRIPT=$(base64 <<'SCRIPT'
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
SCRIPT
)

# Single SSH connection — decode and run the script on the remote side
ssh -t "$SSH_DEST" \
    "export DECK_TMUX='$TMUX_SESSION' DECK_SESSION_ID='$DECK_SESSION_ID'; \
     cd '${REMOTE_DIR:-\$HOME}' 2>/dev/null; \
     echo '$REMOTE_SCRIPT' | base64 -d | bash"

deck exit
