#!/usr/bin/env python3
"""Lint agent skills. Pass SKILL.md files or directories to search (default: agents/.agents/skills).

- frontmatter with a name matching the skill's folder, and a description
- no direct fetch of external URLs: route it through a script that returns validated fields,
  or mark a reviewed exception with `lint: allow-fetch` on the same line
- no per-skill "Untrusted content" section: the rule lives once in AGENTS.md
"""
from pathlib import Path
import re
import sys

FETCH = re.compile(r'\b(curl|wget|WebFetch|urlopen|requests\.get)\b')
URL = re.compile(r'https?://([^/\s"\'`)>]+)')
API = re.compile(r'^/(api|v\d+)(/|\b)|\.json\b')
LOCAL = re.compile(r'(^|\.)(localhost|test|localhost:\d+|ddev\.site|example\.(com|org|net))$|^127\.0\.0\.1(:\d+)?$|^\$|^<|^opensearch(:\d+)?$')


def lint(path):
    problems = []
    text = path.read_text()
    front = re.match(r'---\n(.*?)\n---\n', text, re.S)
    if not front:
        problems.append((1, 'missing frontmatter'))
    else:
        name = re.search(r'^name:\s*(\S+)', front.group(1), re.M)
        if not name or name.group(1) != path.resolve().parent.name:
            problems.append((1, f'frontmatter name must be "{path.resolve().parent.name}"'))
        if not re.search(r'^description:\s*\S', front.group(1), re.M):
            problems.append((1, 'frontmatter description is missing'))
    for number, line in enumerate(text.splitlines(), 1):
        if re.match(r'#{2,}\s+Untrusted content\b', line):
            problems.append((number, 'per-skill "Untrusted content" section: the rule lives in AGENTS.md'))
        if 'lint: allow-fetch' in line:
            continue
        external = [m for m in URL.finditer(line) if not LOCAL.search(m.group(1).lower())]
        api = [m for m in external if API.search(line[m.end():].split()[0] if line[m.end():].split() else '')]
        if external and (FETCH.search(line) or api):
            host = (api or external)[0].group(1)
            problems.append((number, f'direct fetch of {host}: use a script that validates the response'))
    return problems


def main(args):
    targets = [Path(a) for a in args] or [Path('agents/.agents/skills')]
    files = []
    for target in targets:
        files += sorted(target.rglob('SKILL.md')) if target.is_dir() else [target]
    failed = False
    for path in files:
        for number, message in lint(path):
            print(f'{path}:{number}: {message}')
            failed = True
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
