#!/usr/bin/env bash
set -euo pipefail

source ops/ci/lib.sh

# Interface contracts: the generated mirror must match its reviewed lock (ADR 0015).
sh ops/ci/contract_compat.sh
sh ops/ci/contract_compat_test.sh


cargo fmt --all --check
cargo check --workspace --all-targets --jobs "${JERYU_CI_JOBS:-40}"
cargo test --workspace --lib --bins --jobs "${JERYU_CI_JOBS:-40}"

for script in scripts/*.sh ops/ci/*.sh; do
  [[ -e "$script" ]] || continue
  bash -n "$script"
done

printf 'check ok: %s\n' "$(pwd)"
