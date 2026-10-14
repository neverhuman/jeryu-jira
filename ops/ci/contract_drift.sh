#!/usr/bin/env bash
set -euo pipefail
source ops/ci/lib.sh

if [[ -e crates/jeryu-jira/bindings ]]; then
  printf 'contract drift failed: generated TypeScript must live only in contracts/generated\n' >&2
  exit 1
fi

# The repository's own toolchain pin is its contract with its Cargo.toml
# rust-version. The governed auditor's build toolchain (a public Jankurai
# release since 1.7) is the auditor's business and is not compared here.
pinned_toolchain="$(sed -n 's/^channel = "\(.*\)"$/\1/p' rust-toolchain.toml)"
if [[ ! "$pinned_toolchain" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'contract drift failed: rust-toolchain.toml must pin an exact toolchain, got %s\n' "${pinned_toolchain:-<none>}" >&2
  exit 1
fi
workspace_msrv="$(sed -n 's/^rust-version = "\(.*\)"$/\1/p' Cargo.toml)"
if [[ "$pinned_toolchain" != "$workspace_msrv"* ]]; then
  printf 'contract drift failed: rust-toolchain.toml pins %s but Cargo.toml rust-version is %s\n' "$pinned_toolchain" "$workspace_msrv" >&2
  exit 1
fi

cargo test -p jeryu-jira --test contract_drift --jobs "${JERYU_CI_JOBS:-40}"
printf 'contract drift ok: %s\n' "$(pwd)"
