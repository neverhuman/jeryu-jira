use thiserror::Error;

pub type Result<T> = std::result::Result<T, WorkError>;

#[derive(Debug, Error)]
pub enum WorkError {
    #[error("validation error: {0}")]
    Validation(String),
    #[error("work item not found: {0}")]
    NotFound(String),
    #[error("conflict: {0}")]
    Conflict(String),
    #[error("storage error: {0}")]
    Storage(String),
    #[error("serialization error: {0}")]
    Serialization(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WorkRepairHint {
    pub purpose: &'static str,
    pub reason: &'static str,
    pub common_fixes: &'static [&'static str],
    pub docs_url: &'static str,
    pub repair_hint: &'static str,
}

impl WorkError {
    pub(crate) fn storage(error: impl std::fmt::Display) -> Self {
        Self::Storage(error.to_string())
    }

    pub(crate) fn serialization(error: impl std::fmt::Display) -> Self {
        Self::Serialization(error.to_string())
    }

    pub fn repair_hint(&self) -> WorkRepairHint {
        match self {
            Self::Validation(_) => WorkRepairHint {
                purpose: "repair Work request validation",
                reason: "the request crossed a Work boundary with an empty field or non-positive issue or pull request number",
                common_fixes: &[
                    "trim titles, comments, owners, and repo names before retrying",
                    "send Work issue and pull request numbers greater than zero",
                    "rerun `rtk just check` and the affected API or web lane",
                ],
                docs_url: "docs/testing.md#repair-evidence",
                repair_hint: "fix the request payload, then rerun the narrow Work proof lane named in agent/test-map.json",
            },
            Self::NotFound(_) => WorkRepairHint {
                purpose: "repair missing Work item lookup",
                reason: "the requested Work key does not resolve to a persisted item",
                common_fixes: &[
                    "verify the key has the JRY-<number> shape",
                    "list Work items for the repo before linking or commenting",
                    "rerun `rtk just migration-drift` if the database was recreated",
                ],
                docs_url: "docs/testing.md#repair-evidence",
                repair_hint: "load the Work list first and retry with an existing key",
            },
            Self::Conflict(_) => WorkRepairHint {
                purpose: "repair Work link conflict",
                reason: "a GitHub-compatible issue link is already owned by another Work item",
                common_fixes: &[
                    "call find_by_issue before creating a mirrored Work item",
                    "reuse the existing Work item instead of creating a duplicate",
                    "rerun `rtk just migration-drift` to prove the uniqueness constraint",
                ],
                docs_url: "docs/boundaries.md#data-boundary",
                repair_hint: "preserve one Work item per mirrored issue and attach new evidence to the existing item",
            },
            Self::Storage(_) => WorkRepairHint {
                purpose: "repair Work storage failure",
                reason: "SQLite rejected or could not persist the Work operation",
                common_fixes: &[
                    "check the SQLite path and parent directory permissions",
                    "rerun `rtk just migration-drift` for schema or constraint failures",
                    "inspect target/jankurai/migration-report.json when migration analysis ran",
                ],
                docs_url: "docs/boundaries.md#data-boundary",
                repair_hint: "fix the storage condition, then rerun migration drift and the caller integration test",
            },
            Self::Serialization(_) => WorkRepairHint {
                purpose: "repair Work row decoding",
                reason: "stored JSON, timestamps, or enum strings no longer match the Work contract",
                common_fixes: &[
                    "regenerate contracts with `rtk cargo run -p jeryu-jira --bin export_contracts`",
                    "rerun `rtk just contract-drift`",
                    "repair malformed rows through a reviewed migration, not ad hoc SQL",
                ],
                docs_url: "docs/testing.md#repair-evidence",
                repair_hint: "restore contract/schema alignment before retrying the caller",
            },
        }
    }
}
