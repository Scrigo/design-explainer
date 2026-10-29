#!/usr/bin/env bash
# Stops the project's likeC4 dev server started by ensure-server.sh.
# Usage: stop-server.sh [project-root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

de_set_paths "$(de_resolve_root "${1:-}")"

pid="$(cat "$DE_PIDFILE" 2>/dev/null || true)"
if ! de_pid_alive "$pid"; then
  rm -f "$DE_PIDFILE"
  echo "status: not-running"
  exit 0
fi

# Kill the whole process group (npx + node children); fall back to the single pid.
kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
for _ in $(seq 1 25); do
  de_pid_alive "$pid" || break
  sleep 0.2
done
if de_pid_alive "$pid"; then
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
fi

rm -f "$DE_PIDFILE"
echo "status: stopped"
