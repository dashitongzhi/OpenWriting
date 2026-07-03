# Local Codex PR Review Fallback

`.github/workflows/codex-pr-review.yml` uploads a reusable artifact named
`codex-pr-review-bundle-pr-<PR>` whenever it builds the hosted review prompt. If
the hosted Codex or Copilot review is blocked by quota, usage limits, or another
action failure, use the repo-local helper to continue the review locally.

```sh
scripts/download-codex-review-bundle.sh <pr-number>
```

The helper downloads the latest matching bundle, prepares a local directory such
as `.codex-pr-review-bundles/pr-17`, and ensures these files are available at the
top level:

- `review-prompt.md`
- `diff-bundle.md`
- `continue-review.md`
- `metadata.json`

If the fallback comment links a specific Actions run, pass it to avoid selecting
an older artifact:

```sh
scripts/download-codex-review-bundle.sh <pr-number> --run-id <run-id>
```

After the command finishes, follow the printed instructions: submit
`review-prompt.md` to a local trusted reviewer, keep `diff-bundle.md` available
as preserved PR context, save the result as `local-review.md`, then post it back
to the PR with the `gh pr comment` command shown by the helper.
