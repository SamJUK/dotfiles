---
name: magento-smoke-test
description: Quick health check of a local Magento 2 / Mage-OS store with plain commands and HTTP requests, no browser or test suite. Deploys as production would (setup:upgrade, setup:di:compile, setup:static-content:deploy), where most bugs surface, then runs CLI status checks, loads the home, customer login, cart and admin login pages, and flags new exceptions or error reports. Use when asked to "smoke test", "quick check the store", "is the store still up", after applying a patch or migration, or when another skill needs a fast before/after check (magento-patch-check, magento-validate-migrations). For a full end-to-end run use magento-e2e-test.
---

# Magento smoke test

No browser: does the store deploy, do the key pages load, and did anything new land in the error
logs? The deploy steps are the core of it: a broken patch, plugin or migration usually fails in
`setup:upgrade`, `setup:di:compile` or `setup:static-content:deploy` before any page loads.
Local stores only.

```sh
smoke.sh [project-root]                          # deploy, status checks, pages, new errors
smoke.sh [project-root] --url https://shop.test  # when the configured base URL is not the local one
SCD_LANGS="en_GB en_US" smoke.sh [project-root]  # locales for static content, default en_US
```

It detects Warden, DDEV or host PHP. It refuses to run unless `env.php` points at a local
database, and refuses a non-local store URL. The exit code is the number of failed checks.

## What it checks

- `setup:upgrade` (without `--keep-generated`), `setup:di:compile`, `setup:static-content:deploy -f`
- `cache:flush`, `setup:db:status`, `app:config:status`
- Home, customer login, cart and admin login pages return 200, render fully and show no Magento
  error page
- No new lines in `var/log/exception.log` and no new files in `var/report` since the run started

## Using it for before/after

Run it before the change and keep the output, then again after. A check failing both times is
pre-existing: report it as such, not as a regression.

## Reporting

List each failed check with its output. Say what was not covered: no checkout, no admin saves,
no JavaScript. If those matter for the change, run `magento-e2e-test`.
