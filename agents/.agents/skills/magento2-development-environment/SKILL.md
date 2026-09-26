---
name: magento2-development-environment
description: How to run commands in a local Magento 2 / Mage-OS development environment, whatever it is built on. Finds the project's own documented commands first, then detects Warden, DDEV, Docker Compose or host PHP, and maps everyday tasks (shell, bin/magento, composer, database connect/import/dump, mail, Xdebug, Redis) to the right command. Use whenever working in a Magento 2 project locally, or when another skill needs to run bin/magento or reach the database (magento-upgrade, magento-smoke-test, magento-validate-migrations).
---

# Magento 2 development environment

## 1. Use what the project documents

Check, in order, and prefer what you find over this file:

- README, AGENTS.md, CLAUDE.md, and any loaded rules
- `make help` when there is a `Makefile`; read the target before running it
- `.ddev/commands/` or other project scripts

## 2. Detect the tooling

| Signal | Environment |
|---|---|
| `.warden/warden-env.yml`, or `WARDEN_ENV_TYPE` in `.env` | Warden |
| `.ddev/config.yaml` | DDEV |
| `docker-compose.yml` / `compose.yaml` with a PHP service | Docker Compose: run commands in that service |
| none of the above, `bin/magento` present | host PHP |

Say which one you found. Container PHP is not host PHP: never judge versions from `php -v` on
the host.

## 3. Commands

| Task | Warden | DDEV |
|---|---|---|
| Start / stop | `warden env up` / `down` (global services: `warden svc up`) | `ddev start` / `ddev stop` |
| Shell | `warden shell` | `ddev ssh` |
| `bin/magento` | `warden shell -c "bin/magento …"` | `ddev magento …` or `ddev exec bin/magento …` |
| Composer | `warden shell -c "composer …"` | `ddev composer …` |
| Database client | `warden db connect` (`-e "<sql>"` for one query) | `ddev mysql` (MySQL/MariaDB projects) |
| Database dump | `warden db dump \| gzip > <file>.sql.gz` | `ddev export-db --file=<file>.sql.gz` |
| Database import | `gunzip -c <file>.sql.gz \| warden db import` | `ddev import-db --file=<file>.sql.gz` |
| Mail (Mailpit) | `https://webmail.warden.test/` | `ddev launch -m` |
| Xdebug | `warden debug` (a debug-enabled shell) | `ddev xdebug on` / `off` |
| Redis flush | `warden redis flushall` | `ddev redis-cli flushall` (Redis add-on) |
| Local TLS certificate | `warden sign-certificate <domain> [more domains]` | automatic |

On the host, run the same commands directly, using the database credentials in `env.php`.

## 4. Before anything destructive

A database import, a drop, or any target that reinstalls or resets (`make install`,
`make reset` and similar) replaces local data. Dump the database first, outside the repo, and
get the user's OK. Warden's Mailpit is shared by every project on the machine: never clear all
of its messages.

## 5. Things that catch people out

- **`env.php` overrides the database.** Values under `system` in `env.php` or `config.php`
  win over `core_config_data`. If a setting looks wrong in the database but the site behaves
  as if it were right (or the reverse), check there before editing the table.
  `bin/magento config:show <path> --scope=websites --scope-code=<code>` shows the resolved value.
- **`env.php` is usually git-ignored.** A committed template (for example
  `app/etc/env.warden.php`) is the source of truth; edits to `env.php` itself are lost on reinstall.
- **Git LFS dumps.** If `.gitattributes` uses `filter=lfs`, install Git LFS before pulling, or
  database dumps arrive as pointer files.
- **Several domains, one environment.** Check the environment's routing config (Warden:
  Traefik rules and `extra_hosts` in `.warden/warden-env.yml`) before assuming one domain.
- **`generated/`, `var/cache` and `var/page_cache` are safe to clear** when state looks stale;
  Magento rebuilds them.
- **Check upstream before debugging custom code.** Search `magento/magento2` issues for the
  symptom, and Adobe's quality patches catalogue for an official fix:
  `gh api repos/magento/quality-patches/contents/patches-info.json --jq .content | base64 -d`
  (write it to your scratch area, not the repo). If the project installs
  `magento/quality-patches`, `vendor/bin/magento-patches status` answers the same locally.
