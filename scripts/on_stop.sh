#!/usr/bin/env bash
# Stop hook handler — fires when Claude Code finishes a response.
# Only triggers the OpenClaw callback if the last user message was
# tagged with [openclaw], meaning it came from OpenClaw (not a user
# chatting directly via remote control).
#
# Called by Claude Code's hook runner with JSON on stdin.

OC_SESSION_KEY="${1:?Missing OpenClaw session key}"
CHANNEL="${2:?Missing channel}"
TARGET="${3:?Missing target}"
SESSION_LABEL="${4:?Missing session label}"

# Read hook stdin
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# Find the last user message (plain text, not tool results) and check for [openclaw] tag
TAGGED=$(tac "$TRANSCRIPT" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
    except:
        continue
    if entry.get('type') == 'user':
        content = entry.get('message', {}).get('content', '')
        if isinstance(content, str) and content.strip().startswith('[openclaw]'):
            print('yes')
        break
" 2>/dev/null)

if [[ "$TAGGED" != "yes" ]]; then
  exit 0
fi

# Tagged message — trigger OpenClaw callback
exec openclaw agent \
  --session-id "$OC_SESSION_KEY" \
  --message "The Claude Code remote session $SESSION_LABEL just finished responding. Let the user know briefly and ask if they want to review or give it another task. Do not include HEARTBEAT_OK in your reply." \
  --deliver \
  --channel "$CHANNEL" \
  --reply-to "$TARGET" \
  --thinking off \
  --timeout 30
