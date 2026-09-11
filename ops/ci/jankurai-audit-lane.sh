#!/usr/bin/env bash
set -euo pipefail
source ops/ci/lib.sh
require_jankurai
jankurai audit . --full --mode advisory --policy agent/audit-policy.toml --json .jankurai/repo-score.json --md .jankurai/repo-score.md
bash ops/ci/score.sh
