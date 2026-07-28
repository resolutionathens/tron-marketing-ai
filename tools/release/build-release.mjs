#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  createReadStream,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, relative, resolve } from "node:path";
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

function normalizeTimes(path) {
  const stat = statSync(path);
  if (stat.isDirectory()) {
    for (const entry of readdirSync(path).sort()) normalizeTimes(join(path, entry));
  }
  utimesSync(path, 0, 0);
}

async function archiveGenerated(harness, packageName, version, source) {
  normalizeTimes(source);
  const filename = `tron-${packageName}-${harness}-v${version}.tar.gz`;
  const destination = join(outDir, filename);
  const inventory = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else inventory.push(relative(source, path));
    }
  };
  walk(source);
  const initResult = spawnSync("git", ["-C", source, "init", "-q"], { encoding: "utf8" });
  if (initResult.status !== 0) fail(initResult.stderr.trim() || `could not initialize ${packageName}`);
  const addResult = spawnSync(
    "git",
    ["--literal-pathspecs", "-C", source, "add", "-f", "--", ...inventory],
    { encoding: "utf8" },
  );
  if (addResult.status !== 0) fail(addResult.stderr.trim() || `could not stage ${packageName}`);
  const treeResult = spawnSync("git", ["-C", source, "write-tree"], { encoding: "utf8" });
  if (treeResult.status !== 0) fail(treeResult.stderr.trim() || `could not write ${packageName} tree`);
  const commitResult = spawnSync("git", ["-C", source, "commit-tree", treeResult.stdout.trim(), "-m", "package"], {
    encoding: "utf8",
    env: {
      ...process.env,
      GIT_AUTHOR_NAME: "Tron Release",
      GIT_AUTHOR_EMAIL: "release@facilitron.com",
      GIT_AUTHOR_DATE: "1970-01-01T00:00:00Z",
      GIT_COMMITTER_NAME: "Tron Release",
      GIT_COMMITTER_EMAIL: "release@facilitron.com",
      GIT_COMMITTER_DATE: "1970-01-01T00:00:00Z",
    },
  });
  if (commitResult.status !== 0) fail(commitResult.stderr.trim() || `could not commit ${packageName} tree`);
  const archiveResult = spawnSync("git", ["-C", source, "archive", "--format=tar", commitResult.stdout.trim()], {
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
    harness,
    package: `tron-${packageName}`,
    filename,
    location: `https://github.com/${repository}/releases/download/v${version}/${filename}`,
    sha256: await sha256(destination),
    bytes: statSync(destination).size,
    inventory,
  };
}

const claude = manifest(".claude-plugin/plugin.json");
const codex = manifest(".codex-plugin/plugin.json");
if (claude.name !== "tron" || codex.name !== "tron") fail("both package names must be tron");
if (claude.version !== codex.version) fail("Claude and Codex package versions must match");
if (!/^\d+\.\d+\.\d+$/.test(claude.version)) fail("package version must be stable semver");

const dirty = git("status", "--porcelain", "--untracked-files=no");
if (dirty) {
  fail(
    `tracked files must be committed before building a release; the release fixture requires committed tracked changes, so rerun the release fixture after the atomic commit:\n${dirty}`,
  );
}

mkdirSync(outDir, { recursive: true });
const version = claude.version;
const commit = git("rev-parse", "HEAD");
const commonPaths = ["skills", "agents", "tools", "hooks", "README.md", "WORKER_CONTRACT.md"];
const packages = [
  await archive("claude", version, [".claude-plugin", ...commonPaths]),
  await archive("codex", version, [".codex-plugin", ".agents", ...commonPaths]),
];
const packageRoot = mkdtempSync(join(tmpdir(), "tron-role-packages."));
try {
  const build = spawnSync("node", [join(root, "tools/package/build-packages.mjs"), packageRoot], {
    encoding: "utf8",
  });
  if (build.status !== 0) fail(build.stderr.trim() || "could not build role package matrix");
  // The generated inventory is the single source of truth for what was built, so
  // repo bundles ship without the release re-deriving the package map's shape.
  const inventory = JSON.parse(readFileSync(join(packageRoot, "inventory.json"), "utf8"));
  for (const entry of inventory.packages) {
    packages.push(
      await archiveGenerated(
        entry.harness,
        entry.package.replace(/^tron-/, ""),
        version,
        join(packageRoot, entry.harness, entry.package),
      ),
    );
  }
} finally {
  rmSync(packageRoot, { recursive: true, force: true });
}

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
