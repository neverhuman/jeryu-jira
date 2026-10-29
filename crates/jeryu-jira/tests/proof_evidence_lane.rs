//! The evidence lane's own guards: where its ratchet baseline may come from,
//! and that it still refuses what it is meant to refuse.
//!
//! `ops/ci/proof_baseline.sh` is sourced and its guards are called here. The
//! history and clone guards run against real throwaway git repositories served
//! over `file://` (a depth-1 checkout, a forked branch, unrelated history), so
//! what real git does with `--unshallow` and ancestry is what is tested; the
//! origin guard uses a `git` stub. No forge, no network and no auditor are
//! needed. The lane itself (`ops/ci/proof_evidence.sh`) runs every Jankurai
//! tool for real and cannot be run from a unit test; what is checked of it here
//! is wiring a reader cannot see from one file. Those wiring checks are line
//! tripwires over the script, not a shell parser: they catch the named
//! regressions, not every way of writing them.
//!
//! This target is run by `ops/ci/check.sh`.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("repository root above crates/jeryu-jira")
        .to_path_buf()
}

fn temp_dir() -> tempfile::TempDir {
    tempfile::tempdir().expect("temp dir")
}

/// Install a `git` stub whose body is `body`, and return the directory to put
/// first on PATH.
fn git_stub(dir: &Path, body: &str) -> PathBuf {
    let bin = dir.join("bin");
    fs::create_dir_all(&bin).expect("stub bin");
    let script = format!("#!/usr/bin/env bash\nset -u\n{body}\n");
    let path = bin.join("git");
    fs::write(&path, script).expect("write git stub");
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).expect("chmod stub");
    bin
}

/// A git environment that reads no user or system configuration.
fn isolated(cmd: &mut Command) -> &mut Command {
    cmd.env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_AUTHOR_NAME", "proof test")
        .env("GIT_AUTHOR_EMAIL", "proof@example.invalid")
        .env("GIT_COMMITTER_NAME", "proof test")
        .env("GIT_COMMITTER_EMAIL", "proof@example.invalid")
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE")
}

/// Source the baseline guards and run `snippet` with `stub_bin` first on PATH.
fn run_guard(stub_bin: Option<&Path>, snippet: &str) -> Output {
    let base_path = std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".to_string());
    let path = match stub_bin {
        Some(bin) => format!("{}:{base_path}", bin.display()),
        None => base_path,
    };
    let root = repo_root();
    isolated(&mut Command::new("bash"))
        .arg("-c")
        .arg(format!(
            "source {}\n{snippet}",
            path_arg(&root.join("ops/ci/proof_baseline.sh"))
        ))
        .current_dir(&root)
        .env("PATH", path)
        .output()
        .expect("run guard")
}

fn git(dir: &Path, args: &[&str]) -> String {
    let out = isolated(&mut Command::new("git"))
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .expect("run git");
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn commit(dir: &Path, name: &str) -> String {
    fs::write(dir.join(name), name).expect("write file");
    git(dir, &["add", name]);
    git(dir, &["commit", "--quiet", "--no-gpg-sign", "-m", name]);
    git(dir, &["rev-parse", "HEAD"])
}

fn path_arg(path: &Path) -> String {
    format!("{:?}", path.display().to_string())
}

fn stderr(out: &Output) -> String {
    String::from_utf8_lossy(&out.stderr).to_string()
}

fn lane_source() -> String {
    fs::read_to_string(repo_root().join("ops/ci/proof_evidence.sh")).expect("lane source")
}

/// A forge stand-in: a bare repository whose `main` has two commits, with a
/// three-commit `topic` branch forked from the first (so behind main's tip), a
/// `current` branch built on main's tip, and a `lonely` branch with no shared
/// history.
struct Forge {
    _dir: tempfile::TempDir,
    bare: PathBuf,
    fork: String,
    main_tip: String,
    topic_tip: String,
    current_tip: String,
}

impl Forge {
    fn new() -> Self {
        let dir = temp_dir();
        let work = dir.path().join("work");
        let bare = dir.path().join("forge.git");
        fs::create_dir_all(&work).expect("work dir");
        git(&work, &["init", "--quiet", "--initial-branch=main"]);
        fs::create_dir_all(work.join("agent")).expect("agent dir");
        fs::write(work.join("agent/audit-policy.toml"), "minimum_score = 85\n").expect("policy");
        git(&work, &["add", "agent/audit-policy.toml"]);
        let fork = commit(&work, "m1");
        git(&work, &["switch", "--quiet", "-c", "topic"]);
        commit(&work, "t1");
        commit(&work, "t2");
        let topic_tip = commit(&work, "t3");
        git(&work, &["switch", "--quiet", "main"]);
        let main_tip = commit(&work, "m2");
        git(&work, &["switch", "--quiet", "-c", "current"]);
        let current_tip = commit(&work, "c1");
        git(&work, &["switch", "--quiet", "--orphan", "lonely"]);
        commit(&work, "l1");
        git(
            dir.path(),
            &["clone", "--quiet", "--bare", "work", "forge.git"],
        );
        Forge {
            _dir: dir,
            bare,
            fork,
            main_tip,
            topic_tip,
            current_tip,
        }
    }

    fn url(&self) -> String {
        format!("file://{}", self.bare.display())
    }

    /// A depth-1 checkout of `branch`, as a CI checkout of a pull request is.
    fn shallow_checkout(&self, into: &Path, branch: &str) -> PathBuf {
        let dir = into.join(format!("checkout-{branch}"));
        let parent = into.to_path_buf();
        git(
            &parent,
            &[
                "clone",
                "--quiet",
                "--depth",
                "1",
                "--no-single-branch",
                "--branch",
                branch,
                &self.url(),
                dir.to_str().expect("utf-8 path"),
            ],
        );
        dir
    }
}

#[test]
fn baseline_origin_must_be_an_authenticated_remote_the_head_cannot_write() {
    let dir = temp_dir();
    let remote = git_stub(
        dir.path(),
        r#"if [[ "$1 $2 $3" == "remote get-url origin" ]]; then
  printf '%s\n' "$STUB_ORIGIN"; exit 0
fi
exit 1"#,
    );
    for good in [
        "https://forge.example/jeryu/jeryu-jira.git",
        "ssh://git@forge.example/jeryu/jeryu-jira.git",
        "git@forge.example:jeryu/jeryu-jira.git",
    ] {
        let out = run_guard(
            Some(&remote),
            &format!("STUB_ORIGIN={good:?} proof_baseline_remote_url"),
        );
        assert!(out.status.success(), "{good} is a baseline source");
        assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), good);
    }
    for bad in [
        "/home/someone/jeryu-jira",
        "../jeryu-jira",
        "",
        "http://forge.example/jeryu/jeryu-jira.git",
        "git://forge.example/jeryu/jeryu-jira.git",
        "file:///srv/jeryu-jira.git",
    ] {
        let out = run_guard(
            Some(&remote),
            &format!("STUB_ORIGIN={bad:?} proof_baseline_remote_url"),
        );
        assert!(
            !out.status.success(),
            "origin {bad:?} must not be trusted as the forge"
        );
    }
}

#[test]
fn credentials_in_the_origin_url_never_reach_a_log_or_receipt() {
    for (url, shown) in [
        (
            "https://ci:s3cr3t-pw@forge.example/jeryu/jeryu-jira.git",
            "https://forge.example/jeryu/jeryu-jira.git",
        ),
        (
            "https://x-access@forge.example/r.git",
            "https://forge.example/r.git",
        ),
        ("https://forge.example/r.git", "https://forge.example/r.git"),
        ("git@forge.example:r.git", "git@forge.example:r.git"),
    ] {
        let out = run_guard(None, &format!("proof_baseline_redact_url {url:?}"));
        assert!(out.status.success());
        assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), shown);
    }
    let dir = temp_dir();
    let remote = git_stub(
        dir.path(),
        r#"[[ "$1 $2 $3" == "remote get-url origin" ]] && { printf 'http://ci:s3cr3t-pw@forge.example/r.git\n'; exit 0; }
exit 1"#,
    );
    let refused = run_guard(Some(&remote), "proof_baseline_remote_url");
    assert!(!refused.status.success());
    assert!(
        !stderr(&refused).contains("s3cr3t-pw"),
        "a refusal message must not print the credential: {}",
        stderr(&refused)
    );

    let lane = lane_source();
    assert!(
        lane.contains("--arg origin \"$origin_shown\""),
        "the receipt records the redacted origin"
    );
    for line in lane.lines() {
        if line.contains("printf") && line.contains("origin_url") {
            panic!("the lane prints the raw origin URL: {line}");
        }
    }
}

#[test]
fn a_depth_one_pull_request_checkout_is_deepened_with_the_heads_own_history() {
    let forge = Forge::new();
    let work = temp_dir();
    let checkout = forge.shallow_checkout(work.path(), "current");
    assert_eq!(
        git(&checkout, &["rev-parse", "--is-shallow-repository"]),
        "true"
    );
    let out = run_guard(
        None,
        &format!(
            "cd {} && tip=\"$(proof_baseline_fetch_main)\" && printf '%s\\n' \"$tip\" && proof_baseline_fork_point \"$tip\" HEAD",
            path_arg(&checkout)
        ),
    );
    assert!(out.status.success(), "real git deepening: {}", stderr(&out));
    let printed = String::from_utf8_lossy(&out.stdout);
    let lines: Vec<&str> = printed.lines().collect();
    assert_eq!(
        lines,
        vec![forge.main_tip.as_str(), forge.main_tip.as_str()]
    );
    assert_eq!(
        git(&checkout, &["rev-parse", "--is-shallow-repository"]),
        "false"
    );
    assert_eq!(git(&checkout, &["rev-parse", "HEAD"]), forge.current_tip);
}

/// A head behind main's tip is not refused for it: its change set starts at
/// its fork point, so another pull request landing does not turn it red, and
/// the lane ratchets it against the tip itself, never against that fork point.
#[test]
fn a_head_behind_the_tip_is_measured_from_its_fork_point_and_ratcheted_against_the_tip() {
    let forge = Forge::new();
    let work = temp_dir();
    let checkout = forge.shallow_checkout(work.path(), "topic");
    let out = run_guard(
        None,
        &format!(
            "cd {} && tip=\"$(proof_baseline_fetch_main)\" && proof_baseline_fork_point \"$tip\" HEAD",
            path_arg(&checkout)
        ),
    );
    assert!(out.status.success(), "{}", stderr(&out));
    assert_ne!(forge.fork, forge.main_tip, "main has moved past the fork");
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), forge.fork);

    // Line tripwires over the lane: the clone and audit are of the tip, the
    // change set and the proof tools start at the fork point.
    let lane = lane_source();
    assert!(
        lane.contains("base_commit=\"$main_tip\""),
        "the baseline is main's tip"
    );
    assert!(
        lane.contains("proof_baseline_clone \"$origin_url\" \"$baseline_root\" \"$base_commit\"")
    );
    assert!(lane.contains("\"${fork_commit}...${head_commit}\""));
    assert!(!lane.contains("--changed-from \"$base_commit\""));
}

#[test]
fn a_head_sharing_no_history_with_protected_main_is_refused() {
    let forge = Forge::new();
    let work = temp_dir();
    let checkout = forge.shallow_checkout(work.path(), "lonely");
    let out = run_guard(
        None,
        &format!(
            "cd {} && tip=\"$(proof_baseline_fetch_main)\" && proof_baseline_fork_point \"$tip\" HEAD",
            path_arg(&checkout)
        ),
    );
    assert!(
        !out.status.success(),
        "unrelated history must fail the lane"
    );
    assert!(stderr(&out).contains("shares no history with protected main"));

    // A commit id is all the guard will pass to git: no ref name, no option.
    for bad in ["--upload-pack=touch /tmp/x", "origin/main", "1111111"] {
        let out = run_guard(None, &format!("proof_baseline_fork_point {bad:?} HEAD"));
        assert!(!out.status.success(), "{bad} is not a commit id");
    }
}

#[test]
fn the_protected_clone_must_serve_the_baseline_on_main() {
    let forge = Forge::new();
    let work = temp_dir();
    let clone = |commit: &str, name: &str| {
        run_guard(
            None,
            &format!(
                "proof_baseline_clone {:?} {} {commit:?}",
                forge.url(),
                path_arg(&work.path().join(name))
            ),
        )
    };
    let ok = clone(&forge.fork, "a");
    assert!(ok.status.success(), "{}", stderr(&ok));
    assert_eq!(String::from_utf8_lossy(&ok.stdout).trim(), forge.fork);
    assert_eq!(
        git(&work.path().join("a"), &["rev-parse", "HEAD"]),
        forge.fork
    );

    let off_main = clone(&forge.topic_tip, "b");
    assert!(
        !off_main.status.success(),
        "a commit the forge does not serve on main is not protected main"
    );
    assert!(stderr(&off_main).contains("not in the history the forge serves"));

    let short = clone(&forge.fork[..7], "c");
    assert!(
        !short.status.success(),
        "an abbreviated id is not a commit id"
    );
}

#[test]
fn protected_mains_policy_judges_the_head_and_the_head_may_edit_its_own() {
    let dir = temp_dir();
    let main = dir.path().join("main");
    fs::create_dir_all(main.join("agent")).expect("agent dir");
    fs::write(main.join("agent/audit-policy.toml"), "minimum_score = 85\n").expect("policy");
    let out = run_guard(None, &format!("proof_baseline_policy {}", path_arg(&main)));
    assert!(out.status.success(), "{}", stderr(&out));
    assert_eq!(
        String::from_utf8_lossy(&out.stdout).trim(),
        main.join("agent/audit-policy.toml").display().to_string()
    );

    let missing = run_guard(
        None,
        &format!(
            "proof_baseline_policy {}",
            path_arg(&dir.path().join("none"))
        ),
    );
    assert!(!missing.status.success(), "a missing policy fails closed");

    let linked = dir.path().join("linked");
    fs::create_dir_all(linked.join("agent")).expect("agent dir");
    std::os::unix::fs::symlink(
        main.join("agent/audit-policy.toml"),
        linked.join("agent/audit-policy.toml"),
    )
    .expect("symlink");
    let symlink = run_guard(
        None,
        &format!("proof_baseline_policy {}", path_arg(&linked)),
    );
    assert!(!symlink.status.success(), "a symlinked policy fails closed");

    // Both audits read protected main's policy; the head's own file never
    // judges the ratchet, and a head that edits it is not refused for that.
    let lane = lane_source();
    assert!(lane.contains("policy=\"$(proof_baseline_policy \"$baseline_root\")\""));
    assert!(lane.contains("--policy \"$policy\""));
    assert!(lane.contains("proof_baseline_judged_commit \"$head_commit\" \"$policy\""));
    assert!(lane.contains("--policy \"${judged_args[0]}/agent/audit-policy.toml\""));
    assert!(
        lane.contains(".decision.passed == true and .score >= .decision.minimum_score"),
        "a head that edits the policy must meet its own new floor"
    );
    // A tripwire only: in the common case the ratchet does read the head's own
    // ./agent/audit-policy.toml, which is safe because proof_baseline_judged_commit
    // returns the head only when that file is byte-equal to main's (tested with
    // real git in a_head_that_edits_the_policy_is_judged_as_its_tree_under_mains_policy).
    assert!(
        !lane.contains("--policy agent/audit-policy.toml"),
        "the ratchet names its policy through the judged tree, not the head's path"
    );
    assert!(
        !lane.contains("require_policy_identity"),
        "a policy edit is not refused outright"
    );
}

#[test]
fn a_head_that_edits_the_policy_is_judged_as_its_tree_under_mains_policy() {
    let forge = Forge::new();
    let work = temp_dir();
    let checkout = forge.shallow_checkout(work.path(), "topic");
    git(&checkout, &["fetch", "--quiet", "--unshallow", "origin"]);
    let main_policy = work.path().join("main-policy.toml");
    fs::write(&main_policy, "minimum_score = 85\n").expect("main policy");
    let judged = |name: &str| {
        run_guard(
            None,
            &format!(
                "cd {} && proof_baseline_judged_commit \"$(git rev-parse HEAD)\" {} {}",
                path_arg(&checkout),
                path_arg(&main_policy),
                path_arg(&work.path().join(name))
            ),
        )
    };

    let same = judged("same");
    assert!(same.status.success(), "{}", stderr(&same));
    assert_eq!(
        String::from_utf8_lossy(&same.stdout).trim(),
        forge.topic_tip,
        "a head carrying main's policy is judged as it stands"
    );

    // The head lowers the floor. It is still judged, on its own code, under
    // the policy main has.
    fs::write(
        checkout.join("agent/audit-policy.toml"),
        "minimum_score = 10\n",
    )
    .expect("edit policy");
    git(&checkout, &["add", "agent/audit-policy.toml"]);
    git(
        &checkout,
        &[
            "commit",
            "--quiet",
            "--no-gpg-sign",
            "-m",
            "lower the floor",
        ],
    );
    let head = git(&checkout, &["rev-parse", "HEAD"]);
    let edited = judged("edited");
    assert!(edited.status.success(), "{}", stderr(&edited));
    let scratch = String::from_utf8_lossy(&edited.stdout).trim().to_string();
    assert_ne!(scratch, head);
    let dir = work.path().join("edited");
    assert_eq!(git(&dir, &["rev-parse", "HEAD^"]), head);
    assert_eq!(
        git(&dir, &["diff", "--name-only", &head, &scratch]),
        "agent/audit-policy.toml"
    );
    assert_eq!(
        fs::read_to_string(dir.join("agent/audit-policy.toml")).expect("judged policy"),
        "minimum_score = 85\n",
        "the judged tree carries protected main's policy"
    );

    // A head whose policy is a symlink is refused before anything is written,
    // so the copy cannot write through it to a file outside the scratch tree.
    let victim = work.path().join("victim");
    fs::write(&victim, "untouched\n").expect("victim");
    git(&checkout, &["rm", "--quiet", "agent/audit-policy.toml"]);
    fs::create_dir_all(checkout.join("agent")).expect("agent dir");
    std::os::unix::fs::symlink(&victim, checkout.join("agent/audit-policy.toml"))
        .expect("symlink policy");
    git(&checkout, &["add", "agent/audit-policy.toml"]);
    git(
        &checkout,
        &[
            "commit",
            "--quiet",
            "--no-gpg-sign",
            "-m",
            "symlink the policy",
        ],
    );
    let linked = judged("linked");
    assert!(
        !linked.status.success(),
        "a symlinked head policy is refused"
    );
    assert!(stderr(&linked).contains("must be a regular file"));
    assert_eq!(
        fs::read_to_string(&victim).expect("victim"),
        "untouched\n",
        "nothing was written through the symlink"
    );
}

#[test]
fn the_lane_keeps_no_baseline_and_no_result_it_did_not_produce() {
    let lane = lane_source();
    assert!(
        !lane.contains("|| true"),
        "no tool in the lane may have its failure discarded"
    );
    assert!(
        !lane.contains("agent/baselines"),
        "the ratchet baseline may not come from a file in the tree under test"
    );
    assert!(
        lane.contains("proof_baseline_clone"),
        "the baseline comes from the forge's copy of protected main"
    );
    // Every `>` write into target/ is a tool's own output or the summary of
    // this run; a `printf > target/...` fallback would be a result nobody
    // produced.
    for line in lane.lines() {
        let line = line.trim();
        if line.starts_with('#') || !line.contains("> target/") {
            continue;
        }
        assert!(
            line.starts_with("> \"target/jankurai/proof-evidence-summary.json\""),
            "the lane synthesizes an artifact: {line}"
        );
    }
    assert!(
        lane.contains("migration-report.json") && lane.contains("liability_score <= $baseline"),
        "the migration analysis result is gated, not merely written"
    );
    // No command is planted in a comment for the adoption detector to find.
    for line in lane.lines().map(str::trim) {
        if line.starts_with('#') {
            assert!(
                !line.contains("cargo run -p jankurai") && !line.contains("cargo test -p jankurai"),
                "the lane names a command it does not run: {line}"
            );
        }
    }
    assert!(
        lane.contains("needs a clean checkout"),
        "the lane refuses a tree that is not the head it reports on"
    );
}

#[test]
fn the_security_run_requires_every_scanner_and_reads_every_check() {
    let lane = lane_source();
    assert!(
        lane.contains("JERYU_REQUIRE_SECURITY_TOOLS=1 jankurai security run"),
        "a missing scanner must fail the security run, not be recorded as not_run"
    );
    assert!(
        lane.contains("--out target/jankurai/security-wrapper.json"),
        "the wrapper receipt has its own path"
    );
    assert!(
        !lane.contains("--out target/jankurai/security/evidence.json"),
        "the wrapper must not overwrite the script's own evidence"
    );
    assert!(
        lane.contains("select(.status != \"pass\")")
            && lane.contains("\"dependency-audit\", \"secret-scan\""),
        "every check the security script recorded is read, scanners included"
    );
}

#[test]
fn the_required_gate_runs_the_lane_and_its_tests() {
    let root = repo_root();
    let pr_ci = fs::read_to_string(root.join("ops/ci/pr-ci.sh")).expect("pr-ci.sh");
    assert!(
        pr_ci
            .lines()
            .any(|line| line.trim() == "bash ops/ci/proof_evidence.sh"),
        "ops/ci/pr-ci.sh must run the evidence lane unconditionally"
    );
    let workflow = fs::read_to_string(root.join(".github/workflows/ci.yml")).expect("ci.yml");
    assert!(
        workflow.contains("bash ops/ci/proof_evidence.sh"),
        "the mirrored workflow runs the same lane"
    );
    let lanes = fs::read_to_string(root.join("agent/proof-lanes.toml")).expect("lanes");
    assert!(
        lanes.contains("[lanes.proof-evidence]")
            && lanes.contains("required = [\"just proof-evidence\"]"),
        "the lane is declared in proof-lanes.toml as a just recipe, like every other lane"
    );
    let justfile = fs::read_to_string(root.join("Justfile")).expect("Justfile");
    assert!(justfile.contains("proof-evidence:\n  bash ops/ci/proof_evidence.sh"));
    let check = fs::read_to_string(root.join("ops/ci/check.sh")).expect("check.sh");
    assert!(
        check.contains("cargo test -p jeryu-jira --test proof_evidence_lane"),
        "the gate runs this test target"
    );
}
