---
name: claude-remote-control
description: Start a Claude Code remote control session in tmux with bypass permissions. Use when asked to start a remote session, start a Claude Code session, spin up Claude Code, or any variation of starting Claude Code remotely for a project. Multiple sessions can run simultaneously.
metadata:
  {"openclaw": {"requires": {"bins": ["tmux", "python3", "claude", "openclaw"]}}}
---

# Claude Code Remote Control

Starts a persistent Claude Code session in tmux with `--dangerously-skip-permissions --remote-control`. Auto-exits after 30 minutes of inactivity via `CLAUDE_CODE_EXIT_AFTER_STOP_DELAY` (Claude's native idle timer). Multiple concurrent sessions supported — each gets a unique animal name.

## Starting a Session

**Single session:**
```bash
bash skills/claude-remote-control/scripts/start_session.sh <dir>
```

**With notifications (pings when idle or session ends):**
```bash
bash skills/claude-remote-control/scripts/start_session.sh <dir> --notify <channel> <target>
# e.g. start_session.sh /path/to/project --notify discord my-channel
#      start_session.sh /path/to/project --notify telegram @mygroup
#      start_session.sh /path/to/project --notify slack "#alerts"
```

**Multiple sessions in parallel (faster):**
```bash
bash skills/claude-remote-control/scripts/start_sessions.sh <dir> <count> [--notify <channel> <target>]
# e.g. start_sessions.sh /path/to/project 3 --notify discord my-channel
```

Each session gets a friendly name like `🦊 Fox | my-project` — used in tmux and the registry.

## Listing Sessions

```bash
bash skills/claude-remote-control/scripts/list_sessions.sh
```

Registry stored at `~/.local/share/claude-rc/sessions.json`.

## Attaching to a Session

```bash
tmux attach -t cc-fox-my-project   # use tmux name shown on start
```

## Killing a Session

```bash
tmux kill-session -t <tmux-name>
```

The `SessionEnd` hook fires (notifying via `--notify` channel if configured) and marks the registry entry `dead` with UUID capture.

## Resuming a Session by UUID

When a session dies (killed or idle timeout), the registry entry is marked `dead` and the local UUID is captured at that moment. UUIDs persist for 30 days before being pruned.

Look up the UUID:
```bash
cat ~/.local/share/claude-rc/sessions.json
```

Resume in a new tmux session (`<dirbase>` is the basename, e.g. `my-project`, not the full path):
```bash
tmux new-session -d -s "cc-<animal>-<dirbase>" -c "/full/path/to/project"
tmux send-keys -t "cc-<animal>-<dirbase>" 'claude -r "<uuid>" --dangerously-skip-permissions --remote-control --name "<animal> | <dirbase>"' Enter
# e.g.: tmux new-session -d -s "cc-fox-my-project" -c "/path/to/project"
#        tmux send-keys -t "cc-fox-my-project" 'claude -r "abc123..." --dangerously-skip-permissions --remote-control --name "Fox | my-project"' Enter
```

This restores full conversation history. A new remote control URL is issued on reconnect.

## Notifications (Ping When Done)

Pass `--notify <channel> <target>` to get pinged when a session goes idle or ends. Works with any openclaw-supported channel (discord, telegram, slack, etc.). Uses Claude Code's native hook system — no cron jobs or tmux polling.

Two hooks are installed into `<project-dir>/.claude/settings.json`:
- **`Notification` (idle_prompt)** — fires instantly when Claude finishes its task and is waiting for input. Calls `notify.sh`.
- **`SessionEnd`** — fires once when the session terminates (idle timeout, manual kill, or exit). Calls `on_session_end.sh` which both notifies AND marks the registry entry dead with UUID capture.

**Install hooks manually (without starting a session):**
```bash
bash skills/claude-remote-control/scripts/install_hooks.sh <project-dir> <channel> <target>
# e.g. install_hooks.sh /path/to/project discord my-channel
```

**Send a notification manually:**
```bash
bash skills/claude-remote-control/scripts/notify.sh discord "my-channel" "🦊 Fox | my-project" idle
bash skills/claude-remote-control/scripts/notify.sh telegram "@mygroup" "🦊 Fox | my-project" stopped "idle timeout"
```

## How Idle Timeout Works

1. `CLAUDE_CODE_EXIT_AFTER_STOP_DELAY=1800000` (30m) is set as an env var when launching Claude in tmux.
2. Claude's internal timer starts when it finishes responding and is idle at the prompt.
3. After 30m idle, Claude auto-exits — triggering the `SessionEnd` hook.
4. `on_session_end.sh` fires: posts via `notify.sh` and marks the registry dead with UUID.

No background watcher process — everything is driven by Claude Code's native hooks.

The `Notification` (idle_prompt) hook fires earlier — the moment Claude goes idle — for an immediate "task done" ping. The `SessionEnd` hook fires later when the session actually terminates.

## Notes

- `--remote-control` is undocumented but valid — activates remote control on startup
- Session URL looks like `https://claude.ai/code/session_...` — report this to the user
- The `session_0...` URL is a cloud-side remote control ID — it cannot be used with `claude -r`. Only the local UUID from the registry works for resuming.
- UUID is captured lazily when the session dies, not during startup — no background polling
- Dead entries auto-prune after 30 days (runs at each startup)
- The project dir formula: `~/.claude/projects/$(echo $WORKDIR | sed 's|/|-|g')` (leading `-` is kept)
- No background watcher — idle timeout and registry cleanup are handled entirely by Claude Code hooks
- Workspace trust is pre-seeded in `~/.claude.json` (under `projects[<path>].hasTrustDialogAccepted`) so headless sessions skip the "do you trust this folder?" dialog