#!/usr/bin/env python3
"""Lifecycle data for Magento versions from magento.watch, reduced to fields of the expected
shape. Anything else is dropped and named under "dropped", so response text never reaches the
agent unchecked.

    watch.py <dist> <version> [<target-version> ...]

dist: magento-community | magento-commerce | mage-os
"""
import json
import re
import sys
import urllib.request

API = 'https://magento.watch/api/v1'
DISTS = {'magento-community', 'magento-commerce', 'mage-os'}
VERSION = re.compile(r'\d+\.\d+\.\d+(-p\d+)?')
DATE = re.compile(r'\d{4}-\d{2}-\d{2}')
WORD = re.compile(r'[a-z][a-z-]{0,29}')
STATUS = re.compile(r'[a-z][a-z ()-]{0,39}')
ADVISORY = re.compile(r'(APSB\d{2}-\d{1,4}|CVE-\d{4}-\d{4,7})')
STACK = {'php', 'composer', 'mysql', 'mariadb', 'elasticsearch', 'opensearch', 'rabbitmq',
         'valkey', 'redis', 'varnish', 'nginx', 'apache', 'activemq', 'aws-aurora-mysql',
         'aws-s3', 'aws-mq', 'aws-elasticache', 'aws-opensearch'}
STACK_VERSION = re.compile(r'([a-z]{1,12}-)?\d+(\.[0-9x]+){0,3}|[a-z]{1,12}')
KEY = re.compile(r'[A-Za-z0-9-]{1,30}')


def get(path):
    request = urllib.request.Request(f'{API}/{path}', headers={'User-Agent': 'magento-upgrade-skill'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)['data']


def keep(value, pattern):
    return isinstance(value, str) and pattern.fullmatch(value)


def clean(info, dropped, where):
    out = {}
    for key, pattern in (('version', VERSION), ('releaseDate', DATE), ('eolDate', DATE), ('statusLabel', STATUS)):
        if keep(info.get(key), pattern):
            out[key] = info[key]
        elif info.get(key) is not None:
            dropped.append(f'{where}.{key}')
    for key in ('isEOLVersion', 'isSecureVersion', 'isLatestVersion'):
        if isinstance(info.get(key), bool):
            out[key] = info[key]
        elif info.get(key) is not None:
            dropped.append(f'{where}.{key}')
    requirements = info.get('systemRequirements')
    if isinstance(requirements, dict):
        for name, versions in requirements.items():
            if name in STACK and isinstance(versions, list) and all(keep(v, STACK_VERSION) for v in versions):
                out.setdefault('requirements', {})[name] = versions
            else:
                dropped.append(f'{where}.systemRequirements.' + (name if keep(name, KEY) else '<unexpected key>'))
    security = info.get('security')
    if isinstance(security, dict):
        if keep(security.get('status'), WORD):
            out['securityStatus'] = security['status']
        for key in ('vulnerableTo', 'fixedBy'):
            ids = [a.get('id') for a in security.get(key) or [] if isinstance(a, dict)]
            out[key] = [i for i in ids if keep(i, ADVISORY)]
            if len(out[key]) != len(ids):
                dropped.append(f'{where}.security.{key}')
    return out


def branch(version):
    return tuple(int(x) for x in version.split('-')[0].split('.')[:3])


def main(argv):
    if len(argv) < 2 or argv[0] not in DISTS or not all(VERSION.fullmatch(v) for v in argv[1:]):
        sys.exit(__doc__)
    dist, versions, dropped = argv[0], argv[1:], []
    listed = [v for v in get(f'{dist}/versions') if keep(v, VERSION)]
    order = lambda v: (branch(v), int(v.split('-p')[1]) if '-p' in v else 0)
    report = {'latestOverall': max(listed, key=order) if listed else None, 'versions': {}}
    for version in versions:
        info = clean(get(f'{dist}/versions/{version}'), dropped, version)
        same = [v for v in listed if branch(v) == branch(version)]
        info['latestInBranch'] = max(same, key=order) if same else None
        report['versions'][version] = info
    report['dropped'] = dropped
    json.dump(report, sys.stdout, indent=2)
    print()


if __name__ == '__main__':
    main(sys.argv[1:])
