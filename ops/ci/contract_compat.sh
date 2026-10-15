#!/bin/sh
# Contract compatibility check (ADR 0015 in jeryu-deploy docs/adr).
#
# The generated TypeScript mirror under contracts/generated is the contract this
# repository consumes. contracts/generated.lock records the sha256 of every
# mirror file the last reviewed sync carried. Any difference between the two is
# an interface change that must be made on purpose, in the same change as the
# lock, so a reviewer sees it. Usage:
#   ops/ci/contract_compat.sh           check; exit 1 on a mismatch
#   ops/ci/contract_compat.sh --write   rewrite the lock from the mirror
# JERYU_CONTRACT_ROOT overrides the repository root (used by the tests).
set -eu

consumer="jeryu-web"
producer="jeryu-jira"
holder="$producer"  # the repository holding the mirror and the lock
root="${JERYU_CONTRACT_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
dir="$root/contracts/generated"
lock="$root/contracts/generated.lock"

if [ ! -d "$dir" ]; then
  printf 'contract compat failed: %s has no contracts/generated\n' "$holder" >&2
  exit 1
fi

actual="$(cd "$dir" && for f in *.ts; do [ -e "$f" ] && printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"; done | LC_ALL=C sort -k2)"

if [ "${1:-}" = "--write" ]; then
  {
    printf '# contract lock: producer %s, consumer %s (ADR 0015)\n' "$producer" "$consumer"
    printf '# sha256  file; rewrite with ops/ci/contract_compat.sh --write\n'
    printf '%s\n' "$actual"
  } >"$lock"
  printf 'contract compat: wrote %s\n' "$lock"
  exit 0
fi

if [ ! -f "$lock" ]; then
  printf 'contract compat failed: %s has no contracts/generated.lock; run ops/ci/contract_compat.sh --write\n' "$holder" >&2
  exit 1
fi

want="$(grep -v '^#' "$lock" | grep -v '^$' | LC_ALL=C sort -k2 || true)"
removed=""
changed=""
added=""
for name in $(printf '%s\n%s\n' "$want" "$actual" | awk 'NF==2{print $2}' | LC_ALL=C sort -u); do
  w="$(printf '%s\n' "$want" | awk -v n="$name" '$2==n{print $1}')"
  a="$(printf '%s\n' "$actual" | awk -v n="$name" '$2==n{print $1}')"
  if [ -n "$w" ] && [ -z "$a" ]; then
    removed="$removed $name"
  elif [ -z "$w" ] && [ -n "$a" ]; then
    added="$added $name"
  elif [ "$w" != "$a" ]; then
    changed="$changed $name"
  fi
done

if [ -z "$removed$changed$added" ]; then
  printf 'contract compat ok: %s -> %s (%s files)\n' "$producer" "$consumer" "$(printf '%s\n' "$actual" | grep -c .)"
  exit 0
fi

{
  printf 'contract compat failed: contracts/generated (producer %s, consumer %s) differs from contracts/generated.lock.\n' "$producer" "$consumer"
  [ -z "$removed" ] || printf '  removed (breaking for consumer %s):%s\n' "$consumer" "$removed"
  [ -z "$changed" ] || printf '  changed (breaking unless only fields were added):%s\n' "$changed"
  [ -z "$added" ] || printf '  added (additive):%s\n' "$added"
  printf 'Consumer %s must be updated in the same change. Regenerate the contracts from %s,\n' "$consumer" "$producer"
  printf 'review the diff against ADR 0015, then run ops/ci/contract_compat.sh --write and commit the lock.\n'
} >&2
exit 1
