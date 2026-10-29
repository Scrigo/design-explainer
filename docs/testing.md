# End-to-end test: bookshop-example

Manual end-to-end test of `/design-explain:show` on a small Python app at `~/Projects/bookshop-example` (its own git repo). This file holds the **expected model** and must stay outside the test project: the agent under test reads the project during recon, so any hint there would invalidate the test. The test project has no `CLAUDE.md` on purpose — the plugin alone must be enough.

## The test app

Python monolith with a background worker (initial commit `7d41b56`):
- `bookshop/api/main.py` — FastAPI app (compose service `api`), mounts the catalog and orders routers;
- `bookshop/catalog/` — book listing/search, stock reservation (SQLAlchemy → Postgres);
- `bookshop/orders/` — places orders: checks/reserves stock via catalog, charges via payments, stores the order, enqueues a confirmation job;
- `bookshop/payments/` — Stripe `PaymentIntent`;
- `bookshop/notifications/` — SendGrid e-mail;
- `bookshop/worker/main.py` — compose service `worker`, consumes jobs from Redis and sends confirmations;
- shared helpers `bookshop/{config,db,jobs}.py`; `docker-compose.yml` with `api`, `worker`, `postgres`, `redis`.

Deliberate traps:
- `boto3` is in `requirements.txt` but never imported → AWS must **not** appear.
- `scripts/seed_db.py` is a dev tool, not part of the running system → must not be a container; ideally not in the model at all (later used to test `exclude` in `config.yaml`).
- `api` and `worker` never call each other directly — only through Redis.

## Expected model

IDs may differ slightly in spelling only where noted; anything structural below is the reference.

| Kind | ID | sourcePath / evidence |
|---|---|---|
| system | `bookshop` | `.` |
| actor | `customer` (any reasonable name) | — |
| external-system | `stripe` | `bookshop/payments/stripe_client.py:1` or `:9` |
| external-system | `sendgrid` | `bookshop/notifications/email.py:1` or `:6` |
| container | `api` | `bookshop/api` (an array also listing the component dirs is fine) |
| container | `worker` | `bookshop/worker` |
| database | `postgres` | `docker-compose.yml` |
| queue | `redis` | `docker-compose.yml` |
| component (api) | `catalog` | `bookshop/catalog` |
| component (api) | `orders` | `bookshop/orders` |
| component (api) | `payments` | `bookshop/payments` |
| component (worker) | `notifications` | `bookshop/notifications` |

`config.py`, `db.py`, `jobs.py` are shared helpers — expected **not** as components; their use shows up as relationships from the components that use them to `postgres` / `redis`. Modeling them as one shared component is a tolerable deviation; modeling individual files (models.py, routes.py) as elements is a failure (Code level).

Expected relationships (evidence = at least one of the listed locations):

| # | From → To | Meaning | Evidence |
|---|---|---|---|
| R1 | customer → `catalog` (or `api`) | browses/searches books | `bookshop/catalog/routes.py:23`, `:28` |
| R2 | customer → `orders` (or `api`) | places orders | `bookshop/orders/routes.py:33` |
| R3 | `orders` → `catalog` | looks up books, reserves stock | `bookshop/orders/service.py:30`, `:33` |
| R4 | `orders` → `payments` | charges the order | `bookshop/orders/service.py:39` |
| R5 | `orders` → `postgres` | stores orders | `bookshop/orders/service.py:45`, `:46` |
| R6 | `catalog` → `postgres` | reads/updates books | `bookshop/catalog/repository.py:16`, `:20` |
| R7 | `payments` → `stripe` | creates PaymentIntent (HTTPS) | `bookshop/payments/stripe_client.py:9` |
| R8 | `orders` → `redis` | enqueues confirmation job | `bookshop/orders/service.py:48`, `bookshop/jobs.py:13` |
| R9 | `worker` → `redis` | consumes jobs | `bookshop/worker/main.py:21`, `bookshop/jobs.py:17` |
| R10 | `worker` → `notifications` | dispatches confirmation | **not modeled**: likeC4 rejects container → own-component relationships; implied by containment |
| R11 | `notifications` → `sendgrid` | sends e-mail | `bookshop/notifications/email.py:16` |

Must **not** appear: AWS/S3; `scripts/` as a container; a direct `api` → `worker` relationship; any relationship without evidence; Code-level elements.

## Scenario

### Step 1 — first run
In a new Claude Code session started in `~/Projects/bookshop-example`: `/design-explain:show`.

Check:
- [ ] viewer starts, URL reported, diagram renders (context, containers, components views);
- [ ] elements match the table above (kinds, IDs, `sourcePath`);
- [ ] relationships R1–R9 and R11 present, each with evidence pointing at a real line; no entrypoint component (e.g. `main`) created to carry R9/R10;
- [ ] none of the "must not appear" items;
- [ ] report mentions it's the first model, gives counts, lists unconfirmed suspicions;
- [ ] `state.json` written with `lastAnalyzedCommit` = HEAD; `.design-explainer/.gitignore` ignores `run/`;
- [ ] `validate.sh` passes.

Then commit the model: `git add .design-explainer && git commit -m "Add architecture model"`.

### Step 2 — code change, second run
Change (applied from the design-explainer session so it's reproducible): extract invoicing from `orders` — new `bookshop/invoicing/` (an `Invoice` model stored in Postgres and `create_invoice(session, order)`), called from `orders/service.py` after a successful payment. Commit it, then run `/design-explain:show` again in the test session.

Check:
- [ ] new component `invoicing` (`sourcePath bookshop/invoicing`) in `api`, with `orders` → `invoicing` and `invoicing` → `postgres`, both with evidence;
- [ ] **all other element IDs unchanged** — except `worker.main` from step 1, which must disappear (R9 moves to `worker` → `redis`), reported as a correction;
- [ ] report summarizes the change from `git diff` of the model (new component + relationships; shifted evidence line numbers are fine);
- [ ] `state.json` updated; the viewer was reused (no second server), the open page reloaded by itself.

Optionally also test `config.yaml`: add `exclude: [scripts/]` (if step 1 modeled `scripts/` in any way) and confirm it disappears.

### Step 3 — architect feedback
In the test session, ask in terms of the diagram, e.g. "why does `orders` call `payments`?" and "split `orders` so that order validation is separate".

Check:
- [ ] the agent resolves the IDs via `sourcePath` / `evidence` to the right files without re-exploring the whole repo;
- [ ] changes are made in the code (not by editing the model); the next `/design-explain:show` reflects them.

### Step 4 — lifecycle
- [ ] `/design-explain:stop` stops the viewer (`status: stopped`), a second call reports `not-running`;
- [ ] after `/design-explain:show` again, exiting the session stops the viewer (check: no process listening on the port from `.design-explainer/run/server.port`);
- [ ] `/clear` does **not** stop it.

## Results

### Step 1 (2026-10-29, plugin 0.1.0, likeC4 1.60.0)
- Passed: all 12 expected elements; R1–R9, R11 present; 19/19 evidence lines correct; no traps hit (no AWS, no `scripts/`, no `api` → `worker`); `state.json` = HEAD, `run/` gitignored, spec/config untouched, nothing committed; validate OK, viewer up. Bonus: `db.py` / `jobs.py` listed in the `sourcePath` of `postgres` / `redis`.
- Deviation: `worker/main.py` modeled as component `main` ('Job dispatcher') to carry `→ redis` and `→ notifications` — a workaround for likeC4 rejecting parent → child relationships. Fixed in SKILL.md: entrypoint/wiring code is the container itself, no container → own-component relationships, no IDs from generic names (`main`, `app`, `index`, …).
- Minor: `Dockerfile` / `docker-compose.yml` in container `sourcePath` arrays. Fixed in SKILL.md: the first `sourcePath` entry is the main code path; deployment files only after it.
- Report checklist item: not evaluated (report not captured).

### Step 2 (2026-10-29, after SKILL.md fixes; code change `c809cd9`)
- Passed: `invoicing` (`sourcePath bookshop/invoicing`) in `api`; `orders` → `invoicing` (`orders/service.py:48`) and `invoicing` → `postgres` (`invoicing/service.py:14`, `:15`); all other IDs unchanged; `worker.main` removed, R9 now `worker` → `redis`, reported as a correction; shifted evidence lines updated, all 9 changed lines correct; `state.json` = `c809cd9`; viewer reused (same PID, no second server); validate OK; nothing committed.
- Report: counts correct (11 relationships), change summary and correction separated. It also flagged findings outside the model: a two-way dependency (`invoicing` imports `Order` from `orders`), a partial-failure risk (order committed before the invoice), and the still-unused `boto3`.
- Minor: the change list doesn't name `invoicing` → `postgres` as a new relationship (it's only in the component description).
- Open question: import-only dependencies (types/models, no runtime call) are not modeled, so cycles like `orders` ⇄ `invoicing` stay invisible in the diagram. **Decision:** the architect wants them visible. Added relationship kind `code-dependency` (dotted, plugin-owned `spec.c4`, now re-synced on every run) and rules in SKILL.md.

### Step 2b — code dependencies (rerun, no code change)
Expected: `spec.c4` reported as updated from the plugin template; exactly one new relationship `invoicing -[code-dependency]-> orders` (evidence `bookshop/invoicing/service.py:4`, uses the `Order` model); no code dependency for `orders/routes.py` → `catalog` (`OutOfStock`: runtime `orders` → `catalog` already exists) or for `worker/main.py` / `api/main.py` (own components); the report names the cycle `orders` ⇄ `invoicing`; all IDs unchanged.

Result (2026-10-29): **passed exactly as expected.** The model diff is the single new relationship (evidence `invoicing/service.py:4`, `:7`); `spec.c4` was synced and reported; the cycle was named, with a suggested fix (pass primitives instead of `Order`); each import left undrawn was listed with its reason; the viewer was reused; nothing committed. The diagram renders the dotted line correctly (confirmed by the architect).

### Step 3 (2026-10-29)
- Q1 "why does `orders` call `payments`?": correct — all cited lines verified (`orders/service.py:23,31,34,40,45–47`, `stripe_client.py:9,13`); explained the roles (Payments = thin Stripe wrapper, the rule lives in Orders) and the risks (charge before commit with no compensation or idempotency key; stock reservation only in the session; no Stripe timeout); proposed options without changing code. Whether it started from `model.c4` is unconfirmed.
- Q2 "remove the `orders` ⇄ `invoicing` cycle": done in code — `create_invoice(session, order_id, customer_email, amount)`, the `Order` import is removed. The rerun dropped the `code-dependency` and updated the evidence lines; no manual model edit. The DB-level FK `ForeignKey("orders.id")` (a string, not an import) is correctly not modeled.
- Minor: show ran on an uncommitted working tree, but `state.json` records `lastAnalyzedCommit` = HEAD (`5d029be`) as if that commit had been analyzed. Harmless for the next run (`git diff <commit>` includes working-tree changes), but misleading. **Fixed:** `init-workspace.sh` prints `working_tree_dirty` and the skill stores it as `workingTreeDirty` in `state.json` and mentions it in the report.

### Step 4 (2026-10-29)
**Passed.** The first `/design-explain:stop` stopped the viewer: pid and its process group gone, port 61326 closed, pidfile removed (`server.port` is kept for reuse). The second call reported not-running. `/design-explain:show` restarted the viewer on the same port. It survived `/clear` and returned HTTP 200. Exiting the session stopped it through the SessionEnd hook. The rerun with no code change changed only `state.json` (`workingTreeDirty: false`, `lastAnalyzedCommit` = HEAD `a059e1c`); `model.c4` was identical.

### Summary
All four steps passed. SKILL.md changes driven by the test:
- entrypoint/wiring code belongs to the container;
- no parent → child relationships;
- no IDs from generic names;
- the first `sourcePath` entry is the main code path;
- `code-dependency` relationship kind, with cycles named in the report;
- `spec.c4` re-synced from the plugin on every run;
- `workingTreeDirty` in `state.json`.

## Evaluation

After each step, come back to the design-explainer session; the generated `.design-explainer/` is read from `~/Projects/bookshop-example` and compared with this file. Deviations become changes to `plugin/skills/show/SKILL.md`.
