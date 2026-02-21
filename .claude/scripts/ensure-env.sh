#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-$PWD}"

SESSION_INFO="$CWD/.session-info"

# Self-heal: if session-info is missing, regenerate it via mise
if [ ! -f "$SESSION_INFO" ]; then
  MISE_BIN="${MISE_BIN:-$(command -v mise 2>/dev/null || echo "$HOME/.local/bin/mise")}"
  if [ -x "$MISE_BIN" ]; then
    "$MISE_BIN" trust "$CWD" 2>/dev/null || true
    MISE_OUTPUT=$("$MISE_BIN" env --shell bash -C "$CWD" 2>/dev/null) || true
    if [ -n "$MISE_OUTPUT" ]; then
      echo "$MISE_OUTPUT" | sed 's/^export //' > "$SESSION_INFO"
    fi
  fi
fi

[ -f "$SESSION_INFO" ] || exit 0

ENV_FILE="${CLAUDE_ENV_FILE:-$(grep '^CLAUDE_ENV_FILE=' "$SESSION_INFO" | head -1 | cut -d= -f2-)}"
[ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ] || exit 0

# Only re-inject if mise vars are missing (MIX_HOME as sentinel)
if ! grep -q "^export MIX_HOME=" "$ENV_FILE" 2>/dev/null; then
  sed 's/^/export /' "$SESSION_INFO" | grep -v '^export CLAUDE_ENV_FILE=' >> "$ENV_FILE"
fi

exit 0
