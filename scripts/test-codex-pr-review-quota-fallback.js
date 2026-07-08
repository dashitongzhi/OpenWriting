#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  buildCodexReviewComment,
  detectCodexReviewQuotaState,
  detectQuotaSignals,
  quotaSignalMetadata,
} = require("./codex-pr-review-utils.cjs");

const workflow = fs.readFileSync(".github/workflows/codex-pr-review.yml", "utf8");

assert.equal(
  workflow.includes("EXTERNAL_CODEX_QUOTA_SIGNAL"),
  false,
  "publish_review must not consume quota state captured before the current review run"
);
assert.equal(
  workflow.includes("process.env.COPILOT_QUOTA_SIGNAL"),
  false,
  "publish_review must not consume pre-run Copilot quota state"
);
assert.equal(
  workflow.includes("helper_has_expected_exports"),
  true,
  "workflow bootstrap must validate base-checkout helper exports before skipping the fallback"
);
assert.equal(
  workflow.includes("if [[ -f scripts/codex-pr-review-utils.cjs ]]; then"),
  false,
  "workflow bootstrap must not trust mere helper file presence on the base checkout"
);

const actionStartedAt = "2026-07-04T12:00:00.000Z";
const actionFinishedAt = "2026-07-04T12:05:00.000Z";

assert.deepEqual(
  pickFreshQuotaSignals({
    comments: [
      {
        id: 1,
        user: { login: "chatgpt-codex-connector[bot]", type: "Bot" },
        body: "Previous run hit a quota limit.",
        created_at: "2026-07-04T11:59:59.000Z",
      },
    ],
    reviews: [
      {
        id: 2,
        user: { login: "copilot-pull-request-reviewer[bot]", type: "Bot" },
        body: "Previous run hit a usage limit.",
        submitted_at: "2026-07-04T11:58:00.000Z",
      },
    ],
  }),
  { freshCodexQuotaSignal: false, freshCopilotQuotaSignal: false },
  "historical quota comments/reviews must not count as current-run fallback signals"
);

assert.deepEqual(
  pickFreshQuotaSignals({
    comments: [
      {
        id: 3,
        user: { login: "chatgpt-codex-connector[bot]", type: "Bot" },
        body: "Current run hit a quota limit.",
        created_at: "2026-07-04T12:00:01.000Z",
      },
    ],
  }),
  { freshCodexQuotaSignal: true, freshCopilotQuotaSignal: false },
  "fresh Codex quota comments must count as current-run fallback signals"
);

assert.deepEqual(
  pickFreshQuotaSignals({
    reviews: [
      {
        id: 4,
        user: { login: "copilot-pull-request-reviewer[bot]", type: "Bot" },
        body: "Current run hit a usage limit.",
        submitted_at: "2026-07-04T12:00:01.000Z",
      },
    ],
  }),
  { freshCodexQuotaSignal: false, freshCopilotQuotaSignal: true },
  "fresh Copilot quota reviews must count for fallback messaging without suppressing Codex failures"
);

const initialQuotaSignals = detectCodexReviewQuotaState({
  comments: [
    {
      id: 10,
      user: { login: "chatgpt-codex-connector[bot]", type: "Bot" },
      body: "Previous run hit a quota limit.",
      created_at: "2026-07-04T11:58:00.000Z",
    },
  ],
});
const sharedQuotaSignals = detectCodexReviewQuotaState({
  comments: [
    {
      id: 10,
      user: { login: "chatgpt-codex-connector[bot]", type: "Bot" },
      body: "Previous run hit a quota limit.",
      created_at: "2026-07-04T12:01:00.000Z",
    },
    {
      id: 11,
      user: { login: "chatgpt-codex-connector[bot]", type: "Bot" },
      body: "Current run hit a quota limit.",
      created_at: "2026-07-04T12:02:00.000Z",
    },
  ],
  reviews: [
    {
      id: 12,
      user: { login: "copilot-pull-request-reviewer[bot]", type: "Bot" },
      body: "Current run hit a usage limit.",
      submitted_at: "2026-07-04T12:03:00.000Z",
    },
  ],
  initialMetadata: quotaSignalMetadata(initialQuotaSignals),
  actionStartedAt,
  actionFinishedAt,
});
const sharedComment = buildCodexReviewComment({
  codexReview: "No blocking findings.",
  hasCodexReview: true,
  codexFailed: false,
  freshCodexQuotaSignal: sharedQuotaSignals.freshCodexQuotaSignal,
  freshCopilotQuotaSignal: sharedQuotaSignals.freshCopilotQuotaSignal,
  bundleArtifactName: "codex-pr-review-bundle-pr-42",
  runUrl: "https://github.com/dashitongzhi/OpenWriting/actions/runs/123",
  owner: "dashitongzhi",
  repo: "OpenWriting",
  issueNumber: 42,
});

assert.deepEqual(
  sharedComment.fallbackReasons,
  [
    "Codex review reported a usage/quota limit.",
    "Copilot review reported a usage/quota limit.",
  ],
  "shared quota/comment path should ignore initial signals and emit only current-run fallback reasons"
);
assert.match(
  sharedComment.body,
  /<!-- codex-pr-review -->\n## Codex PR Review\n\nNo blocking findings\./,
  "shared comment builder should include the standard review marker and review body"
);
assert.match(
  sharedComment.body,
  /gh workflow run codex-pr-review\.yml -R dashitongzhi\/OpenWriting -f pr_number=42/,
  "shared fallback comment should preserve the retry command"
);
assert.match(
  sharedComment.body,
  /codex-pr-review-bundle-pr-42/,
  "shared fallback comment should include the review bundle artifact name"
);

function pickFreshQuotaSignals({ comments = [], reviews = [] }) {
  const signals = detectQuotaSignals({
    comments,
    reviews,
    actionStartedAt,
    actionFinishedAt,
  });

  return {
    freshCodexQuotaSignal: signals.freshCodexQuotaSignal,
    freshCopilotQuotaSignal: signals.freshCopilotQuotaSignal,
  };
}

console.log("codex-pr-review quota fallback checks passed");
