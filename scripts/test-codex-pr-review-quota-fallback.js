#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");

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

const quotaPattern = /\b(quota|usage limit|usage limits|rate limit|billing limit)\b/i;
const codexQuotaBotLogins = new Set(["chatgpt-codex-connector"]);
const isCodexQuotaAuthor = (user) => user && codexQuotaBotLogins.has(user.login);
const isFreshSignal = (timestamp, reviewStartedAt) => {
  const parsed = new Date(timestamp);
  return !Number.isNaN(parsed.valueOf()) && parsed >= reviewStartedAt;
};

function detectFreshQuotaSignals({ reviewStartedAt, comments = [], reviews = [] }) {
  const startedAt = new Date(reviewStartedAt);
  const freshCodexQuotaSignal =
    comments.some((comment) =>
      isCodexQuotaAuthor(comment.user) &&
      quotaPattern.test(comment.body || "") &&
      isFreshSignal(comment.created_at, startedAt)
    ) ||
    reviews.some((review) =>
      isCodexQuotaAuthor(review.user) &&
      quotaPattern.test(review.body || "") &&
      isFreshSignal(review.submitted_at, startedAt)
    );
  const freshCopilotQuotaSignal = reviews.some((review) =>
    review.user &&
    review.user.login === "copilot-pull-request-reviewer" &&
    quotaPattern.test(review.body || "") &&
    isFreshSignal(review.submitted_at, startedAt)
  );

  return { freshCodexQuotaSignal, freshCopilotQuotaSignal };
}

const reviewStartedAt = "2026-07-04T12:00:00.000Z";

assert.deepEqual(
  detectFreshQuotaSignals({
    reviewStartedAt,
    comments: [
      {
        user: { login: "chatgpt-codex-connector" },
        body: "Previous run hit a quota limit.",
        created_at: "2026-07-04T11:59:59.000Z",
      },
    ],
    reviews: [
      {
        user: { login: "copilot-pull-request-reviewer" },
        body: "Previous run hit a usage limit.",
        submitted_at: "2026-07-04T11:58:00.000Z",
      },
    ],
  }),
  { freshCodexQuotaSignal: false, freshCopilotQuotaSignal: false },
  "historical quota comments/reviews must not count as current-run fallback signals"
);

assert.deepEqual(
  detectFreshQuotaSignals({
    reviewStartedAt,
    comments: [
      {
        user: { login: "chatgpt-codex-connector" },
        body: "Current run hit a quota limit.",
        created_at: "2026-07-04T12:00:01.000Z",
      },
    ],
  }),
  { freshCodexQuotaSignal: true, freshCopilotQuotaSignal: false },
  "fresh Codex quota comments must count as current-run fallback signals"
);

assert.deepEqual(
  detectFreshQuotaSignals({
    reviewStartedAt,
    reviews: [
      {
        user: { login: "copilot-pull-request-reviewer" },
        body: "Current run hit a usage limit.",
        submitted_at: "2026-07-04T12:00:01.000Z",
      },
    ],
  }),
  { freshCodexQuotaSignal: false, freshCopilotQuotaSignal: true },
  "fresh Copilot quota reviews must count as current-run fallback signals"
);

console.log("codex-pr-review quota fallback checks passed");
