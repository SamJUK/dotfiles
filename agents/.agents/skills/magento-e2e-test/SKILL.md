---
name: magento-e2e-test
description: Run end-to-end tests against a local Magento 2 / Mage-OS store and report the results, or compare two runs taken before and after a change. Uses the project's own suite when it has one (the m2-e2e testing platform in dev/tests/e2e, or another Playwright suite), otherwise a bundled critical-path harness. Use when asked to "run the e2e tests", "smoke test this store", "check checkout still works", "did this break anything", or when another skill needs a before/after comparison (magento-upgrade, magento-patch-check, magento-validate-migrations). Local stores only.
---

# Magento e2e tests

Runs a store's end-to-end tests and says what passed, failed and was skipped. For a change, run
it twice, before and after, and compare.

## Before any run

1. **Local store only.** Every harness here creates customers and orders. The bundled harness
   refuses non-local hosts itself (`*.test`, `*.localhost`, `localhost`, `127.0.0.1`,
   `*.ddev.site`). For a project suite, check its configured base URL yourself.
2. **Mail is caught.** A production database copy may still point at real SMTP. Trigger a
   forgotten-password email for a test account and confirm it lands in Mailpit (Warden and DDEV
   both ship it). Check no SMTP extension config points at a real host. If mail would leave
   the machine, stop.
3. **Data changes are expected.** The bundled harness registers a customer, places and
   invoices an order, and saves a product and a CMS page. The m2-e2e platform dumps and
   restores the database itself. If the local data matters, dump it first.

## Pick the harness

Say which one you picked and why.

1. **m2-e2e testing platform:** `dev/tests/e2e/package.json` depends on `@samjuk/e2e-m2-*`.
   ```sh
   cd dev/tests/e2e && pnpm exec playwright test --reporter=json > "$RUN/results.json"
   ```
   Add `--grep @smoke` for a quick pass. Its `docs/test-environment.md` covers the Mailpit
   port trap that fails only the mail tests.
2. **Another Playwright suite:** a `playwright.config.*` outside `node_modules` and `vendor`.
   Run it the same way with `npx playwright test --reporter=json`.
3. **Bundled harness:** everything else. Discovery first (`reference/discovery.md`), then:
   ```sh
   LABEL=before DISCOVERY="$CACHE/discovery.json" OUT_DIR="$RUN" ADMIN_PASS=… \
     node harness/critical-paths.js
   ```
   Under DDEV set `DB_CMD='ddev mysql -e'`. The admin invoice step needs at least one order in
   the admin order grid. With async grid indexing on (`dev/grid/async_indexing`), run
   `n98-magerun sys:cron:run sales_grid_order_async_insert` then `bin/magento cache:flush`
   (inside `warden shell` or `ddev exec`).

A project with MFTF only (`dev/tests/acceptance`): mention it and ask before running it,
because it is slow and needs Selenium.

## Where results go

Outside the repo, per project:

- `CACHE=~/.cache/magento-e2e-test/<project directory name>`
- `RUN=$CACHE/<label>`, for example `before`, `after` or a timestamp

**Discovery is cached** at `$CACHE/discovery.json`. Before reusing it, check that the fixture
URLs still return 200 and are in stock, and that the payment methods are still active.
Rediscover when that check fails, or when the Magento version or theme has changed.

## Report a run

```sh
results.py summary "$RUN/results.json"
```

Report counts, then each failure with its detail, then skips with their reasons. Report
failures as found; do not fix anything unless asked. Before calling a failure a store bug,
check `reference/harness-traps.md`: selector drift, captchas and duplicate ids all look like
product failures.

## Compare two runs

Same harness, same fixtures (same `discovery.json`), same mode (developer or production).

```sh
results.py compare "$CACHE/before/results.json" "$CACHE/after/results.json"
```

- **Still failing** tests were broken before the change: report them as pre-existing.
- **Regression**: classify each as a real regression or a harness fault, with the screenshot
  or trace as evidence, before reporting it.
- **New** or **removed** tests mean the two runs were not comparable. Explain why.

## After the run

If you created the throwaway `upgradetest` admin (`reference/discovery.md`), delete it and
confirm the row is gone.
