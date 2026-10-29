#!/usr/bin/env bash
# Creates the .design-explainer/ workspace if missing and prints its current state.
# Usage: init-workspace.sh [project-root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/../templates"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

de_set_paths "$(de_resolve_root "${1:-}")"

mkdir -p "$DE_MODEL" "$DE_RUN"
[[ -f "$DE_WS/.gitignore" ]] || printf 'run/\n' > "$DE_WS/.gitignore"
[[ -f "$DE_WS/config.yaml" ]] || cp "$TEMPLATES/config.yaml" "$DE_WS/config.yaml"
# spec.c4 is owned by the plugin: keep it in sync with the template.
spec_status="unchanged"
if [[ ! -f "$DE_MODEL/spec.c4" ]]; then
  spec_status="created"
elif ! cmp -s "$TEMPLATES/spec.c4" "$DE_MODEL/spec.c4"; then
  spec_status="updated from plugin template"
fi
[[ "$spec_status" == "unchanged" ]] || cp "$TEMPLATES/spec.c4" "$DE_MODEL/spec.c4"

echo "project_root: $DE_ROOT"
echo "workspace: $DE_WS"
echo "model_dir: $DE_MODEL"
echo "spec.c4: $spec_status"

if git -C "$DE_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "git: yes"
  echo "head_commit: $(git -C "$DE_ROOT" rev-parse HEAD 2>/dev/null || echo none)"
  # Uncommitted code changes (the workspace itself doesn't count: the model is dirty after every run).
  if [[ -n "$(git -C "$DE_ROOT" status --porcelain -- . ':!.design-explainer' 2>/dev/null)" ]]; then
    echo "working_tree_dirty: yes"
  else
    echo "working_tree_dirty: no"
  fi
else
  echo "git: no"
fi

if [[ -f "$DE_WS/state.json" ]]; then
  echo "state.json:"
  sed 's/^/  /' "$DE_WS/state.json"
  last="$(sed -n 's/.*"lastAnalyzedCommit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DE_WS/state.json")"
  if [[ -n "$last" ]] && git -C "$DE_ROOT" cat-file -e "$last^{commit}" 2>/dev/null; then
    echo "files_changed_since_last_analysis:"
    { git -C "$DE_ROOT" diff --name-only "$last" -- . ':!.design-explainer'
      git -C "$DE_ROOT" ls-files --others --exclude-standard -- . ':!.design-explainer'; } | sort -u | sed 's/^/  /'
  fi
else
  echo "state.json: none (first run)"
fi

echo "model_files:"
for f in "$DE_MODEL"/*.c4 "$DE_MODEL"/*.likec4; do
  [[ -f "$f" ]] && echo "  $(basename "$f")"
done
