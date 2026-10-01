#!/usr/bin/env bash
set -euo pipefail

# BEGIN GENERATED JANKURAI PIN — DO NOT EDIT
# The governed Jankurai identity is the binary installed on this host and its
# installation receipt: require_jankurai verifies both and exports JERYU_JANKURAI_*
# from the receipt. The one pin of record is jeryu-tool's tool-manifest.toml.
# END GENERATED JANKURAI PIN

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
