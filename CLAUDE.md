# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

MVP implemented as the plugin in `plugin/` (scripts, hook and the full show workflow verified end-to-end on a test project). Full design, implementation notes and rationale live in [docs/architecture.md](docs/architecture.md); this file holds only a summary. Keep both in sync as decisions evolve.

## Commands

- Install from this repo (it is also the marketplace): `claude plugin marketplace add <path-to-this-repo>` then `claude plugin install design-explain@design-explainer`. Installed from a local path, the plugin is read live — apply edits with `/reload-plugins`.
- Run without installing: `claude --plugin-dir ./plugin`
- Validate manifests: `claude plugin validate ./plugin` and `claude plugin validate .` (missing README/LICENSE/icon warnings only matter for submission to Anthropic's directory).
- Scripts (each takes an optional target project root): `plugin/scripts/{init-workspace,validate,ensure-server,stop-server,session-end}.sh`
- likeC4 version is pinned only in `plugin/scripts/common.sh` (`LIKEC4_VERSION`); after bumping it, re-check the DSL reference in `plugin/skills/show/SKILL.md` with `validate.sh` on a sample model.
- There is no automated test suite. The show workflow is tested manually end-to-end per docs/testing.md; scripts are tested manually against a throwaway git repo in a scratch directory (init → write model → validate → ensure-server twice → curl → stop; hook: `CLAUDE_PROJECT_DIR=<repo> plugin/scripts/session-end.sh`).

## Vision

`design-explainer` gives a software architect oversight over code produced by AI agents. It is invoked *from other projects*: it analyzes the target project's codebase, builds a C4 model (Context, Container, Component — deliberately not the Code level), and renders it as an interactive diagram where selecting an element shows its role and connections.

## What this repo is

A **Claude Code plugin** (`design-explain`) plus a local marketplace (`design-explainer`), not an application:
- `/design-explain:show` — `plugin/skills/show/SKILL.md`, the extraction workflow for the agent; scripts are referenced via `${CLAUDE_PLUGIN_ROOT}/scripts/`.
- `/design-explain:stop` — stops the likeC4 viewer.
- `SessionEnd` hook (`plugin/hooks/hooks.json`) — stops the viewer when the session ends, but not on `/clear` or `/resume`.

The extraction "engine" is Claude Code's own agentic loop; rendering is [likeC4](https://likec4.dev). Runtime prerequisite: Node.js with `npx`.

## Key decisions (summary)

- **Extraction**: LLM-based (language-agnostic), done by the agent itself following the skill's instructions. Every relationship must carry `evidence` (file:line); no evidence → not in the model. Relationships are runtime (default) or `code-dependency` (dotted; type/model imports without calls), so cycles are visible. Elements get stable path-derived IDs with the original path in `sourcePath` metadata.
- **Mapping convention**: System = repo; Context = external systems/actors; Container = deployable unit (plus owned DBs/queues); Component = cohesive internal module, using per-ecosystem hints (Go, Java, Python, Node) rather than "top-level folder".
- **Rendering**: likeC4 (local-first, auto layout, interactive viewer, hot-reload dev server).
- **Server lifecycle**: `show` idempotently ensures a **detached** (`setsid nohup`) likeC4 server with a per-project port and pidfile; stopped by the stop skill or the session-end hook.
- **Storage & git**: the model is committed in the target repo; runtime state is gitignored. "What changed" = `git diff` of the model; history = `git log`.
- **Not in the MVP**: likeC4 MCP server (can't be bootstrapped mid-session) and its Agent Skill; subagent fan-out; incremental runs; architecture-rules conformance checking (the main long-term direction).
- **No manual model override**: architect feedback becomes real code changes; the next run picks them up. Categorization disagreements go into optional mapping hints in `.design-explainer/config.yaml`.

Target-repo workspace: `.design-explainer/` with `model/{spec,model,views}.c4`, `config.yaml`, `state.json` (committed) and `run/` (pidfile/port/log, gitignored). End-to-end test: test app in `examples/bookshop/` (+ `examples/bookshop-invoicing.patch` for step 2); setup, expected model, scenario and results in docs/testing.md. Always run it on a copy outside this repo, and never put docs/testing.md (or hints from it) into the copy: the agent under test would read it during recon.

## Working on this repo

- The likeC4 DSL is the contract between extraction (the skill's workflow) and rendering (likeC4) — keep these concerns separate.
- The session-end hook fires in every project where the plugin is enabled and has a short time budget: keep `session-end.sh` a no-op unless a design-explain pidfile exists, and keep it fast.
- When implementation decisions get made, record them in docs/architecture.md and keep this summary short.
