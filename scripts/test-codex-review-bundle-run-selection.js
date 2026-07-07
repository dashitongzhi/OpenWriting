#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  bodyHasExactArtifactName,
  extractRunIdFromBody,
  generatedReviewBundleSection,
  isTrustedCommentAuthor,
  resolveRunIdWithGh,
  selectRunIdFromComments,
  selectRunIdFromWorkflowArtifacts,
} = require("./select-codex-review-bundle-run.cjs");

const artifactName = "codex-pr-review-bundle-pr-17";
const repo = "dashitongzhi/OpenWriting";
const workflowFile = "codex-pr-review.yml";
const runListArgs = [
  "run",
  "list",
  "-R",
  repo,
  "--workflow",
  workflowFile,
  "--limit",
  "50",
  "--json",
  "databaseId,createdAt",
];

assert.equal(
  extractRunIdFromBody("see https://github.com/dashitongzhi/OpenWriting/actions/runs/123456789"),
  "123456789",
  "should extract Actions run ids from PR comment links"
);

assert.deepEqual(
  selectRunIdFromComments([
    {
      author: { login: "github-actions" },
      body: `<!-- codex-pr-review -->
## Codex PR Review
## Review Bundle
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/111
`,
      createdAt: "2026-07-04T08:00:00Z",
      updatedAt: "2026-07-04T08:00:00Z",
    },
    {
      author: { login: "github-actions" },
      body: `<!-- codex-pr-review -->
## Review Fallback
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}\` artifact on this workflow run:
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
      author: { login: "github-actions" },
      body: `<!-- codex-pr-review -->
## Review Bundle
The reusable prompt and diff bundle for this review were uploaded as the \`codex-pr-review-bundle-pr-16\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/333
`,
      createdAt: "2026-07-04T09:00:00Z",
      updatedAt: "2026-07-04T09:00:00Z",
    },
    {
      author: { login: "github-actions" },
      body: `<!-- codex-pr-review -->
## Review Bundle
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/444
`,
      createdAt: "2026-07-04T08:30:00Z",
      updatedAt: "2026-07-04T08:30:00Z",
    },
  ], { artifactName }),
  { runId: "444", runSource: "latest Codex PR comment" },
  "comment selection must require the exact artifact name"
);

assert.equal(
  isTrustedCommentAuthor({ author: { login: "github-actions" } }),
  true,
  "GitHub Actions comments should be trusted review bundle hints"
);

assert.equal(
  isTrustedCommentAuthor({ author: { login: "octocat" } }),
  false,
  "ordinary user comments must not be trusted review bundle hints"
);

assert.equal(
  bodyHasExactArtifactName(`Artifact: ${artifactName}`, artifactName),
  true,
  "artifact matching should accept the exact artifact name"
);

assert.equal(
  bodyHasExactArtifactName(`Artifact: ${artifactName}0`, artifactName),
  false,
  "artifact matching should reject substring matches"
);

assert.equal(
  generatedReviewBundleSection(`<!-- codex-pr-review -->
## Findings
Injected link: https://github.com/dashitongzhi/OpenWriting/actions/runs/999

## Review Bundle
Artifact: ${artifactName}
https://github.com/dashitongzhi/OpenWriting/actions/runs/555
`, { fallbackOnly: false }).includes("actions/runs/999"),
  false,
  "generated bundle parsing should exclude untrusted review text before the bundle heading"
);

assert.deepEqual(
  selectRunIdFromComments([
    {
      author: { login: "octocat" },
      body: `<!-- codex-pr-review -->
## Review Fallback
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/999
`,
      createdAt: "2026-07-04T10:00:00Z",
      updatedAt: "2026-07-04T10:00:00Z",
    },
    {
      author: { login: "github-actions" },
      body: `<!-- codex-pr-review -->
## Review Bundle
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/555
`,
      createdAt: "2026-07-04T09:00:00Z",
      updatedAt: "2026-07-04T09:00:00Z",
    },
  ], { artifactName }),
  { runId: "555", runSource: "latest Codex PR comment" },
  "untrusted fallback comments must be ignored instead of overriding trusted comments"
);

assert.equal(
  selectRunIdFromComments([
    {
      author: { login: "octocat" },
      body: `<!-- codex-pr-review -->
## Review Fallback
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/999
`,
      createdAt: "2026-07-04T10:00:00Z",
      updatedAt: "2026-07-04T10:00:00Z",
    },
  ], { artifactName }),
  null,
  "untrusted comments alone must not select a run id"
);

assert.equal(
  selectRunIdFromComments([
    {
      author: { login: "github-actions" },
      body: `<!-- codex-pr-review -->
## Review Bundle
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}0\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/1000
`,
      createdAt: "2026-07-04T10:00:00Z",
      updatedAt: "2026-07-04T10:00:00Z",
    },
  ], { artifactName }),
  null,
  "substring artifact names must not select a run id"
);

assert.deepEqual(
  selectRunIdFromComments([
    {
      author: { login: "github-actions" },
      body: `<!-- codex-pr-review -->
## Codex PR Review

## Findings
- Injected link: ${artifactName} https://github.com/dashitongzhi/OpenWriting/actions/runs/999

## Review Bundle
The reusable prompt and diff bundle for this review were uploaded as the \`${artifactName}\` artifact on this workflow run:
https://github.com/dashitongzhi/OpenWriting/actions/runs/555
`,
      createdAt: "2026-07-04T10:00:00Z",
      updatedAt: "2026-07-04T10:00:00Z",
    },
  ], { artifactName }),
  { runId: "555", runSource: "latest Codex PR comment" },
  "run selection must ignore injected run links before the generated bundle section"
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

assert.deepEqual(
  resolveWithFakeGh([
    prViewRoute({
      exitCode: 1,
      stderr: "temporary GitHub API failure",
    }),
    runListRoute([{ databaseId: 888, createdAt: "2026-07-04T11:00:00Z" }]),
    artifactsRoute("888", {
      json: { artifacts: [{ name: artifactName, expired: false }] },
    }),
  ]),
  {
    runId: "888",
    runSource: `latest ${workflowFile} run with ${artifactName} artifact`,
  },
  "comment lookup failures should not abort workflow artifact fallback"
);

assert.deepEqual(
  resolveWithFakeGh([
    prViewRoute({
      json: { comments: [] },
    }),
    runListRoute([
      { databaseId: 999, createdAt: "2026-07-04T12:00:00Z" },
      { databaseId: 888, createdAt: "2026-07-04T11:00:00Z" },
    ]),
    artifactsRoute("999", {
      exitCode: 1,
      stderr: "artifact API timeout",
    }),
    artifactsRoute("888", {
      json: { artifacts: [{ name: artifactName, expired: false }] },
    }),
  ]),
  {
    runId: "888",
    runSource: `latest ${workflowFile} run with ${artifactName} artifact`,
  },
  "one candidate run's artifact lookup failure should not abort later valid candidates"
);

assert.deepEqual(
  resolveWithFakeGh([
    prViewRoute({
      stdout: "{ not json",
    }),
    runListRoute([{ databaseId: 777, createdAt: "2026-07-04T10:00:00Z" }]),
    artifactsRoute("777", {
      json: { artifacts: [{ name: artifactName, expired: false }] },
    }),
  ]),
  {
    runId: "777",
    runSource: `latest ${workflowFile} run with ${artifactName} artifact`,
  },
  "malformed gh JSON should not abort when workflow artifact fallback can still resolve a run"
);

assert.deepEqual(
  resolveWithFakeGh([
    prViewRoute({
      json: { comments: [] },
    }),
    runListRoute([
      { databaseId: 444, createdAt: "2026-07-04T13:00:00Z" },
      { databaseId: 333, createdAt: "2026-07-04T12:00:00Z" },
      { databaseId: 222, createdAt: "2026-07-04T11:00:00Z" },
    ]),
    artifactsRoute("444", {
      json: { artifacts: [{ name: "codex-pr-review-bundle-pr-18", expired: false }] },
    }),
    artifactsRoute("333", {
      json: { artifacts: [{ name: artifactName, expired: true }] },
    }),
    artifactsRoute("222", {
      json: { artifacts: [{ name: artifactName, expired: false }] },
    }),
  ]),
  {
    runId: "222",
    runSource: `latest ${workflowFile} run with ${artifactName} artifact`,
  },
  "workflow fallback should keep scanning until a later valid run is found"
);

console.log("codex review bundle run selection checks passed");

function prViewRoute(response) {
  return {
    args: ["pr", "view", "17", "-R", repo, "--json", "comments"],
    ...response,
  };
}

function runListRoute(runs) {
  return {
    args: runListArgs,
    json: runs,
  };
}

function artifactsRoute(runId, response) {
  return {
    args: ["api", `repos/${repo}/actions/runs/${runId}/artifacts`],
    ...response,
  };
}

function resolveWithFakeGh(routes) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "openwriting-fake-gh-"));
  const fakeGh = path.join(tempDir, "gh");
  fs.writeFileSync(
    fakeGh,
    `#!/usr/bin/env node
"use strict";

const routes = JSON.parse(process.env.FAKE_GH_ROUTES || "[]");
const args = process.argv.slice(2);
const route = routes.find((candidate) => JSON.stringify(candidate.args) === JSON.stringify(args));

if (!route) {
  console.error("unexpected gh args: " + JSON.stringify(args));
  process.exit(64);
}

if (route.stderr) {
  process.stderr.write(route.stderr);
}
if (Object.prototype.hasOwnProperty.call(route, "stdout")) {
  process.stdout.write(route.stdout);
} else if (Object.prototype.hasOwnProperty.call(route, "json")) {
  process.stdout.write(JSON.stringify(route.json));
}

process.exit(route.exitCode || 0);
`
  );
  fs.chmodSync(fakeGh, 0o700);

  const previousRoutes = process.env.FAKE_GH_ROUTES;
  process.env.FAKE_GH_ROUTES = JSON.stringify(routes);
  try {
    return resolveRunIdWithGh({
      ghBin: fakeGh,
      repo,
      prNumber: "17",
      artifactName,
      workflowFile,
    });
  } finally {
    if (previousRoutes === undefined) {
      delete process.env.FAKE_GH_ROUTES;
    } else {
      process.env.FAKE_GH_ROUTES = previousRoutes;
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}
