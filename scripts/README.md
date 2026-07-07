# Scripts

## Codex review bundle download

`download-codex-review-bundle.sh` downloads the `codex-pr-review-bundle-pr-<PR>` artifact for local review continuation.

By default it resolves an exact GitHub Actions run before downloading:

1. Use the latest PR comment containing `<!-- codex-pr-review -->`, the exact artifact name, and an Actions run URL, preferring a `## Review Fallback` comment.
2. If the PR comment is unavailable, scan recent `codex-pr-review.yml` runs and pick the newest run whose artifacts include the exact `codex-pr-review-bundle-pr-<PR>` name.

Pass `--run-id <id>` to override auto-detection when an operator already knows the run to use.

The exact run selection lives in `select-codex-review-bundle-run.cjs` so it can be regression-tested without touching GitHub.

## Codex PR review checks

`run-codex-pr-review-checks.sh` runs the offline regression checks for:

1. Codex/Copilot quota signal detection.
2. Current Codex action window handling.
3. Exact review bundle run selection.

`run-smoke-checks.sh` calls these checks, so they run locally and in PR merge checks.
