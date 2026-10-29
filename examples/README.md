# Examples

> **Test fixtures only.** The bookshop app is not a working application and isn't meant to be run, deployed or used as a template. It exists only as input for testing design-explainer: realistic enough to have a non-trivial architecture, and it contains deliberate traps such as an unused dependency and a dev-only script.

- `bookshop/`: a small Python app (FastAPI API, background worker, Postgres, Redis, Stripe, SendGrid) used for the end-to-end test of `/design-explain:show`.
- `bookshop-invoicing.patch`: the code change for step 2 of the test, which extracts an `invoicing` component from `orders`.

Don't run the test inside this repository. The agent under test explores the whole repo, so it would read the expected model in [docs/testing.md](../docs/testing.md). Copy `bookshop/` to a separate directory and make it its own git repo, as described in [docs/testing.md](../docs/testing.md#setup).
