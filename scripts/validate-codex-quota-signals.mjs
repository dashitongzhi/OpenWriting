#!/usr/bin/env node

import assert from "node:assert/strict";

const quotaPattern = /\b(quota|usage limit|usage limits|rate limit|billing limit)\b/i;
const codexQuotaBotLogins = new Set([
  "chatgpt-codex-connector[bot]",
  "chatgpt-codex-connector",
]);
const codexQuotaAppSlugs = new Set(["chatgpt-codex-connector"]);
const copilotQuotaBotLogins = new Set([
  "copilot-pull-request-reviewer[bot]",
  "copilot-pull-request-reviewer",
]);

const isCodexQuotaActor = (signal) => {
  const user = signal && signal.user;
  if (!user || user.type !== "Bot" || !codexQuotaBotLogins.has(user.login)) {
    return false;
  }

  const app = signal.performed_via_github_app;
  return !app || codexQuotaAppSlugs.has(app.slug);
};

const isCopilotQuotaActor = (signal) => {
  const user = signal && signal.user;
  return user && user.type === "Bot" && copilotQuotaBotLogins.has(user.login);
};

const isDuringThisCodexAction = (timestamp, startedAt, finishedAt) => {
  const parsed = new Date(timestamp);
  return (
    !Number.isNaN(parsed.valueOf()) &&
    parsed >= startedAt &&
    parsed <= finishedAt
  );
};

const freshCodexQuotaSignal = ({
  comments = [],
  reviews = [],
  initialSignalKeys = new Set(),
  actionStartedAt,
  actionFinishedAt,
}) => {
  const startedAt = new Date(actionStartedAt);
  const finishedAt = new Date(actionFinishedAt);

  return (
    comments.some((comment) =>
      isCodexQuotaActor(comment) &&
      quotaPattern.test(comment.body || "") &&
      !initialSignalKeys.has(`comment:${comment.id}`) &&
      isDuringThisCodexAction(comment.created_at, startedAt, finishedAt)
    ) ||
    reviews.some((review) =>
      isCodexQuotaActor(review) &&
      quotaPattern.test(review.body || "") &&
      !initialSignalKeys.has(`review:${review.id}`) &&
      isDuringThisCodexAction(review.submitted_at, startedAt, finishedAt)
    )
  );
};

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
  freshCodexQuotaSignal({ ...window, comments: [codexQuotaComment] }),
  true,
  "expected Codex app/bot quota comment inside this action window should count"
);

assert.equal(
  freshCodexQuotaSignal({
    ...window,
    comments: [{ ...codexQuotaComment, id: 102, created_at: "2026-07-04T08:06:00.000Z" }],
  }),
  false,
  "Codex quota comments outside this action window should not count"
);

assert.equal(
  freshCodexQuotaSignal({
    ...window,
    comments: [codexQuotaComment],
    initialSignalKeys: new Set(["comment:101"]),
  }),
  false,
  "pre-existing Codex quota comments should not become fresh signals"
);

assert.equal(
  freshCodexQuotaSignal({
    ...window,
    comments: [{
      id: 103,
      created_at: "2026-07-04T08:02:00.000Z",
      body: "quota quota quota",
      user: { login: "chatgpt-codex-connector", type: "User" },
    }],
  }),
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
  freshCodexQuotaSignal({ ...window, reviews: [copilotQuotaReview] }),
  false,
  "fresh Copilot quota should not suppress Codex action failures"
);

console.log("codex quota signal simulation passed");
