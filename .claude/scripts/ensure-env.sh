#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-$PWD}"

SESSION_INFO="$CWD/.session-info"
[ -f "$SESSION_INFO" ] || exit 0

ENV_FILE="${CLAUDE_ENV_FILE:-$(grep '^CLAUDE_ENV_FILE=' "$SESSION_INFO" | head -1 | cut -d= -f2-)}"
[ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ] || exit 0

# Only re-inject if mise vars are missing (MIX_HOME as sentinel)
if ! grep -q "^export MIX_HOME=" "$ENV_FILE" 2>/dev/null; then
  sed 's/^/export /' "$SESSION_INFO" | grep -v '^export CLAUDE_ENV_FILE=' >> "$ENV_FILE"
fi

exit 0
