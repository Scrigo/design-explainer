# shellcheck shell=bash
# Sourced by the other scripts. Single place for the likeC4 version and workspace layout.

LIKEC4_VERSION="1.60.0"
PORT_BASE=61000
PORT_RANGE=1000

# Project root: explicit argument, else git toplevel, else current directory.
de_resolve_root() {
  local root="${1:-}"
  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  (cd "$root" && pwd)
}

de_set_paths() {
  DE_ROOT="$1"
  DE_WS="$DE_ROOT/.design-explainer"
  DE_MODEL="$DE_WS/model"
  DE_RUN="$DE_WS/run"
  DE_PIDFILE="$DE_RUN/server.pid"
  DE_PORTFILE="$DE_RUN/server.port"
  DE_LOGFILE="$DE_RUN/server.log"
}

de_likec4() {
  npx -y "likec4@${LIKEC4_VERSION}" "$@"
}

de_port_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

de_pid_alive() {
  [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null
}

# Deterministic per-project port so several projects can run servers side by side.
de_default_port() {
  local hash
  hash="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  echo $((PORT_BASE + hash % PORT_RANGE))
}
