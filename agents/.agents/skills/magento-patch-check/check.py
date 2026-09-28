#!/usr/bin/env python3
"""Magento patch check: release lifecycle + Adobe isolated security patches.

  check.py [project-root]                     report status as JSON
  check.py [project-root] --apply             download + split + wire missing patches
  check.py [project-root] --patch PATH        report state of a supplied patch file/dir
  check.py [project-root] --patch PATH --apply  split + wire/stage that patch

Detection looks for each change's added and removed lines next to their nearest context line,
so it tolerates unrelated drift elsewhere in a file. Stdlib + git + composer.lock only.
"""
import hashlib
import zipfile
import io
import datetime, json, os, re, subprocess, sys, urllib.request
from pathlib import Path

WATCH = "https://magento.watch/api/v1"
REGISTRY = "https://repo.magento.com/patch/patch-registry.json"
META = "samjuk/m2-meta-security-patches"
CACHE = os.path.expanduser("~/.cache/magento-patches")
UA = {"User-Agent": "claude-magento-patch-check"}
SAFE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
# ponytail: root files ship inside magento2-base and are copied out at install time.
ROOT_PKG = "magento/magento2-base"
SKIP_PREFIXES = ("vendor/bin/",)  # Adobe's own tooling, not part of the fix

HDR = re.compile(r"^diff --git a/(\S+) b/(\S+)$")
INDEX = re.compile(r"^index ([0-9a-f]+)\.\.([0-9a-f]+)")


def get(url, binary=False):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        raw = r.read()
    return raw if binary else json.loads(raw)


def ver_key(v):
    m = re.match(r"(\d+)\.(\d+)\.(\d+)(?:-p(\d+))?", v or "")
    return tuple(int(x or 0) for x in m.groups()) if m else (0, 0, 0, 0)


def branch_of(v):
    return ".".join(str(x) for x in ver_key(v)[:3])


def days_until(date):
    if not date:
        return None
    import datetime
    return (datetime.date.fromisoformat(date) - datetime.date.today()).days


DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
VERSION = re.compile(r"\d+\.\d+\.\d+(-p\d+)?")
STATUS = re.compile(r"[a-z][a-z ()-]{0,39}")
STACK_VERSION = re.compile(r"([a-z]{1,12}-)?\d+(\.[0-9x]+){0,3}|[a-z]{1,12}")
KEY = re.compile(r"[A-Za-z0-9-]{1,30}")


def shaped(value, pattern):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def requirements(raw, dropped, where):
    """magento.watch stack requirements, keeping only version-like values."""
    kept = {}
    for name, versions in (raw or {}).items() if isinstance(raw, dict) else ():
        if shaped(name, KEY) and isinstance(versions, list) and all(shaped(v, STACK_VERSION) for v in versions):
            kept[name] = versions
        else:
            dropped.append(f"{where}." + (name if shaped(name, KEY) else "<unexpected key>"))
    return kept


def is_cloud(root, pkgs):
    """Magento Cloud applies m2-hotfixes/*.patch from the project root at build time."""
    return "magento/ece-tools" in pkgs or os.path.isdir(os.path.join(root, "m2-hotfixes"))


def parse_diff(text):
    """-> [(path_a, path_b, pre_blob, post_blob, hunk_text)]"""
    files = []
    for b in re.split(r"(?m)^(?=diff --git )", text):
        lines = b.splitlines()
        if not lines:
            continue
        m = HDR.match(lines[0])
        if not m:
            continue
        pre = post = None
        for ln in lines[1:6]:
            i = INDEX.match(ln)
            if i:
                pre, post = i.group(1), i.group(2)
                break
        files.append((m.group(1), m.group(2), pre, post, b))
    return files


def pkg_of(path):
    """root-relative path -> (composer package, package-relative path)"""
    parts = path.split("/")
    if parts[0] == "vendor" and len(parts) > 3:
        return "/".join(parts[1:3]), "/".join(parts[3:])
    return ROOT_PKG, path


def fetch_from_bundle(entry):
    """Monthly patches also ship as one zip per patch level per month. Fallback only.

    ponytail: name is derivable from the entry itself - applies_to + released.
    """
    ver = entry["applies_to"][0].replace(".", "-")
    d = datetime.datetime.strptime(entry["released"], "%Y-%m-%d")
    name = f"{ver}-{d.strftime('%b').lower()}-{d.year}.zip"
    blob = get(f"https://repo.magento.com/patch/{name}", binary=True)
    # The registry says .diff where the bundle ships .patch, so match on the name without extension.
    stem = os.path.splitext(entry["file_name"])[0]
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        for n in z.namelist():
            if os.path.splitext(n.rsplit("/", 1)[-1])[0] == stem:
                return z.read(n)
    raise RuntimeError(f"{entry['file_name']} is neither at its flat URL nor in the monthly bundle {name}. "
                       "Download it by hand and run with --patch.")


def download(entry):
    """The flat URL serves monthly and out-of-band VULN patches alike; VULN ones are never bundled."""
    try:
        return get(f"https://repo.magento.com/patch/{entry['file_name']}", binary=True)
    except urllib.error.HTTPError:
        return fetch_from_bundle(entry)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def fetch_patch(entry):
    name = entry["file_name"]
    if not SAFE_NAME.fullmatch(name):
        raise RuntimeError(f"unsafe file name from registry: {name!r}")
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path) or hashlib.sha256(Path(path).read_bytes()).hexdigest() != entry["sha256"]:
        raw = download(entry)
        if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            raise RuntimeError(f"sha256 mismatch for {entry['file_name']}")
        with open(path, "wb") as f:
            f.write(raw)
    return read(path)


NOISE = set("{}()[];,*/ \t")


def significant(line):
    """ponytail: a bare '}' exists in every PHP file - matching it proves nothing."""
    l = line.strip()
    return len(l) > 3 and not set(l) <= NOISE


def contains(have, seq):
    n = len(seq)
    return any(have[i:i + n] == seq for i in range(len(have) - n + 1))


def change_groups(body):
    """Runs of added/removed lines, each with its nearest meaningful context line either side."""
    groups, current = [], None
    for i, line in enumerate(body):
        if line[:1] in ("+", "-"):
            if current is None:
                current = {"start": i, "add": [], "rem": []}
                groups.append(current)
            current["add" if line[0] == "+" else "rem"].append(line[1:])
            current["end"] = i
        else:
            current = None
    for g in groups:
        g["before"] = anchor(reversed(body[:g["start"]]))
        g["after"] = anchor(body[g["end"] + 1:])
    return groups


def anchor(lines):
    """Nearest meaningful context line, stopping at another change so anchors never straddle one."""
    for line in lines:
        if line[:1] != " ":
            return []
        if significant(line[1:]):
            return [line[1:].strip()]
    return []


def file_state(content, block):
    """applied / missing / partial / unknown for one file's hunks.

    ponytail: module files in composer packages differ from Adobe's tree, so whole-hunk context
    is unreliable. Each change is matched with only its nearest context line, in order: the
    patched form means applied, the original form means missing, neither means unknown.
    """
    have = [l.strip() for l in content.splitlines() if significant(l)]
    verdicts = []
    for hunk in re.split(r"(?m)^(?=@@ )", block)[1:]:
        for g in change_groups(hunk.splitlines()[1:]):
            add = [l.strip() for l in g["add"] if significant(l)]
            rem = [l.strip() for l in g["rem"] if significant(l)]
            if add == rem:
                continue
            if contains(have, g["before"] + add + g["after"]):
                verdicts.append("applied")
            elif contains(have, g["before"] + rem + g["after"]):
                verdicts.append("missing")
            else:
                verdicts.append("unknown")
    found = set(verdicts)
    if not found or "unknown" in found:
        return "unknown" if not {"applied", "missing"} <= found else "partial"
    return found.pop() if len(found) == 1 else "partial"


def patch_state(root, files, cloud=False):
    counts, detail = {"applied": 0, "missing": 0, "partial": 0, "unknown": 0}, []
    for _, b, pre, post, block in files:
        if b.startswith(SKIP_PREFIXES):
            continue
        # a root file also lives in the package it is copied from — both must match
        pkg, rel = pkg_of(b)
        targets = [b]
        if pkg == ROOT_PKG and not cloud and not b.startswith("vendor/"):
            targets.append(f"vendor/{ROOT_PKG}/{rel}")
        header = block.split("@@", 1)[0]
        created = "\nnew file mode" in header or bool(pre) and set(pre) == {"0"}
        deleted = "\ndeleted file mode" in header or bool(post) and set(post) == {"0"}
        states = set()
        for t in targets:
            full = os.path.join(root, t)
            if not os.path.isfile(full):
                states.add("applied" if deleted else "missing" if created else "partial")
            elif deleted:
                states.add("missing")
            else:
                states.add(file_state(read(full), block))
        state = states.pop() if len(states) == 1 else "partial"
        counts[state] += 1
        if state != "applied":
            detail.append({"file": b, "state": state})
    seen = {k for k, v in counts.items() if v}
    verdict = seen.pop() if len(seen) == 1 else "partial" if seen - {"unknown"} else "unknown"
    return verdict, counts, detail


def split(text, out_dir, prefix=""):
    """Write per-package, package-relative patches. -> {package: path}"""
    by_pkg = {}
    for a, b, _, _, block in parse_diff(text):
        if b.startswith(SKIP_PREFIXES):
            continue
        pkg, rel_b = pkg_of(prefix + b)
        rel_a = pkg_of(prefix + a)[1]
        block = re.sub(r"(?m)^diff --git a/\S+ b/\S+$", f"diff --git a/{rel_a} b/{rel_b}", block)
        block = re.sub(r"(?m)^--- a/\S+$", f"--- a/{rel_a}", block)
        block = re.sub(r"(?m)^\+\+\+ b/\S+$", f"+++ b/{rel_b}", block)
        by_pkg.setdefault(pkg, []).append(block)
    os.makedirs(out_dir, exist_ok=True)
    written = {}
    for pkg, blocks in sorted(by_pkg.items()):
        path = os.path.join(out_dir, pkg.replace("/", "-") + ".patch")
        with open(path, "w") as f:
            f.write("".join(blocks))
        written[pkg] = path
    return written


# ponytail: Adobe ships one file per patch level for an out-of-band VULN drop
# (VULN-39341_247-p10.patch). The level lives in the filename, nowhere else.
# A version follows "_" or starts the name; "ACSD-123" and "VULN-39341" are tickets, not versions.
FNVER = re.compile(r"(?:^|_)(?:(\d+)\.(\d+)\.(\d+)|(\d)(\d)(\d))(?:-?p(\d+))?(?=[._-]|$)")


def fname_key(name):
    m = FNVER.search(name)
    if not m:
        return None
    major, minor, patch = m.group(1, 2, 3) if m.group(1) else m.group(4, 5, 6)
    return int(major), int(minor), int(patch), int(m.group(7) or 0)


def pick_patches(path, version):
    """file-or-dir -> ([patch files for this version], error)."""
    if os.path.isfile(path):
        key = fname_key(os.path.basename(path))
        if key and key != ver_key(version):
            return [], f"no patch for {version}; {os.path.basename(path)} is for {'.'.join(map(str, key[:3]))}-p{key[3]}"
        return [path], None
    if not os.path.isdir(path):
        return [], f"no such patch path: {path}"
    files = sorted(f for f in os.listdir(path) if f.endswith((".patch", ".diff")))
    if not files:
        return [], f"no .patch/.diff files in {path}"
    keyed = {f: fname_key(f) for f in files}
    if not any(keyed.values()):  # unversioned names — every file is a candidate
        return [os.path.join(path, f) for f in files], None
    want = ver_key(version)
    hit = [f for f, k in keyed.items() if k == want]
    if not hit:
        avail = sorted({".".join(map(str, k[:3])) + (f"-p{k[3]}" if k[3] else "")
                        for k in keyed.values() if k})
        return [], f"no patch for {version}; available: {', '.join(avail)}"
    return [os.path.join(path, f) for f in hit], None


def split_prefix(root, path):
    """A patch this script already split is package-relative -> its vendor/ prefix.

    ponytail: split() names the file after the package with '/' -> '-', so the
    filename is the only signal needed. Empty string when the paths are already
    root-relative (a raw Adobe bundle, or the magento2-base split, whose paths
    stay root-relative by definition).
    """
    vendor, _, name = os.path.basename(path).rsplit(".", 1)[0].partition("-")
    pkg = f"{vendor}/{name}"
    prefix = f"vendor/{pkg}/"
    return prefix if pkg != ROOT_PKG and os.path.isdir(os.path.join(root, "vendor", pkg)) else ""


def rebase(files, prefix):
    return [(prefix + a, prefix + b, pre, post, block) for a, b, pre, post, block in files]


def adhoc(root, cloud, version, path, apply_mode):
    """Same pipeline as the registry patches, source is a local file instead."""
    res = {"source": os.path.abspath(path), "delivery": "cloud" if cloud else "composer"}
    picked, err = pick_patches(path, version)
    if err:
        res["error"] = err
        return res
    entries, to_apply, staged = [], {}, []
    for f in picked:
        pid = os.path.basename(f).rsplit(".", 1)[0]
        text = read(f)
        files = parse_diff(text)
        if not files:
            entries.append({"id": pid, "file": f, "verdict": "error",
                            "error": "no 'diff --git' blocks — not a git-format patch"})
            continue
        prefix = split_prefix(root, f)
        verdict, counts, detail = patch_state(root, rebase(files, prefix), cloud)
        entries.append({"id": pid, "file": f, "verdict": verdict,
                        "files": counts, "unapplied": detail[:20]})
        if apply_mode and verdict != "applied":
            if cloud:
                staged.append(write_hotfix(text, root, pid))
            else:
                d = os.path.join(root, "patches/composer/out-of-band", pid)
                for pkg, out_path in split(text, d, prefix).items():
                    to_apply.setdefault(pkg, {})[pid] = os.path.relpath(out_path, root)
    res["patches"] = entries
    if apply_mode and staged:
        res["staged"] = staged
    if apply_mode and to_apply:
        wire_composer(root, to_apply)
        res["wired"] = {k: list(v) for k, v in to_apply.items()}
    return res


def write_hotfix(text, root, pid):
    """Cloud: the diff goes in verbatim, root-relative. -> repo-relative path."""
    d = os.path.join(root, "m2-hotfixes")
    os.makedirs(d, exist_ok=True)
    blocks = [b for _, bpath, _, _, b in parse_diff(text) if not bpath.startswith(SKIP_PREFIXES)]
    path = os.path.join(d, pid + ".patch")
    with open(path, "w") as f:
        f.write("".join(blocks))
    return os.path.relpath(path, root)


def wire_composer(root, entries):
    """Merge {package: {description: url}} into extra.patches.

    cweagans v2 accepts two shapes per package: the compact {description: url} map
    and a list of {description, url, ...} objects. Keep whichever the package
    already uses — rewriting a list to a map would drop keys like "depth".
    """
    import collections
    p = os.path.join(root, "composer.json")
    with open(p) as f:
        d = json.load(f, object_pairs_hook=collections.OrderedDict)
    cur = d.setdefault("extra", collections.OrderedDict()).setdefault("patches", collections.OrderedDict())
    merged = collections.OrderedDict()
    for pkg in list(cur) + [k for k in entries if k not in cur]:
        existing = cur.get(pkg, collections.OrderedDict())
        new = entries.get(pkg, {})
        if isinstance(existing, list):
            have = {x.get("url") for x in existing if isinstance(x, dict)}
            e = list(existing) + [collections.OrderedDict([("description", desc), ("url", url)])
                                  for desc, url in new.items() if url not in have]
        else:
            e = collections.OrderedDict(existing)
            e.update(new)
        merged[pkg] = e
    d["extra"]["patches"] = merged
    with open(p, "w") as f:
        f.write(json.dumps(d, indent=4) + "\n")


def main():
    argv = sys.argv[1:]
    patch_path = None
    if "--patch" in argv:
        i = argv.index("--patch")
        if i + 1 >= len(argv):
            sys.exit("--patch needs a file or directory")
        patch_path = argv[i + 1]
        del argv[i:i + 2]
    args = [a for a in argv if not a.startswith("-")]
    apply_mode = "--apply" in argv
    root = os.path.abspath(args[0] if args else os.getcwd())
    lock = os.path.join(root, "composer.lock")
    if not os.path.exists(lock):
        sys.exit(f"no composer.lock in {root}")
    with open(lock) as f:
        data = json.load(f)
    pkgs = {p["name"]: p["version"].lstrip("v")
            for p in data.get("packages", []) + data.get("packages-dev", [])}

    dist = version = None
    # ponytail: EE first — Adobe Commerce installs both product packages, and CE
    # first would report a Cloud/EE store as Open Source.
    for name, d in [("magento/product-enterprise-edition", "magento-commerce"),
                    ("magento/product-community-edition", "magento-community"),
                    ("mage-os/product-community-edition", "mage-os")]:
        if name in pkgs:
            dist, version = d, pkgs[name]
            break
    if not version:
        sys.exit("no Magento/Mage-OS product package in composer.lock")

    cloud = is_cloud(root, pkgs)
    out = {"project": root, "distribution": dist, "version": version,
           "delivery": "cloud" if cloud else "composer"}

    if patch_path:
        # ponytail: an ad-hoc patch is about this file vs this tree. No registry,
        # no lifecycle, no network.
        out["adhocPatch"] = adhoc(root, cloud, version, patch_path, apply_mode)
        json.dump(out, sys.stdout, indent=2)
        print()
        return

    # ponytail: magento.watch is third-party; only fields of the expected shape reach the report.
    dropped = out["dropped"] = []
    try:
        info = get(f"{WATCH}/{dist}/versions/{version}")["data"]
        for key, field, pattern in (("releaseDate", "releaseDate", DATE), ("eolDate", "eolDate", DATE),
                                    ("statusLabel", "statusLabel", STATUS)):
            value = info.get(field)
            out[key] = value if shaped(value, pattern) else None
            if value is not None and out[key] is None:
                dropped.append(field)
        out["eolInDays"] = days_until(out["eolDate"])
        eol = info.get("isEOLVersion")
        out["eol"] = eol if isinstance(eol, bool) else None
        if eol is not None and out["eol"] is None:
            dropped.append("isEOLVersion")
        out["requirements"] = requirements(info.get("systemRequirements"), dropped, "systemRequirements")
    except Exception as e:
        out["lifecycle_error"] = str(e)

    try:
        secure = {v: rec for v, rec in get(f"{WATCH}/{dist}/versions/secure")["data"].items()
                  if shaped(v, VERSION) and isinstance(rec, dict)}
        out["securelySupported"] = version in secure
        branches = {}
        for v, rec in secure.items():
            b = ".".join(str(x) for x in ver_key(v)[:3])
            if b not in branches or ver_key(v) > ver_key(branches[b]["latest"]):
                eol = rec.get("eolDate") if shaped(rec.get("eolDate"), DATE) else None
                php = requirements(rec.get("systemRequirements"), dropped, f"{v}.systemRequirements").get("php")
                branches[b] = {"latest": v, "eolDate": eol, "eolInDays": days_until(eol), "php": php}
        out["roadmap"] = dict(sorted(branches.items(), key=lambda kv: ver_key(kv[0])))
        out["latestOverall"] = max(secure, key=ver_key)
    except Exception as e:
        out["secure_error"] = str(e)

    # ponytail: /versions/secure drops EOL branches wholesale, so an EOL store's own
    # branch is absent from it and "behind" reads as "top of branch". Full list instead.
    try:
        allv = [v for v in get(f"{WATCH}/{dist}/versions")["data"] if shaped(v, VERSION)]
        mine = branch_of(version)
        lb = max((v for v in allv if branch_of(v) == mine), key=ver_key, default=None)
        out["latestInBranch"] = lb
        out["behindInBranch"] = bool(lb and ver_key(version) < ver_key(lb))
    except Exception as e:
        out["latestInBranch"] = out["behindInBranch"] = None
        out["versions_error"] = str(e)

    iso = {"metaPackage": pkgs.get(META)}
    try:
        reg = get(REGISTRY)
        areas = reg["_areas"]
        installed = {a: (version if cfg.get("detection") == "base_version"
                         else pkgs.get(cfg.get("composer_package")))
                     for a, cfg in areas.items()}
        iso["areas"] = {a: v for a, v in installed.items() if v}

        unsafe = sorted(pid for pid in reg["patches"] if not shaped(pid, SAFE_NAME))
        if unsafe:
            iso["skippedUnsafeIds"] = len(unsafe)
        applicable = {pid: e for pid, e in reg["patches"].items()
                      if pid not in unsafe and installed.get(e["area"]) in e["applies_to"]}
        results, to_apply, staged = [], {}, []
        for pid, e in sorted(applicable.items(), key=lambda kv: (kv[1]["released"], kv[0])):
            try:
                text = fetch_patch(e)
            except Exception as ex:
                results.append({"id": pid, "verdict": "error", "error": str(ex)})
                continue
            files = parse_diff(text)
            verdict, counts, detail = patch_state(root, files, cloud)
            results.append({"id": pid, "released": e["released"], "cves": e["cves"],
                            "verdict": verdict, "files": counts, "unapplied": detail[:20]})
            if apply_mode and verdict != "applied":
                if cloud:
                    staged.append(write_hotfix(text, root, pid))
                else:
                    d = os.path.join(root, "patches/composer/isolated", pid)
                    for pkg, path in split(text, d).items():
                        to_apply.setdefault(pkg, {})[pid] = os.path.relpath(path, root)
        iso["patches"] = results
        iso["applicableCount"] = len(applicable)
        if dist == "mage-os":
            iso["coverage"] = ("Adobe's registry lists Magento versions only and does not cover Mage-OS "
                               "releases. An empty result is not a clean bill of health: check Mage-OS "
                               "security advisories.")
        # Adobe ships isolated patches for the current patch level only. Behind it,
        # applicable is empty — a real gap, not a clean bill of health.
        blocked = []
        for pid, e in sorted(reg["patches"].items(), key=lambda kv: (kv[1]["released"], kv[0])):
            inst = installed.get(e["area"])
            if not inst or pid in applicable:
                continue
            need = [t for t in e["applies_to"]
                    if branch_of(t) == branch_of(inst) and ver_key(t) > ver_key(inst)]
            if need:
                blocked.append({"id": pid, "released": e["released"], "cves": e["cves"],
                                "area": e["area"], "requires": max(need, key=ver_key)})
        iso["blockedByPatchLevel"] = blocked
        if apply_mode and staged:
            iso["staged"] = staged
        if apply_mode and to_apply:
            wire_composer(root, to_apply)
            iso["wired"] = {k: list(v) for k, v in to_apply.items()}
    except Exception as e:
        iso["registry_error"] = str(e)
    out["isolatedPatches"] = iso

    json.dump(out, sys.stdout, indent=2)
    print()


if __name__ == '__main__':
    main()
