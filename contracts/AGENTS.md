# Work Tracker Contracts

`contracts/generated/` is generated from `crates/jeryu-jira` with ts-rs.
Do not edit generated TypeScript files by hand.

Regenerate with:

```bash
rtk cargo run -p jeryu-jira --bin jeryu-jira-export-contracts
```

Compatibility lock (ADR 0015, jeryu-deploy `docs/adr`):
- `contracts/generated.lock` pins the sha256 of every generated file;
  `ops/ci/contract_compat.sh` fails the gate when they differ and names the
  consumer. After a reviewed regeneration run it with `--write` and commit the
  lock together with the generated files.
