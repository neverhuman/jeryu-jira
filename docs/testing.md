# Testing

Primary local lanes:

- `rtk just fast`: formatting plus Rust type/build check.
- `rtk just check`: Rust unit tests and script syntax checks.
- `rtk just property-tests`: property tests for Work invariants.
- `rtk just migration-drift`: SQLite schema, constraints, and migration
  idempotence.
- `rtk just contract-drift`: generated TypeScript file set and bytes.
- `rtk just score`: pinned Jankurai audit lane.
- `rtk just security`: secret scan, dependency audit, workflow lint, and SBOM
  provenance evidence when tools are installed.
- `rtk just ci-local`: local parity wrapper for hosted lanes.

The pre-push hook at `ops/git-hooks/pre-push` runs
`bash ops/ci/quality-gates.sh`. Enable it locally with:

```bash
git config core.hooksPath ops/git-hooks
```

## Repair Evidence

Typed Work errors expose `purpose`, `reason`, `common_fixes`, `docs_url`, and
`repair_hint` through `WorkError::repair_hint()`. Failed lanes should print the
rerun command and preserve local artifacts under `target/jankurai/` when an
artifact exists.

## Launch Gates

Release readiness requires artifact-backed evidence for:

- security: `target/jankurai/security/evidence.json`
- backups: SQLite backup path recorded before any Work schema-changing release
- monitoring: `target/jankurai/release-readiness.json`
- rollback: `docs/rollback.md` and the previous split-family tag
- abuse controls: Work validation, DB constraints, and bridge repair evidence

`rtk just release-readiness` verifies these control documents and writes the
release-readiness receipt consumed by artifact support.
