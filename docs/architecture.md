# design-explainer — architecture

Living design document: decisions made so far, their rationale, MVP scope, and what's deferred. Keep it in sync with CLAUDE.md (which holds only a short summary) and with the code once it exists.

## Vision

`design-explainer` gives a software architect oversight over code produced by AI agents. It is invoked *from other projects*: on request, it analyzes the target project's codebase, builds a C4 model of its architecture, and renders it as an interactive diagram — selecting an element shows its role and its connections.

Target C4 levels: **Context, Container, Component**. We deliberately do **not** go down to the Code level (individual classes/files).

## What design-explainer actually is

Not an application — a **Claude Code plugin** named `design-explain`: two skills (`/design-explain:show` runs the extraction workflow, `/design-explain:stop` stops the viewer), a `SessionEnd` hook, and a few small scripts. The "engine" is Claude Code's own agentic loop; rendering is likeC4.

**Distribution**: a plugin, not a user-level skill. Originally the MVP was going to be a user-level skill (`~/.claude/skills/`) with the plugin deferred, but two requirements need the plugin now: the namespaced command `design-explain:stop` (a colon in a command name exists only as the `/<plugin>:<skill>` plugin namespace) and the session-end hook (plugin hooks register on install, with no edits to the user's `settings.json`). This repo is also the marketplace (`.claude-plugin/marketplace.json`, plugin under `plugin/`). Installed from the local directory, the plugin is read live: edits apply on `/reload-plugins` or the next session.

**Runtime prerequisites in the target environment**: Node.js with `npx` (to run `npx likec4`). Nothing has to be added to the target project's own dependencies.

## Decisions

### 1. Extraction: LLM-based, run by the agent itself

**LLM-based**, not static/AST analysis — target codebases can be in any language (Python, Java, Go, ...), and maintaining a parser per language isn't viable. Concretely this is **not a separate LLM pipeline**: the skill's instructions drive Claude Code's own tool use (reading files, grepping, optionally spawning subagents).

**Every relationship must carry evidence.** Relationships are the most valuable part of the diagram for an architect ("too many connections", "A must not call B") and also the part most exposed to LLM non-determinism and hallucination. In a tool meant to give control over AI agents, a wrong diagram is worse than none — it creates false confidence. Therefore:
- each relationship stores evidence in metadata, e.g. `evidence: "src/billing/client.py:42"` (an import, an HTTP call, a config entry, a queue topic);
- a relationship without evidence does not go into the model;
- evidence makes relationships verifiable (by the architect and by the agent during validation) and more stable across runs.

### 2. Model format & rendering: likeC4

**[likeC4](https://likec4.dev)**, rather than a custom format/viewer or IcePanel.

Why not IcePanel: it's a hosted SaaS — architecture data of potentially proprietary codebases would go to a third-party cloud; it's freemium with per-object limits; its strengths (collaborative manual editing, hosted sharing) matter for multi-stakeholder dashboards, not for an architect's local per-project tool. Can be revisited if that need appears.

**likeC4 covers 100% of "model → diagram" and 0% of "code → model"** — none of its CLI commands, MCP tools, or its Agent Skill analyze source code. Extraction is entirely ours.

What likeC4 gives out of the box:
- DSL (`.c4` / `.likec4`) for elements and relationships, a `specification` block for custom element/relationship kinds, tags, and free-form metadata;
- view types: context, container, component, deployment, dynamic;
- `likec4 serve` / `dev` — dev server with file watching and hot reload;
- interactive browser viewer — click an element to see description, technology, relationships, drill down into nested levels (covers the interactivity requirement, no custom frontend);
- automatic layout computed from the graph — so stable element IDs and relationships imply a stable layout;
- exports (PNG/JPG, JSON, drawio, mermaid/d2/plantuml/dot), static site `build`, React/Web Components embedding;
- TypeScript Model API; `validate` (syntax + layout drift).

likeC4 AI tooling — investigated, **not used in the MVP**:
- **Agent Skill `likec4-dsl`** (`npx skills add https://likec4.dev/`) — teaches DSL syntax. Optional helper; the MVP can rely on `likec4 validate` to catch syntax errors and fix them.
- **MCP server `@likec4/mcp`** (`claude mcp add likec4 -- npx -y @likec4/mcp`) — ~30 tools for querying an *existing* model. Not used in the MVP: an MCP server registered mid-session only becomes available in a new session, so the skill can't bootstrap it on first run, and it would be an extra setup step. Syntax validation is done via CLI; evidence checking is done by the agent itself.
  - `element-diff` — verified: pairwise comparison of two elements within a model, **not** a diff of the model over time. Not useful for regeneration.
  - `list-diffs` (DSL `diff` blocks) and `removal-impact` — not investigated; possible later building blocks for architecture history (see Deferred).

### 3. Invocation & server lifecycle

**One skill** (`design-explain`) does everything on an explicit call: runs the extraction workflow, writes the model, and ensures the likeC4 server is running. Splitting "init" from "generate" would force the user to remember an ordering; an idempotent check removes that.

Server handling:
- check a pidfile (and that the process is alive / the port answers); if no live server → start one, otherwise do nothing — likeC4's file watcher reloads the browser on its own;
- the server must be **detached from the Claude Code session** (`nohup` / `setsid`) — a process started via the Bash tool's background mode is tied to the session and would die with it;
- **port per project**, so multiple projects can have servers running at the same time;
- **stopping**: `/design-explain:stop` on demand, and automatically via a `SessionEnd` hook when the session ends — matcher `logout|prompt_input_exit|other`, so **not** on `/clear` or `/resume` (the user keeps working in the same terminal and likely still views the diagram). The next `/design-explain:show` starts the server again.
- known limitation: with two concurrent Claude Code sessions in the same project, ending one stops the server the other may still be looking at (the server is per project, not per session); the next `/design-explain:show` restarts it.

### 4. Storage & git

The generated model lives in the target repo and **is committed**; runtime state (pidfile, logs) is gitignored. Committing the model gives us, almost for free:
- **"what changed" report** = `git diff` of the model files;
- **architecture history over time** = `git log` of the model — covers most of what the deferred "diff blocks" idea was meant to give;
- **incremental regeneration** (post-MVP) — the model records the last analyzed commit hash, so the next run can re-analyze only containers with changes since then.

## Extraction workflow

What `/design-explain:show` instructs the agent to do:

1. **Load the previous model** (if any) and the last analyzed commit hash. The previous model is the reference point, not something to be discarded.
2. **Lightweight recon** before reading code: directory tree, manifests (`package.json`, `pyproject.toml`, `go.mod`, `pom.xml`/`build.gradle`), Dockerfiles / `docker-compose.yml`, README, config files. Cheap signals for language, frameworks, monorepo vs. single service, deployable units, external dependencies.
3. **Apply the mapping convention** (fixed rules, not re-invented each run):
   - **System** = the analyzed project/repo.
   - **Context level** = **external systems** (third-party APIs, managed services such as Stripe or S3, other systems — detected via SDK imports, client config, URLs, env vars) and **actors** (users / other systems calling in, where identifiable).
   - **Container** = independently deployable/runnable unit: distinct entrypoint, Dockerfile / compose service, deployable module; also databases, queues, caches the system owns.
   - **Component** = cohesive internal module within a container — **not** necessarily a top-level folder. Per-ecosystem starting hints (to be refined on real repos):
     - *Go*: `cmd/*` → containers; `internal/*`, `pkg/*` → components.
     - *Java/Kotlin*: deployable Maven/Gradle modules (e.g. a Spring Boot app) → containers; packages directly under the base package (`com/acme/billing`) → components.
     - *Python*: separately deployed services/apps → containers; subpackages of the main package (`src/<pkg>/*`) → components.
     - *Node/TS*: workspace packages with their own entrypoint → containers; feature/module directories under `src/` → components.
   - Mapping hints from the project config (see below) override these defaults.
   - A container's entrypoint/wiring code (`main.py`, `app.py`, DI setup) is the container itself, not a component. likeC4 rejects parent → child relationships, so container → own-component calls are not modeled (they are implied by containment). Without this rule the first e2e run invented a file-level component `main` just to carry those relationships.
4. **Explore**: MVP — a single direct pass. Post-MVP — for large/multi-container repos, fan out one `Explore` subagent per candidate container (each returns a condensed summary: components, mutual dependencies, external connections, **with evidence**), and incremental runs that only re-explore containers changed since the last analyzed commit.
5. **Stable IDs**: element ID = slug derived from its path; the original path is kept in metadata (`sourcePath`), so an ID mentioned by the user in conversation resolves reliably back to the code. Titles/descriptions may be refreshed each run; identity doesn't change unless the path does. IDs never come from generic names (`main`, `app`, `index`, …). The first `sourcePath` entry is the main code path; shared deployment files (Dockerfile, compose) only follow it, unless the element exists only there (a compose-only database).
6. **Relationships with evidence** (decision 1): every relationship carries `evidence` (file:line); no evidence → no relationship. Two kinds: runtime (default — calls, HTTP, SQL, queues) and `code-dependency` (dotted — importing another element's types/models/constants without calling it; only between modeled elements, omitted when a runtime relationship in the same direction exists). Code dependencies were added after e2e step 2 so that cycles like `orders` ⇄ `invoicing` show up on the diagram; the report names cycles explicitly.
7. **Regenerate with the previous model as reference** — keep IDs of elements whose paths still exist, drop elements whose paths are gone, add new ones. No elaborate merge machinery: stable IDs plus likeC4's automatic layout already keep the diagram stable.
8. **Validate**: `npx likec4 validate` (syntax), plus the agent spot-checks that evidence entries point at real code. Bounded number of fix attempts.
9. **Ensure the server is running** (decision 3) and **report**: the URL plus a short summary of changes derived from `git diff` of the model.

**No manual override layer for structure.** Architect feedback ("split this component", "simplify these connections") is carried out by the agent as a real code change; the next run picks up the new structure through stable path-based IDs. Code is the single source of truth; the model is always its reflection.

## Project config: `.design-explainer/config`

A small, optional, committed config file in the target repo. Not a model override — input to extraction:
- **mapping hints** — e.g. "`billing/legacy_auth.py` belongs to the `auth` component", "treat `tools/` as not part of the system". This resolves the case where the architect disagrees with a categorization without wanting to move files.
- **architecture rules** (post-MVP, see Deferred) — e.g. "`billing` must not call `auth` directly".

## MVP scope

1. Plugin `design-explain`: `explain` and `stop` skills, `SessionEnd` hook, scripts.
2. Model in a committed directory in the target repo; pidfile/logs gitignored.
3. Single-pass extraction (no fan-out), tried on one small real repo.
4. Mandatory `evidence` on relationships, `sourcePath` on elements; Context level (external systems) included.
5. Validation via `npx likec4 validate` — no MCP, no likeC4 Agent Skill dependency.
6. Change report via `git diff`.
7. Detached likeC4 server with per-project port and pidfile; stop skill + automatic stop at session end.

## Deferred / future

- **Architecture rules & conformance checking** — the architect declares intended architecture rules in the project config; each run flags violations (with evidence). Likely the main long-term value of the tool: comparing what the agents built with what was *meant* to be built, not just showing the as-is state.
- Fan-out exploration via `Explore` subagents for large repos; incremental regeneration based on the last analyzed commit.
- Optional likeC4 MCP integration (querying the model, `removal-impact`) and the `likec4-dsl` Agent Skill.
- likeC4 DSL `diff` blocks / `list-diffs` for richer architecture history in the viewer — only if git-based history turns out insufficient; otherwise a custom mechanism.
- Hosting the marketplace in a git repo for installation on other machines; README/LICENSE (required only for submission to Anthropic's plugin directory).

## Implementation (MVP)

Repo layout:
- `.claude-plugin/marketplace.json` — local marketplace `design-explainer` listing the plugin;
- `plugin/.claude-plugin/plugin.json` — plugin `design-explain`;
- `plugin/skills/show/SKILL.md` — the workflow above as agent instructions, including a verified DSL syntax reference; scripts referenced via `${CLAUDE_PLUGIN_ROOT}/scripts/`;
- `plugin/skills/stop/SKILL.md` — runs `stop-server.sh`;
- `plugin/hooks/hooks.json` — `SessionEnd` → `scripts/session-end.sh` (timeout 15 s; the default hook budget at session end is 1.5 s);
- `plugin/scripts/`, `plugin/templates/`.

Install: `claude plugin marketplace add <path-to-this-repo>`, then `claude plugin install design-explain@design-explainer`. For development without installing: `claude --plugin-dir <repo>/plugin`. Check manifests with `claude plugin validate ./plugin` and `claude plugin validate .`.

**likeC4 version**: pinned to **1.60.0** in one place, `scripts/common.sh` (`LIKEC4_VERSION`), always run as `npx -y likec4@<version>`. Bumping it is a deliberate change: re-verify the DSL reference in `SKILL.md` with `validate` afterwards.

**Workspace layout in the target repo** (`.design-explainer/`):
- `model/spec.c4` — element and relationship kinds, owned by the plugin: `init-workspace.sh` re-syncs it from `templates/spec.c4` on every run (so spec changes reach existing workspaces), never edited by the agent;
- `model/model.c4` — elements and relationships; `model/views.c4` — views (both fully rewritten each run, after the previous version was read as reference);
- `config.yaml` — optional mapping hints / exclusions / notes (template with commented examples);
- `state.json` — `lastAnalyzedCommit`, `workingTreeDirty` (the model also reflects uncommitted code changes, so it describes HEAD + working tree, not HEAD; groundwork for incremental runs and per-commit conformance checks), `analyzedAt`, `likec4Version`;
- `.gitignore` → ignores `run/`; `run/` holds `server.pid`, `server.port`, `server.log`.
Everything except `run/` is meant to be committed.

**Scripts** (all take an optional project root; default = git toplevel, else cwd):
- `init-workspace.sh` — creates the workspace if missing; syncs `spec.c4` from the template; prints root, HEAD, `working_tree_dirty` (uncommitted changes outside `.design-explainer/`), `state.json`, files changed since the last analyzed commit, existing model files.
- `validate.sh` — `likec4 validate` on `model/`; exit code 0 = valid (verified: a dangling reference yields exit 1 with file/line errors).
- `ensure-server.sh` — idempotent: reuses a live server (pidfile + process alive + port open) or starts `likec4 serve` detached via `setsid nohup`, bound to `127.0.0.1`; waits up to 120 s for the port.
- `stop-server.sh` — kills the server's whole process group; safe to call when nothing runs.
- `session-end.sh` — hook entry point: exits immediately unless `$CLAUDE_PROJECT_DIR/.design-explainer/run/server.pid` exists (the hook fires in every project where the plugin is enabled), otherwise calls `stop-server.sh`. Measured: ~0.2 s with a running server, ~3 ms without a workspace.

**Port scheme**: `61000 + cksum(project path) % 1000`, probing upward (max 50) if the port is taken; the chosen port is stored in `run/server.port` and reused on restart.

**Verified behavior** (WSL2, likeC4 1.60.0): DSL incl. array `evidence` metadata on relationships and hyphenated IDs validates; the server survives across separate shell invocations; editing a model file triggers a hot reload within ~1 s; on first start likeC4 opens the browser by itself (on WSL via `powershell.exe`).

## Open items

1. ~~End-to-end test of the skill~~ — done 2026-10-29 on `~/Projects/bookshop-example`, all 4 steps passed; results and the resulting `SKILL.md` changes in [docs/testing.md](testing.md). Next: a larger/real project (multi-container, another language) to test scale and the ecosystem hints.
2. Non-Linux hosts: `setsid` is absent on macOS (scripts fall back to plain `nohup`, process-group kill then degrades to killing the npx pid) — untested.
