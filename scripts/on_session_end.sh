#!/usr/bin/env bash
# Called by the SessionEnd hook when a Claude Code session terminates.
# Sends a notification and marks the registry entry dead.
#
# Usage: on_session_end.sh <channel> <target> <session-label> [state-dir]
#
# Designed to be called from .claude/settings.json SessionEnd hook.

CHANNEL="${1:?Missing channel (discord, telegram, etc.)}"
TARGET="${2:?Missing target}"
SESSION_LABEL="${3:?Missing session label}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Notify (generic reason — SessionEnd fires for any termination) (#16) ────
bash "$SCRIPT_DIR/notify.sh" "$CHANNEL" "$TARGET" "$SESSION_LABEL" stopped &

# ── Mark registry dead + capture UUID ────────────────────────────────────────
python3 "$SCRIPT_DIR/registry.py" mark-dead "$SESSION_LABEL"

wait
