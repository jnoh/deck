#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

TMUX_SESSION="deck-${DECK_SESSION_ID}"
SSH_DEST="$SSH_HOST"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

# Copy deck CLI to remote host
REMOTE_DECK_DIR="/tmp/deck-bin-remote"
DECK_CLI=$(which deck 2>/dev/null)
if [ -n "$DECK_CLI" ]; then
    ssh "$SSH_DEST" "mkdir -p $REMOTE_DECK_DIR" 2>/dev/null
    scp -q "$DECK_CLI" "$SSH_DEST:$REMOTE_DECK_DIR/deck" 2>/dev/null
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
if ssh "$SSH_DEST" "tmux has-session -t $TMUX_SESSION 2>/dev/null"; then
    deck status --state starting --desc "Reattaching to $SSH_HOST"
    ssh -t "$SSH_DEST" "tmux attach -t $TMUX_SESSION"
else
    deck status --state starting --desc "Starting Claude on $SSH_HOST"
    ssh -t "$SSH_DEST" "
        export PATH='$REMOTE_DECK_DIR:\$PATH'
        export DECK_SESSION_ID='$DECK_SESSION_ID'
        cd '${REMOTE_DIR:-~}'
        tmux new-session -s '$TMUX_SESSION' \"claude --settings '\$HOOKS'\"
    "
fi

deck exit
