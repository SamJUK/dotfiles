#!/usr/bin/env python3
"""Plan the Stow packages and agent integrations before changing the target home."""
import argparse
import configparser
import difflib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime

PACKAGES = 'zsh git ansible nvim ghostty warp btop sublime vscode composer agents claude pi warden ddev'.split()
INTEGRATIONS = {'.gitconfig', '.claude/CLAUDE.md'}
VENDOR_DIR = '.local/share/dotfiles/vendor'
SAFE_NAME = re.compile(r'[A-Za-z0-9._-]+')


def git(cwd, *args):
    return subprocess.run(['git', '-C', str(cwd), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def read_manifest(repo):
    path = repo / 'vendor.ini'
    if not path.is_file():
        return []
    parser = configparser.ConfigParser(interpolation=None, default_section='-',
                                       inline_comment_prefixes=('#', ';'))
    parser.read_string(path.read_text(), source=str(path))
    entries = []
    for name in parser.sections():
        section = parser[name]
        where = f'{path} [{name}]'
        unknown = set(section) - {'url', 'commit', 'path', 'link', 'track'}
        if unknown:
            raise ValueError(f'{where}: unknown keys {", ".join(sorted(unknown))}')
        if not SAFE_NAME.fullmatch(name):
            raise ValueError(f'{where}: invalid name')
        if not section.get('url'):
            raise ValueError(f'{where}: url is required')
        sha = section.get('commit', '')
        if not re.fullmatch(r'[0-9a-f]{40}', sha):
            raise ValueError(f'{where}: commit must be a full 40-character hash')
        sub, dest = section.get('path', '.'), section.get('link', '-')
        for value in (sub, dest):
            if value.startswith('/') or '..' in Path(value).parts:
                raise ValueError(f'{where}: paths must be relative and stay inside: {value}')
        entries.append(dict(name=name, url=section['url'], sha=sha, path=sub, dest=dest,
                            track=section.get('track', 'HEAD'), manifest=path))
    return entries


def vendor_state(checkout, sha):
    if not (checkout / '.git').is_dir():
        if present(checkout):
            raise ValueError(f'{checkout} exists but is not a vendor checkout; move it aside.')
        return 'fetch'
    if git(checkout, 'status', '--porcelain'):
        raise ValueError(f'Local changes in {checkout}; discard them, vendor checkouts are pinned.')
    return 'unchanged' if git(checkout, 'rev-parse', 'HEAD') == sha else 'update'


def fetch(entry):
    checkout, sha = entry['checkout'], entry['sha']
    if not (checkout / '.git').is_dir():
        checkout.mkdir(parents=True)
        git(checkout, 'init', '-q')
        git(checkout, 'remote', 'add', 'origin', entry['url'])
        if entry['path'] != '.':
            git(checkout, 'sparse-checkout', 'set', '--no-cone', '/' + entry['path'].strip('/') + '/')
    extra = ['--filter=blob:none'] if entry['path'] != '.' else []
    git(checkout, 'fetch', '-q', '--depth', '1', *extra, 'origin', sha)
    git(checkout, '-c', 'advice.detachedHead=false', 'checkout', '-q', '--detach', sha)
    if git(checkout, 'rev-parse', 'HEAD') != sha:
        raise ValueError(f'{entry["name"]}: checkout does not match pinned {sha}')


def present(path):
    return path.exists() or path.is_symlink()


def physical(path):
    return path.parent.resolve() / path.name


def fingerprint(path):
    if not present(path):
        return None
    info = path.lstat()
    return (info.st_dev, info.st_ino, info.st_mode, info.st_mtime_ns, info.st_size,
            os.readlink(path) if path.is_symlink() else None,
            (path.stat().st_mtime_ns, path.stat().st_size) if path.is_file() else None)


def block(text, name, body, markdown=False):
    start = f'<!-- BEGIN {name} -->' if markdown else f'# BEGIN {name}'
    end = f'<!-- END {name} -->' if markdown else f'# END {name}'
    replacement = f'{start}\n{body.rstrip()}\n{end}\n'
    if start in text or end in text:
        if text.count(start) != 1 or text.count(end) != 1 or text.index(start) > text.index(end):
            raise ValueError(f'Malformed {name} block; resolve it before installing.')
        return re.sub(re.escape(start) + r'.*?' + re.escape(end) + r'\n?',
                      lambda _: replacement, text, count=1, flags=re.S)
    return text.rstrip('\n') + ('\n\n' if text else '') + replacement


class Plan:
    def __init__(self, home):
        self.home = home
        self.entries = {}
        self.packages = []
        self.owners = {}
        self.stow_ignored = set(INTEGRATIONS)
        self.backup = None
        self.saved = []
        self.vendored = {}

    def link(self, source, dest, owner, stow=False, mirror=False, pending=False):
        source = source.absolute()
        if not pending and not source.exists():
            raise ValueError(f'Missing or broken source: {source}')
        if stow:
            for parent in dest.parents:
                if parent == self.home:
                    break
                if parent.is_symlink() and parent.is_dir():
                    self.stow_ignored.add(parent.relative_to(self.home).as_posix())
                    stow = False
        key = physical(dest)
        if key in self.entries:
            old = self.entries[key]
            if mirror and old.get('source') == source:
                return
            raise ValueError(f'Two sources claim {dest}: {old["owner"]} and {owner}')
        self.entries[key] = dict(dest=dest, physical=key, source=source, owner=owner,
                                 stow=stow, kind='link')

    def package(self, repo, name):
        source = repo / name
        if not source.is_dir():
            raise ValueError(f'Missing package: {source}')
        self.packages.append((repo, name))
        linked_skills = set()
        for item in sorted(source.rglob('*')):
            if item.is_dir() and not item.is_symlink():
                continue
            relative = item.relative_to(source)
            if relative.as_posix() in INTEGRATIONS and repo == PUBLIC:
                continue
            # Stow's default ignore rules include README and VCS metadata.
            if any(p in {'.git', '__pycache__', '.DS_Store'} for p in relative.parts):
                continue
            if relative.parts[:2] == ('.agents', 'skills'):
                skill = relative.parts[2]
                previous = self.owners.setdefault(skill, repo)
                if previous != repo:
                    raise ValueError(f'Skill {skill} belongs to both {previous} and {repo}')
                skill_path = Path(*relative.parts[:3])
                if (self.home / skill_path).is_symlink():
                    if skill not in linked_skills:
                        self.link(source / skill_path, self.home / skill_path, str(repo / name))
                        self.stow_ignored.add(skill_path.as_posix())
                        linked_skills.add(skill)
                    continue
            self.link(item, self.home / relative, str(repo / name), stow=True)

    def vendor(self, entry):
        name = entry['name']
        if name in self.vendored:
            raise ValueError(f'Vendor entry {name} is declared twice: {self.vendored[name]["manifest"]} and {entry["manifest"]}')
        checkout = self.home / VENDOR_DIR / name
        self.vendored[name] = dict(entry, checkout=checkout, action=vendor_state(checkout, entry['sha']))
        if entry['dest'] == '-':
            return
        dest = Path(entry['dest'])
        if dest.parts[:2] == ('.agents', 'skills'):
            skill = dest.parts[2]
            if skill in self.owners:
                raise ValueError(f'Skill {skill} belongs to both {self.owners[skill]} and vendor manifest {entry["manifest"]}')
            self.owners[skill] = entry['manifest']
        source = checkout if entry['path'] == '.' else checkout / entry['path']
        self.link(source, self.home / dest, f'vendor:{name}', pending=True)

    def integrate(self, dest, body, markdown=False, equivalent=None):
        key = physical(dest)
        if key in self.entries:
            raise ValueError(f'Integration collides with a package: {dest}')
        if equivalent and dest.is_symlink() and dest.resolve() == equivalent.resolve():
            return
        if present(dest) and not dest.is_file():
            if not dest.is_symlink() or dest.exists():
                raise ValueError(f'Expected an instruction/config file, found {dest}')
            text = ''
        else:
            text = dest.read_text() if dest.exists() else ''
        wanted = body.strip().splitlines()
        if 'BEGIN dotfiles' not in text and all(line in text.splitlines() for line in wanted):
            return
        content = block(text, 'dotfiles', body, markdown)
        self.entries[key] = dict(dest=dest, physical=key, kind='text', content=content,
                                 previous=text, owner='integration', stow=False)

    def inspect(self):
        for key, item in self.entries.items():
            parent = key.parent
            while parent != parent.parent:
                if parent in self.entries:
                    raise ValueError(f'File/directory collision: {parent} and {key}')
                if present(parent) and not parent.is_dir():
                    raise ValueError(f'Parent is not a directory: {parent}')
                parent = parent.parent
            if item['kind'] == 'link':
                same = item['dest'].resolve() == item['source'].resolve()
                item['action'] = 'unchanged' if same else 'conflict' if present(key) else 'link'
            else:
                same = key.is_file() and key.read_text() == item['content']
                item['action'] = 'unchanged' if same else 'conflict' if key.is_symlink() else 'integrate'
            item['before'] = fingerprint(key)
            item['mode'] = stat.S_IMODE(key.stat().st_mode) if key.is_file() else 0o600

    def preview(self):
        counts = {}
        for entry in self.vendored.values():
            if entry['action'] != 'unchanged':
                counts[entry['action']] = counts.get(entry['action'], 0) + 1
                print(f'{entry["action"].upper():10} {entry["name"]} @ {entry["sha"][:12]} from {entry["url"]} ({entry["path"]})')
        for item in self.entries.values():
            action = item['action']
            counts[action] = counts.get(action, 0) + 1
            if action == 'unchanged':
                continue
            suffix = f' -> {item["source"]}' if item['kind'] == 'link' else ''
            if item['dest'] != item['physical']:
                suffix += f' (resolved destination: {item["physical"]})'
            print(f'{action.upper():10} {item["dest"]}{suffix}')
        print(', '.join(f'{n} {name}' for name, n in sorted(counts.items())))

    def diff(self, item):
        path = item['physical']
        if path.is_dir():
            print(f'{path} is a directory; replacement would back up that directory.')
            return
        try:
            old = path.read_text() if path.exists() else ''
            new = item['source'].read_text() if item['kind'] == 'link' else item['content']
        except (UnicodeError, OSError) as error:
            print(f'Text diff unavailable: {error}')
            return
        print(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                         fromfile=str(path), tofile='proposed')), end='')

    def resolve(self):
        conflicts = [i for i in self.entries.values() if i['action'] == 'conflict']
        if len(conflicts) > 1:
            while True:
                answer = input(f'{len(conflicts)} conflicts: [r]eview individually, [k]eep all, [b]ack up and replace all, [q]uit [r]: ').lower()
                if answer in ('', 'r'):
                    break
                if answer in ('k', 'b'):
                    for item in conflicts:
                        item['action'] = 'keep' if answer == 'k' else 'replace'
                    return
                if answer == 'q':
                    raise ValueError('Cancelled; no changes applied.')
        for item in self.entries.values():
            if item['action'] != 'conflict':
                continue
            while True:
                answer = input(f'{item["dest"]}: [k]eep, [d]iff, [b]ack up and replace, [q]uit [k]: ').lower()
                if answer in ('', 'k'):
                    item['action'] = 'keep'
                    break
                if answer == 'd':
                    self.diff(item)
                elif answer == 'b':
                    item['action'] = 'replace'
                    break
                elif answer == 'q':
                    raise ValueError('Cancelled; no changes applied.')

    def save(self, item):
        path = item['physical']
        if not present(path):
            return
        if self.backup is None:
            parent = self.home / '.local/state/dotfiles/backups'
            parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            self.backup = Path(tempfile.mkdtemp(prefix=datetime.now().strftime('%Y%m%d-%H%M%S-'), dir=parent))
            print(f'Backups: {self.backup}')
        saved = self.backup / str(len(self.saved) + 1)
        # Rename symlinks themselves; never modify their old targets.
        shutil.move(str(path), str(saved))
        self.saved.append(dict(original=str(path), backup=str(saved)))
        (self.backup / 'manifest.json').write_text(json.dumps(self.saved, indent=2) + '\n')

    def apply(self):
        if any(i['action'] == 'conflict' for i in self.entries.values()):
            raise ValueError('Resolve conflicts before applying the plan.')
        for item in self.entries.values():
            if physical(item['dest']) != item['physical'] or fingerprint(item['physical']) != item['before']:
                raise ValueError(f'Changed since preview; rerun the installer: {item["dest"]}')
        for entry in self.vendored.values():
            if entry['action'] != 'unchanged':
                fetch(entry)
        try:
            for item in self.entries.values():
                if item['action'] not in ('keep', 'unchanged'):
                    self.save(item)
            ignored = [r'^' + re.escape(name) + '$' for name in sorted(self.stow_ignored)]
            ignored += [r'^' + re.escape(str(i['dest'].relative_to(self.home))) + '$'
                        for i in self.entries.values() if i['stow'] and i['action'] == 'keep']
            for repo, package in self.packages:
                subprocess.run(['stow', '--dir=' + str(repo), '--target=' + str(self.home),
                                '--no-folding', '--restow',
                                *['--ignore=' + pattern for pattern in ignored], package], check=True)
            for item in self.entries.values():
                if item['stow'] or item['action'] in ('keep', 'unchanged'):
                    continue
                path = item['physical']
                path.parent.mkdir(parents=True, exist_ok=True)
                if item['kind'] == 'link':
                    path.symlink_to(item['source'])
                else:
                    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, item['mode'])
                    with os.fdopen(fd, 'w') as stream:
                        stream.write(item['content'])
            for item in self.entries.values():
                if item['action'] == 'keep':
                    continue
                path = item['dest']
                if item['kind'] == 'link':
                    valid = path.exists() and path.resolve() == item['source'].resolve()
                else:
                    valid = path.is_file() and path.read_text() == item['content']
                if not valid:
                    raise ValueError(f'Installed path does not match the plan: {path}')
            if self.backup:
                print(f'Original files and symlinks are recorded in {self.backup / "manifest.json"}')
        except Exception:
            print('Install stopped. Restoring backed-up paths; newly created links may remain.', file=sys.stderr)
            for record in reversed(self.saved):
                path = Path(record['original'])
                if path.is_symlink() or path.is_file():
                    path.unlink()
                elif path.exists():
                    print(f'Cannot restore over directory {path}; use {record["backup"]}', file=sys.stderr)
                    continue
                shutil.move(record['backup'], path)
            raise


def build(home, private, work):
    plan = Plan(home)
    for package in PACKAGES:
        plan.package(PUBLIC, package)
    if private:
        for package in (private / '.stow-packages').read_text().split():
            if '/' in package or package.startswith('.'):
                raise ValueError(f'Invalid private package name: {package}')
            plan.package(private, package)
    if work:
        for skill in sorted((work / 'skills').glob('*/')):
            if skill.name in plan.owners:
                raise ValueError(f'Skill {skill.name} belongs to both {plan.owners[skill.name]} and {work}')
            plan.owners[skill.name] = work
            plan.link(skill, home / '.agents/skills' / skill.name, str(work))
        plan.link(work / 'AGENTS.md', home / '.agents/rules/bed.md', str(work))
    for repo in (PUBLIC, private):
        if repo:
            for entry in read_manifest(repo):
                plan.vendor(entry)
    for item in list(plan.entries.values()):
        relative = item['dest'].relative_to(home)
        if relative.parts[:2] in (('.agents', 'skills'), ('.agents', 'rules')):
            plan.link(item['source'], home / '.claude' / Path(*relative.parts[1:]),
                      item['owner'], mirror=True, pending=True)
    plan.integrate(home / '.gitconfig', (PUBLIC / 'git/.gitconfig').read_text())
    plan.integrate(home / '.claude/CLAUDE.md', '@~/.agents/AGENTS.md', markdown=True,
                   equivalent=PUBLIC / 'claude/.claude/CLAUDE.md')
    # Codex and pi read one global file each: link it when free so the shared instructions are loaded directly.
    for agent in (home / '.codex/AGENTS.md', home / '.pi/agent/AGENTS.md'):
        if agent.is_symlink() and Path(os.path.normpath(agent.parent / os.readlink(agent))) == home / '.agents/AGENTS.md':
            pass
        elif not present(agent):
            plan.link(PUBLIC / 'agents/.agents/AGENTS.md', agent, str(PUBLIC / 'agents'))
        else:
            plan.integrate(agent,
                           'Read `~/.agents/AGENTS.md` and `~/.agents/rules/*.md` and follow their instructions.',
                           markdown=True, equivalent=PUBLIC / 'agents/.agents/AGENTS.md')
    plan.inspect()
    return plan


PUBLIC = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='preview only; return nonzero for conflicts')
    parser.add_argument('--yes', action='store_true', help='apply only if there are no unresolved conflicts')
    parser.add_argument('--full', action='store_true', help='also install workstation dependencies')
    args = parser.parse_args()
    home = Path.home().resolve()
    private = Path(os.environ.get('DOTFILES_PRIVATE', home / 'dotfiles-private')).expanduser().resolve()
    work = Path(os.environ.get('BED_DEV_TOOLS', home / 'Projects/bed/dev-tools')).expanduser().resolve()
    for variable, repo, marker in [('DOTFILES_PRIVATE', private, '.stow-packages'), ('BED_DEV_TOOLS', work, 'AGENTS.md')]:
        if variable in os.environ and not (repo / marker).is_file():
            raise ValueError(f'{variable} does not point to an overlay: {repo}')
    plan = build(home, private if (private / '.stow-packages').is_file() else None,
                 work if (work / 'AGENTS.md').is_file() else None)
    plan.preview()
    if args.full:
        print(f'Workstation dependencies: Homebrew + {PUBLIC / "Brewfile"} (may install or upgrade listed packages).')
        print('Composer: install the global lockfile when the dotfiles Composer config is selected.')
    conflicts = any(i['action'] == 'conflict' for i in plan.entries.values())
    if args.check:
        return int(conflicts)
    if conflicts and (args.yes or not sys.stdin.isatty()):
        raise ValueError('Conflicts need a decision. Run interactively, or resolve them and rerun --check. --yes never overwrites them.')
    if not args.yes:
        if not sys.stdin.isatty():
            raise ValueError('No terminal. Use --check, or --yes after reviewing the plan.')
        plan.resolve()
        plan.preview()
        if input('Apply this plan? [y/N] ').lower() != 'y':
            return 1
    if args.full:
        if sys.platform != 'darwin':
            raise ValueError('The full workstation installer supports macOS. Use manual linking on other systems.')
        for prefix in ('/opt/homebrew', '/usr/local'):
            if (Path(prefix) / 'bin/brew').exists():
                os.environ['PATH'] = f'{prefix}/bin:{prefix}/sbin:' + os.environ['PATH']
                break
        subprocess.run([str(PUBLIC / 'scripts/install-dependencies.sh')], check=True)
        if not shutil.which('stow'):
            for prefix in ('/opt/homebrew', '/usr/local'):
                if (Path(prefix) / 'bin/stow').exists():
                    os.environ['PATH'] = f'{prefix}/bin:{prefix}/sbin:' + os.environ['PATH']
                    break
    elif not shutil.which('stow'):
        raise ValueError('GNU Stow is required to apply links. Install it first, or run install.sh.')
    plan.apply()
    if args.full:
        if (home / '.composer/composer.json').resolve() == (PUBLIC / 'composer/.composer/composer.json').resolve():
            subprocess.run(['composer', 'global', 'install', '--working-dir=' + str(home / '.composer')], check=True)
        print('Links installed. Enable the optional secret-scanning hook with: pre-commit install')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)
