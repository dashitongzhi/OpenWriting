#!/usr/bin/env node
"use strict";

const { execFileSync } = require("node:child_process");

const DEFAULT_COMMENT_MARKER = "<!-- codex-pr-review -->";
const DEFAULT_WORKFLOW_FILE = "codex-pr-review.yml";
const trustedCommentAuthors = new Set(["github-actions", "github-actions[bot]"]);

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function extractRunIdFromBody(body) {
  const match = String(body || "").match(/\/actions\/runs\/([0-9]+)/);
  return match ? match[1] : "";
}

function commentAuthorLogin(comment) {
  return (comment && comment.author && comment.author.login) ||
    (comment && comment.user && comment.user.login) ||
    "";
}

function isTrustedCommentAuthor(comment) {
  return trustedCommentAuthors.has(commentAuthorLogin(comment));
}

function bodyHasExactArtifactName(body, artifactName) {
  const artifactPattern = new RegExp(`(^|[^A-Za-z0-9_-])${escapeRegExp(artifactName)}(?=$|[^A-Za-z0-9_-])`);
  return artifactPattern.test(String(body || ""));
}

function generatedReviewBundleSection(body, { fallbackOnly = false } = {}) {
  const text = String(body || "");
  const heading = fallbackOnly ? "## Review Fallback" : "## Review Bundle";
  const index = text.indexOf(heading);
  return index >= 0 ? text.slice(index) : "";
}

function latestMatchingCommentBody(comments, { artifactName, commentMarker = DEFAULT_COMMENT_MARKER, fallbackOnly = false }) {
  return [...(comments || [])]
    .filter((comment) => {
      const body = comment && comment.body;
      const bundleSection = generatedReviewBundleSection(body, { fallbackOnly });
      return (
        isTrustedCommentAuthor(comment) &&
        typeof body === "string" &&
        body.includes(commentMarker) &&
        bodyHasExactArtifactName(bundleSection, artifactName) &&
        /\/actions\/runs\/[0-9]+/.test(bundleSection)
      );
    })
    .sort((left, right) => {
      const leftTime = new Date(left.updatedAt || left.createdAt || 0).valueOf();
      const rightTime = new Date(right.updatedAt || right.createdAt || 0).valueOf();
      return rightTime - leftTime;
    })
    .map((comment) => generatedReviewBundleSection(comment.body, { fallbackOnly }))[0] || "";
}

function selectRunIdFromComments(comments, options) {
  for (const fallbackOnly of [true, false]) {
    const body = latestMatchingCommentBody(comments, { ...options, fallbackOnly });
    const runId = extractRunIdFromBody(body);
    if (runId) {
      return {
        runId,
        runSource: fallbackOnly ? "latest Codex fallback PR comment" : "latest Codex PR comment",
      };
    }
  }

  return null;
}

function selectRunIdFromWorkflowArtifacts(runs, artifactsByRunId, { artifactName, workflowFile = DEFAULT_WORKFLOW_FILE }) {
  const sortedRuns = [...(runs || [])].sort((left, right) => {
    const leftTime = new Date(left.createdAt || 0).valueOf();
    const rightTime = new Date(right.createdAt || 0).valueOf();
    return rightTime - leftTime;
  });

  for (const run of sortedRuns) {
    const runId = String(run.databaseId || run.id || "");
    if (!/^[0-9]+$/.test(runId)) {
      continue;
    }

    const artifacts = artifactsByRunId[runId] || [];
    if (artifacts.some((artifact) => artifact.name === artifactName && artifact.expired !== true)) {
      return {
        runId,
        runSource: `latest ${workflowFile} run with ${artifactName} artifact`,
      };
    }
  }

  return null;
}

function ghJson(ghBin, args) {
  const output = execFileSync(ghBin, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  return JSON.parse(output);
}

function fallbackGhJson(ghBin, args) {
  try {
    return ghJson(ghBin, args);
  } catch (_) {
    return null;
  }
}

function resolveRunIdWithGh({ ghBin, repo, prNumber, artifactName, workflowFile = DEFAULT_WORKFLOW_FILE }) {
  const pr = fallbackGhJson(ghBin, ["pr", "view", prNumber, "-R", repo, "--json", "comments"]);
  if (pr && Array.isArray(pr.comments)) {
    const fromComments = selectRunIdFromComments(pr.comments, { artifactName });
    if (fromComments) {
      return fromComments;
    }
  }

  const runs = fallbackGhJson(ghBin, [
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
  ]);
  if (!Array.isArray(runs)) {
    return null;
  }

  const artifactsByRunId = {};

  for (const run of [...runs].sort((left, right) => {
    const leftTime = new Date(left.createdAt || 0).valueOf();
    const rightTime = new Date(right.createdAt || 0).valueOf();
    return rightTime - leftTime;
  })) {
    const runId = String(run.databaseId || "");
    if (!/^[0-9]+$/.test(runId)) {
      continue;
    }

    const artifactResponse = fallbackGhJson(ghBin, ["api", `repos/${repo}/actions/runs/${runId}/artifacts`]);
    if (!artifactResponse || !Array.isArray(artifactResponse.artifacts)) {
      continue;
    }

    artifactsByRunId[runId] = artifactResponse.artifacts;
    const selected = selectRunIdFromWorkflowArtifacts([run], artifactsByRunId, { artifactName, workflowFile });
    if (selected) {
      return selected;
    }
  }

  return null;
}

function parseArgs(argv) {
  const options = {
    ghBin: process.env.GH_BIN || "gh",
    workflowFile: DEFAULT_WORKFLOW_FILE,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`${arg} requires a value`);
      }
      return argv[index];
    };

    if (arg === "--gh-bin") {
      options.ghBin = next();
    } else if (arg === "--repo") {
      options.repo = next();
    } else if (arg === "--pr") {
      options.prNumber = next();
    } else if (arg === "--artifact-name") {
      options.artifactName = next();
    } else if (arg === "--workflow") {
      options.workflowFile = next();
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  const requiredOptions = [
    ["repo", "--repo"],
    ["prNumber", "--pr"],
    ["artifactName", "--artifact-name"],
  ];
  for (const [key, flag] of requiredOptions) {
    if (!options[key]) {
      throw new Error(`Missing required option: ${flag}`);
    }
  }

  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const selected = resolveRunIdWithGh(options);
  if (!selected) {
    process.exitCode = 1;
    return;
  }

  process.stdout.write(`${selected.runId}\t${selected.runSource}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exit(1);
  }
}

module.exports = {
  bodyHasExactArtifactName,
  extractRunIdFromBody,
  generatedReviewBundleSection,
  isTrustedCommentAuthor,
  latestMatchingCommentBody,
  resolveRunIdWithGh,
  selectRunIdFromComments,
  selectRunIdFromWorkflowArtifacts,
};
