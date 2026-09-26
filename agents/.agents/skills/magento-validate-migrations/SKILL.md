---
name: magento-validate-migrations
description: Prove a Magento 2 change's migrations (Setup/Patch data and schema patches, db_schema.xml, EAV attributes, config, customer groups) apply cleanly to a fresh copy of the upstream database. Backs up the local database, syncs the latest dev database, runs setup:upgrade, setup:di:compile and static content deploy as a deploy would (via magento-smoke-test), checks the migrations landed, and verifies any acceptance criteria given. Use before raising a PR that touches Setup/Patch or db_schema.xml, or when asked "will this deploy cleanly?", "do the migrations apply to a fresh database?", "validate the migrations". Not for Adobe security patches (magento-patch-check) and not a full end-to-end run (magento-e2e-test).
---

# Magento: validate migrations

A migration that works locally has usually already run there: half-applied, re-run, fixed by
hand. Production runs it once, cold, on real data. This recreates that: a fresh copy of the
upstream database, one deploy-style run, then checks.

## 1. Safety first

- **Local only.** `app/etc/env.php` must point at the project's local database container
  (Warden or DDEV `db`). Anything else: stop.
- **Back up the current local database** before replacing it, outside the repo:

  ```bash
  B=~/.local/state/magento-validate-migrations/<project>; mkdir -p -m 700 "$B"
  warden db dump | gzip > "$B/before-sync-$(date +%s).sql.gz"   # DDEV: ddev export-db --file="$B/…"
  ```

  Check it with `gzip -t` and a plausible size. Keep it until the user decides at the end.
- Dumps hold customer data. Never write them inside the repo, and delete them when done.

## 2. Get the latest database

How a project syncs its dev database is project knowledge:

1. Look for a documented command or source (an S3 path, a Git LFS dump, a DDEV provider, a
   script) in the project's README, AGENTS.md or CLAUDE.md, and in any loaded rules.
2. If none is documented, ask the user how to get it. Offer to record the answer as one line in
   the project's AGENTS.md, and write it only on a yes.

Run it, then confirm the import finished: exit status 0 and core tables present
(`SELECT COUNT(*) FROM store`).

## 3. Apply it as a deploy would

Run `magento-smoke-test`: `setup:upgrade` without `--keep-generated`, `setup:di:compile` (a
production deploy compiles, and that catches plugin and type errors) and
`setup:static-content:deploy`, then the key pages and a check for new exceptions.

Any failure here is the main finding: report the first error verbatim, with the patch class that
raised it.

## 4. Check the migrations landed

Query the database, do not eyeball the storefront:

- Every patch present in `patch_list`, in dependency order.
- Attributes created with the flags intended (`is_searchable`,
  `is_used_for_promo_rules`, `is_global`), and in the right attribute sets.
- Declarative schema columns present with the right default.
- Config rows written at the intended scope. Default scope and website scope
  behave very differently.
- Rows the patches create: customer groups, rules, CMS blocks. Check the
  **scope** of each, not just that it exists. A rule created for one website
  when the rule it copies covers three is a silent bug.
- A moved patch: its old class name should appear in `patch_list` via
  `getAliases()`, so it does not re-run and duplicate what it creates.

## 5. Check the acceptance criteria

Criteria come from the user, the PR or the ticket. Turn each one into a check with a control:

- Page content: request the local URL and assert the expected text is there, and that a control
  page or string that should differ does.
- Config: `SELECT scope, scope_id, value FROM core_config_data WHERE path = '…'`.
- Data: a SQL query for the rows the change should create or alter.

If a criterion cannot be expressed as a check, say so rather than eyeballing it. For broad
regression coverage, run `magento-e2e-test`.

## 6. Report, then restore or keep

Report the deploy commands' results, the migration checks, each criterion with its evidence,
and the deploy facts below. Then ask: keep the upgraded database, or restore the backup
(`warden db import`, `ddev import-db`)? Delete the backup once the user is done with it.

## Migration rules this checks

- **A patch runs once.** A precondition that quietly `return`s records the patch
  as applied and leaves the feature permanently missing. Throw instead, so
  `setup:upgrade` fails visibly.
- **Never hardcode an id.** Customer groups, attribute sets, websites, store
  ids, tax classes all differ per environment. Resolve by code and fail loudly
  if absent. Hardcoding means the patch matches nothing, writes nothing, and is
  still recorded as applied.
- **Two related inserts need a transaction.** A half-applied patch is worse than
  a failed one, especially where a missing pivot row reads as "applies to
  everything".
- `lastInsertId()` is **not** on `Magento\Framework\DB\Adapter\AdapterInterface`.
  Read the row back instead, inside the transaction.
- Config written by one patch is not visible to a later patch in the same run
  until `ReinitableConfigInterface::reinit()`.
- A large `INSERT ... SELECT` inside the patch transaction takes shared next-key
  locks across the source table under REPEATABLE READ, blocking concurrent
  writes for its duration. Chunk it, or ask whether it is needed at all.

## Deploy facts for the PR description

- Which indexers `setup:upgrade` invalidates. Adding a searchable product
  attribute invalidates `catalogsearch_fulltext`, and on a six-figure catalogue
  that reindex is the whole cost of the deploy. Until it runs, anything relying
  on the index is inert while direct-URL behaviour already works.
- Anything that locks, and for how long.
- Anything left manual after release, and where.

## Local traps

**OpenSearch flood-stage watermark.** When the disk crosses it, OpenSearch sets
a **persistent** `cluster.blocks.create_index` and marks indices read-only.
Reindex then fails with `FORBIDDEN/10 cluster create-index blocked (api)`.
Nulling the setting does not clear it; setting it explicitly to `false` does. Run these inside
the PHP container (`warden shell`, `ddev ssh`), where `opensearch` resolves:

```bash
curl -s -X PUT 'http://opensearch:9200/_cluster/settings' -H 'Content-Type: application/json' \
  -d '{"persistent":{"cluster.blocks.create_index":false}}'
curl -s -X PUT 'http://opensearch:9200/magento__*/_settings' -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'
```

It re-asserts while the disk stays full, so this buys one reindex, not a fix.
Free the space. Raising the watermark thresholds is papering over it, and the
byte-based `max_headroom` settings are rejected on some versions anyway.

**Docker disk on a shared machine.** Most reclaimable space usually belongs to
other projects. Never run `docker volume prune` to make room — dangling volumes
routinely hold other clients' databases. Report the numbers and let the owner
decide.
