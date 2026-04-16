#!/bin/bash
# Claude Code session with Deck status integration

# If a project was selected, cd into it and set the title
if [ -n "$PROJECT" ] && [ -d "$PROJECT" ]; then
    cd "$PROJECT"
    deck title "$(basename "$PROJECT")"
fi

deck status --state starting --desc "Launching Claude Code"

HOOK_DIR="${DECK_PACKAGE_DIR}/hooks"

# Hook mapping:
#   UserPromptSubmit → user sent a prompt, Claude is now working (+ title from first prompt)
#   PostToolUse      → Claude used a tool, still working
#   Stop             → Claude finished responding, YOUR TURN (triggers macOS notification)
#   SessionStart     → session connected
HOOKS=$(cat <<EOF
{"hooks":{
  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"$HOOK_DIR/on-prompt.sh"}]}],
  "PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}],
  "Stop":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc 'Your turn'"}]}],
  "SessionStart":[{"hooks":[{"type":"command","command":"deck status --state connected --desc Connected"}]}]
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
