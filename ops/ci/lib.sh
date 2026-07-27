#!/usr/bin/env bash
set -euo pipefail

require_jankurai() {
  local expected="jankurai 1.6.11"
  local actual
  actual="$(jankurai --version 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected %s, got %s\n' "$expected" "${actual:-missing jankurai}" >&2
    exit 1
  fi
}
