#!/usr/bin/env bash
# Start N Claude Code remote control sessions in parallel.
# Usage: start_sessions.sh [dir] [count] [--notify <channel> <target>]
#
# Example: start_sessions.sh /path/to/project 3 --notify discord my-channel

WORKDIR="${1:?Usage: start_sessions.sh <working-dir> <count> [--notify <channel> <target>]}"
COUNT="${2:-3}"
shift 2 2>/dev/null || true
EXTRA_ARGS=("$@")  # pass through --notify, --resume, etc.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Starting $COUNT sessions in parallel for: $WORKDIR"
echo ""

OUTDIR=$(mktemp -d)
PIDS=()

for i in $(seq 1 "$COUNT"); do
  OUTFILE="$OUTDIR/session_$i.txt"
  bash "$SCRIPT_DIR/start_session.sh" "$WORKDIR" "${EXTRA_ARGS[@]}" > "$OUTFILE" 2>&1 &
  PIDS+=($!)
done

# Wait for all to complete
for pid in "${PIDS[@]}"; do
  wait "$pid"
done

# Print all outputs in order
for i in $(seq 1 "$COUNT"); do
  cat "$OUTDIR/session_$i.txt"
  echo ""
done

rm -rf "$OUTDIR"
