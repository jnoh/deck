#!/bin/bash
# Remote Claude Code session — SSH + tmux + Claude with status hooks

SSH_DEST="$SSH_HOST"
TMUX_SESSION="deck-${DECK_SESSION_ID}"

deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"

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

# Single SSH connection — start tmux with Claude directly
# If a tmux session already exists, attach to it. Otherwise create one.
ssh -t "$SSH_DEST" "
    export PATH='/tmp/deck-bin-remote:\$PATH'
    export DECK_SESSION_ID='$DECK_SESSION_ID'
    cd '${REMOTE_DIR:-~}'
    if tmux has-session -t '$TMUX_SESSION' 2>/dev/null; then
        tmux attach -t '$TMUX_SESSION'
    else
        tmux new-session -s '$TMUX_SESSION' 'claude --settings '\"'\"'$HOOKS'\"'\"''
    fi
"

deck exit
