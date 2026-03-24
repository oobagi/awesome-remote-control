#!/usr/bin/env bash
# Install Claude Code hooks for ping-when-done notifications.
#
# Writes Notification (idle_prompt) and SessionEnd hooks into
# the project-level .claude/settings.json so that remote sessions
# notify a channel when they go idle or end.
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
import json, os

import re, sys

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
    settings = json.load(open(settings_path))
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

hooks = settings.setdefault("hooks", {})

# Notification hook — fires when Claude goes idle (waiting for input)
hooks["Notification"] = [
    {
        "matcher": "idle_prompt",
        "hooks": [
            {
                "type": "command",
                "command": f'bash {notify_script} {channel} "{target}" "$CLAUDE_SESSION_NAME" idle',
                "timeout": 15,
            }
        ],
    }
]

# SessionEnd hook — fires once when the session terminates.
# Calls on_session_end.sh which both notifies and marks the registry dead.
hooks["SessionEnd"] = [
    {
        "hooks": [
            {
                "type": "command",
                "command": f'bash {session_end_script} {channel} "{target}" "$CLAUDE_SESSION_NAME"',
                "timeout": 30,
            }
        ],
    }
]

json.dump(settings, open(settings_path, "w"), indent=2)
print(f"Hooks installed in {settings_path}")
print(f"  Notification (idle_prompt) -> {channel}:{target}")
print(f"  SessionEnd                 -> {channel}:{target} (+ registry update)")
PYEOF
