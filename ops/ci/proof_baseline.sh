#!/usr/bin/env bash
# Where the ratchet baseline of this repository comes from: the forge's copy of
# protected main, audited in this run, never a report committed in the tree
# under test. A pull request can edit any file it likes; it cannot edit what the
# forge serves for `main`, so the baseline a head is judged against stays out of
# that head's reach.
#
# The ratchet baseline is protected main's tip as the forge serves it at gate
# time: the tip's audit, under the tip's agent/audit-policy.toml. Never the
# head's fork point, which a head picks by choosing where it branched (an old
# main's score and old main's policy). What the head changed is still measured
# from its fork point (the merge-base of head and tip), so a head behind the tip
# is not blamed or credited for main's later commits and is not refused for
# being behind: another pull request landing does not turn it red by itself.
# Its score is compared with the tip's, and the forge's merge queue replays it
# onto the tip and gates that replay (jeryu-deploy
# crates/jeryu-api/src/web/merge_queue/, refs/queue/<base>/<n> per
# jeryu-ci-runner ops/pr-gate/README.md) before anything lands.
#
# The lane needs the forge: it fetches and clones protected main over the
# network. A baseline the head cannot write has to come from there, and it is
# refused loudly when the forge cannot be reached rather than skipped.
#
# Sourced by ops/ci/proof_evidence.sh. Each guard below is also called directly
# by crates/jeryu-jira/tests/proof_evidence_lane.rs, with a git stub on PATH or
# against real throwaway repositories, so the refusals are exercised without a
# forge or an auditor.

# The fetch URL of `origin`, and only when it is an authenticated-transport
# remote URL. `origin` is the checkout's own configuration, which a pull request
# does not write; a filesystem path (a sibling checkout, a bundle, a worktree)
# could be anything, and plaintext http:// or git:// can be answered by anyone
# on the path, so neither is trusted as the forge.
proof_baseline_remote_url() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  case "$url" in
    https://*|ssh://*)
      printf '%s\n' "$url"
      ;;
    *://*)
      printf 'proof evidence refuses a baseline over an unauthenticated transport: %s\n' \
        "$(proof_baseline_redact_url "$url")" >&2
      return 1
      ;;
    *@*:*)
      printf '%s\n' "$url"
      ;;
    '')
      printf 'proof evidence has no origin remote to take the baseline from\n' >&2
      return 1
      ;;
    *)
      printf 'proof evidence refuses a baseline from a local origin: %s\n' "$url" >&2
      return 1
      ;;
  esac
}

# URL with any userinfo (`user:password@`) removed, for logs and receipts. A runner
# may configure origin as https://<user>:<password>@host/...; that credential must
# not reach the build log or target/, which CI uploads.
proof_baseline_redact_url() {
  local url="$1"
  if [[ "$url" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@(.*)$ ]]; then
    printf '%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s\n' "$url"
  fi
}

# Make this checkout's history answer ancestry questions, then print protected
# main's tip as the forge serves it now.
#
# A depth-1 CI checkout has a grafted head: its own parents are absent, so a
# fetch that names only `main` deepens main but leaves the head's graft in place
# and every ancestry question about the head answers "no". `--unshallow` with
# the remote's whole refspec deepens every ref the forge serves, the head's
# branch among them. If the checkout is still shallow after that (a head the
# forge does not serve), the lane refuses rather than ask git a question this
# checkout cannot answer.
proof_baseline_fetch_main() {
  local tip
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo true)" == true ]]; then
    if ! git fetch --quiet --no-tags --unshallow origin; then
      printf 'cannot deepen this checkout to compare it with protected main\n' >&2
      return 1
    fi
    if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo true)" == true ]]; then
      printf 'this checkout is still shallow after fetching every ref the forge serves: the head'"'"'s history is not on the forge\n' >&2
      return 1
    fi
  fi
  if ! git fetch --quiet --no-tags origin '+refs/heads/main:refs/remotes/origin/main'; then
    printf 'cannot fetch protected main to compare this head with it\n' >&2
    return 1
  fi
  tip="$(git rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}' || true)"
  if [[ ! "$tip" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'protected main served no commit id: %s\n' "${tip:-none}" >&2
    return 1
  fi
  printf '%s\n' "$tip"
}

# The head's fork point on protected main: the newest commit of main's history
# that the head contains, which is where its change set starts. A head sharing
# no history with main is refused.
proof_baseline_fork_point() {
  local tip="$1" head="$2" base
  if [[ ! "$tip" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'protected-main tip is not a commit id: %s\n' "$tip" >&2
    return 1
  fi
  if ! git cat-file -e "${tip}^{commit}" 2>/dev/null; then
    printf 'protected-main commit %s is not in this checkout after fetching it\n' "$tip" >&2
    return 1
  fi
  base="$(git merge-base "$tip" "$head" 2>/dev/null || true)"
  if [[ ! "$base" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'the head under test shares no history with protected main %s\n' "$tip" >&2
    return 1
  fi
  printf '%s\n' "$base"
}

# Clone protected main from the forge into DIR, require COMMIT to be in the
# history the forge serves for main, and check COMMIT out there. --no-local and
# --no-hardlinks so no object is shared with anything on this host. The commit is
# found in this checkout; this clone is the forge's independent word
# that it is a commit of protected main.
proof_baseline_clone() {
  local url="$1" dir="$2" commit="$3" head
  if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'protected-main baseline is not a commit id: %s\n' "$commit" >&2
    return 1
  fi
  if ! git clone --quiet --no-local --no-hardlinks --single-branch \
      --branch main -- "$url" "$dir"; then
    printf 'cannot clone protected main from %s\n' "$(proof_baseline_redact_url "$url")" >&2
    return 1
  fi
  if ! git -C "$dir" merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
    printf 'baseline %s is not in the history the forge serves for protected main\n' "$commit" >&2
    return 1
  fi
  if ! git -C "$dir" checkout --quiet --detach "$commit"; then
    printf 'cannot check out protected-main baseline %s\n' "$commit" >&2
    return 1
  fi
  head="$(git -C "$dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"
  if [[ "$head" != "$commit" ]]; then
    printf 'the protected-main clone is at %s, not %s\n' "${head:-none}" "$commit" >&2
    return 1
  fi
  if [[ -n "$(git -C "$dir" status --porcelain=v1 --untracked-files=all)" ]]; then
    printf 'the protected-main clone is not clean\n' >&2
    return 1
  fi
  printf '%s\n' "$commit"
}

# A ratchet compares two scores, so one policy has to produce both, and the
# head under test may not choose it: both sides are judged by protected main's
# agent/audit-policy.toml, taken from the clone. Prints that policy's path.
proof_baseline_policy() {
  local baseline_root="$1" file
  file="$baseline_root/agent/audit-policy.toml"
  if [[ ! -f "$file" || -L "$file" ]]; then
    printf 'protected main has no regular agent/audit-policy.toml: %s\n' "$file" >&2
    return 1
  fi
  printf '%s\n' "$file"
}

# The tree the ratchet judges. The auditor takes its policy only from the tree
# it audits, so a head whose agent/audit-policy.toml is main's is judged as it
# stands, and this prints HEAD unchanged. A head that edits the policy (raising
# the floor, adding an exclusion) is not refused for it: it is judged as a
# scratch commit in DIR that is the head's tree with protected main's policy
# put back, and this prints that commit. The scratch commit's only difference
# from the head is that one file, which is checked here, so the head's score
# floor, caps and exclusions are main's, not ones it wrote; its edit takes
# effect for the heads after it lands. Only the policy file is put back: the
# other agent/ metadata the auditor reads (owner, test and generated-zone maps,
# proof lanes, boundaries, the standard) is read from the head, as it is for
# every audit of this repository.
proof_baseline_judged_commit() {
  local head="$1" policy="$2" dir="$3" scratch diff
  if [[ ! "$head" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'head under test is not a commit id: %s\n' "$head" >&2
    return 1
  fi
  # The head's tree is untrusted: agent/ must be a directory and the policy a
  # regular file in it, never a symlink or submodule, before anything is read
  # from or written to those paths. (A symlinked policy would otherwise make
  # the copy below write through it to a path outside the scratch tree.)
  if [[ "$(git ls-tree "$head" -- agent | cut -f1 | cut -d' ' -f1,2)" != "040000 tree" ||
        ! "$(git ls-tree "$head" -- agent/audit-policy.toml | cut -f1 | cut -d' ' -f1,2)" =~ ^100(644|755)\ blob$ ]]; then
    printf 'the head'"'"'s agent/audit-policy.toml must be a regular file in an agent/ directory\n' >&2
    return 1
  fi
  if cmp -s <(git show "${head}:agent/audit-policy.toml" 2>/dev/null) "$policy"; then
    printf '%s\n' "$head"
    return 0
  fi
  if ! { git init --quiet "$dir" &&
         git -C "$dir" fetch --quiet --no-tags "$(git rev-parse --show-toplevel)" "$head" &&
         git -C "$dir" checkout --quiet --detach "$head"; }; then
    printf 'cannot stage the head under protected main'"'"'s policy\n' >&2
    return 1
  fi
  if [[ -L "$dir/agent" || ! -d "$dir/agent" ||
        -L "$dir/agent/audit-policy.toml" || ! -f "$dir/agent/audit-policy.toml" ]]; then
    printf 'the checked-out head has no regular agent/audit-policy.toml\n' >&2
    return 1
  fi
  rm -f -- "$dir/agent/audit-policy.toml"
  cp -- "$policy" "$dir/agent/audit-policy.toml"
  if ! git -C "$dir" -c user.name=proof-evidence -c user.email=proof-evidence@invalid \
      -c commit.gpgsign=false commit --quiet --allow-empty -m 'proof evidence: protected main policy' \
      -- agent/audit-policy.toml; then
    printf 'cannot stage the head under protected main'"'"'s policy\n' >&2
    return 1
  fi
  scratch="$(git -C "$dir" rev-parse --verify 'HEAD^{commit}')"
  diff="$(git -C "$dir" diff --no-ext-diff --name-only "$head" "$scratch")"
  if [[ "$diff" != "agent/audit-policy.toml" ||
        "$(git -C "$dir" rev-parse --verify "${scratch}^")" != "$head" ||
        -n "$(git -C "$dir" status --porcelain=v1 --untracked-files=all)" ]]; then
    printf 'the policy-restored head differs from the head by more than its policy: %s\n' "$diff" >&2
    return 1
  fi
  printf '%s\n' "$scratch"
}
