---
name: magento-upgrade
description: Drive a Magento 2 / Adobe Commerce / Mage-OS version upgrade end to end — minor (2.4.6 → 2.4.8) or patch level (2.4.8-p5 → p6) — with a before/after regression baseline so a real break can be told apart from a fault the store already had. Use when asked to "upgrade Magento", "update this store to 2.4.x", "move us to the latest Magento", "bump Magento version", or when planning what a version jump would involve. Covers the platform migration (PHP, search engine, certified stack drift), third-party module resolution, the app/code and app/design fixes composer cannot make, build-output verification, and an honest coverage report. NOT for "is this store patched?" or applying a security patch to the version already running — that is magento-patch-check.
---

# Magento upgrade

Moves a store from one version to another and **proves what did and did not break**.

The hard part is not `composer update`. It is knowing whether something broken afterwards was
broken before, and catching failures that exit 0.

**Scope:** minor and patch-level upgrades. Patch moves run the same phases and skip phase 3.

**Standalone, but co-operative.** Where these exist, use them; where they do not, fall back
and say so in the report:

| If present | Use it for | Fallback |
|---|---|---|
| `magento-e2e-test` | phase 2 and 8 before/after runs and comparison | required; stop if missing |
| `magento-patch-check` | phase 6, isolated security patches | query Adobe's registry directly |
| `magento-validate-migrations` | migrations applied cold to a fresh database | phase 7 build gate alone |
| `magento2-development-environment` | container and environment commands | detect Warden/DDEV/host PHP directly |

## Rules that carry the weight

Read these before starting. Each one cost real time on a real upgrade.

1. **Baseline before touching anything.** Without a before-run you cannot tell a regression
   from a pre-existing fault. Most "regressions" are not.
2. **A green build is not a correct build.** `setup:static-content:deploy` will exit 0 while
   emitting `width: 100%/2`, which browsers discard. Verify generated output, not exit codes.
3. **Triage every failure before reporting it.** About half of a first run's failures are the
   harness, not the store (`magento-e2e-test`'s harness traps). Reporting a selector bug as a
   regression burns trust.
4. **Stay in developer mode locally.** It turns PHP warnings into exceptions, so faults surface
   loudly. CI proves the production build. The one production-only artefact worth checking
   locally, SRI hashes, gets a per-process override in phase 7, never a mode switch.
5. **Composer cannot fix `app/code` or `app/design`.** Dynamic properties, changed library
   signatures and LESS division are hand edits or nothing.
6. **A fully patched store can still ship a broken release.** Bugs introduced *inside* a
   release never appear in the patch registry.
7. **Never drive a payment gateway.** Offline Check/Money order and Purchase Order only, even
   where sandbox keys are configured. Name every active gateway in the report as untested.

`reference/traps.md` has each known failure mode with a detection command.

## Phases

★ = stop for the human. Everything else runs through.

### 0 — Recon (read-only) ★

Detect the project, then build a compatibility picture. Change nothing.

- `composer.lock` → edition and version. Warden/DDEV/host. Container PHP ≠ host PHP.
- Inventory `app/code` modules, `app/design` themes, third-party packages, existing patches.
- Snapshot the core ancestor of every `app/design` override, outside the repo (see
  `reference/traps.md`, theme overrides).
- `watch.py <dist> <current> <target>` (dist is `magento-community`, `magento-commerce` or
  `mage-os`) for status, EOL, latest in branch, latest overall, advisories and stack
  requirements for **both** versions. It fetches magento.watch and keeps only fields of the
  expected shape; never fetch the API directly. Anything under `dropped` was malformed or
  unexpected: mention it, don't interpret it.
- Classify every stack delta:
  - **Required** — the target will not run without it. PHP below the minimum; a search engine
    whose module no longer exists (`Magento_Elasticsearch7` is absent from 2.4.8).
  - **Advisory drift** — works, but is not the certified pairing. Report at the end. Never gate.

**Ask once, then do not interrupt again until the next gate:**

1. **Target version** — specific, or latest. Flag if the choice is not the latest security
   patch level for its branch.
2. **Required infrastructure bumps**, current → required, so they can be confirmed as
   possible on dev/staging/production *before* work starts. Also state the next version's
   requirements so a PHP choice is not made twice.
3. **Environment URLs** — local, dev, staging, production. Propose what was found (README
   first, then `store` + `core_config_data web/unsecure/base_url`) for confirmation.
4. **Known release bugs in the target.** Check `magento-patch-check`'s `known-issues.md`
   against the target's package versions (`composer show magento/product-community-edition
   <target> -a`). For each hit, ask whether to apply the fix, recommending yes: the trigger
   config may be off locally and on in production.

Do not ask about module bumps (always latest compatible) or payments (always offline only).

Where the README does not document the environments, **add them to it** on the upgrade
branch. Undocumented environments are a defect to fix while we are here.

### 1 — Environment preparation (no code changes)

Make the baseline trustworthy: containers up, search engine reachable and indexed, caches
and indexers sane. Fix environment faults now so they cannot masquerade as upgrade
regressions later.

**Hard boundary: no composer changes, no code edits, no version bumps.** If the store cannot
be made healthy without them, stop and report.

Run `magento-e2e-test`'s "Before any run" checks now: local store, mail caught, data safe.

Check free disk **inside the container** (`df -h /`). Under about 5 GB, stop and tell the user
before phase 4; what to free is their call. A composer run that dies mid-extract leaves `vendor`
truncated; delete it and reinstall from the lock.

`.env` and other local-only environment files may be corrected where they are wrong for the
*current* state — a committed MySQL distribution that does not match the actual data volume,
which stops the container booting at all. Version bumps belonging to the upgrade are phase 3.
Keep local-only edits out of commits.

### 2 — Baseline ★

1. **Database dump first**, timestamped, before anything else.
2. Run `magento-e2e-test` with label `before`. It picks the harness (the project's own suite, or the
   bundled one with runtime discovery), caches discovery, and keeps results outside the repo.
3. Keep the `before` results: phase 8 compares against them with the same harness and fixtures.
4. **Everything failing here is a known pre-existing failure.** Record it, report it as
   "pre-existing, not investigated", and diff the after-run against this set.
5. **Build the widen list now** and run it with the baseline: a sample of product URLs per type
   (random, but saved, so both runs use the same ones), every store's home page, account and
   B2B routes, CMS pages. Record status and error markers per URL:
   ```bash
   while read -r u; do
     code=$(curl -sk -o /tmp/w.html -w '%{http_code}' "$BASE/$u")
     err=$(grep -cE 'exception\(s\):|Report ID:|Undefined array key' /tmp/w.html)
     echo "$code $err $u"
   done < "$CACHE/widen-urls.txt" > "$CACHE/widen-before.txt"
   ```

Gate: present the baseline and its pre-existing failures before changing anything.

### 3 — Platform

Apply the approved required bumps only. Search engine changes also need
`catalog/search/engine` updated in **both** `env.php` and `core_config_data`, then a full
reindex — the DB value silently wins otherwise.

### 4 — Composer resolve

- **Set every patch aside first**, then `composer patches-relock`. cweagans v2 applies what is
  in `patches.lock.json`, so removing entries from `composer.json` alone is not enough. The
  current version's isolated security patches are dropped for good; phase 6 adds the target's.
  The project's own patches (vendor fixes, PR backports) are re-assessed in phase 5.
- **Diff root `require` and `require-dev` against the target's project skeleton** before the
  first update:
  ```bash
  composer create-project --repository-url=https://repo.magento.com/ \
    magento/project-community-edition=<target> /tmp/skeleton --no-install
  ```
  Match `require-dev` to the skeleton, and remove dev packages it no longer carries unless the
  project uses them. Bump any root `magento/module-*` requirement to the major the target
  ships (`composer show magento/product-community-edition <target> -a`).
- Constrain the target as a **range** (`>=2.4.8 <2.4.9`) so patch releases can be pulled in.
- Third-party modules to **latest compatible**.
- Expect to fight: exact pins that cannot resolve, `require-dev` constraints that block the
  target's dependency tree, and **runtime-asserted dependencies** that composer cannot see.

### 5 — Compatibility sweep

The fixes composer structurally cannot make, across `app/code` and `app/design`. See
`reference/traps.md` for detection of each: dynamic properties, changed library signatures,
LESS division, theme overrides whose core ancestor changed.

**Re-assess every project patch** set aside in phase 4 against the updated package, with a
forward and a reverse `patch --dry-run` (`reference/traps.md`). Re-add, drop or rebase each one,
and record why. Applying cleanly does not prove a patch is still needed.

### 6 — Security patches

Delegate to `magento-patch-check` where present. Otherwise query Adobe's registry directly.

Patches go in before the build gate, so the build it verifies and the after-test both run the
code that ships.

Apply the known-issue fixes approved in phase 0. A declined one goes in the report with the
config that would trigger it.

The release does **not** cover isolated patches published after it. A version released in May
still needs the June, July and August isolated patches for that patch level.

### 7 — Build, then verify the output ★

Build the way the project builds, in the store's current mode. Do not switch the local store
to production mode; CI proves the production build. Find the steps in this order:

1. README
2. Makefile, Justfile, `package.json` scripts, build scripts under `bin/` or `scripts/`
3. CI workflow files: `bitbucket-pipelines.yml`, `.github/workflows/`, `.gitlab-ci.yml`
4. Deploy config: `deploy.php` and similar
5. Otherwise Magento's own: `setup:upgrade`, `setup:di:compile`,
   `setup:static-content:deploy -f`, `cache:flush`

Read each target before running it, and skip CI-only steps: `composer install --no-dev`,
permission resets, packaging. Hyvä themes need their Tailwind build before static deploy.

Then verify the artefacts rather than the exit code:

- scan every generated CSS for unevaluated division
- SRI: hashes are only generated in production. Run the static deploy once more with a
  per-process `MAGE_MODE=production` override (`magento-patch-check`'s `known-issues.md`),
  with `dev/js/enable_js_bundling` and `dev/js/minify_files` switched on if they are off.
  Restore both after. With them off no hash file is generated and the check proves nothing.
- load the key pages and sweep the logs for `CRITICAL` and runtime assertions. Some only log
  in production, so check the dev environment's logs after the first deploy as well.
  Take time cutoffs from the container's clock (`date -u` inside it), not the host's.

**Fail this gate on bad output even when the exit code is 0.** That is the whole point of it.

### 8 — After-test

Run `magento-e2e-test` with label `after`, in the same mode as the baseline, and compare it with
`before`. Classify every difference as **fixed**, **regression** or **harness** before
reporting.

Then re-run the widen list from phase 2 into `widen-after.txt` and diff the two. Only a URL
that got worse is a candidate regression. The harness already covers admin writes (save a
product, save a CMS page, invoice an order).

### 9 — Report and ship ★

The report carries: version and stack changes, composer diff and `config.php` module diff
(both against the branch the PR will target, not `master` by habit),
patches applied with provenance, compatibility fixes made, the before/after comparison,
advisory stack drift, and an explicit **untested** section.

Before reporting, complete `magento-e2e-test`'s "After the run" cleanup: the throwaway admin must be
gone.

**Never push or raise a PR without asking.** Offer; do not assume.

## Evidence

Results, screenshots and comparison JSON stay in the **session scratchpad** — enough for the
developer to see exactly what happened. Nothing test-related is committed to the repo.
Rendered or shareable artifacts are produced only on request.

## Reporting honesty

State what was not covered as prominently as what passed: payment gateways (never driven;
name each active one), anything the harness could not reach, and bugs deliberately
left unfixed, with the reasoning.
