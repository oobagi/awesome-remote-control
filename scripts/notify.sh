#!/usr/bin/env bash
# Send a notification when a Claude Code remote session changes state.
# Works with any openclaw-supported channel (discord, telegram, slack, etc.).
#
# Usage: notify.sh <channel> <target> <session-label> <event> [detail]
#
# Events: idle, stopped, error
#
# Examples:
#   notify.sh discord "my-channel" "🦊 Fox | my-project" idle
#   notify.sh telegram "@mygroup" "🦊 Fox | my-project" stopped "idle timeout (30m)"
#   notify.sh slack "#alerts" "🦊 Fox | my-project" error "hook failure"

CHANNEL="${1:?Usage: notify.sh <channel> <target> <session-label> <event> [detail]}"
TARGET="${2:?Missing target}"
SESSION_LABEL="${3:?Missing session label}"
EVENT="${4:?Missing event (idle|stopped|error)}"
DETAIL="${5:-}"

case "$EVENT" in
  idle)
    EMOJI="🔔"
    MSG="**$SESSION_LABEL** is idle — waiting for input."
    ;;
  stopped)
    EMOJI="🛑"
    MSG="**$SESSION_LABEL** session ended."
    [[ -n "$DETAIL" ]] && MSG="$MSG Reason: $DETAIL"
    ;;
  error)
    EMOJI="❌"
    MSG="**$SESSION_LABEL** hit an error."
    [[ -n "$DETAIL" ]] && MSG="$MSG $DETAIL"
    ;;
  *)
    EMOJI="📡"
    MSG="**$SESSION_LABEL** — $EVENT"
    [[ -n "$DETAIL" ]] && MSG="$MSG $DETAIL"
    ;;
esac

# Send notification with fallback stderr warning (#19)
if ! openclaw message send \
  --channel "$CHANNEL" \
  --target "$TARGET" \
  --message "$EMOJI $MSG" 2>&1; then
  echo "Warning: failed to send notification via $CHANNEL to $TARGET" >&2
fi
