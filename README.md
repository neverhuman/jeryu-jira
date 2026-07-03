# jeryu-jira

Lean local-first Work Tracker source for Jeryu.

This split owns the Rust Work model, SQLite persistence, and generated
TypeScript contracts mirrored into `jeryu-web`. The product surface is named
Work or Work Tracker; `jeryu-jira` remains the repository and crate name.

## Docs

- [Architecture](docs/architecture.md)
- [Boundaries](docs/boundaries.md)
- [Testing](docs/testing.md)
- [Generated zones](docs/generated-zones.md)
- [Audit rules](docs/audit-rules.md)
- [Release](docs/release.md)
- [Rollback](docs/rollback.md)

## Owned Cargo Packages

- `crates/jeryu-jira`

## Source Coverage

- `crates/jeryu-jira/**`
- `contracts/generated/**`
- `contracts/AGENTS.md`
- `db/**`
- `.github/**`
- `ops/**`
- `agent/**`
- `Cargo.toml`
- `Cargo.lock`
- `Justfile`

## Local Commands

- `just doctor`
- `just fast`
- `just check`
- `just property-tests`
- `just migration-drift`
- `just contract-drift`
- `just score`
- `just security`
- `just release-readiness`
- `just artifact-support`
- `just ci-local`

## Pre-Push

Run `rtk just ci-local` before pushing. The local script executes the same
lane entrypoints used by the hosted workflow: doctor, fast, check, migration
drift, contract drift, score, security, release readiness, and artifact
support.
