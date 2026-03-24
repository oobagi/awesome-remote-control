#!/usr/bin/env bash
# Install Claude Code hooks for ping-when-done notifications.
#
# Merges Notification (idle_prompt) and SessionEnd hooks into
# the project-level .claude/settings.json.  Existing hooks that
# are not related to remote-control are preserved (#13).
#
# Usage: install_hooks.sh <project-dir> <channel> <target>
#
# Examples:
#   install_hooks.sh /path/to/project discord my-channel
#   install_hooks.sh /path/to/project telegram @mygroup

WORKDIR="${1:?Usage: install_hooks.sh <project-dir> <channel> <target>}"
CHANNEL="${2:?Missing channel (discord, telegram, slack, etc.)}"
TARGET="${3:?Missing target (channel name, chat id, etc.)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
SESSION_END_SCRIPT="$SCRIPT_DIR/on_session_end.sh"
SETTINGS_DIR="$WORKDIR/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

mkdir -p "$SETTINGS_DIR"

# Merge hooks into existing settings (or create new)
RC_SETTINGS="$SETTINGS_FILE" RC_NOTIFY="$NOTIFY_SCRIPT" \
RC_SESSION_END="$SESSION_END_SCRIPT" RC_CHANNEL="$CHANNEL" RC_TARGET="$TARGET" \
python3 - <<'PYEOF'
import json, os, re, sys

settings_path = os.environ["RC_SETTINGS"]
notify_script = os.environ["RC_NOTIFY"]
session_end_script = os.environ["RC_SESSION_END"]
channel = os.environ["RC_CHANNEL"]
target = os.environ["RC_TARGET"]

# Sanitize channel and target to prevent command injection.
# These get embedded in shell commands executed by Claude's hook runner.
SAFE = re.compile(r'^[a-zA-Z0-9@#._:/-]+$')
if not SAFE.match(channel):
    print(f"Error: channel contains unsafe characters: {channel!r}", file=sys.stderr)
    sys.exit(1)
if not SAFE.match(target):
    print(f"Error: target contains unsafe characters: {target!r}", file=sys.stderr)
    sys.exit(1)

try:
    with open(settings_path) as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}
except json.JSONDecodeError:
    print(f"Warning: corrupt {settings_path}, resetting", file=sys.stderr)
    settings = {}

hooks = settings.setdefault("hooks", {})

# ── Helper: merge a hook entry without clobbering unrelated hooks (#13) ──

def merge_hook(hook_type, marker_script, new_entry):
    """Replace any existing entry whose command references marker_script,
    preserving all other entries under the same hook type."""
    existing = hooks.get(hook_type, [])
    # Keep entries that are NOT from this skill
    kept = []
    for group in existing:
        filtered_hooks = [
            h for h in group.get("hooks", [])
            if marker_script not in h.get("command", "")
        ]
        if filtered_hooks:
            group["hooks"] = filtered_hooks
            kept.append(group)
    kept.append(new_entry)
    hooks[hook_type] = kept

# Use shell-safe quoting for CLAUDE_SESSION_NAME (#10).
# The variable is expanded by the hook runner's shell at execution time;
# wrapping it in double quotes prevents word-splitting on special chars.
notify_entry = {
    "matcher": "idle_prompt",
    "hooks": [
        {
            "type": "command",
            "command": (
                f'bash {notify_script} {channel} '
                f"'{target}' "
                f'"$CLAUDE_SESSION_NAME" idle'
            ),
            "timeout": 15,
        }
    ],
}

session_end_entry = {
    "hooks": [
        {
            "type": "command",
            "command": (
                f'bash {session_end_script} {channel} '
                f"'{target}' "
                f'"$CLAUDE_SESSION_NAME"'
            ),
            "timeout": 30,
        }
    ],
}

merge_hook("Notification", "notify.sh", notify_entry)
merge_hook("SessionEnd", "on_session_end.sh", session_end_entry)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print(f"Hooks installed in {settings_path}")
print(f"  Notification (idle_prompt) -> {channel}:{target}")
print(f"  SessionEnd                 -> {channel}:{target} (+ registry update)")
PYEOF
