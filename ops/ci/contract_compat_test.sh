#!/bin/sh
# Self-test for ops/ci/contract_compat.sh (ADR 0015 in jeryu-deploy docs/adr).
#
# Proves the gate check accepts the committed mirror, and that a mirror which
# drifts from the lock fails with a message that names the consumer and
# classifies every file it saw. Runs against copies under a temporary root, so
# the repository's own mirror and lock are never written.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
script="$here/contract_compat.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  printf 'contract compat self-test failed: %s\n' "$1" >&2
  exit 1
}

# A throwaway copy of the mirror and its lock.
fixture() {
  dest="$tmp/$1"
  rm -rf "$dest"
  mkdir -p "$dest/contracts"
  cp -R "$root/contracts/generated" "$dest/contracts/generated"
  cp "$root/contracts/generated.lock" "$dest/contracts/generated.lock"
  printf '%s\n' "$dest"
}

# 1. The committed mirror matches its committed lock.
out="$(JERYU_CONTRACT_ROOT="$root" sh "$script" 2>"$tmp/err")" ||
  fail "the committed mirror does not match contracts/generated.lock: $(cat "$tmp/err")"
case "$out" in
  'contract compat ok: jeryu-jira -> jeryu-web'*) ;;
  *) fail "unexpected success message: $out" ;;
esac

# 2. A removed, a changed and an added file are each reported, by class, with
#    the consumer named.
case_dir="$(fixture drift)"
rm "$case_dir/contracts/generated/WorkComment.ts"
printf 'export type WorkItem = never;\n' >"$case_dir/contracts/generated/WorkItem.ts"
printf 'export type WorkWidget = string;\n' >"$case_dir/contracts/generated/WorkWidget.ts"
if JERYU_CONTRACT_ROOT="$case_dir" sh "$script" >"$tmp/out" 2>"$tmp/err"; then
  fail 'a drifted mirror passed the check'
fi
for want in \
  'consumer jeryu-web' \
  'removed (breaking for consumer jeryu-web): WorkComment.ts' \
  'changed (breaking unless only fields were added): WorkItem.ts' \
  'added (additive): WorkWidget.ts'
do
  grep -qF "$want" "$tmp/err" || fail "failure message is missing \"$want\": $(cat "$tmp/err")"
done

# 3. A mirror with no lock at all fails, and says how to write one.
case_dir="$(fixture nolock)"
rm "$case_dir/contracts/generated.lock"
if JERYU_CONTRACT_ROOT="$case_dir" sh "$script" >"$tmp/out" 2>"$tmp/err"; then
  fail 'a mirror with no lock passed the check'
fi
grep -qF 'jeryu-jira has no contracts/generated.lock' "$tmp/err" ||
  fail "missing-lock message is wrong: $(cat "$tmp/err")"

# 4. --write records the mirror in front of it, so the drift in case 2 is
#    accepted once the lock moves with it, and the repository's lock is intact.
case_dir="$(fixture rewrite)"
printf 'export type WorkWidget = string;\n' >"$case_dir/contracts/generated/WorkWidget.ts"
JERYU_CONTRACT_ROOT="$case_dir" sh "$script" --write >/dev/null
JERYU_CONTRACT_ROOT="$case_dir" sh "$script" >/dev/null ||
  fail '--write did not produce a lock the check accepts'
grep -qF 'WorkWidget.ts' "$case_dir/contracts/generated.lock" ||
  fail '--write did not record the added file'
if cmp -s "$root/contracts/generated.lock" "$case_dir/contracts/generated.lock"; then
  fail '--write under a temporary root must not match the repository lock'
fi

printf 'contract compat self-test ok: %s\n' "$root"
