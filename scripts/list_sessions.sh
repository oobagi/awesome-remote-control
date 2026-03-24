#!/usr/bin/env bash
# List all Claude Code remote control sessions.

REGISTRY="$HOME/.local/share/claude-rc/sessions.json"

if [[ ! -f "$REGISTRY" ]]; then
  echo "No sessions registry found."
  exit 0
fi

python3 - "$REGISTRY" <<'PYEOF'
import json, sys, subprocess

registry_path = sys.argv[1]

try:
    r = json.load(open(registry_path))
except Exception:
    r = {}

if not r:
    print("No sessions.")
    sys.exit()

for name, v in r.items():
    # Derive tmux session name the same way start_session.sh does
    emoji_and_animal = name.split(" | ")[0].strip()
    # Strip the emoji prefix: "🦊 Fox" -> "Fox" -> "fox"
    animal_slug = emoji_and_animal.split(None, 1)[-1].lower() if " " in emoji_and_animal else emoji_and_animal.lower()
    dirbase = name.split(" | ")[-1].strip()
    tmux_name = f"cc-{animal_slug}-{dirbase}"
    # Sanitize the same way the script does (tr -cd '[:alnum:]-')
    tmux_name = "".join(c for c in tmux_name if c.isalnum() or c == "-")

    # Check if the tmux session is actually alive
    tmux_alive = subprocess.run(
        ["tmux", "has-session", "-t", tmux_name],
        capture_output=True
    ).returncode == 0

    registry_status = v.get("status", "unknown")

    if tmux_alive:
        status = "\U0001f7e2"  # green
    elif registry_status == "dead":
        status = "\U0001f534"  # red
    else:
        status = "\U0001f7e1"  # yellow — registry says active but tmux is gone

    print(f"{status} {name}  (tmux: {tmux_name})")
    print(f"   dir:    {v.get('dir', '?')}")
    print(f"   url:    {v.get('url', '?')}")
    if registry_status == "dead":
        uuid = v.get("local_uuid", "")
        if uuid:
            print(f"   uuid:   {uuid}")
            print(f"   resume: claude -r \"{uuid}\" --dangerously-skip-permissions --remote-control")
        else:
            print(f"   uuid:   (not captured)")
    print()
PYEOF
