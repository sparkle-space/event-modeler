#!/bin/bash
set -e

PROJECT_ROOT="$PWD"
SESSION_INFO="$PROJECT_ROOT/.session-info"

MISE_BIN="${MISE_BIN:-$(command -v mise 2>/dev/null || echo "$HOME/.local/bin/mise")}"
if [ ! -x "$MISE_BIN" ]; then
  echo "Warning: mise not found, skipping environment setup" >&2
  exit 0
fi

MISE_OUTPUT=$("$MISE_BIN" env --shell bash -C "$PROJECT_ROOT" 2>/dev/null) || {
  echo "Warning: mise env failed, skipping environment setup" >&2
  exit 0
}

# Store raw KEY=VALUE lines in .session-info
echo "$MISE_OUTPUT" | sed 's/^export //' > "$SESSION_INFO"

# Inject into Claude Code session env
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "CLAUDE_ENV_FILE=$CLAUDE_ENV_FILE" >> "$SESSION_INFO"
  echo "$MISE_OUTPUT" >> "$CLAUDE_ENV_FILE"
fi
