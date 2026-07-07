#!/usr/bin/env node
"use strict";

const { execFileSync } = require("node:child_process");

const DEFAULT_COMMENT_MARKER = "<!-- codex-pr-review -->";
const DEFAULT_WORKFLOW_FILE = "codex-pr-review.yml";

function extractRunIdFromBody(body) {
  const match = String(body || "").match(/\/actions\/runs\/([0-9]+)/);
  return match ? match[1] : "";
}

function latestMatchingCommentBody(comments, { artifactName, commentMarker = DEFAULT_COMMENT_MARKER, fallbackOnly = false }) {
  return [...(comments || [])]
    .filter((comment) => {
      const body = comment && comment.body;
      return (
        typeof body === "string" &&
        body.includes(commentMarker) &&
        body.includes(artifactName) &&
        /\/actions\/runs\/[0-9]+/.test(body) &&
        (!fallbackOnly || body.includes("## Review Fallback"))
      );
    })
    .sort((left, right) => {
      const leftTime = new Date(left.updatedAt || left.createdAt || 0).valueOf();
      const rightTime = new Date(right.updatedAt || right.createdAt || 0).valueOf();
      return rightTime - leftTime;
    })[0]?.body || "";
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

function resolveRunIdWithGh({ ghBin, repo, prNumber, artifactName, workflowFile = DEFAULT_WORKFLOW_FILE }) {
  const pr = ghJson(ghBin, ["pr", "view", prNumber, "-R", repo, "--json", "comments"]);
  const fromComments = selectRunIdFromComments(pr.comments || [], { artifactName });
  if (fromComments) {
    return fromComments;
  }

  const runs = ghJson(ghBin, [
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

    const artifactResponse = ghJson(ghBin, ["api", `repos/${repo}/actions/runs/${runId}/artifacts`]);
    artifactsByRunId[runId] = artifactResponse.artifacts || [];
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
  extractRunIdFromBody,
  latestMatchingCommentBody,
  resolveRunIdWithGh,
  selectRunIdFromComments,
  selectRunIdFromWorkflowArtifacts,
};
