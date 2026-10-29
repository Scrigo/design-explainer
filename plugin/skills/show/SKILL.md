---
description: Generate or refresh an interactive C4 architecture diagram (likeC4) of the current project and open it in the browser. Use when the user asks to explain, visualize, map or review the architecture/design of the codebase, to show a C4 diagram, or calls /design-explain:show.
---

# design-explain:show

Builds a C4 model (Context, Container, Component — never the Code level) of the **current project** from its source code, writes it as likeC4 DSL into `.design-explainer/model/`, validates it, and makes sure a likeC4 dev server shows it in the browser (it hot-reloads on every model change).

The user is a software architect reviewing code written by AI agents. **A wrong diagram is worse than no diagram** — it creates false confidence. Every relationship must be backed by evidence you actually saw in the code. When unsure, leave it out and say so in the report.

All scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Each takes the project root as an optional argument (default: git toplevel, else the current directory). Stopping the viewer is a separate skill, `/design-explain:stop`; it also stops automatically when the session ends.

## Workflow

### 1. Prepare the workspace and load the previous state

Run `${CLAUDE_PLUGIN_ROOT}/scripts/init-workspace.sh`. It creates (if missing) `.design-explainer/` with `model/spec.c4`, `config.yaml`, a `.gitignore` for runtime files, and prints: project root, git HEAD, `state.json` (last analyzed commit), files changed since the last analysis, existing model files.

- If the previous `state.json` has `"workingTreeDirty": true`, the previous model also reflected uncommitted changes that may since have been committed or discarded. Treat the changed-files list as incomplete, and compare the model with the code, not with the list.
- If model files beyond `spec.c4` exist, **read them** — they are the reference point: keep element IDs that still map to existing paths.
- Read `.design-explainer/config.yaml`. Its `exclude`, `mapping` and `notes` entries override the default conventions below.
- Never edit `model/spec.c4` (the script re-syncs it from the plugin on every run); use only the element and relationship kinds it defines.

### 2. Lightweight recon (before reading source)

Look at: the directory tree (2–3 levels), manifests (`package.json`, `pyproject.toml`/`requirements*.txt`, `go.mod`, `pom.xml`/`build.gradle*`, `Cargo.toml`, `*.csproj`), Dockerfiles, `docker-compose*.yml`, k8s/deploy configs, `.env.example`, README. Determine languages, frameworks, deployable units, owned datastores/queues, and external dependencies (SDKs, API base URLs, env vars like `STRIPE_KEY`).

Do not read the whole codebase. Use Grep to find imports, HTTP clients/routes, DB access, queue producers/consumers, and read only the files needed to confirm them.

### 3. Map the code onto C4 (fixed convention)

| Element kind | What it is | Typical signals |
|---|---|---|
| `system` | The analyzed project (exactly one) | repo root |
| `actor` | Users or other systems calling in (only if identifiable) | auth/login flows, public routes, webhooks |
| `external-system` | Third-party/other systems this project calls | SDK imports, client config, API base URLs, env vars |
| `container` | Independently deployable/runnable unit | own entrypoint, Dockerfile, compose service, deployable module |
| `database` / `queue` | Datastore or broker owned/used by the system, modeled inside the `system` | compose services, connection strings, ORM/driver setup |
| `component` | Cohesive internal module of a container | see ecosystem hints |

Ecosystem hints for components (defaults; `config.yaml` mapping wins):
- **Go**: `cmd/*` → containers; `internal/*`, `pkg/*` → components.
- **Java/Kotlin**: deployable Maven/Gradle modules (e.g. a Spring Boot app) → containers; packages directly under the base package (`com/acme/billing`) → components.
- **Python**: separately deployed apps/services → containers; subpackages of the main package (`src/<pkg>/*` or `<pkg>/*`) → components.
- **Node/TS**: workspace packages with their own entrypoint → containers; feature/module directories under `src/` → components.

A single-service repo is one container. Aim for components an architect can reason about (typically 3–15 per container); don't turn every folder into a component, and skip trivial ones (utils, constants, generated code) unless they carry real dependencies.

A container's own entrypoint and wiring code (`main.py`, `app.py`, `main.go`, `index.ts`, the app/DI setup that mounts routers or dispatches jobs) **is the container itself, not a component**. Its outgoing relationships (e.g. consuming a queue) are modeled from the container; its calls into the container's own components are implied by containment and are not modeled (likeC4 rejects parent → child relationships anyway). Never create a component just to have a source for such a relationship.

Make the entrypoint visible on the container instead:
- `entrypoint '<file:line>'`: where the app is created or started (e.g. `bookshop/api/main.py:6` for `app = FastAPI(...)`);
- `endpoints [...]`: endpoints the entrypoint itself serves rather than mounting them from a component (e.g. `'GET /health'`). Omit it when there are none.

An entrypoint becomes a component only if it contains substantial logic of its own beyond wiring and trivial endpoints. It is then named after its role, never `main`/`app`.

### 4. IDs and metadata (stability rules)

- **ID** = slug of the element's main path's last segment: lowercase, `[a-z0-9-]`, starting with a letter (`internal/billing` → `billing`, `cmd/api-server` → `api-server`). If two siblings collide, prefix the parent segment (`orders-api`). Never derive an ID from a generic file or folder name (`main`, `app`, `index`, `src`, `lib`, `__init__`, `cmd`): use the nearest meaningful path segment, or else a slug of the element's role. External systems/actors: slug of their name (`stripe`). Elements are referenced by their dotted path: `shop.api-server.billing`.
- **Keep existing IDs** from the previous model whenever the element still maps to the same path. Never rename an ID just because a nicer name came up — change the title instead. The exception is an element that breaks the rules in this skill (e.g. an entrypoint modeled as a component): fix it, and list it in the report as a correction, not a code change.
- Every element inside the `system` gets `metadata { sourcePath '<path relative to repo root>' }` (several paths: an array). The `system` itself gets `sourcePath '.'`.
- The **first** `sourcePath` entry is the element's main code path — the one the ID is derived from and the one to open when the user refers to the element. Shared deployment files (`Dockerfile`, `docker-compose.yml`, k8s manifests) may follow it, but come first only for elements defined solely there (e.g. a database that exists only as a compose service).
- `external-system` elements get `metadata { evidence '<file:line>' }` showing where the dependency is visible.
- Titles and descriptions: short, concrete, describing the role ("Charges orders via Stripe"), not the folder name.

### 5. Relationships — evidence is mandatory

- Add a relationship only if you saw it in the code. Every relationship carries `metadata { evidence '<file:line>' }` or an array of up to 3 locations: `evidence ['a.go:12', 'b.go:40']`.
- Model relationships at the **lowest level you have evidence for** (component → component, component → database/external-system). likeC4 derives container- and system-level relationships automatically — do not duplicate them at higher levels.
- **Actors connect to the component that handles their request**, not to the container. Example: `customer -> shop.api.catalog` for the catalog routes and `customer -> shop.api.orders` for the order routes. Never use one `actor -> container` relationship, because the components view would then hide which component serves which endpoint. Label these relationships with the endpoints or operations (`'GET /books, GET /books/{id}'`). Evidence is the route or handler definitions (up to 3; with more endpoints, cite the router declaration plus representative routes). An endpoint served by the entrypoint itself goes into the container's `endpoints` metadata (step 3). It becomes an actor relationship only if a caller is identifiable.
- Never model a relationship between an element and its own descendant (container → own component); see the entrypoint rule in step 3.
- Label with what happens ("charges order", "reads/writes orders"), add `technology` when known (`'HTTPS'`, `'gRPC'`, `'SQL'`, `'Kafka'`).
- No evidence → no relationship. If you suspect a connection you couldn't confirm, mention it in the report instead.

Two kinds of relationships:
- **Runtime** (default, `->`): A invokes B's behavior — function/method calls, HTTP/gRPC, SQL, queue publish/consume.
- **Code dependency** (`-[code-dependency]->`, drawn dotted): A depends on B's code without invoking its behavior — imports B's types, models, schemas, DTOs, enums or constants. Label with what is used (`'uses Order model'`), `technology 'import'`, evidence = the import line (plus a usage line if the import alone is ambiguous).
  - Only between elements in the model (components, containers). Imports of shared helpers that aren't elements (`db.py`, `config.py`) or of third-party libraries are not modeled.
  - Skip it when a runtime relationship A → B already exists — the code dependency is implied.
  - These make dependency cycles visible: if A and B depend on each other in any combination of kinds, name the cycle in the report.

### 6. Write the model

Write two files (overwrite them fully each run; the previous model was already read in step 1):
- `.design-explainer/model/model.c4` — all elements and relationships.
- `.design-explainer/model/views.c4` — views:
  - `view index` — system context (`include *`),
  - `view <system-id>-containers of <system-id>` — containers,
  - one `view <container-id>-components of <system-id>.<container-id>` per container that has components.

Syntax reference (verified against likeC4 1.60.0):

```
model {
  customer = actor 'Customer' {
    description 'Buys things in the shop'
  }
  stripe = external-system 'Stripe' {
    description 'Payment provider'
    metadata {
      evidence 'go.mod:12'
    }
  }
  shop = system 'Shop' {
    metadata {
      sourcePath '.'
    }
    api-server = container 'API server' {
      technology 'Go'
      description 'Public HTTP API'
      metadata {
        sourcePath 'cmd/api-server'
        entrypoint 'cmd/api-server/main.go:14'
        endpoints ['GET /health']
      }
      billing = component 'Billing' {
        description 'Charges orders'
        metadata {
          sourcePath 'internal/billing'
        }
      }
      orders = component 'Orders' {
        description 'Places orders'
        metadata {
          sourcePath 'internal/orders'
        }
      }
    }
    db = database 'Postgres' {
      metadata {
        sourcePath 'docker-compose.yml'
      }
    }
  }

  customer -> shop.api-server.orders 'POST /orders, GET /orders/{id}' {
    technology 'HTTPS/JSON'
    metadata {
      evidence ['internal/orders/http.go:22', 'internal/orders/http.go:31']
    }
  }
  shop.api-server.billing -> stripe 'creates payment intents' {
    technology 'HTTPS'
    metadata {
      evidence ['internal/billing/stripe.go:31', 'internal/billing/client.go:12']
    }
  }
  shop.api-server.billing -[code-dependency]-> shop.api-server.orders 'uses Order type' {
    technology 'import'
    metadata {
      evidence 'internal/billing/invoice.go:7'
    }
  }
}
```

```
views {
  view index {
    title 'System context'
    include *
  }
  view shop-containers of shop {
    title 'Shop - containers'
    include *
  }
  view api-server-components of shop.api-server {
    title 'API server - components'
    include *
  }
}
```

Strings use single quotes; escape a single quote inside a string as `\'`.

### 7. Validate and verify

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh`. Exit code 0 = valid. On errors, fix the reported lines and rerun — **at most 3 attempts**; if still invalid, stop and report the remaining errors.
2. Spot-check evidence: for at least 5 relationships (all if fewer), open the cited `file:line` and confirm it supports the relationship. Fix or drop any that don't.

### 8. Record state, ensure the viewer, report

1. Write `.design-explainer/state.json`:
   ```json
   { "lastAnalyzedCommit": "<git HEAD or null>", "workingTreeDirty": <true|false>, "analyzedAt": "<ISO-8601 UTC>", "likec4Version": "1.60.0" }
   ```
   `workingTreeDirty` is `working_tree_dirty` from step 1 (`false` when there is no git). `true` means the model describes HEAD plus uncommitted changes, not HEAD itself.
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/ensure-server.sh` — it starts a detached server or reuses the running one, and prints the URL. The first start can take a while (npx download).
3. Report to the user, briefly:
   - the URL;
   - if `workingTreeDirty`: that the model includes uncommitted changes, and that the model should be committed together with them;
   - counts: containers, components, external systems, relationships;
   - **what changed** since the last run, derived from `git diff -- .design-explainer/model` (if the model was never committed, say it's the first model);
   - dependency cycles between elements (runtime and/or code dependencies);
   - relationships you suspected but couldn't confirm, and anything you excluded or were unsure about;
   - a reminder that `.design-explainer/` (except `run/`) is meant to be committed — do not commit it yourself unless asked.

## After the diagram: resolving element IDs back to code

When the user refers to an element by its diagram ID or title ("split `billing`", "why does `orders` call `billing`?"), look it up in `.design-explainer/model/model.c4`: `sourcePath` tells you which code it is, `evidence` on relationships tells you where a connection lives. Act on the **code**, not the model — architecture changes are code changes; the next `design-explain` run will reflect them.
