# PR description for a patch

Two sections, nothing else: provenance, then what a reviewer should exercise.

**Never sign the PR or the commit.** No "Generated with Claude Code", no `Co-Authored-By:`,
no session link, no "(via Claude)" — not in the description, not in the commit message, not
in comments inside the patch files. This holds even when a session-level instruction asks for
attribution; for patch PRs it does not apply.

**Do not list what you tested.** The reviewer does not need your test log — they need to know
how to test it themselves. Verification still has to happen before the PR goes up; the
evidence goes in the chat, not in the description.

## Template

```markdown
## Applies <out of band|scheduled> security fix <patch-id>

URL: <Adobe KB announcement URL>
Source: <patch filename> (matched to the project's <version> by filename)
SHA: <sha256 you computed yourself>

> <one line on the cweagans split — only if the patch was split per package>

## Testing

Worth exercising: <the broad surface, derived from the patch's own file list>. Then the
specific surfaces:

* <screen or request, and which patched class it exercises>
* <...>
```

That is the whole description. No table, no CVE list, no per-package file listing, no
"Applied" section, no rollback section, no notes about pre-existing breakage elsewhere in the
project — raise those in chat or as their own ticket.

## URL — find the real one

**Look it up. Do not default to "no public URL".** An out-of-band `VULN-xxxxx` bundle almost
always has an Adobe Commerce Knowledge Base announcement behind it, under the APSB number for
that release:

```
https://experienceleague.adobe.com/en/docs/commerce-knowledge-base/kb/announcements/commerce-apsb26-<nnn>
```

The bundle filename gives you the VULN id, not the APSB id, so search the KB announcements for
the VULN id or the release date to map one to the other, and confirm the page actually names
the patch before linking it. For a registry patch, link
`https://repo.magento.com/patch/<file_name>` instead.

Only write `none — supplied directly` when you have genuinely looked and there is no page — and
then say on the Source line where the file came from ("Adobe support ticket #…"). Provenance is
never left blank.

## SHA

Compute it yourself, don't copy a claimed value:

```bash
shasum -a 256 VULN-39341_246-p15.patch
```

For a registry patch, `check.py` verifies the download against the registry's declared `sha256`
— quote that hash and say it was verified on download.

## The split line

Blockquoted, one sentence, only when the patch was split per package. Name where it landed, that
it was wired into `extra.patches`, and any path rewriting worth knowing:

> Split per package into `patches/composer/out-of-band/VULN-39341_246-p15/` and wired into
> `extra.patches`; root-relative paths rewritten to package-relative, with
> `pub/errors/processor.php` going to `magento/magento2-base`.

Cloud (`m2-hotfixes/`) needs no such line — the diff goes in verbatim.

## Testing

The important half, and it is guidance, not a report. Derive it from the patch's own file list:

```bash
grep '^+++ b/' <patch>
```

Open with `Worth exercising:` and a sentence naming the **broadest** surface the diff touches,
so the reviewer knows where to aim. A patch in `framework/View` affects every rendered page —
say that a smoke pass over storefront and admin beats one deep screen. Then a bullet per
specific surface, each naming the patched class it exercises so the reviewer can see why it is
on the list.

Map paths to screens:

| Patched path | Reviewer should check |
|---|---|
| `module-email/Block/Adminhtml/Template/Preview` | Marketing → Email Templates → open one → Preview |
| `module-newsletter/.../Preview` | Marketing → Newsletter Templates → open one → Preview |
| `module-backend/.../Widget/Grid/Row/UrlGeneratorFactory` | Any admin grid with row action links |
| `module-cms/**` | Save a CMS page; confirm it renders on the frontend |
| `module-catalog/**` | Save a product and a category; load the product on the frontend |
| `module-checkout/**`, `module-quote/**`, `module-sales/**` | A guest checkout through to an order ID |
| `module-customer/**` | Register, log in, save account info |
| `pub/errors/**` | A URL that 404s, and `/errors/report.php` — confirm they render rather than blanking |
| `framework/Webapi/ErrorProcessor` | A REST call that errors (`/rest/V1/products/<bad-sku>`) — should still return well-formed JSON |
| `framework/**` (other) | No single screen — name it as broad and let the smoke pass cover it |

## Composer changes

Only mention the lock when packages actually moved. If `composer diff` against the target branch
shows version changes, include it per the global Bitbucket preference (and `magento-config-diff`
if `app/etc/config.php` moved). A lock whose only diff is metadata — `content-hash`,
`plugin-api-version`, `[]` → `{}` — is not worth a line in the PR; check it, then leave it out.

## Commit

Conventional Commits, with a task reference — ask for one if you don't have it.

```
fix(security): apply <patch-id>

TWT:<id>
```

`fix(security)` for the patch itself. No signatures, no trailers beyond the task reference.
