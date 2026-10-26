# Contributing

Outside pull requests are welcome on GitHub.

## How review works

The GitHub repository is a read-only mirror. Pull requests are reviewed and
merged on the project's forge. When that happens, the GitHub pull request is
closed with a link to the merged change.

Until the importer that brings GitHub pull requests to the forge is live,
pull requests are read but not merged yet. Opening one is still useful; it
will be picked up once the importer is running.

## Tests and fixtures

Tests and fixtures must use invented data only (for example `acme`, `globex`
and `*.example` hosts). Do not include real hosts, organization names, logins,
paths or credentials.

## Running the gate locally

Run the repository gate before opening a pull request:

```sh
./ops/ci/pr-ci.sh
```

This is the same gate pull requests must pass. It runs every lane in order
(doctor, fast, check, property tests, migration drift, contract drift, score,
security, release and artifact support) and stops at the first failure.
`./ops/ci/check.sh` alone is only one of those lanes.

## Security

Do not report vulnerabilities in issues or pull requests; see
[SECURITY.md](SECURITY.md).
