#!/usr/bin/env bash
set -euo pipefail

# BEGIN GENERATED JANKURAI PIN — DO NOT EDIT
# The governed Jankurai identity is the binary installed on this host and its
# installation receipt: require_jankurai verifies both and exports JERYU_JANKURAI_*
# from the receipt. The one pin of record is jeryu-tool's tool-manifest.toml.
# END GENERATED JANKURAI PIN


source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ops/ci/lib.sh"
require_jankurai

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
# The merge-blocking proof-evidence lane (ops/ci/proof_evidence.sh) refuses to
# run without these, so a gate host that lacks one is reported here, before a
# full gate run, as a host-provisioning error rather than a red required check.
require_tool jq
require_tool sha256sum
require_tool gitleaks
require_tool cargo-audit
require_tool actionlint

if command -v jankurai >/dev/null 2>&1; then
  actual="$(jankurai --version 2>/dev/null || true)"
  if [[ "$actual" == "jankurai 1.7.5" ]]; then
    printf 'doctor ok: jankurai=%s\n' "$actual"
  else
    printf 'doctor wrong jankurai version: expected jankurai 1.7.5, got %s\n' "${actual:-unknown}" >&2
    missing=1
  fi
else
  printf 'doctor missing required tool: jankurai\n' >&2
  missing=1
fi

exit "$missing"
