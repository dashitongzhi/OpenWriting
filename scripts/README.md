# Scripts

## Codex review bundle download

`download-codex-review-bundle.sh` downloads the `codex-pr-review-bundle-pr-<PR>` artifact for local review continuation.

By default it resolves an exact GitHub Actions run before downloading:

1. Use the latest PR comment containing `<!-- codex-pr-review -->`, the exact artifact name, and an Actions run URL, preferring a `## Review Fallback` comment.
2. If the PR comment is unavailable, scan recent `codex-pr-review.yml` runs and pick the newest run whose artifacts include the exact `codex-pr-review-bundle-pr-<PR>` name.

Pass `--run-id <id>` to override auto-detection when an operator already knows the run to use.

Offline validation idea: set `GH_BIN` to a temporary fake `gh` script that returns two Codex PR comments, one old run and one newer `## Review Fallback` run, then assert the fake `run download` receives the newer run id and writes `review-prompt.md` plus `diff-bundle.md` into a temp output directory. This exercises the run-selection path without touching GitHub.
