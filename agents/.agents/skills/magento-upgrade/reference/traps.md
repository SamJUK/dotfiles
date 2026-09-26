# Upgrade traps

Failure modes seen on real upgrades, each with a way to detect it. Grouped by the phase that
should catch it. Every one of these was found the hard way.

---

## Phase 4 — resolve

### Runtime-asserted dependencies

A module declares almost nothing in `composer.json` and asserts its real requirement at
runtime. Composer resolves happily and the store logs `CRITICAL` on every page load.

Seen: `stripe/module-payments` 4.6.7 declares only `php: >=7.4`, then demands
`stripe/stripe-php ^20.1` at runtime. Upgrading the module from 4.0.3 left the library at
v13 and logged on every request.

```bash
# after the resolve, in production mode, load a few pages then:
grep -iE "CRITICAL|depends on|requires .* or newer" var/log/system.log | sort -u
```

Check the log after **any** third-party module major bump. Composer cannot catch this class.

### Exact pins that cannot resolve

Pinned module versions (`"stripe/module-payments": "4.0.3"`) block the target. Relax to a
caret range on the same major, let composer pick, then verify the module actually supports
the target rather than assuming the resolve proves it.

### require-dev blocking the tree

A `require-dev` constraint like `"symfony/process": "<=v5.4.23"` will block a target that
needs Symfony 6. Dev-only pins are the least obvious cause of an unsolvable resolve.

---

## Phase 5 — compatibility sweep

### LESS bare division (less.php v3 → v5)

Magento 2.4.8 raises `wikimedia/less.php` from v3.2.1 to v5.5.1. **v5 no longer evaluates a
bare `a/b` as division — it emits it literally.** Two distinct symptoms:

**1. Breaks the build.** `ceil(@var/2)` passes a non-number and aborts
`setup:static-content:deploy`. Loud, unmissable.

**2. Compiles clean, emits invalid CSS.** `width: 100%/2;` becomes `width: 100%/2` in the
output. The browser discards the declaration and the layout silently falls back — product
grids drop from three per row to two oversized ones. **SCD exits 0.**

```bash
# run against compiled output, not source
find pub/static -name '*.css' -exec grep -oE \
  "[a-z-]+:[^;{}]*[0-9](%|px|em|rem)?[[:space:]]*/[[:space:]]*[0-9][^;{}]*" {} \; \
  | grep -vE 'calc\(|url\(|^font:|aspect-ratio|grid-|^background:' | sort -u
```

Fix by wrapping: `width: (100% / 2);`. **Do not blanket-replace every `/` in LESS:**

- divisions already inside parentheses — `-(@var/2)` — still evaluate and need nothing
- `calc(100% / 3)` and `font: 12px/1.5` are valid CSS; rewriting them creates the bug

### Dynamic properties (PHP 8.2+)

Creating an undeclared property is deprecated, and developer mode turns the deprecation into
a fatal. A plain grep over-reports badly, because properties declared on a **parent** class
look undeclared in the child's file.

Detect by reflection against the live class tree instead — load the autoloader, walk
`app/code`, compare `$this->foo =` assignments against every property up the inheritance
chain. On one project a naive grep claimed 77 problems across 37 files; reflection found the
real number: 15 across 7.

### Changed library signatures

Monolog 2 → 3 changes `format(array $record)` to `format(LogRecord $record)`. Any `app/code`
class extending a Monolog formatter or handler is a hard fatal in `setup:di:compile`.

```bash
grep -rln 'Monolog\\' app/code --include='*.php'
```

Same shape applies to any major library bump in the dependency diff. Check the diff for
majors, then grep `app/code` for users of each.

### Theme overrides drifting from core

A template or web file copied into `app/design` stops receiving upstream fixes. The upgrade
changes the original underneath it and nothing fails: the override keeps rendering old markup,
old escaping, old JS contracts. Security fixes in core templates are lost this way.

Diff the override's **ancestor**, not the module file. Fallback order, from
`Magento\Framework\View\Design\Fallback\RulePool`:

1. `<theme>/<Module_Name>/templates` (or `/web`), then each parent theme in turn
2. `<module_dir>/view/<area>/…`
3. `<module_dir>/view/base/…`

Non-modular web files (`<theme>/web/…`) fall back through the parent themes, then `lib/web`;
non-modular templates through the parent themes only. Layout XML merges rather than overrides, so skip it unless it sits under
`layout/override/` or `page_layout/override/`.

In recon, before the resolve, copy each override's ancestor to a scratch directory outside the
repo. After the resolve, diff every snapshot against its new version. For each ancestor that
changed, show that upstream diff next to the override and port the change, or record why not.
An unchanged ancestor needs nothing.

---

## Phase 6 — build and output

### SRI hash corruption (AC-15165)

Adobe KB `ka-27997`. CSP changes generate Subresource Integrity hashes with **incorrect
paths** for minified JS when bundling is enabled, so `mixins.min.js` and `static.min.js` fail
to load on checkout pages.

Affects **2.4.8 p3–p5, 2.4.7 p8–p10, 2.4.6 p13–p15, 2.4.5 p15–p17**. Triggered by
`dev/js/enable_js_bundling` + `dev/js/minify_files`.

**Invisible in developer mode** — no hashes are generated there at all. Detect in production:

```bash
php -r '
$d = json_decode(file_get_contents("pub/static/frontend/sri-hashes.json"), true);
$n = $missing = 0;
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator("pub/static/frontend")) as $f) {
    if (!in_array($f->getFilename(), ["mixins.min.js", "static.min.js"], true)) continue;
    $n++;
    if (!isset($d[substr($f->getPathname(), strlen("pub/static/"))])) $missing++;
}
echo "entries: " . count($d) . " | bundled files: $n | without a hash: $missing\n";'
```

Broken: thousands of entries, and every bundled file missing a hash. Fixed: a small file with
one `requirejs-config.min.js` entry per theme/locale. **The drop in coverage after the fix is
correct**, not a second bug — Adobe documents the trade-off.

Severity depends on CSP mode. `csp/mode/*/report_only` defaults to 1, so nothing is enforced
and checkout keeps working — preventative then, urgent before switching to restrict mode.

Fix is a revert patch against `magento/module-csp`, package-relative so no `depth`. Match it
to the **`module-csp` version**, not the release name — a patch named for 2.4.8-p3 applies
unchanged to 2.4.8-p5 because both ship `module-csp` 100.4.7-p3.

### magento2-base reinstall reverts root files

Reinstalling `magento/magento2-base` silently reverts every patched root file
(`lib/web/underscore.js`, `pub/errors/processor.php`) while `patches.lock.json` still claims
they are applied. A `partial` patch verdict is usually this. Re-verify patches after any
`composer reinstall` or `patches-repatch`.

### Stale config cache during setup:upgrade

`setup:upgrade` failing with `<name> indexer does not exist` is usually a stale config cache
rather than a real problem — new modules declare indexers the cached config has not seen.
`bin/magento cache:clean` and re-run before investigating.

---

## Phase 7 — patches

### Isolated patches published after the release

A release does **not** include isolated patches published after its date. A version released
in May still needs June/July/August isolated patches for that patch level. Dropping the old
version's patches without adding the new version's leaves the store *less* patched than
before the upgrade.

### Registry filename mismatches

Adobe's registry records `.diff` filenames while the monthly bundles ship `.patch`, and
out-of-band `VULN-*` patches are not in the monthly bundle at all — they remain at the flat
per-file URL `https://repo.magento.com/patch/<name>.diff`.

Both present as "the patch does not exist". Download by whichever route works, verify the
sha256 against the registry entry, then place it where the tool expects.

### `partial` verdicts that are actually fine

A patch detector reporting `partial` may be looking for *removed* lines that the base release
already dropped. Confirm by checking the patch's **added** lines are present on disk before
believing it. Positive control: point the same check at a superseded patch and confirm it
does report absence.

---

## Known upstream bugs

### special_price_map undefined key (2.4.8)

`Magento\Catalog\Pricing\Render\FinalPriceBox::hasSpecialPrice()` reads
`special_price_map[$id]` without checking the key exists. The related-products block on some
configurable PDPs hits a missing id:

```
Warning: Undefined array key NNNN in .../Pricing/Render/FinalPriceBox.php
```

Neither `special_price_map` nor its `isProductList()` branch exists in 2.4.6, so this arrives
with 2.4.8. **Developer mode only** — the warning is thrown there and suppressed in
production, where the same URLs return 200. Roughly a third of configurable PDPs on one
catalogue. Log noise in production, broken local dev.

---

## Mode differences, summarised

| | developer | production |
|---|---|---|
| PHP warnings | thrown as exceptions → 500 | suppressed, logged |
| SRI hashes | not generated at all | generated during SCD |
| Module runtime assertions | rarely reached | logged as CRITICAL |
| Static content | compiled on demand | must be deployed |

Run the functional suite in **developer** mode, where faults surface loudly. Run the build,
SRI check and log sweep in **production** mode. Restore the original mode afterwards.
