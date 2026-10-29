#!/usr/bin/env bash
# Idempotently ensures a likeC4 dev server is running for the project and prints its URL.
# The server is detached from the calling session, so it survives the end of the Claude Code session.
# Usage: ensure-server.sh [project-root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

STARTUP_TIMEOUT=120

de_set_paths "$(de_resolve_root "${1:-}")"
mkdir -p "$DE_RUN"

wait_for_port() {
  local pid="$1" port="$2" waited=0
  while ! de_port_open "$port"; do
    if ! de_pid_alive "$pid"; then
      echo "error: likeC4 server exited during startup; log tail:" >&2
      tail -n 30 "$DE_LOGFILE" >&2 || true
      return 1
    fi
    if (( waited >= STARTUP_TIMEOUT )); then
      echo "error: likeC4 server did not open port $port within ${STARTUP_TIMEOUT}s; see $DE_LOGFILE" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

pid="$(cat "$DE_PIDFILE" 2>/dev/null || true)"
port="$(cat "$DE_PORTFILE" 2>/dev/null || true)"

if de_pid_alive "$pid" && [[ -n "$port" ]]; then
  wait_for_port "$pid" "$port"
  echo "status: already-running"
  echo "url: http://localhost:$port/"
  exit 0
fi

rm -f "$DE_PIDFILE"

[[ -n "$port" ]] || port="$(de_default_port "$DE_ROOT")"
attempts=0
while de_port_open "$port"; do
  port=$((port + 1))
  attempts=$((attempts + 1))
  if (( attempts > 50 )); then
    echo "error: no free port found near $(de_default_port "$DE_ROOT")" >&2
    exit 1
  fi
done

title="$(basename "$DE_ROOT") architecture"
launcher=()
if command -v setsid >/dev/null 2>&1; then
  launcher=(setsid)
fi

# setsid makes the server its own process group leader, so stop-server.sh can kill npx and its children together.
"${launcher[@]}" nohup npx -y "likec4@${LIKEC4_VERSION}" serve "$DE_MODEL" \
  --listen 127.0.0.1 --port "$port" --title "$title" \
  >"$DE_LOGFILE" 2>&1 </dev/null &
pid=$!
echo "$pid" >"$DE_PIDFILE"
echo "$port" >"$DE_PORTFILE"

wait_for_port "$pid" "$port"
echo "status: started"
echo "url: http://localhost:$port/"
