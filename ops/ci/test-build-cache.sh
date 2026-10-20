#!/usr/bin/env bash
# Exercise the production guard without running the later compilation lanes.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
mkdir -p "$repo_root/target"
fixture="$(mktemp -d "$repo_root/target/cache-guard-test.XXXXXX")"
mkdir -p "$fixture/local/target/build-cache" "$fixture/foreign/target/build-cache"
{
  printf '%s\n' 'set -euo pipefail' 'repo_root="$1"' 'cd "$repo_root"'
  sed -n '/^# BEGIN BUILD CACHE GUARD$/,/^# END BUILD CACHE GUARD$/p' "$repo_root/ops/ci/pr-ci.sh"
  printf '%s\n' '[[ "$CARGO_TARGET_DIR" == "$repo_root/target/build-cache" && "$CARGO_INCREMENTAL" == 0 ]]'
} > "$fixture/guard.sh"
run_guard() {
  env JERYU_CI_BUILD_CACHE_DIR="$1" bash "$fixture/guard.sh" "$fixture/local" >"$fixture/output" 2>&1
}
refuse() {
  if run_guard "$1"; then
    echo "cache guard accepted $1" >&2
    exit 1
  fi
  grep -q 'refusing' "$fixture/output"
}
# Archives work without Git; physical foreign paths and symlinks are refused.
run_guard "$fixture/local/target/build-cache"
refuse "$fixture/foreign/target/build-cache"
ln -s "$fixture/foreign/target/build-cache" "$fixture/local/linked-cache"
refuse "$fixture/local/linked-cache"
mv "$fixture/local/target" "$fixture/local/saved-target"
ln -s "$fixture/local/saved-target" "$fixture/local/target"
refuse "$fixture/local/target/build-cache"
unlink "$fixture/local/target"
mv "$fixture/local/saved-target" "$fixture/local/target"
# Real indexes prove ambient Git overrides cannot select another repository.
git init -q "$fixture/local"
git init -q "$fixture/foreign"
export GIT_DIR="$fixture/foreign/.git" GIT_WORK_TREE="$fixture/foreign"
export GIT_INDEX_FILE="$fixture/foreign/.git/index" GIT_COMMON_DIR="$fixture/foreign/.git"
run_guard "$fixture/local/target/build-cache"
refuse "$fixture/foreign/target/build-cache"
printf 'tracked\n' > "$fixture/local/target/injected"
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
  git -C "$fixture/local" add -f -- target/injected
refuse "$fixture/local/target/build-cache"
grep -q 'target/ contains tracked files' "$fixture/output"
printf 'build cache guard tests passed\n'
