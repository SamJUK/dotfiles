---
name: magento-patch-check
description: Check and apply Magento security patches on any project — release patch level and EOL dates (magento.watch API) plus Adobe's monthly isolated (ad-hoc) security patches, pulled straight from Adobe's registry for whatever version the project runs. Use when asked "is this store patched?", "are we on a secure Magento version?", "check/apply Magento security patches", "when does our Magento go EOL?", "APSB26-xx", "isolated patch", or during a security/upgrade audit of a Magento 2 / Adobe Commerce / Mage-OS project. Also applies ad-hoc/out-of-band patch files supplied by hand rather than via the registry (a downloaded VULN-xxxxx bundle, a hotfix from Adobe support, a vendor patch) — "apply this patch file", "VULN-39341", "StyleSmuggler".
---

# Magento patch check

```bash
python3 ~/.claude/skills/magento-patch-check/check.py [project-root]           # report
python3 ~/.claude/skills/magento-patch-check/check.py [project-root] --apply   # + stage missing patches

# ad-hoc: a patch file or a directory of them, supplied by hand
python3 ~/.claude/skills/magento-patch-check/check.py [project-root] --patch PATH
python3 ~/.claude/skills/magento-patch-check/check.py [project-root] --patch PATH --apply

```

Verify with `magento-smoke-test` after applying; see Verifying below.

Works on any Magento version — the applicable patches are resolved from the project's own
`composer.lock` against Adobe's registry. Nothing is version-hardcoded. JSON out;
**report using the template below, never dump the JSON.**

## Report template

```
**<name>** — Magento <edition> <version>

Release      <version> · <statusLabel> · EOL <eolDate> (<eolInDays> days)
Patch level  <✅ top of branch (latestInBranch) | 🔴 behind — latestInBranch available | ⚠️ unknown>
Isolated     <✅ N/N applied | 🔴 N missing: ids | ⚠️ N partial or unknown: ids | 🔴 N blocked — needs <requires>>
CVEs         <✅ covered | 🔴 N exposed via <missing patch ids>>

Roadmap
  2.4.7 → p10   EOL 2027-04-09  PHP 8.2/8.3
  2.4.8 → p5    EOL 2028-04-11  PHP 8.3/8.4
  ...

<one line per action needed, or "No action.">
```

Expand only where there's a real finding.

## Reading the fields

**Release level**
- `eol: true` → unsupported, no further security fixes. Lead with it.
- `eolInDays` under ~180 → upgrade belongs on a roadmap now; say so.
- `securelySupported: false` → this exact version no longer gets security updates.
- `behindInBranch: true` → `composer require magento/product-<edition>-edition:<latestInBranch> --no-update && composer update magento/product-<edition>-edition -W`
  (`<edition>` is `community` or `enterprise`; a bare `composer update` would update every dependency)
- `latestInBranch: null` (with `versions_error`) → the lookup failed. Report patch level as
  **unknown**. Never render it as "top of branch" — absence of data is not a clean result.
- `dropped` → magento.watch fields that were malformed or unexpected and left out. Mention them;
  never interpret them.
- `isolatedPatches.coverage` → present on Mage-OS: Adobe's registry does not cover it, so an
  empty result is not a clean bill of health.
- `roadmap` → newest secure release per branch with EOL date + declared PHP. Always print it.
- `latestOverall` is context, not a demand. Minor upgrades are projects, not patches.
- `requirements` = declared stack. Surface only if asked, or if it contradicts what the project runs.

**Isolated patches** (`isolatedPatches`) — monthly out-of-band patches between quarterly releases.
They **stack** (August does not replace July) and each targets **exactly one** patch level.
- `areas` → installed version of every patchable component (CE, PageBuilder, Inventory, B2B, …).
  Applicability is resolved per area, so EE and B2B stores get their own patches automatically.
- `patches[]` → one entry per patch that applies to this project, oldest first:
  - `verdict: applied` — every file carries the change.
  - `verdict: missing` — no file does. Real gap; the `cves` list is what's exposed.
  - `verdict: partial` — some files patched, some not. **Treat as unpatched and loud.** This is
    what a `magento/magento2-base` reinstall looks like after it silently reverts root files.
    `unapplied[]` names the files.
  - `verdict: unknown` — a changed file no longer looks like either version of the patched code,
    usually a local override or heavy drift. Check those files by hand; never count them as applied.
- `blockedByPatchLevel[]` → patches published for a **higher patch level of this same branch**.
  Adobe targets only the current patch level, so a store one release behind gets
  `applicableCount: 0` and an empty `patches[]`. That is a gap, not a pass — report the
  count, the `cves`, and the `requires` version needed to become eligible.
- `metaPackage` = installed `samjuk/m2-meta-security-patches`, an alternative to wiring patches
  by hand. `null` just means patches came some other way (or never).

Detection reads the hunks' own added/removed lines against the files on disk. It does not use
`vendor/bin/patch-status` — that tool needs its own dry-run staging, degrades to `UNKNOWN` on an
already-patched tree, and is not present unless a patch was applied first.

## Delivery mode (`delivery`)

Reported per project, and it changes what `--apply` writes.

- `cloud` — `magento/ece-tools` in the lock, or an `m2-hotfixes/` directory. Adobe Commerce
  Cloud applies `m2-hotfixes/*.patch` **from the project root, in alphabetical filename order**,
  after Adobe's own patches during build. Root-relative diffs go in verbatim; cweagans is not
  involved even when it is installed for third-party modules.
- `composer` — everything else. cweagans `extra.patches`, per-package, package-relative.

**Adobe Commerce (EE) ships two isolated patches per month**: `…-CE` and `…-EE`, plus `…-B2B`
where B2B is installed. They are separate registry entries with separate CVE lists, and the
EE one must land **after** the CE one. Naming each staged file `<patch-id>.patch` makes
alphabetical order do that for free (`247p10-2026-08-001-CE` sorts before `…-EE`, and July
before August). Do not rename them.

## Applying (`--apply`)

**Cloud**: writes each missing patch to `m2-hotfixes/<patch-id>.patch`, root-relative,
`vendor/bin/` blocks stripped. Nothing else changes — no `composer.json` edit, no lock churn.
Verify locally, then commit `m2-hotfixes/`:

```bash
warden env exec php-fpm php ./vendor/bin/ece-patches apply   # applies Adobe's + m2-hotfixes
```

`composer-exit-on-patch-failure: true` means a hotfix that no longer applies cleanly **fails
the Cloud build**. If a root file (`lib/web/underscore.js`, `nginx.conf.sample`) carries local
edits, check it before committing.

**Composer**: for every patch not fully applied, the script:
1. downloads the official diff from `repo.magento.com` and verifies its `sha256` against the registry
2. splits it per composer package into `patches/composer/isolated/<patch-id>/`, rewriting the
   root-relative paths to package-relative (root files like `nginx.conf.sample` and
   `lib/web/underscore.js` go to `magento/magento2-base`, which is where they are copied from)
3. merges them into `extra.patches` in `composer.json`, compact `"description": "url"` format,
   oldest patch first so they stack in order

It stops there. **Run composer yourself, in the project's real PHP environment** — a Warden/DDEV
project with no `config.platform` will resolve against the wrong PHP if run on the host:

```bash
warden env exec php-fpm composer install          # if the patches plugin isn't in vendor/ yet
warden env exec php-fpm composer patches-relock
warden env exec php-fpm composer patches-repatch  # deletes + reinstalls the patched packages
warden env exec php-fpm composer update --lock
```

Then re-run the check to confirm. Commit `composer.json`, `composer.lock`, `patches.lock.json`
and `patches/composer/isolated/` together, or the next `composer install` drops the patches.

Assumes cweagans/composer-patches v2. `patches-repatch` wipes and reinstalls those vendor
packages — any uncommitted edits inside them are lost. Check before running.

## Ad-hoc patches (`--patch`)

For drops that never reach the registry: a hotfix from support, a vendor's own patch, or a
`VULN-xxxxx` bundle before Adobe adds it to the registry. Once a VULN patch has a registry entry
(`248p5-VULN-39341-CE`), the default run fetches it like any other. Same detection, splitting and
wiring as the registry path; the only difference is where the diff came from.

`PATH` is a single `.patch`/`.diff` file, or a directory of them. Adobe ships **one file per
patch level** in a bundle and encodes the level in the filename
(`VULN-39341_247-p10.patch` → 2.4.7-p10). Given a directory, the script reads the project's
version from `composer.lock` and picks the exact match — no guessing, no "closest" fallback.

- No file for this version → `error` listing the levels that *are* in the bundle. Usually means
  the store is behind its branch: reach the current patch level first, then re-run.
- Filenames with no version in them → every file in the directory is treated as applicable.
- Several files match the same version (CE/EE splits) → all are applied, in filename order.

Output lands in `adhocPatch`, one entry per file, with the same `applied`/`missing`/`partial`/`unknown`
verdicts. `--patch` does no network calls and skips the lifecycle and registry sections
entirely — it is only ever "does this diff match this tree".

`--apply` writes to a separate directory so ad-hoc and registry patches never collide:
- **composer** → `patches/composer/out-of-band/<patch-id>/`, split per package, then wired into
  `extra.patches`. Run the composer steps from the **Applying** section afterwards.
- **cloud** → `m2-hotfixes/<patch-id>.patch`, verbatim, root-relative.

`<patch-id>` is the filename without its extension. Don't rename staged files — alphabetical
order is what makes stacked patches land in the right sequence.

Patches must be git-format (`diff --git` headers). A plain `diff -u` gets `verdict: error` —
convert it or apply it by hand.

## Verifying (after any apply)

**A patch is not applied until the store has been exercised.** Detection only proves the lines
are on disk. Verify locally or on staging, **never production**.

1. **Before patching**, run `magento-smoke-test` and keep the result, so a pre-existing failure
   is not reported as a regression.
2. **After applying**, run `magento-smoke-test`: it deploys as production would (upgrade, compile,
   static content), loads the key pages and flags new exceptions.
3. **Targeted check.** Generic smoke will not notice that email template preview broke. Read the patch's own file list
(`check.py --patch PATH` prints it, or `grep '^+++ b/' <patch>`) and add one check per surface it
touches. Map the path to the screen:

| Patched path | Check |
|---|---|
| `module-email/Block/Adminhtml/Template/Preview` | Marketing → Email Templates → open one → **Preview** |
| `module-newsletter/.../Preview` | Marketing → Newsletter Templates → open one → **Preview** |
| `module-cms/**` | the CMS page save above, plus a widget/block render on the frontend |
| `module-catalog/**` | product + category save, frontend product page |
| `module-checkout/**`, `module-quote/**`, `module-sales/**` | the full checkout above |
| `module-customer/**` | the customer account block above |
| `pub/errors/**` | trigger a 404 and confirm the error page renders (not a blank 500) |
| `framework/**` | no single screen — widen coverage rather than picking one |

A patch that hardens an admin ACL check (StyleSmuggler's shape) needs the **negative** case too:
log in as a restricted admin role without that resource and confirm the screen is now denied.
Ask the user whether such a role exists before creating one.
4. **Full run** for a patch touching `framework/`, checkout or `magento2-base`, and before
   anything reaches staging: `magento-e2e-test` before and after, then compare.

## Raising the PR

Patch PRs are short: provenance (URL, source file, sha256 you computed) and guidance on what a
reviewer should exercise. Follow `pr-template.md`. Verification evidence belongs in the chat,
not the description. **Go and find the advisory URL.** An out-of-band `VULN-xxxxx` bundle normally has an Adobe
  Commerce KB announcement at
  `experienceleague.adobe.com/en/docs/commerce-knowledge-base/kb/announcements/commerce-apsb26-<nnn>`.
  The filename gives the VULN id, not the APSB id — map one to the other and link it.
  "No public URL" is a last resort, not a first answer.

Still run the verification before raising the PR — it just doesn't go in the description.

## Gotchas

- Cloud stores keep the root copy only — `magento2-base` in `vendor/` is never patched by a
  hotfix, and detection accounts for that. On a composer-mode store both copies must match.
- **Reinstalling `magento/magento2-base` silently reverts every patched file**, and
  `patches.lock.json` still claims they're applied. A `partial` verdict is usually this.
- Order matters: reach the target release patch level first, *then* isolated patches. A store
  below the current patch level cannot take the current isolated patch.
- Host PHP ≠ container PHP. Don't judge stack compliance from `php -v` on the host.
- Never apply patches unasked. Report first.
- `setup:di:compile` failing after a patch usually means the patch applied against the wrong
  version and left a broken signature. Re-check the patch level before debugging the compile.
- An ad-hoc patch is **not** a substitute for the release patch level. It fixes one CVE on the
  version you are on; the next quarterly release still has to happen.
- Empty `patches[]` means "nothing applies", never "nothing is wrong". Check
  `blockedByPatchLevel` before calling a store patched.
- **A fully patched store can still ship a broken release.** Bugs introduced *inside* a
  release need patches that never reach the registry, so `check.py` reports nothing wrong.
  `known-issues.md` carries the ones seen so far, with detection steps — check it on any
  upgrade or patch-level move.
