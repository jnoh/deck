#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Single SSH: pipe a script via stdin and execute it with bash
ssh -t "$SSH_DEST" bash -s "$TMUX_SESSION" "${REMOTE_DIR:-\$HOME}" "$DECK_SESSION_ID" <<'REMOTE_SCRIPT'
TMUX_SESSION="$1"
REMOTE_DIR="$2"
DECK_SESSION_ID="$3"

export PATH="/tmp/deck-bin-remote:$PATH"
export DECK_SESSION_ID
cd "$REMOTE_DIR" 2>/dev/null || cd ~

if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is not installed."
    exec bash -l
fi
if ! command -v claude &>/dev/null; then
    echo "Error: claude is not installed."
    exec bash -l
fi

HOOKS='{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}],"Stop":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc Your_turn"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"deck status --state connected --desc Connected"}]}]}}'

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux attach -t "$TMUX_SESSION"
else
    tmux new-session -s "$TMUX_SESSION" "claude --settings '$HOOKS'"
fi
REMOTE_SCRIPT

deck exit
