#!/usr/bin/env bash
# Start a Claude Code remote control session in tmux with bypass permissions.
# Supports multiple concurrent sessions — each gets a friendly animal name.
#
# Usage: start_session.sh <working-dir> [--resume] [--notify <channel> <target>]

WORKDIR="${1:?Usage: start_session.sh <working-dir> [--resume] [--notify <channel> <target>]}"
RESUME=""
NOTIFY_CHANNEL=""
NOTIFY_TARGET=""

shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume)  RESUME="--resume"; shift ;;
    --notify)  NOTIFY_CHANNEL="$2"; NOTIFY_TARGET="$3"; shift 3 ;;
    *)         shift ;;
  esac
done
IDLE_TIMEOUT=1800  # 30 minutes in seconds
STATE_DIR="$HOME/.local/share/claude-rc"
REGISTRY="$STATE_DIR/sessions.json"
REGISTRY_LOCK="$STATE_DIR/sessions.lock"
NAME_LOCK="$STATE_DIR/name.lock"

mkdir -p "$STATE_DIR"

# ── Animal name generator ────────────────────────────────────────────────────

ANIMALS=(
  "🦊 Fox" "🐻 Bear" "🐼 Panda" "🐨 Koala" "🦁 Lion"
  "🐯 Tiger" "🐺 Wolf" "🦝 Raccoon" "🦦 Otter" "🦔 Hedgehog"
  "🐸 Frog" "🦋 Moth" "🐙 Octopus" "🦈 Shark" "🐊 Croc"
  "🦜 Parrot" "🦚 Peacock" "🦩 Flamingo" "🦉 Owl" "🐧 Penguin"
  "🦭 Seal" "🦬 Bison" "🦌 Deer" "🐐 Goat" "🦘 Kangaroo"
  "🐘 Elephant" "🦏 Rhino" "🦛 Hippo" "🐪 Camel" "🦒 Giraffe"
)

pick_animal() {
  echo "${ANIMALS[$((RANDOM % ${#ANIMALS[@]}))]}"
}

# ── Registry helpers ─────────────────────────────────────────────────────────

registry_add() {
  local name="$1" url="$2" dir="$3" local_uuid="$4"
  [[ ! -f "$REGISTRY" ]] && echo '{}' > "$REGISTRY"
  (
    flock 9
    RC_REGISTRY="$REGISTRY" RC_NAME="$name" RC_URL="$url" \
    RC_DIR="$dir" RC_UUID="$local_uuid" \
    python3 - <<'PYEOF'
import json, time, os
reg = os.environ["RC_REGISTRY"]
try:
    r = json.load(open(reg))
except Exception:
    r = {}
r[os.environ["RC_NAME"]] = {
    "url": os.environ["RC_URL"],
    "dir": os.environ["RC_DIR"],
    "local_uuid": os.environ["RC_UUID"],
    "status": "active",
    "started_at": int(time.time()),
}
json.dump(r, open(reg, "w"), indent=2)
PYEOF
  ) 9>"$REGISTRY_LOCK"
}

registry_prune() {
  # Remove dead entries older than 30 days
  [[ ! -f "$REGISTRY" ]] && return
  (
    flock 9
    RC_REGISTRY="$REGISTRY" \
    python3 - <<'PYEOF'
import json, time, os
reg = os.environ["RC_REGISTRY"]
cutoff = int(time.time()) - 30 * 86400
try:
    r = json.load(open(reg))
except Exception:
    r = {}
r = {k: v for k, v in r.items() if not (v.get("status") == "dead" and v.get("stopped_at", 0) < cutoff)}
json.dump(r, open(reg, "w"), indent=2)
PYEOF
  ) 9>"$REGISTRY_LOCK"
}

# ── Prune stale entries on startup ───────────────────────────────────────────
registry_prune

# ── Pre-trust workspace (skip "do you trust this folder?" dialog) ────────────
# Claude Code stores trust state in ~/.claude.json under projects[<path>].
# Pre-seeding this lets headless sessions start without manual confirmation.
CLAUDE_CONFIG="$HOME/.claude.json"
RC_CONFIG="$CLAUDE_CONFIG" RC_WORKDIR="$WORKDIR" \
python3 - <<'PYEOF'
import json, os
config_path = os.environ["RC_CONFIG"]
workdir = os.environ["RC_WORKDIR"]
try:
    config = json.load(open(config_path))
except (FileNotFoundError, json.JSONDecodeError):
    config = {}
projects = config.setdefault("projects", {})
proj = projects.setdefault(workdir, {})
if not proj.get("hasTrustDialogAccepted"):
    proj["hasTrustDialogAccepted"] = True
    json.dump(config, open(config_path, "w"), indent=2)
PYEOF

# ── Install notification hooks (if --notify was given) ───────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$NOTIFY_CHANNEL" ]]; then
  bash "$SCRIPT_DIR/install_hooks.sh" "$WORKDIR" "$NOTIFY_CHANNEL" "$NOTIFY_TARGET"
fi

# ── Derive dir basename ───────────────────────────────────────────────────────

DIRBASE=$(basename "$WORKDIR")

# ── Pick a unique animal name + create tmux (locked for parallel safety) ─────

(
  flock 8

  while true; do
    ANIMAL=$(pick_animal)
    ANIMAL_SLUG=$(echo "$ANIMAL" | sed 's/[^ ]* //' | tr '[:upper:]' '[:lower:]')
    SESSION_LABEL="$ANIMAL | $DIRBASE"
    TMUX_NAME="cc-$ANIMAL_SLUG-$DIRBASE"
    TMUX_NAME=$(echo "$TMUX_NAME" | tr ' ' '-' | tr -cd '[:alnum:]-')
    if ! tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
      break
    fi
  done

  # Create tmux session while still holding the lock — prevents another
  # process from picking the same name before the session exists.
  tmux new-session -d -s "$TMUX_NAME" -c "$WORKDIR"

  # Export chosen names for the outer shell
  echo "$ANIMAL" > "$STATE_DIR/.name_$$"
  echo "$ANIMAL_SLUG" >> "$STATE_DIR/.name_$$"
  echo "$SESSION_LABEL" >> "$STATE_DIR/.name_$$"
  echo "$TMUX_NAME" >> "$STATE_DIR/.name_$$"

) 8>"$NAME_LOCK"

# Read back the names chosen under lock
{
  read -r ANIMAL
  read -r ANIMAL_SLUG
  read -r SESSION_LABEL
  read -r TMUX_NAME
} < "$STATE_DIR/.name_$$"
rm -f "$STATE_DIR/.name_$$"

echo "Starting session: $SESSION_LABEL  (tmux: $TMUX_NAME)"

# ── Start claude in tmux ─────────────────────────────────────────────────────
# CLAUDE_CODE_EXIT_AFTER_STOP_DELAY makes Claude auto-exit after being idle at
# the prompt for IDLE_TIMEOUT. This is the primary idle-kill mechanism — Claude
# handles the timer internally and fires SessionEnd on exit (which triggers
# on_session_end.sh for Discord notification + registry update).

IDLE_DELAY_MS=$((IDLE_TIMEOUT * 1000))

CLAUDE_ARGS="--dangerously-skip-permissions --remote-control --name \"$SESSION_LABEL\""
if [[ "$RESUME" == "--resume" ]]; then
  CLAUDE_ARGS="--continue $CLAUDE_ARGS"
fi

CMD="CLAUDE_CODE_EXIT_AFTER_STOP_DELAY=$IDLE_DELAY_MS claude $CLAUDE_ARGS"

tmux send-keys -t "$TMUX_NAME" "$CMD" Enter

# ── Capture URL ───────────────────────────────────────────────────────────────
# URL appears in tmux pane within ~2-3s (Claude Code prints it immediately).
# UUID is captured by on_session_end.sh when the session dies (SessionEnd hook).

URL=""

for i in {1..15}; do
  sleep 1
  PANE_URL=$(tmux capture-pane -t "$TMUX_NAME" -p 2>/dev/null | grep -o 'https://claude\.ai/code/session_[A-Za-z0-9]*' | tail -1)
  if [[ -n "$PANE_URL" ]]; then
    URL="$PANE_URL"
    break
  fi
done

# Register session (UUID filled in by on_session_end.sh when session stops)
registry_add "$SESSION_LABEL" "${URL:-}" "$WORKDIR" ""

echo ""
echo "✅ $SESSION_LABEL"
echo "   URL:        ${URL:-<not captured yet>}"
echo "   local UUID: <capturing in background>"
echo "   resume:     claude -r \"<uuid>\" --dangerously-skip-permissions --remote-control"
echo "   tmux:       tmux attach -t $TMUX_NAME"
echo "   State:      $REGISTRY"
[[ -n "$NOTIFY_CHANNEL" ]] && echo "   notify:     $NOTIFY_CHANNEL → $NOTIFY_TARGET"
echo "   Auto-closes after 30m idle."
