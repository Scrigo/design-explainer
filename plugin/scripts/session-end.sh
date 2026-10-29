#!/usr/bin/env bash
# SessionEnd hook: stops the project's likeC4 server if one was started by design-explain.
# Fires for every project the plugin is enabled in, so it exits immediately when there is nothing to stop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

[[ -f "$ROOT/.design-explainer/run/server.pid" ]] || exit 0

"$SCRIPT_DIR/stop-server.sh" "$ROOT" >/dev/null
