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
STATE_DIR="${4:-$HOME/.local/share/claude-rc}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$STATE_DIR/sessions.json"
REGISTRY_LOCK="$STATE_DIR/sessions.lock"

# ── Notify ───────────────────────────────────────────────────────────────────
bash "$SCRIPT_DIR/notify.sh" "$CHANNEL" "$TARGET" "$SESSION_LABEL" stopped "idle timeout (30m)" &

# ── Mark registry dead + capture UUID ────────────────────────────────────────
if [[ -f "$REGISTRY" ]]; then
  (
    flock 9
    RC_REGISTRY="$REGISTRY" RC_NAME="$SESSION_LABEL" \
    python3 - <<'PYEOF'
import json, time, glob, os
reg = os.environ["RC_REGISTRY"]
name = os.environ["RC_NAME"]
try:
    r = json.load(open(reg))
except Exception:
    r = {}
if name in r:
    entry = r[name]
    entry["status"] = "dead"
    entry["stopped_at"] = int(time.time())
    if not entry.get("local_uuid"):
        proj_dir = os.path.expanduser("~/.claude/projects/" + entry["dir"].replace("/", "-"))
        started_at = entry.get("started_at", 0)
        files = [f for f in glob.glob(proj_dir + "/*.jsonl") if os.path.getmtime(f) > started_at]
        if files:
            entry["local_uuid"] = os.path.basename(sorted(files, key=os.path.getmtime)[-1]).replace(".jsonl", "")
    json.dump(r, open(reg, "w"), indent=2)
PYEOF
  ) 9>"$REGISTRY_LOCK"
fi

wait
