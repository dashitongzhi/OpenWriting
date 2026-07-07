#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_FILE="codex-pr-review.yml"
ARTIFACT_PREFIX="codex-pr-review-bundle-pr-"
GH_BIN="${GH_BIN:-gh}"

usage() {
  cat <<'USAGE'
Download and prepare a local Codex PR review bundle.

Usage:
  scripts/download-codex-review-bundle.sh <pr-number> [options]
  scripts/download-codex-review-bundle.sh --pr <pr-number> [options]

Options:
  --repo OWNER/REPO      GitHub repository. Defaults to the current gh repo.
  --run-id RUN_ID        Download from a specific GitHub Actions run. Overrides auto-detection.
  --output-dir DIR       Directory to prepare. Defaults to .codex-pr-review-bundles/pr-<pr-number>.
  -h, --help             Show this help.

Examples:
  scripts/download-codex-review-bundle.sh 17
  scripts/download-codex-review-bundle.sh 17 --run-id 1234567890
  scripts/download-codex-review-bundle.sh --pr 17 --repo dashitongzhi/OpenWriting
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

pr_number=""
repo=""
run_id=""
output_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      [[ $# -ge 2 ]] || die "--pr requires a PR number"
      pr_number="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires OWNER/REPO"
      repo="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || die "--run-id requires a GitHub Actions run id"
      run_id="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a directory"
      output_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -z "$pr_number" ]] || die "PR number was provided more than once"
      pr_number="$1"
      shift
      ;;
  esac
done

[[ "$pr_number" =~ ^[0-9]+$ ]] || die "PR number must be a positive integer"
if [[ -n "$run_id" && ! "$run_id" =~ ^[0-9]+$ ]]; then
  die "--run-id must be a positive integer"
fi

require_command "$GH_BIN"

if [[ -z "$repo" ]]; then
  repo="$("$GH_BIN" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
    || die "Could not detect the GitHub repository. Pass --repo OWNER/REPO."
fi
[[ "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die "--repo must look like OWNER/REPO"

artifact_name="${ARTIFACT_PREFIX}${pr_number}"
if [[ -z "$output_dir" ]]; then
  output_dir=".codex-pr-review-bundles/pr-${pr_number}"
fi

if [[ -e "$output_dir" ]]; then
  [[ -d "$output_dir" ]] || die "Output path exists and is not a directory: $output_dir"
  if [[ -n "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    die "Output directory is not empty: $output_dir. Pass a fresh --output-dir to avoid mixing bundles."
  fi
else
  mkdir -p "$output_dir"
fi
abs_output_dir="$(cd "$output_dir" && pwd)"

run_source="--run-id"
if [[ -z "$run_id" ]]; then
  echo "Resolving the latest exact Actions run for PR #$pr_number..."

  require_command node
  resolution="$(node "$SCRIPT_DIR/select-codex-review-bundle-run.cjs" \
    --pr "$pr_number" \
    --repo "$repo" \
    --artifact-name "$artifact_name" \
    --workflow "$WORKFLOW_FILE" \
    --gh-bin "$GH_BIN" || true)"

  if [[ -z "$resolution" ]]; then
    cat >&2 <<EOF
error: Could not resolve an exact GitHub Actions run for PR #$pr_number.

Looked for:
  - latest Codex PR comment containing '$artifact_name' and an Actions run URL
  - latest $WORKFLOW_FILE run whose artifacts include '$artifact_name'

If you know the exact Actions run, retry with:
  scripts/download-codex-review-bundle.sh $pr_number --repo $repo --run-id <run-id> --output-dir <fresh-dir>
EOF
    exit 1
  fi

  IFS=$'\t' read -r run_id run_source <<< "$resolution"
fi

download_args=(-R "$repo" -n "$artifact_name" -D "$abs_output_dir")
download_args=("$run_id" "${download_args[@]}")

echo "Downloading artifact '$artifact_name' from $repo run $run_id ($run_source)..."
if ! "$GH_BIN" run download "${download_args[@]}"; then
  cat >&2 <<EOF

Could not download the review bundle artifact.

Expected artifact: $artifact_name
Workflow: $WORKFLOW_FILE
Repository: $repo
Run ID: $run_id
Run source: $run_source

If the hosted review has not produced a bundle yet, trigger or re-run it:
  $GH_BIN workflow run $WORKFLOW_FILE -R $repo -f pr_number=$pr_number

If you know the exact Actions run, retry with:
  scripts/download-codex-review-bundle.sh $pr_number --repo $repo --run-id <run-id> --output-dir <fresh-dir>
EOF
  exit 1
fi

copy_to_top_level() {
  local filename="$1"
  local top_level_path="$abs_output_dir/$filename"
  local found_path

  if [[ -f "$top_level_path" ]]; then
    return 0
  fi

  found_path="$(find "$abs_output_dir" -type f -name "$filename" | sort | head -n 1)"
  if [[ -n "$found_path" ]]; then
    cp "$found_path" "$top_level_path"
  fi
}

copy_to_top_level "review-prompt.md"
copy_to_top_level "diff-bundle.md"
copy_to_top_level "continue-review.md"
copy_to_top_level "metadata.json"

[[ -s "$abs_output_dir/review-prompt.md" ]] || die "Downloaded artifact did not contain review-prompt.md"
[[ -s "$abs_output_dir/diff-bundle.md" ]] || die "Downloaded artifact did not contain diff-bundle.md"

pr_url="https://github.com/${repo}/pull/${pr_number}"

cat <<EOF

Review bundle ready:
  Repository: $repo
  PR: #$pr_number
  Artifact: $artifact_name
  Run ID: $run_id
  Run source: $run_source
  Directory: $abs_output_dir

Primary files:
  $abs_output_dir/review-prompt.md
  $abs_output_dir/diff-bundle.md

Next local review instructions:
  1. Start a local trusted review session from this repository checkout.
  2. Give it $abs_output_dir/review-prompt.md as the review prompt.
  3. Keep $abs_output_dir/diff-bundle.md attached or available as the preserved PR diff context.
  4. Ask it to return exactly the workflow sections: Findings, Tests And Risk, Merge Recommendation.
  5. Save the local review as $abs_output_dir/local-review.md.
  6. Post it back to the PR with:
     $GH_BIN pr comment $pr_number -R $repo --body-file "$abs_output_dir/local-review.md"

PR:
  $pr_url

To retry the hosted workflow instead:
  $GH_BIN workflow run $WORKFLOW_FILE -R $repo -f pr_number=$pr_number
EOF
