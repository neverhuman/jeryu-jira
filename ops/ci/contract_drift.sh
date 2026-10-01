#!/usr/bin/env bash
set -euo pipefail
source ops/ci/lib.sh
# The toolchain the governed auditor was built with comes from its verified receipt.
require_jankurai

if [[ -e crates/jeryu-jira/bindings ]]; then
  printf 'contract drift failed: generated TypeScript must live only in contracts/generated\n' >&2
  exit 1
fi

pinned_toolchain="$(sed -n 's/^channel = "\(.*\)"$/\1/p' rust-toolchain.toml)"
if [[ "$pinned_toolchain" != "$JERYU_JANKURAI_RUST_TOOLCHAIN" ]]; then
  printf 'contract drift failed: rust-toolchain.toml pins %s, CI expects %s\n' "${pinned_toolchain:-<none>}" "$JERYU_JANKURAI_RUST_TOOLCHAIN" >&2
  exit 1
fi
workspace_msrv="$(sed -n 's/^rust-version = "\(.*\)"$/\1/p' Cargo.toml)"
if [[ "$pinned_toolchain" != "$workspace_msrv"* ]]; then
  printf 'contract drift failed: rust-toolchain.toml pins %s but Cargo.toml rust-version is %s\n' "$pinned_toolchain" "$workspace_msrv" >&2
  exit 1
fi

cargo test -p jeryu-jira --test contract_drift --jobs "${JERYU_CI_JOBS:-40}"
printf 'contract drift ok: %s\n' "$(pwd)"
