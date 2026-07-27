#!/usr/bin/env bash
set -euo pipefail

missing=0

require_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'doctor ok: %s=%s\n' "$tool" "$(command -v "$tool")"
  else
    printf 'doctor missing required tool: %s\n' "$tool" >&2
    missing=1
  fi
}

require_tool bash
require_tool cargo
require_tool git
require_tool just
require_tool python3

if command -v jankurai >/dev/null 2>&1; then
  actual="$(jankurai --version 2>/dev/null || true)"
  if [[ "$actual" == "jankurai 1.6.11" ]]; then
    printf 'doctor ok: jankurai=%s\n' "$actual"
  else
    printf 'doctor wrong jankurai version: expected jankurai 1.6.11, got %s\n' "${actual:-unknown}" >&2
    missing=1
  fi
else
  printf 'doctor missing required tool: jankurai\n' >&2
  missing=1
fi

exit "$missing"
