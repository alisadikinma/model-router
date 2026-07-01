#!/usr/bin/env python3
"""Minimal JSONC loader for router config — no deps.

Strips `//` comments (full-line and trailing). A negative lookbehind protects
`://` inside values, so URLs survive. ponytail ceiling: breaks only if a STRING
value contains `//` not preceded by ':' (e.g. "a//b") — our config has none.

CLI:  python3 lib/jsonc.py <config> [dotted.path]
      no path  -> prints whole config as JSON
      path     -> prints the value (scalars raw, dict/list as JSON)
"""
import json
import re
import sys


def load(path):
    raw = open(path).read()
    clean = re.sub(r'(?<!:)//.*$', '', raw, flags=re.M)
    return json.loads(clean)


def get(d, dotted):
    for k in dotted.split('.'):
        d = d[k]
    return d


if __name__ == '__main__':
    cfg = load(sys.argv[1])
    if len(sys.argv) > 2:
        v = get(cfg, sys.argv[2])
        print(v if not isinstance(v, (dict, list)) else json.dumps(v))
    else:
        print(json.dumps(cfg))
