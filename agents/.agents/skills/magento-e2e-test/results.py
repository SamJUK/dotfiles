#!/usr/bin/env python3
"""Summarise one e2e run, or compare two. Reads the bundled harness's results.json or a
Playwright JSON report (--reporter=json).

    results.py summary RUN.json
    results.py compare BEFORE.json AFTER.json
"""
import json
import re
import sys

ANSI = re.compile(r'\x1b\[[0-9;]*m')


def playwright(suite, trail=()):
    for spec in suite.get('specs', []):
        for test in spec.get('tests', []):
            name = ' › '.join(filter(None, (*trail, spec['title'], test.get('projectName'))))
            status = {'expected': 'pass', 'unexpected': 'fail', 'flaky': 'flaky',
                      'skipped': 'skip'}.get(test.get('status'), test.get('status'))
            notes = [a.get('description') or a.get('type') for a in test.get('annotations', [])]
            errors = [ANSI.sub('', e.get('message', '')).strip().splitlines()[0]
                      for r in test.get('results', []) for e in r.get('errors', []) if e.get('message')]
            yield name, status, '; '.join(filter(None, notes + errors))[:300]
    for child in suite.get('suites', []):
        yield from playwright(child, (*trail, child.get('title', '')))


def load(path):
    with open(path) as stream:
        data = json.load(stream)
    if 'results' in data and isinstance(data['results'], list):
        rows = ((r['name'], 'pass' if r['ok'] else 'fail', r.get('detail', '')) for r in data['results'])
    elif 'suites' in data:
        rows = (row for suite in data['suites'] for row in playwright(suite, (suite.get('title', ''),)))
    else:
        raise SystemExit(f'{path}: not a harness results.json or Playwright JSON report')
    return {name: (status, detail) for name, status, detail in rows}


def summary(path):
    run = load(path)
    counts = {}
    for status, _ in run.values():
        counts[status] = counts.get(status, 0) + 1
    print(', '.join(f'{n} {s}' for s, n in sorted(counts.items())))
    for status in ('fail', 'flaky', 'skip'):
        for name, (s, detail) in run.items():
            if s == status:
                print(f'{status.upper():6} {name}' + (f'\n       {detail}' if detail else ''))
    return 1 if counts.get('fail') else 0


def compare(before_path, after_path):
    before, after = load(before_path), load(after_path)
    groups = {'REGRESSION': [], 'FIXED': [], 'STILL FAILING': [], 'CHANGED': [], 'NEW': [], 'REMOVED': []}
    for name in sorted(before.keys() | after.keys()):
        old, new = before.get(name, (None,))[0], after.get(name, (None,))[0]
        if old is None:
            groups['NEW'].append((name, new))
        elif new is None:
            groups['REMOVED'].append((name, old))
        elif old != 'fail' and new == 'fail':
            groups['REGRESSION'].append((name, after[name][1]))
        elif old == 'fail' and new == 'pass':
            groups['FIXED'].append((name, ''))
        elif old == new == 'fail':
            groups['STILL FAILING'].append((name, ''))
        elif old != new:
            groups['CHANGED'].append((name, f'{old} -> {new}'))
    for group, items in groups.items():
        for name, detail in items:
            print(f'{group:14} {name}' + (f'  ({detail})' if detail else ''))
    print(', '.join(f'{len(v)} {k.lower()}' for k, v in groups.items()))
    return 1 if groups['REGRESSION'] else 0


if __name__ == '__main__':
    command, *paths = sys.argv[1:] or ['']
    if command == 'summary' and len(paths) == 1:
        sys.exit(summary(*paths))
    if command == 'compare' and len(paths) == 2:
        sys.exit(compare(*paths))
    sys.exit(__doc__)
