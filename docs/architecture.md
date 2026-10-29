# design-explainer: architecture

The design of the `design-explain` plugin: what it does, the key decisions and their rationale, how it is implemented, and what is planned next.

## Vision

`design-explainer` gives a software architect oversight of code produced by AI agents. It is invoked *from other projects*. On request it analyzes the target project's codebase, builds a C4 model of its architecture, and renders it as an interactive diagram in which selecting an element shows its role and its connections.

Target C4 levels: **Context, Container, Component**. It deliberately does **not** go down to the Code level (individual classes or files).

## What it is

A **Claude Code plugin** named `design-explain`:
- `/design-explain:show` runs the extraction workflow, validates the model and makes sure the viewer is running;
- `/design-explain:stop` stops the viewer;
- a `SessionEnd` hook stops the viewer automatically.

The extraction "engine" is Claude Code's own agentic loop following the skill's instructions; rendering is done by [likeC4](https://likec4.dev). This repository is also a plugin marketplace (`.claude-plugin/marketplace.json`, plugin under `plugin/`).

It is a plugin rather than a standalone skill because both of these need one: the namespaced commands (`/<plugin>:<skill>`), and a hook that registers on install without editing the user's `settings.json`.

**Runtime prerequisites**: Node.js with `npx` (likeC4 runs via `npx`). Nothing is added to the target project's own dependencies.

## Decisions

### 1. Extraction: LLM-based, run by the agent itself

Extraction is **LLM-based**, not static/AST analysis. Target codebases can be in any language, and maintaining a parser per language isn't viable. It is **not a separate LLM pipeline**: the skill's instructions drive Claude Code's own tool use (reading files, grepping).

**Every relationship must carry evidence.** Relationships are the most valuable part of the diagram for an architect ("too many connections", "A must not call B"). They are also the part most exposed to LLM non-determinism and hallucination. In a tool meant to give control over AI agents, a wrong diagram is worse than none, because it creates false confidence. Therefore:
- each relationship stores `evidence` (`file:line`) in its metadata: an import, a call, a query, a queue operation;
- a relationship without evidence does not go into the model;
- evidence makes relationships verifiable, both by the architect and by the agent during validation, and more stable across runs.

### 2. Model format and rendering: likeC4

likeC4 is local-first: the model stays in the repository and nothing is sent to a third-party service. It covers everything from model to diagram, but nothing from code to model. None of its CLI commands, MCP tools or its Agent Skill analyze source code, so extraction is done entirely by this plugin.

What likeC4 provides:
- a DSL (`.c4`) for elements and relationships, with a `specification` block for custom element and relationship kinds and free-form metadata;
- `likec4 serve`: a dev server with file watching and hot reload;
- an interactive browser viewer: clicking an element shows its description, technology and relationships, and you can drill down into nested levels, with no custom frontend needed;
- automatic layout computed from the graph, so stable element IDs and relationships give a stable layout;
- `validate` (syntax and references), exports and a static site `build`.

Not used: the likeC4 MCP server and the `likec4-dsl` Agent Skill. An MCP server registered mid-session only becomes available in the next session, so the skill couldn't bootstrap it on first run. Syntax checking is done with `likec4 validate`, and the agent checks the evidence itself.

### 3. Invocation and server lifecycle

**One command** (`/design-explain:show`) does everything on an explicit call: it runs the extraction, writes the model, and ensures the viewer is running. There is no separate init step to remember, because the server check is idempotent.

Server handling:
- a pidfile, plus a check that the process is alive and the port answers. If no server is live, one is started; otherwise likeC4's file watcher reloads the open page by itself;
- the server is **detached from the Claude Code session** (`setsid nohup`). A process started in the Bash tool's background mode would die with the session;
- **a port per project**, so several projects can have viewers running at the same time;
- **stopping**: `/design-explain:stop` on demand, and automatically through the `SessionEnd` hook when the session ends. The hook's matcher is `logout|prompt_input_exit|other`, so it does **not** fire on `/clear` or `/resume`: the user keeps working in the same terminal and likely still views the diagram. The next `/design-explain:show` starts the server again.
- known limitation: with two concurrent sessions in the same project, ending one stops the viewer the other may still be using, because the server is per project, not per session. The next `/design-explain:show` restarts it.

### 4. Storage and git

The generated model lives in the target repo and **is committed**; runtime state (pidfile, port, log) is gitignored. Committing the model gives:
- a **"what changed" report** from `git diff` of the model files;
- **architecture history** from `git log` of the model;
- groundwork for **incremental regeneration**: `state.json` records the last analyzed commit.

### 5. Code is the single source of truth

There is no manual override layer for the model's structure. Architect feedback ("split this component", "remove this cycle") is carried out by the agent as a code change, and the next run picks up the new structure through stable, path-based IDs. When the architect disagrees with how code is categorized and doesn't want to move files, the remedy is a mapping hint in the project config, not an edit to the model.

## Extraction workflow

What `/design-explain:show` instructs the agent to do (details in `plugin/skills/show/SKILL.md`):

1. **Load the previous state**: the previous model (the reference point for IDs), `state.json`, the files changed since the last analyzed commit, and the project config.
2. **Lightweight recon** before reading code: the directory tree, manifests (`package.json`, `pyproject.toml`, `go.mod`, `pom.xml`/`build.gradle`, …), Dockerfiles and compose files, the README and config files. Then Grep for imports, routes, DB access and queue producers/consumers, reading only the files needed to confirm them.
3. **Apply the mapping convention**:
   - **System** = the analyzed repository.
   - **Context level** = **external systems** (third-party APIs and managed services, detected via SDK imports, client config, URLs and env vars) and **actors** (users or other systems calling in, where identifiable).
   - **Container** = an independently deployable or runnable unit (own entrypoint, Dockerfile, compose service, deployable module), plus the databases and queues the system uses.
   - **Component** = a cohesive internal module within a container, not necessarily a top-level folder. Per-ecosystem defaults:
     - *Go*: `cmd/*` → containers; `internal/*`, `pkg/*` → components.
     - *Java/Kotlin*: deployable Maven/Gradle modules → containers; packages directly under the base package → components.
     - *Python*: separately deployed apps → containers; subpackages of the main package → components.
     - *Node/TS*: workspace packages with their own entrypoint → containers; feature/module directories under `src/` → components.
   - A container's entrypoint and wiring code (`main.py`, `app.py`, DI setup) is the container itself, not a component. likeC4 rejects parent → child relationships, so calls from a container into its own components are not modeled; containment implies them.
   - Mapping hints in the project config override these defaults.
4. **Stable IDs**: an element's ID is a slug of the last segment of its main path, and the original path is kept in `sourcePath` metadata. An ID mentioned in conversation therefore resolves reliably back to the code. Existing IDs are kept as long as the path exists. IDs never come from generic names (`main`, `app`, `index`, …). The first `sourcePath` entry is the main code path; shared deployment files may follow it.
5. **Relationships with evidence**, modeled at the lowest level that has evidence (likeC4 aggregates them upward). There are two kinds:
   - **runtime** (default): calls, HTTP, SQL, queues;
   - **`code-dependency`** (drawn dotted): one element imports another's types, models or constants without calling it. These are only drawn between modeled elements, and omitted when a runtime relationship already exists in the same direction. They make dependency cycles visible, and the report names each cycle.
6. **Write** `model.c4` and `views.c4` in full: a system context view, a containers view, and a components view per container.
7. **Validate** with `likec4 validate` (at most 3 fix attempts), and spot-check that the cited evidence lines support the relationships.
8. **Record the state, ensure the viewer, report**: the URL, counts, the changes since the last run (from `git diff` of the model), dependency cycles, and suspected but unconfirmed relationships. The agent never commits on its own.

## Project config: `.design-explainer/config.yaml`

An optional, committed config file in the target repo. It is input to extraction, not a model override:
- `exclude`: paths that are not part of the system (e.g. dev scripts);
- `mapping`: categorization hints (e.g. "`billing/legacy_auth.py` belongs to `auth`");
- `notes`: free-form context for the agent.

## Current scope and limitations

- Single-pass extraction (no subagent fan-out), re-run in full on every invocation; previous IDs are kept as the reference point.
- Tested end-to-end on a small Python project (see [testing.md](testing.md)). Larger, multi-language repositories are not tested yet.
- Linux and WSL2 only tested. On macOS there is no `setsid`: the scripts fall back to plain `nohup`, and stopping then kills only the `npx` process.

## Roadmap

- **Architecture rules and conformance checking**: the architect declares the intended rules in the project config (e.g. "`billing` must not call `auth`", "no dependency cycles"). Each run flags violations, with evidence. This is the main long-term goal: comparing what the agents built with what was *meant* to be built, not just showing the as-is state.
- **Scale**: fan-out exploration with one `Explore` subagent per container for large repos, and incremental runs that only re-analyze containers changed since the last analyzed commit (`workingTreeDirty` in `state.json` keeps that baseline honest).
- **Optional likeC4 MCP integration** for querying the model (e.g. `removal-impact`).

## Implementation

Repository layout:
- `.claude-plugin/marketplace.json`: the marketplace `design-explainer`, listing the plugin;
- `plugin/.claude-plugin/plugin.json`: the plugin `design-explain`;
- `plugin/skills/show/SKILL.md`: the workflow as agent instructions, including a DSL syntax reference verified against the pinned likeC4 version. Scripts are referenced via `${CLAUDE_PLUGIN_ROOT}/scripts/`;
- `plugin/skills/stop/SKILL.md`: runs `stop-server.sh`;
- `plugin/hooks/hooks.json`: `SessionEnd` → `scripts/session-end.sh`, with a 15 s timeout (the default hook budget at session end is 1.5 s);
- `plugin/scripts/`, `plugin/templates/`;
- `examples/bookshop/`: the test application, with `examples/bookshop-invoicing.patch` for the second test step.

**likeC4 version**: pinned to **1.60.0** in one place, `scripts/common.sh` (`LIKEC4_VERSION`), and always run as `npx -y likec4@<version>`. Bumping it is a deliberate change: re-verify the DSL reference in `SKILL.md` with `validate` afterwards.

**Workspace layout in the target repo** (`.design-explainer/`):
- `model/spec.c4`: element and relationship kinds. The plugin owns this file: `init-workspace.sh` re-syncs it from `templates/spec.c4` on every run, so spec changes reach existing workspaces. The agent never edits it;
- `model/model.c4` (elements and relationships) and `model/views.c4` (views): both fully rewritten on each run, after the previous version has been read as the reference;
- `config.yaml`: the project config (the template contains commented examples);
- `state.json`: `lastAnalyzedCommit`, `workingTreeDirty` (true when the model also reflects uncommitted code changes, so it describes HEAD plus the working tree), `analyzedAt`, `likec4Version`;
- `.gitignore` ignores `run/`, which holds `server.pid`, `server.port` and `server.log`.

Everything except `run/` is meant to be committed.

**Scripts** (each takes an optional project root; the default is the git toplevel, else the current directory):
- `init-workspace.sh`: creates the workspace if it is missing and syncs `spec.c4`. Prints the root, HEAD, `working_tree_dirty` (uncommitted changes outside `.design-explainer/`), `state.json`, the files changed since the last analyzed commit, and the existing model files.
- `validate.sh`: runs `likec4 validate` on `model/`. Exit code 0 means valid; errors come with file and line.
- `ensure-server.sh`: idempotent. Reuses a live server (pidfile, live process, open port) or starts `likec4 serve` detached via `setsid nohup`, bound to `127.0.0.1`, and waits up to 120 s for the port.
- `stop-server.sh`: kills the server's whole process group; safe to call when nothing is running.
- `session-end.sh`: the hook entry point. It exits immediately unless `$CLAUDE_PROJECT_DIR/.design-explainer/run/server.pid` exists, because the hook fires in every project where the plugin is enabled; otherwise it calls `stop-server.sh`. It takes about 0.2 s with a running server and about 3 ms without a workspace.

**Port scheme**: `61000 + cksum(project path) % 1000`, probing upward (up to 50 ports) if that port is taken. The chosen port is stored in `run/server.port` and reused on restart.

**Verified behavior** (WSL2, likeC4 1.60.0):
- the DSL, including array metadata, hyphenated IDs and relationship kinds, validates, and an unknown relationship kind fails validation;
- the server survives across separate shell invocations and sessions;
- editing a model file triggers a hot reload within about 1 s;
- on first start likeC4 opens the browser by itself (on WSL via `powershell.exe`).
