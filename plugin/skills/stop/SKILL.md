---
description: Stop the likeC4 architecture viewer (dev server) started by design-explain for the current project. Use when the user asks to stop, close or shut down the architecture diagram viewer, or calls /design-explain:stop.
---

# design-explain:stop

Run `${CLAUDE_PLUGIN_ROOT}/scripts/stop-server.sh` (optionally with the project root as the argument) and report the printed status in one sentence:
- `status: stopped` — the viewer was running and is now stopped;
- `status: not-running` — nothing was running for this project.

Do nothing else. The viewer is also stopped automatically when the Claude Code session ends (but not on `/clear` or `/resume`); the next `/design-explain:show` starts it again.
