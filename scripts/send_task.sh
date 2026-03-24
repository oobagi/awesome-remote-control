#!/usr/bin/env bash
# Send a task/message to a running Claude Code remote control session.
# Messages are tagged with [openclaw] so the Stop hook (on_stop.sh)
# recognises them and triggers the callback to the orchestrator.
#
# Usage: send_task.sh <session-label|tmux-name> <message>
#
# Examples:
#   send_task.sh "🦊 Fox | my-project" "Do an analysis of the codebase"
#   send_task.sh cc-fox-my-project "Fix the issues you identified"
#
# The [openclaw] tag is prepended automatically — do NOT include it yourself.

set -euo pipefail

NAME="${1:?Usage: send_task.sh <session-label|tmux-name> <message>}"
MESSAGE="${2:?Missing message}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Resolve tmux session name ────────────────────────────────────────────────

if [[ "$NAME" =~ ^cc- ]]; then
  TMUX_NAME="$NAME"
else
  # Derive tmux name from session label (same logic as start_session.sh)
  EMOJI_AND_ANIMAL=$(echo "$NAME" | cut -d'|' -f1 | xargs)
  ANIMAL_SLUG=$(echo "$EMOJI_AND_ANIMAL" | sed 's/[^ ]* //' | tr '[:upper:]' '[:lower:]')
  DIRBASE=$(echo "$NAME" | cut -d'|' -f2 | xargs)
  TMUX_NAME="cc-${ANIMAL_SLUG}-${DIRBASE}"
  TMUX_NAME=$(echo "$TMUX_NAME" | tr ' ' '-' | tr -cd '[:alnum:]-')
fi

# ── Verify session is alive ──────────────────────────────────────────────────

if ! tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
  echo "Error: session '$TMUX_NAME' is not running." >&2
  exit 1
fi

# ── Check that Claude is at the prompt (not mid-response) ────────────────────
# Capture the last few lines of the pane. If Claude is still generating,
# sending keys would queue behind the current response — which is fine,
# but we warn so the orchestrator knows.

PANE_TAIL=$(tmux capture-pane -t "$TMUX_NAME" -p -l 5 2>/dev/null || true)

if echo "$PANE_TAIL" | grep -q '^\s*>\s*$'; then
  # Prompt character visible — Claude is idle, good to send
  :
elif echo "$PANE_TAIL" | grep -qiE '(thinking|working|running)'; then
  echo "Warning: session may still be working. Message will queue." >&2
fi

# ── Send the tagged message via tmux ─────────────────────────────────────────
# The [openclaw] prefix tells on_stop.sh this came from the orchestrator,
# so it fires the openclaw agent callback when Claude finishes responding.
#
# We use tmux's send-keys with literal flag (-l) to avoid interpreting
# special characters in the message, then send Enter separately.

TAGGED_MESSAGE="[openclaw] ${MESSAGE}"

tmux send-keys -t "$TMUX_NAME" -l "$TAGGED_MESSAGE"
tmux send-keys -t "$TMUX_NAME" Enter

echo "Task sent to $TMUX_NAME"
