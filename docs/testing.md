# End-to-end test: bookshop

Manual end-to-end test of `/design-explain:show` on the small Python app in [`examples/bookshop/`](../examples/bookshop). This file holds the **expected model**, so the test has to run on a copy outside this repository: the agent under test explores the project during recon, and any hint it finds there invalidates the test. The copy has no `CLAUDE.md` on purpose, because the plugin alone must be enough.

## Setup

```bash
cp -r examples/bookshop /tmp/bookshop-test     # any directory outside this repo
cd /tmp/bookshop-test
git init && git add -A && git commit -m "Initial bookshop app"
```

The plugin must be installed (see the [README](../README.md#installation)). Start a new Claude Code session in the copy for the scenario steps. Evaluate each step from a separate session in this repository by comparing the copy's `.design-explainer/` with this file.

## The test app

A Python monolith with a background worker:
- `bookshop/api/main.py`: FastAPI app (compose service `api`), mounts the catalog and orders routers;
- `bookshop/catalog/`: book listing and search, stock reservation (SQLAlchemy → Postgres);
- `bookshop/orders/`: places orders. Checks and reserves stock via catalog, charges via payments, stores the order, enqueues a confirmation job;
- `bookshop/payments/`: Stripe `PaymentIntent`;
- `bookshop/notifications/`: SendGrid e-mail;
- `bookshop/worker/main.py`: compose service `worker`, consumes jobs from Redis and sends confirmations;
- shared helpers `bookshop/{config,db,jobs}.py`; `docker-compose.yml` with `api`, `worker`, `postgres`, `redis`.

Deliberate traps:
- `boto3` is in `requirements.txt` but never imported, so AWS must **not** appear.
- `scripts/seed_db.py` is a dev tool, not part of the running system. It must not be a container, and ideally isn't in the model at all.
- `api` and `worker` never call each other directly, only through Redis.

## Expected model

IDs may differ in spelling only where noted; the structure below is the reference.

| Kind | ID | sourcePath / evidence |
|---|---|---|
| system | `bookshop` | `.` |
| actor | `customer` (any reasonable name) | — |
| external-system | `stripe` | `bookshop/payments/stripe_client.py:1` or `:9` |
| external-system | `sendgrid` | `bookshop/notifications/email.py:1` or `:6` |
| container | `api` | `bookshop/api` first (deployment files may follow); `entrypoint` `bookshop/api/main.py:6`; `endpoints` `GET /health` |
| container | `worker` | `bookshop/worker` first; `entrypoint` in `bookshop/worker/main.py` |
| database | `postgres` | `docker-compose.yml` (`bookshop/db.py` may follow) |
| queue | `redis` | `docker-compose.yml` (`bookshop/jobs.py` may follow) |
| component (api) | `catalog` | `bookshop/catalog` |
| component (api) | `orders` | `bookshop/orders` |
| component (api) | `payments` | `bookshop/payments` |
| component (worker) | `notifications` | `bookshop/notifications` |

`config.py`, `db.py` and `jobs.py` are shared helpers, so they should **not** be components. Their use shows up as relationships to `postgres` and `redis` from the components that use them. Modeling them as one shared component is a tolerable deviation. Modeling individual files (`models.py`, `routes.py`, `worker/main.py`) as elements is a failure (Code level).

Expected relationships (evidence = at least one of the listed locations):

| # | From → To | Meaning | Evidence |
|---|---|---|---|
| R1 | customer → `catalog` (**not** `api`) | `GET /books`, `GET /books/{id}` | `bookshop/catalog/routes.py:23`, `:28` (`:10` router) |
| R2 | customer → `orders` (**not** `api`) | `POST /orders`, `GET /orders/{id}` | `bookshop/orders/routes.py:33`, `:48` (`:11` router) |
| R3 | `orders` → `catalog` | looks up books, reserves stock | `bookshop/orders/service.py:30`, `:33` |
| R4 | `orders` → `payments` | charges the order | `bookshop/orders/service.py:39` |
| R5 | `orders` → `postgres` | stores orders | `bookshop/orders/service.py:45`, `:46` |
| R6 | `catalog` → `postgres` | reads/updates books | `bookshop/catalog/repository.py:16`, `:20` |
| R7 | `payments` → `stripe` | creates PaymentIntent (HTTPS) | `bookshop/payments/stripe_client.py:9` |
| R8 | `orders` → `redis` | enqueues confirmation job | `bookshop/orders/service.py:48`, `bookshop/jobs.py:13` |
| R9 | `worker` → `redis` | consumes jobs | `bookshop/worker/main.py:21`, `bookshop/jobs.py:17` |
| R10 | `notifications` → `sendgrid` | sends e-mail | `bookshop/notifications/email.py:16` |

A single customer → `api` relationship is a failure: the components view would show `catalog` as reachable only through `orders`. `GET /health` (served by `api/main.py` itself, with no caller in the code) is container metadata, not a relationship.

`worker` → `notifications` is **not** modeled: likeC4 rejects container → own-component relationships, and containment already implies it. No code dependencies are expected in step 1: every import between components is already covered by a runtime relationship, or it is a container importing its own components.

Must **not** appear: AWS/S3; `scripts/` as a container; a direct `api` → `worker` relationship; any relationship without evidence; Code-level elements.

## Scenario

### Step 1: first run
In the copy: `/design-explain:show`.

Check:
- [ ] viewer starts, the report gives the URL, and the diagram renders (context, containers and components views);
- [ ] elements match the table above (kinds, IDs, `sourcePath`, `entrypoint`/`endpoints` on containers), with no entrypoint component (e.g. `main`);
- [ ] relationships R1–R10 are present, each with evidence pointing at a real line; R1/R2 go to the components and are labeled with the endpoints;
- [ ] none of the "must not appear" items appear;
- [ ] the report says it's the first model, gives counts, and lists unconfirmed suspicions;
- [ ] `state.json` has `lastAnalyzedCommit` = HEAD and `workingTreeDirty: false`; `.design-explainer/.gitignore` ignores `run/`;
- [ ] `validate.sh` passes; nothing is committed by the agent.

Then commit the model: `git add .design-explainer && git commit -m "Add architecture model"`.

### Step 2: code change, second run
Apply the change and commit it, then run `/design-explain:show` again in the same session:

```bash
git apply <this-repo>/examples/bookshop-invoicing.patch
git add -A && git commit -m "Extract invoicing from orders"
```

The patch adds `bookshop/invoicing/`: an `Invoice` model stored in Postgres and `create_invoice(session, order)`. `orders/service.py` calls it after a successful payment. `invoicing` imports the `Order` model, which deliberately creates a dependency cycle.

Check:
- [ ] new component `invoicing` (`sourcePath bookshop/invoicing`) in `api`;
- [ ] `orders` → `invoicing` (`orders/service.py:48`) and `invoicing` → `postgres` (`invoicing/service.py:14`, `:15`), both with evidence;
- [ ] `invoicing -[code-dependency]-> orders` ("uses Order model", `invoicing/service.py:4`), drawn dotted;
- [ ] the report names the cycle `orders` ⇄ `invoicing`;
- [ ] **all other element IDs unchanged**; shifted evidence line numbers in `orders` are updated;
- [ ] the report summarizes the change from `git diff` of the model; `state.json` is updated; the viewer was reused (same PID, no second server) and the open page reloaded by itself.

Commit the model again.

### Step 3: architect feedback
In the same session, ask in terms of the diagram:
1. "Why does `orders` call `payments`?"
2. "Remove the cycle between `orders` and `invoicing`." Then `/design-explain:show`.

Check:
- [ ] the agent resolves the IDs to the right files via `sourcePath` / `evidence`, without re-exploring the whole repo;
- [ ] the answer to Q1 cites correct lines and explains the roles (synchronous charge inside `place_order`);
- [ ] Q2 is done in the code, not by editing the model; the rerun removes the code dependency and nothing else changes structurally;
- [ ] when the code change is not committed yet, `state.json` has `workingTreeDirty: true` and the report says so.

### Step 4: lifecycle
- [ ] `/design-explain:stop` stops the viewer; a second call reports that it was not running;
- [ ] `/design-explain:show` again restarts it on the same port; with no code change, only `state.json` changes;
- [ ] `/clear` does **not** stop the viewer;
- [ ] exiting the session stops it (no process listening on the port from `.design-explainer/run/server.port`).

## Results

### 2026-10-29: plugin 0.1.0, likeC4 1.60.0 (WSL2)
All four steps passed after these changes to `SKILL.md`. Each was prompted by a deviation in an earlier step:
- Step 1 created a component `main` for `worker/main.py` to carry `→ redis` and `→ notifications`, working around likeC4's ban on parent → child relationships. Fix: entrypoint/wiring code is the container itself, there are no container → own-component relationships, and IDs never come from generic names. Container `sourcePath` arrays also started with deployment files. Fix: the main code path comes first.
- Step 2 left the `invoicing` → `orders` import invisible, which hid the cycle. Fix: the `code-dependency` relationship kind, with cycles named in the report. `spec.c4` is now re-synced from the plugin on every run, so spec changes reach existing workspaces.
- Step 3 analyzed an uncommitted working tree but recorded HEAD as if it had been analyzed. Fix: `workingTreeDirty` in `state.json`.
- Architect review afterwards: the customer was connected only to the `api` container, which an exception in `SKILL.md` allowed. In the components view `catalog` therefore looked reachable only through `orders`, although `GET /books` is called directly. `api/main.py` (the entrypoint, mounting routers, serving `/health`) was not visible anywhere either. Fix: actor relationships go to the handling component, labeled with endpoints; containers carry `entrypoint` and `endpoints` metadata. Step 1 has to be re-run against the updated expectations.

Notable positives: every cited evidence line was correct (19/19 in step 1); no traps were hit; the reports flagged real design risks outside the model (charge before commit with no compensation, the still-unused `boto3`); the step 3 answer cited correct lines; and the viewer lifecycle behaved exactly as specified.
