#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const {
  extractRunIdFromBody,
  selectRunIdFromComments,
  selectRunIdFromWorkflowArtifacts,
} = require("./select-codex-review-bundle-run.cjs");

const artifactName = "codex-pr-review-bundle-pr-17";

assert.equal(
  extractRunIdFromBody("see https://github.com/dashitongzhi/OpenWriting/actions/runs/123456789"),
  "123456789",
  "should extract Actions run ids from PR comment links"
);

assert.deepEqual(
  selectRunIdFromComments([
    {
      body: `<!-- codex-pr-review -->
## Codex PR Review
Artifact: ${artifactName}
https://github.com/dashitongzhi/OpenWriting/actions/runs/111
`,
      createdAt: "2026-07-04T08:00:00Z",
      updatedAt: "2026-07-04T08:00:00Z",
    },
    {
      body: `<!-- codex-pr-review -->
## Review Fallback
Artifact: ${artifactName}
https://github.com/dashitongzhi/OpenWriting/actions/runs/222
`,
      createdAt: "2026-07-04T07:00:00Z",
      updatedAt: "2026-07-04T07:00:00Z",
    },
  ], { artifactName }),
  { runId: "222", runSource: "latest Codex fallback PR comment" },
  "fallback comments should be preferred over newer non-fallback comments"
);

assert.deepEqual(
  selectRunIdFromComments([
    {
      body: `<!-- codex-pr-review -->
Artifact: codex-pr-review-bundle-pr-16
https://github.com/dashitongzhi/OpenWriting/actions/runs/333
`,
      createdAt: "2026-07-04T09:00:00Z",
      updatedAt: "2026-07-04T09:00:00Z",
    },
    {
      body: `<!-- codex-pr-review -->
Artifact: ${artifactName}
https://github.com/dashitongzhi/OpenWriting/actions/runs/444
`,
      createdAt: "2026-07-04T08:30:00Z",
      updatedAt: "2026-07-04T08:30:00Z",
    },
  ], { artifactName }),
  { runId: "444", runSource: "latest Codex PR comment" },
  "comment selection must require the exact artifact name"
);

assert.deepEqual(
  selectRunIdFromWorkflowArtifacts(
    [
      { databaseId: 555, createdAt: "2026-07-04T08:00:00Z" },
      { databaseId: 666, createdAt: "2026-07-04T09:00:00Z" },
      { databaseId: 777, createdAt: "2026-07-04T10:00:00Z" },
    ],
    {
      555: [{ name: artifactName, expired: false }],
      666: [{ name: artifactName, expired: true }],
      777: [{ name: "codex-pr-review-bundle-pr-18", expired: false }],
    },
    { artifactName, workflowFile: "codex-pr-review.yml" }
  ),
  {
    runId: "555",
    runSource: `latest codex-pr-review.yml run with ${artifactName} artifact`,
  },
  "workflow fallback should pick the newest non-expired exact artifact"
);

console.log("codex review bundle run selection checks passed");
