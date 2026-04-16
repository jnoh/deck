#!/bin/bash
# Claude Code session with Deck status integration

# If a project was selected, cd into it and set the title
if [ -n "$PROJECT" ] && [ -d "$PROJECT" ]; then
    cd "$PROJECT"
    deck title "$(basename "$PROJECT")"
fi

deck status --state starting --desc "Launching Claude Code"

HOOK_DIR="${DECK_PACKAGE_DIR}/hooks"

HOOKS=$(cat <<EOF
{"hooks":{
  "SessionStart":[{"hooks":[{"type":"command","command":"$HOOK_DIR/update-status.sh needs-input"}]}],
  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"$HOOK_DIR/on-prompt.sh"}]}],
  "PostToolUse":[{"hooks":[{"type":"command","command":"$HOOK_DIR/update-status.sh working"}]}],
  "Stop":[{"hooks":[{"type":"command","command":"$HOOK_DIR/update-status.sh needs-input"}]}],
  "StopFailure":[{"hooks":[{"type":"command","command":"$HOOK_DIR/update-status.sh needs-input"}]}],
  "PermissionRequest":[{"hooks":[{"type":"command","command":"$HOOK_DIR/update-status.sh needs-input"}]}]
}}
EOF
)

if command -v claude &>/dev/null; then
    claude --settings "$HOOKS"
else
    echo "Claude Code not found on PATH."
    echo "Install: https://docs.anthropic.com/en/docs/claude-code"
    sleep 3
fi

deck exit
