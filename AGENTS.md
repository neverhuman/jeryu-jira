# jeryu-jira Agent Instructions

This is a Jeryu split repository seeded after the v5 split baseline.

Before editing, read `README.md`, `agent/owner-map.json`,
`agent/test-map.json`, `agent/generated-zones.toml`,
`agent/proof-lanes.toml`, `agent/audit-policy.toml`, and
`agent/boundaries.toml`.

Keep split `main` clean. The legacy monorepo is
deprecated and archived as `jeryu/jeryu-monorepo`; this split family is the
only source of truth. Land changes through PRs with green required checks.

Do not edit `CHANGELOG.md` in a change: release notes are generated at release
time from commit subjects and `Todo:` trailers.

The user-facing product name is Work or Work Tracker. Do not present the
feature as Jira in product UI or docs; `jeryu-jira` is only the repository and
crate name.
