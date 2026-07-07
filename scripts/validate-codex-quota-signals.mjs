#!/usr/bin/env node

import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const {
  detectQuotaSignals,
  isCopilotQuotaActor,
} = require("./codex-pr-review-utils.cjs");

const window = {
  actionStartedAt: "2026-07-04T08:00:00.000Z",
  actionFinishedAt: "2026-07-04T08:05:00.000Z",
};

const codexQuotaComment = {
  id: 101,
  created_at: "2026-07-04T08:02:00.000Z",
  body: "You have reached your Codex usage limits for code reviews.",
  user: { login: "chatgpt-codex-connector[bot]", type: "Bot" },
  performed_via_github_app: { slug: "chatgpt-codex-connector" },
};

assert.equal(
  detectQuotaSignals({ ...window, comments: [codexQuotaComment] }).freshCodexQuotaSignal,
  true,
  "expected Codex app/bot quota comment inside this action window should count"
);

assert.equal(
  detectQuotaSignals({
    ...window,
    comments: [{ ...codexQuotaComment, id: 102, created_at: "2026-07-04T08:06:00.000Z" }],
  }).freshCodexQuotaSignal,
  false,
  "Codex quota comments outside this action window should not count"
);

assert.equal(
  detectQuotaSignals({
    ...window,
    comments: [codexQuotaComment],
    initialCodexQuotaSignalKeys: new Set(["comment:101"]),
  }).freshCodexQuotaSignal,
  false,
  "pre-existing Codex quota comments should not become fresh signals"
);

assert.equal(
  detectQuotaSignals({
    ...window,
    comments: [{
      id: 103,
      created_at: "2026-07-04T08:02:00.000Z",
      body: "quota quota quota",
      user: { login: "chatgpt-codex-connector", type: "User" },
    }],
  }).freshCodexQuotaSignal,
  false,
  "a user spoofing a Codex-looking login/body should not count"
);

const copilotQuotaReview = {
  id: 201,
  submitted_at: "2026-07-04T08:02:00.000Z",
  body: "Copilot was unable to review this pull request because the user has reached their quota limit.",
  user: { login: "copilot-pull-request-reviewer[bot]", type: "Bot" },
};

assert.equal(
  isCopilotQuotaActor(copilotQuotaReview),
  true,
  "expected Copilot bot identity should still be recognized for fallback messaging"
);
assert.equal(
  detectQuotaSignals({ ...window, reviews: [copilotQuotaReview] }).freshCodexQuotaSignal,
  false,
  "fresh Copilot quota should not suppress Codex action failures"
);

console.log("codex quota signal simulation passed");
