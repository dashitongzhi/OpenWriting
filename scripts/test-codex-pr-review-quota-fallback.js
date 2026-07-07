#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const { detectQuotaSignals } = require("./codex-pr-review-utils.cjs");

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
