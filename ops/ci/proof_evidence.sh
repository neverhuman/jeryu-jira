#!/usr/bin/env bash
set -euo pipefail
mkdir -p target/jankurai
if [ -d db/migrations ]; then
  jankurai migrate . --analyze --out target/jankurai/migration-report.json --md target/jankurai/migration-report.md
fi
[ -s target/jankurai/migration-report.json ] || printf '{"schema_version":"jankurai.migration/v1","status":"no-owned-migrations"}\n' > target/jankurai/migration-report.json
printf 'proof evidence ok\n'
