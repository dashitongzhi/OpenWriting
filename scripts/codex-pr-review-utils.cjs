#!/usr/bin/env node
"use strict";

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

function hasQuotaBody(signal) {
  return quotaPattern.test((signal && signal.body) || "");
}

function isCodexQuotaActor(signal) {
  const user = signal && signal.user;
  if (!user || user.type !== "Bot" || !codexQuotaBotLogins.has(user.login)) {
    return false;
  }

  const app = signal.performed_via_github_app;
  return !app || codexQuotaAppSlugs.has(app.slug);
}

function isCopilotQuotaActor(signal) {
  const user = signal && signal.user;
  return Boolean(user && user.type === "Bot" && copilotQuotaBotLogins.has(user.login));
}

function parseValidDate(value) {
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed;
}

function isDuringWindow(timestamp, startedAt, finishedAt) {
  const parsed = parseValidDate(timestamp);
  const started = parseValidDate(startedAt);
  const finished = parseValidDate(finishedAt);
  return Boolean(parsed && started && finished && parsed >= started && parsed <= finished);
}

function codexQuotaSignalKey(kind, signal) {
  return signal && signal.id != null ? `${kind}:${signal.id}` : "";
}

function buildCodexQuotaSignalKeys(metadata = {}) {
  return new Set([
    ...(metadata.codexQuotaComments || []).map((comment) => `comment:${comment.id}`),
    ...(metadata.codexQuotaReviews || []).map((review) => `review:${review.id}`),
  ]);
}

function isFreshCodexSignal(signal, kind, initialSignalKeys, actionStartedAt, actionFinishedAt) {
  const key = codexQuotaSignalKey(kind, signal);
  return (
    isCodexQuotaActor(signal) &&
    hasQuotaBody(signal) &&
    (!key || !initialSignalKeys.has(key)) &&
    isDuringWindow(
      kind === "comment" ? signal.created_at : signal.submitted_at,
      actionStartedAt,
      actionFinishedAt
    )
  );
}

function isFreshCopilotSignal(signal, actionStartedAt, actionFinishedAt) {
  return (
    isCopilotQuotaActor(signal) &&
    hasQuotaBody(signal) &&
    isDuringWindow(signal.submitted_at, actionStartedAt, actionFinishedAt)
  );
}

function detectQuotaSignals({
  comments = [],
  reviews = [],
  initialCodexQuotaSignalKeys = new Set(),
  actionStartedAt,
  actionFinishedAt,
} = {}) {
  const codexQuotaComments = comments.filter((comment) => isCodexQuotaActor(comment) && hasQuotaBody(comment));
  const codexQuotaReviews = reviews.filter((review) => isCodexQuotaActor(review) && hasQuotaBody(review));
  const copilotQuotaReviews = reviews.filter((review) => isCopilotQuotaActor(review) && hasQuotaBody(review));
  const hasActionWindow = actionStartedAt != null && actionFinishedAt != null;

  const freshCodexQuotaSignal = hasActionWindow && (
    comments.some((comment) =>
      isFreshCodexSignal(
        comment,
        "comment",
        initialCodexQuotaSignalKeys,
        actionStartedAt,
        actionFinishedAt
      )
    ) ||
    reviews.some((review) =>
      isFreshCodexSignal(
        review,
        "review",
        initialCodexQuotaSignalKeys,
        actionStartedAt,
        actionFinishedAt
      )
    )
  );
  const freshCopilotQuotaSignal = hasActionWindow && reviews.some((review) =>
    isFreshCopilotSignal(review, actionStartedAt, actionFinishedAt)
  );

  return {
    codexQuotaComments,
    codexQuotaReviews,
    copilotQuotaReviews,
    codexQuotaSignal: codexQuotaComments.length > 0 || codexQuotaReviews.length > 0,
    copilotQuotaSignal: copilotQuotaReviews.length > 0,
    freshCodexQuotaSignal: Boolean(freshCodexQuotaSignal),
    freshCopilotQuotaSignal: Boolean(freshCopilotQuotaSignal),
  };
}

module.exports = {
  buildCodexQuotaSignalKeys,
  detectQuotaSignals,
  hasQuotaBody,
  isCodexQuotaActor,
  isCopilotQuotaActor,
  isDuringWindow,
};
