#!/usr/bin/env bash
set -euo pipefail

# BEGIN GENERATED JANKURAI PIN — DO NOT EDIT
# The governed Jankurai identity is the binary installed on this host and its
# installation receipt: require_jankurai verifies both and exports JERYU_JANKURAI_*
# from the receipt. The one pin of record is jeryu-tool's tool-manifest.toml.
# END GENERATED JANKURAI PIN

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

# Ordinary compilation -- cargo check, the lib/bin, property, migration and contract test builds --
# builds in the gate runner's retained build cache when the gate host offers one
# (JERYU_CI_BUILD_CACHE_DIR; jeryu-ci-runner ops/pr-gate/README.md, "Reusing ordinary compilation
# without retaining proof"). Nothing this gate runs measures a build directory: there is no coverage
# or profile build and no lane reads a binary out of target/, and every report it writes
# (.jankurai/, target/jankurai/, target/security/, target/artifact-support/) goes to a literal path
# outside the cache. Unset (a laptop, another host), cargo builds into target/ as before.
if [ -n "${JERYU_CI_BUILD_CACHE_DIR:-}" ]; then
  case "${JERYU_CI_BUILD_CACHE_DIR}" in
    /*) export CARGO_TARGET_DIR="${JERYU_CI_BUILD_CACHE_DIR}" ;;
    *) export CARGO_TARGET_DIR="${repo_root}/${JERYU_CI_BUILD_CACHE_DIR}" ;;
  esac
  echo "[pr-ci] ordinary compilation in ${CARGO_TARGET_DIR} (the gate runner's build cache)" >&2
fi
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
