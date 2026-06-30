#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${GIT_PREFLIGHT_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
REMOTE="${GIT_PREFLIGHT_REMOTE:-origin}"
OID_PATTERN='^[0-9a-fA-F]{40}$'

errors=()
warnings=()

fail() {
    local newline=$'\n'
    local message="${1//\\n/$newline}"
    errors+=("$message")
}

warn() {
    warnings+=("$1")
}

git_repo() {
    git -C "$REPO_ROOT" "$@"
}

absolute_git_path() {
    local path="$1"
    if [[ "$path" == /* ]]; then
        printf "%s\n" "$path"
    else
        printf "%s\n" "$REPO_ROOT/$path"
    fi
}

first_lines() {
    printf "%s\n" "$1" | sed -n '1,6p'
}

print_ref_file_fix() {
    local ref_file="$1"
    printf "%s\n" "  suggested fix: inspect the file, then remove only that stale ref file if it is not intentional:"
    printf "%s\n" "    rm -- '$ref_file'"
    printf "%s\n" "    git -C '$REPO_ROOT' fetch --prune '$REMOTE'"
}

echo "Running git preflight"

if ! git_repo rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: $REPO_ROOT is not inside a Git work tree" >&2
    exit 1
fi

git_dir="$(absolute_git_path "$(git_repo rev-parse --git-dir)")"
git_common_dir="$(absolute_git_path "$(git_repo rev-parse --git-common-dir)")"

if ! git_repo remote get-url "$REMOTE" >/dev/null 2>&1; then
    fail "remote '$REMOTE' is not configured. Branch inspection and sync checks need a readable remote."
fi

current_branch="$(git_repo symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$current_branch" ]]; then
    fail "HEAD is detached or unborn. Switch to a named branch before branch inspection or sync: git switch <branch>"
fi

if [[ -f "$git_dir/MERGE_HEAD" ]]; then
    fail "a merge is in progress. Finish or abort it before branch inspection: git merge --continue or git merge --abort"
fi

if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
    fail "a rebase or am session is in progress. Finish or abort it before branch inspection: git rebase --continue or git rebase --abort"
fi

if [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
    fail "a cherry-pick is in progress. Finish or abort it before branch inspection: git cherry-pick --continue or git cherry-pick --abort"
fi

if [[ -f "$git_dir/REVERT_HEAD" ]]; then
    fail "a revert is in progress. Finish or abort it before branch inspection: git revert --continue or git revert --abort"
fi

if [[ -f "$git_dir/BISECT_LOG" ]]; then
    fail "a bisect session is in progress. Reset it before branch inspection: git bisect reset"
fi

unmerged_files="$(git_repo diff --name-only --diff-filter=U 2>/dev/null || true)"
if [[ -n "$unmerged_files" ]]; then
    fail "the index has unresolved conflicts, so branch inspection may report misleading results. Resolve these files first:\n$(first_lines "$unmerged_files")"
fi

dirty_tracked="$(git_repo status --porcelain=v1 --untracked-files=no 2>/dev/null || true)"
if [[ -n "$dirty_tracked" ]]; then
    warn "tracked files have uncommitted changes. This does not block local checks, but sync/fast-forward scripts should stop until the work tree is clean."
fi

remote_refs_dir="$git_common_dir/refs/remotes/$REMOTE"
if [[ -d "$remote_refs_dir" ]]; then
    remote_ref_list_file="$(mktemp "${TMPDIR:-/tmp}/openwriting-git-preflight.XXXXXX")"
    find "$remote_refs_dir" -type f ! -name '*.lock' -print >"$remote_ref_list_file"
    while IFS= read -r ref_file || [[ -n "$ref_file" ]]; do
        ref_rel="${ref_file#$remote_refs_dir/}"
        ref_name="refs/remotes/$REMOTE/$ref_rel"
        ref_value="$(sed -n '1p' "$ref_file")"

        if ! git check-ref-format "$ref_name" >/dev/null 2>&1; then
            fail "remote-tracking ref has an invalid name: $ref_name\n  file: $ref_file\n  why this matters: Git commands such as 'git for-each-ref' and branch patrols may ignore or abort on this ref."
        fi

        if [[ "$ref_value" == ref:\ * ]]; then
            target_ref="${ref_value#ref: }"
            if ! git check-ref-format "$target_ref" >/dev/null 2>&1; then
                fail "symbolic remote-tracking ref points to an invalid target: $ref_name -> $target_ref\n  file: $ref_file"
            elif ! git_repo rev-parse --verify --quiet "$target_ref^{commit}" >/dev/null; then
                fail "symbolic remote-tracking ref points to an unreadable target: $ref_name -> $target_ref\n  suggested fix: git -C '$REPO_ROOT' remote set-head '$REMOTE' -a"
            fi
            continue
        fi

        if [[ ! "$ref_value" =~ $OID_PATTERN ]]; then
            fail "remote-tracking ref does not contain a full object id: $ref_name\n  file: $ref_file\n  value: $ref_value"
            continue
        fi

        if ! git_repo cat-file -e "$ref_value^{commit}" 2>/dev/null; then
            fail "remote-tracking ref points to a missing or non-commit object: $ref_name -> $ref_value\n  file: $ref_file"
        fi
    done <"$remote_ref_list_file"
    rm -f "$remote_ref_list_file"
fi

default_ref="$(git_repo symbolic-ref --quiet "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true)"
if [[ -z "$default_ref" ]]; then
    fail "remote default branch is not configured locally: refs/remotes/$REMOTE/HEAD\n  suggested fix: git -C '$REPO_ROOT' remote set-head '$REMOTE' -a"
elif ! git check-ref-format "$default_ref" >/dev/null 2>&1; then
    fail "remote default branch points to an invalid ref name: refs/remotes/$REMOTE/HEAD -> $default_ref"
elif ! git_repo rev-parse --verify --quiet "$default_ref^{commit}" >/dev/null; then
    fail "remote default branch is not readable: $default_ref\n  suggested fix: git -C '$REPO_ROOT' fetch --prune '$REMOTE' && git -C '$REPO_ROOT' remote set-head '$REMOTE' -a"
fi

for_each_ref_stderr_file="$(mktemp "${TMPDIR:-/tmp}/openwriting-git-preflight.XXXXXX")"
git_repo for-each-ref --format='%(refname) %(objectname)' refs/remotes >/dev/null 2>"$for_each_ref_stderr_file"
for_each_ref_status=$?
for_each_ref_stderr="$(sed -n '1,6p' "$for_each_ref_stderr_file")"
rm -f "$for_each_ref_stderr_file"
if (( for_each_ref_status != 0 )); then
    fail "Git cannot enumerate remote-tracking refs cleanly. Branch inspection may abort before it sees all branches.\n  command: git for-each-ref refs/remotes\n$for_each_ref_stderr"
elif [[ -n "$for_each_ref_stderr" ]]; then
    fail "Git reported remote-tracking ref enumeration warnings. Branch inspection may ignore broken refs.\n  command: git for-each-ref refs/remotes\n$for_each_ref_stderr"
fi

if [[ -n "$default_ref" ]]; then
    default_log_output_file="$(mktemp "${TMPDIR:-/tmp}/openwriting-git-preflight.XXXXXX")"
    git_repo log --oneline -1 "$default_ref" >"$default_log_output_file" 2>&1
    default_log_status=$?
    default_log_output="$(sed -n '1,6p' "$default_log_output_file")"
    rm -f "$default_log_output_file"
    if (( default_log_status != 0 )); then
        fail "Git cannot walk the remote default branch. Branch inspection may report a stale default branch.\n  command: git log --oneline -1 $default_ref\n$default_log_output"
    fi
fi

all_log_output_file="$(mktemp "${TMPDIR:-/tmp}/openwriting-git-preflight.XXXXXX")"
git_repo log --all --oneline -1 >"$all_log_output_file" 2>&1
all_log_status=$?
all_log_output="$(sed -n '1,6p' "$all_log_output_file")"
rm -f "$all_log_output_file"
if (( all_log_status != 0 )); then
    fail "Git cannot walk all refs. Any branch patrol based on 'git log --all' will fail.\n  command: git log --all --oneline -1\n$all_log_output"
fi

if (( ${#warnings[@]} > 0 )); then
    for warning in "${warnings[@]}"; do
        printf "%s\n" "warning: $warning" >&2
    done
fi

if (( ${#errors[@]} > 0 )); then
    printf "%s\n" "Git preflight failed:" >&2
    for error in "${errors[@]}"; do
        printf "\n" >&2
        printf "%s\n" "$error" >&2
        if [[ "$error" == *"file: "*".git/refs/remotes/$REMOTE/"* ]]; then
            ref_file_line="$(printf "%s\n" "$error" | sed -n 's/^  file: //p' | sed -n '1p')"
            if [[ -n "$ref_file_line" ]]; then
                print_ref_file_fix "$ref_file_line" >&2
            fi
        fi
    done
    printf "\n" >&2
    printf "%s\n" "After repairing the reported Git state, rerun: ./scripts/git-preflight.sh" >&2
    exit 1
fi

echo "Git preflight passed"
