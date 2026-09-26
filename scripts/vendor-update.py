#!/usr/bin/env python3
"""Propose new pins for vendor.ini entries. Shows upstream changes; rewrites a pin only on a yes."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from importlib.util import module_from_spec, spec_from_file_location

spec = spec_from_file_location('installer', Path(__file__).resolve().parent / 'install-links.py')
installer = module_from_spec(spec)
spec.loader.exec_module(installer)


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def target(entry):
    url, track = entry['url'], entry['track']
    if track == 'latest-release':
        slug = re.sub(r'^https://github\.com/|\.git$', '', url)
        tag = run('gh', 'api', f'repos/{slug}/releases/latest', '--jq', '.tag_name')
        refs = run('git', 'ls-remote', url, f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}').splitlines()
        return tag, refs[-1].split()[0]
    ref = 'HEAD' if track == 'HEAD' else f'refs/heads/{track}'
    line = run('git', 'ls-remote', url, ref).splitlines()
    if not line:
        raise ValueError(f'{entry["name"]}: {track} not found')
    return 'default branch' if track == 'HEAD' else track, line[0].split()[0]


def review(entry, new):
    with tempfile.TemporaryDirectory() as tmp:
        run('git', 'init', '-q', cwd=tmp)
        run('git', 'remote', 'add', 'origin', entry['url'], cwd=tmp)
        run('git', 'fetch', '-q', '--filter=blob:none', 'origin', entry['sha'], new, cwd=tmp)
        scope = [] if entry['path'] == '.' else ['--', entry['path']]
        print(run('git', 'log', '--oneline', f'{entry["sha"]}..{new}', *scope, cwd=tmp) or '(no commits touch this path)')
        print(run('git', 'diff', '--stat', entry['sha'], new, *scope, cwd=tmp))
        if ask('Show full diff?'):
            subprocess.run(['git', '--no-pager', 'diff', entry['sha'], new, *scope], cwd=tmp, check=True)


def ask(question):
    return input(f'{question} [y/N] ').strip().lower() == 'y'


def main():
    check = '--check' in sys.argv
    if not check and not sys.stdin.isatty():
        raise ValueError('Run interactively to review updates, or use --check.')
    home = Path.home().resolve()
    private = Path(os.environ.get('DOTFILES_PRIVATE', home / 'dotfiles-private')).expanduser()
    outdated = 0
    for repo in (installer.PUBLIC, private):
        for entry in installer.read_manifest(repo):
            label, new = target(entry)
            if new == entry['sha']:
                print(f'{entry["name"]}: up to date ({label})')
                continue
            outdated += 1
            print(f'\n== {entry["name"]}: {entry["sha"][:12]} -> {new[:12]} ({label})')
            if check:
                continue
            review(entry, new)
            if ask(f'Pin {entry["name"]} to {new[:12]}?'):
                manifest = entry['manifest']
                manifest.write_text(manifest.read_text().replace(entry['sha'], new, 1))
                print(f'Updated {manifest}. Review, commit, then run install.sh.')
    return 1 if check and outdated else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)
