#!/usr/bin/env bash
# tiny assert helpers for bash tests. ponytail: no framework, just exit-on-fail.
assert_eq() { # expected actual msg
  if [[ "$1" != "$2" ]]; then echo "FAIL: $3 (expected '$1', got '$2')" >&2; exit 1; fi
  echo "ok: $3"
}
assert_contains() { # haystack needle msg
  if [[ "$1" != *"$2"* ]]; then echo "FAIL: $3 (missing '$2')" >&2; exit 1; fi
  echo "ok: $3"
}
assert_not_contains() { # haystack needle msg
  if [[ "$1" == *"$2"* ]]; then echo "FAIL: $3 (should not contain '$2')" >&2; exit 1; fi
  echo "ok: $3"
}
fail() { echo "FAIL: $1" >&2; exit 1; }
