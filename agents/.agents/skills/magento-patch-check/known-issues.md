# Known Magento issues that the registry will not tell you about

Bugs shipped *inside* a release, so `check.py` reports the store as fully patched while a
core feature is broken. Each one needs a patch that is not an Adobe security patch and will
never appear in `patch-registry.json`.

---

## AC-15165 — SRI hashes corrupted for bundled JS, breaks checkout

**Adobe KB:** [ka-27997](https://experienceleague.adobe.com/en/docs/experience-cloud-kcs/kbarticles/ka-27997)
**Internal ticket:** AC-15165

CSP changes generate Subresource Integrity hashes with **incorrect file paths** for minified
JS when bundling is enabled. `mixins.min.js` and `static.min.js` then fail to load on checkout
pages, so orders cannot be placed.

**Affected releases:** 2.4.8 p3–p5 · 2.4.7 p8–p10 · 2.4.6 p13–p15 · 2.4.5 p15–p17

**Trigger conditions:** JS bundling *and* minification on — `dev/js/enable_js_bundling` and
`dev/js/minify_files`, in `core_config_data` or locked in `env.php`. No bundling, no bug.

### Detecting it

It is **invisible in developer mode** — no hashes are generated at all there. Check in
production mode, and compare the files on disk against the hash file rather than trusting a
hash file exists:

```bash
# production-mode static deploy (MAGE_MODE override avoids switching the store's real mode)
warden env exec -T -e MAGE_MODE=production php-fpm bash -lc '
  rm -rf pub/static/frontend pub/static/adminhtml pub/static/_cache var/view_preprocessed/*
  php -dmemory_limit=-1 bin/magento setup:static-content:deploy --force -q --jobs 2 en_GB en_US'

# how many bundled min files exist, and how many of them have no SRI entry
warden env exec -T php-fpm php -r '
$d = json_decode(file_get_contents("pub/static/frontend/sri-hashes.json"), true);
$n = $missing = 0;
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator("pub/static/frontend")) as $f) {
    if (!in_array($f->getFilename(), ["mixins.min.js", "static.min.js"], true)) continue;
    $n++;
    if (!isset($d[substr($f->getPathname(), strlen("pub/static/"))])) $missing++;
}
echo "total entries: " . count($d) . " | bundled files: $n | without a hash: $missing\n";'
```

| | broken | fixed |
|---|---|---|
| total entries | thousands, generated against wrong paths (17,016 on one store) | small — one `requirejs-config.min.js` per theme/locale (12 + 2) |
| bundled files without a hash | all of them | n/a, they are no longer in scope |

The **drop in coverage after patching is correct**, not a second bug. Adobe documents the
trade-off: the revert restores the narrower pre-AC-15165 scope, but the hashes it does
generate are right.

### Severity depends on CSP mode

`Magento_Csp` ships with `csp/mode/storefront/report_only` and `csp/mode/admin/report_only`
set to **1**. In report-only mode nothing is enforced, no `integrity=` attributes render, and
checkout keeps working — the patch is then **preventative**, and stops a corrupt hash file
being produced. It becomes **urgent** before switching CSP to restrict mode.

Check before deciding how loudly to report it:

```bash
warden db connect -e "select path, scope, value from <prefix>core_config_data where path like 'csp/%';"
# no rows = module defaults = report_only = not currently enforced
```

### Fixing it

Revert patch against `magento/module-csp`, 12 files, **package-relative so no `depth`**:

```json
"magento/module-csp": {
    "Revert AC-15165 - fixes SRI hash corruption with JS bundling (ka-27997)":
        "patches/revert-AC-15165-sri-hash-corruption.patch"
}
```

Copies of both variants live in client projects that hit ka-27997. Grep their `composer.json`
`extra.patches` for `AC-15165` to find one rather than rewriting it.

**Match the patch to the `magento/module-csp` version, not to the release patch level in the
filename.** The file named `2.4.8-p3` applies unchanged to a 2.4.8-p5 store, because both ship
`module-csp` **100.4.7-p3**. Check first:

```bash
grep -m1 '"version"' vendor/magento/module-csp/composer.json
patch -p1 --dry-run -i <patch> -d vendor/magento/module-csp   # exit 0 = clean
```

Adobe publishes **three** version-specific builds of this revert covering the different
release ranges. If the local copy does not apply, pull the matching one from the KB rather
than forcing it.

After wiring: `composer patches-relock && composer patches-repatch`, then `setup:di:compile`,
then re-deploy static content and re-run the detection above.
