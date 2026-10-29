#!/usr/bin/env bash
# Validates the model with the pinned likeC4 version. Exit code 0 = valid, non-zero = errors.
# Usage: validate.sh [project-root]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

de_set_paths "$(de_resolve_root "${1:-}")"

out="$(de_likec4 validate "$DE_MODEL" 2>&1)"
code=$?
printf '%s\n' "$out" | grep -v -E '^npm (warn|notice)'
exit "$code"
