#!/usr/bin/env bash
set -euo pipefail

# BEGIN GENERATED JANKURAI PIN — DO NOT EDIT
# The governed Jankurai identity is the binary installed on this host and its
# installation receipt: require_jankurai verifies both and exports JERYU_JANKURAI_*
# from the receipt. The one pin of record is jeryu-tool's tool-manifest.toml.
# END GENERATED JANKURAI PIN

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

# Resolve and verify the absolute governed auditor before any lane runs.
source ops/ci/lib.sh
require_jankurai

# Ordinary compilation -- cargo check, the lib/bin, property, migration and contract test builds --
# builds in the gate runner's retained build cache when the gate host offers one
# (JERYU_CI_BUILD_CACHE_DIR; jeryu-ci-runner ops/pr-gate/README.md, "Reusing ordinary compilation
# without retaining proof"). Nothing this gate runs measures a build directory: there is no coverage
# or profile build and no lane reads a binary out of target/, and every report it writes
# (.jankurai/, target/jankurai/, target/security/, target/artifact-support/) goes to a literal path
# outside the cache. Unset (a laptop, another host), cargo builds into target/ as before.
# BEGIN BUILD CACHE GUARD
if [ -n "${JERYU_CI_BUILD_CACHE_DIR:-}" ]; then
  cache_dir="$JERYU_CI_BUILD_CACHE_DIR"
  cache_top="$repo_root"
  # A source archive has no index. In a checkout, inspect this repository's index,
  # even when the caller supplied Git directory, worktree or index overrides.
  if [ -e "$cache_top/.git" ]; then
    tracked_target="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
      git --git-dir="$cache_top/.git" --work-tree="$cache_top" ls-files -- target)" || exit 1
    if [ -n "$tracked_target" ]; then
      echo "refusing build cache: target/ contains tracked files" >&2
      exit 1
    fi
  fi
  # Accept only this checkout's physical cache owned by this user.
  if [[ -L "$cache_top/target" || -L "$cache_dir" || ! -d "$cache_dir" || ! -O "$cache_dir" \
        || "$(cd "$cache_dir" && pwd -P)" != "$(cd "$cache_top" && pwd -P)/target/build-cache" ]]; then
    echo "refusing JERYU_CI_BUILD_CACHE_DIR=$cache_dir: only this checkout's physical target/build-cache is accepted" >&2
    exit 1
  fi
  CARGO_TARGET_DIR="$(cd "$cache_dir" && pwd -P)"
  export CARGO_TARGET_DIR CARGO_INCREMENTAL=0
  echo "[pr-ci] ordinary compilation in ${CARGO_TARGET_DIR} (the gate runner's build cache)" >&2
fi
# END BUILD CACHE GUARD
./scripts/ci-doctor.sh
./ops/ci/fast.sh
./ops/ci/check.sh
./ops/ci/property_tests.sh
./ops/ci/migration_drift.sh
./ops/ci/contract_drift.sh
./ops/ci/score.sh
./ops/ci/security.sh
./ops/ci/release.sh
./ops/ci/artifact_support.sh

echo "[pr-ci] jankurai evidence lane (ratchet against the forge's protected main)" >&2
bash ops/ci/proof_evidence.sh
