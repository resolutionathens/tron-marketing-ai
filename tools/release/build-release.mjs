#!/usr/bin/env node

import { createHash } from "node:crypto";
import { createReadStream, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { pipeline } from "node:stream/promises";
import { spawnSync } from "node:child_process";

const root = resolve(new URL("../..", import.meta.url).pathname);
const outDir = resolve(process.argv[2] || join(root, "dist", "release"));
const repository = process.env.GITHUB_REPOSITORY || "Facilitron/tron-marketing-ai";
if (outDir === root || outDir === resolve(root, "..") || outDir === "/") {
  throw new Error("release output must be a dedicated directory");
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function git(...args) {
  const result = spawnSync("git", ["-C", root, ...args], { encoding: "utf8" });
  if (result.status !== 0) fail(result.stderr.trim() || `git ${args.join(" ")} failed`);
  return result.stdout.trim();
}

function manifest(path) {
  return JSON.parse(readFileSync(join(root, path), "utf8"));
}

function trackedFiles(paths) {
  const result = spawnSync("git", [
    "-C", root,
    "ls-tree",
    "-r",
    "-z",
    "--name-only",
    "HEAD",
    "--",
    ...paths,
  ]);
  if (result.status !== 0) fail(result.stderr.toString().trim() || "could not inventory package");
  return result.stdout.toString().split("\0").filter(Boolean).sort();
}

async function sha256(path) {
  const hash = createHash("sha256");
  await pipeline(createReadStream(path), hash);
  return hash.digest("hex");
}

async function archive(name, version, paths) {
  const filename = `tron-${name}-v${version}.tar.gz`;
  const destination = join(outDir, filename);
  const archiveResult = spawnSync("git", [
    "-C", root,
    "archive",
    "--format=tar",
    `--prefix=tron-v${version}/`,
    "HEAD",
    "--",
    ...paths,
  ], {
    maxBuffer: 100 * 1024 * 1024,
  });
  if (archiveResult.status !== 0) {
    fail(archiveResult.stderr.toString().trim() || `could not assemble ${filename}`);
  }
  const gzipResult = spawnSync("gzip", ["-n", "-9"], {
    input: archiveResult.stdout,
    maxBuffer: 100 * 1024 * 1024,
  });
  if (gzipResult.status !== 0) {
    fail(gzipResult.stderr.toString().trim() || `could not compress ${filename}`);
  }
  writeFileSync(destination, gzipResult.stdout);
  return {
    harness: name,
    filename,
    location: `https://github.com/${repository}/releases/download/v${version}/${filename}`,
    sha256: await sha256(destination),
    bytes: statSync(destination).size,
    inventory: trackedFiles(paths),
  };
}

const claude = manifest(".claude-plugin/plugin.json");
const codex = manifest(".codex-plugin/plugin.json");
if (claude.name !== "tron" || codex.name !== "tron") fail("both package names must be tron");
if (claude.version !== codex.version) fail("Claude and Codex package versions must match");
if (!/^\d+\.\d+\.\d+$/.test(claude.version)) fail("package version must be stable semver");

const dirty = git("status", "--porcelain", "--untracked-files=no");
if (dirty) fail(`tracked files must be committed before building a release:\n${dirty}`);

mkdirSync(outDir, { recursive: true });
const version = claude.version;
const commit = git("rev-parse", "HEAD");
const commonPaths = ["skills", "agents", "tools", "hooks", "README.md", "WORKER_CONTRACT.md"];
const packages = [
  await archive("claude", version, [".claude-plugin", ...commonPaths]),
  await archive("codex", version, [".codex-plugin", ".agents", ...commonPaths]),
];

const release = {
  schemaVersion: 1,
  name: "tron",
  version,
  tag: `v${version}`,
  commit,
  source: `https://github.com/${repository}/tree/${commit}`,
  currentReleaseApi: `https://api.github.com/repos/${repository}/releases/latest`,
  packages,
};
const releasePath = join(outDir, "release-manifest.json");
writeFileSync(releasePath, `${JSON.stringify(release, null, 2)}\n`);
const checksumLines = [
  ...packages.map((entry) => `${entry.sha256}  ${entry.filename}`),
  `${await sha256(releasePath)}  ${basename(releasePath)}`,
];
writeFileSync(join(outDir, "SHA256SUMS"), `${checksumLines.join("\n")}\n`);
console.log(JSON.stringify({ ok: true, outDir, version, commit, packages }, null, 2));
