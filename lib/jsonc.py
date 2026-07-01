#!/usr/bin/env python3
"""Minimal JSONC loader for router config — no deps.

Strips `//` line comments while preserving `//` INSIDE string values (URLs,
paths). Works by tokenizing: a match is either a full JSON string or a comment;
only comments are dropped. Handles escaped quotes in strings. No block comments.

CLI:  python3 lib/jsonc.py <config> [dotted.path]
      no path  -> prints whole config as JSON
      path     -> prints the value (scalars raw, dict/list as JSON)
"""
import json
import re
import sys

# match a JSON string (with escapes) OR a // line comment; drop only comments
_TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*')


def load(path):
    raw = open(path).read()
    clean = _TOKEN.sub(lambda m: '' if m.group(0).startswith('//') else m.group(0), raw)
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
