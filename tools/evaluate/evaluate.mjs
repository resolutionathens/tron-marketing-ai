#!/usr/bin/env node
// Skill evaluation harness.
//
// Runs the eval scenarios under evaluations/ and the co-located golden examples
// under skills/<name>/example/*.json, in one of two modes per scenario:
//
//   deterministic  — the scenario carries an `exec` block. The harness runs the
//                    command and asserts its exit code / stdout. Fully offline,
//                    CI-safe, no model calls.
//
//   judge          — the scenario carries `expected_behavior`. The harness loads
//                    the SKILL.md under test, asks `claude -p` to describe the
//                    actions it WOULD take (no side effects), then asks a second
//                    `claude -p` call to grade that plan against the expected
//                    behaviors. Requires the `claude` CLI and spends tokens, so
//                    it is opt-in (--judge) and skipped by default.
//
// Usage:
//   node tools/evaluate/evaluate.mjs                 # deterministic only (default)
//   node tools/evaluate/evaluate.mjs --judge         # deterministic + LLM-judge
//   node tools/evaluate/evaluate.mjs --judge-only    # judge scenarios only
//   node tools/evaluate/evaluate.mjs --filter gh     # only scenarios whose path/skill matches
//   node tools/evaluate/evaluate.mjs --dry-run       # list what would run, make no calls
//   node tools/evaluate/evaluate.mjs --json          # machine-readable summary on stdout
//
// Exit code is non-zero if any executed scenario fails (judge scenarios that are
// skipped because --judge was not passed do not count as failures).

import {
  readdirSync,
  readFileSync,
  statSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  rmSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, relative } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..");

// ---- args ------------------------------------------------------------------

const argv = process.argv.slice(2);
const opts = {
  judge: argv.includes("--judge") || argv.includes("--judge-only"),
  judgeOnly: argv.includes("--judge-only"),
  deterministicOnly: argv.includes("--deterministic-only"),
  dryRun: argv.includes("--dry-run"),
  json: argv.includes("--json"),
  filter: argFlag("--filter"),
  roots: [],
};
if (argv.includes("--help") || argv.includes("-h")) {
  printHelpAndExit();
}

function argFlag(name) {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : null;
}

// Positional args (anything not a flag / flag-value) are extra eval roots.
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--filter") {
    i++;
    continue;
  }
  if (a.startsWith("--") || a === "-h") continue;
  opts.roots.push(a);
}

// ---- discovery -------------------------------------------------------------

function walkJson(path) {
  const out = [];
  if (!existsSync(path)) return out;
  const st = statSync(path);
  if (st.isFile()) {
    if (path.endsWith(".json")) out.push(path);
    return out;
  }
  for (const entry of readdirSync(path)) {
    out.push(...walkJson(join(path, entry)));
  }
  return out;
}

function discover() {
  const files = new Set();
  const roots = opts.roots.length
    ? opts.roots.map((r) => join(REPO_ROOT, r))
    : [join(REPO_ROOT, "evaluations")];

  for (const root of roots) {
    for (const f of walkJson(root)) files.add(f);
  }
  // Co-located golden examples (only when scanning the default roots).
  if (!opts.roots.length) {
    const skillsDir = join(REPO_ROOT, "skills");
    if (existsSync(skillsDir)) {
      for (const skill of readdirSync(skillsDir)) {
        const exDir = join(skillsDir, skill, "example");
        for (const f of walkJson(exDir)) files.add(f);
      }
    }
  }
  return [...files].sort();
}

// ---- scenario model --------------------------------------------------------

function loadScenario(file) {
  let raw;
  try {
    raw = JSON.parse(readFileSync(file, "utf8"));
  } catch (e) {
    return { file, error: `invalid JSON: ${e.message}` };
  }
  // template.json and fixtures with empty skills are skipped silently.
  const rel = relative(REPO_ROOT, file);
  const mode = raw.exec ? "deterministic" : "judge";
  return { file, rel, mode, ...raw };
}

function matchesFilter(s) {
  if (!opts.filter) return true;
  const hay = `${s.rel} ${(s.skills || []).join(" ")}`.toLowerCase();
  return hay.includes(opts.filter.toLowerCase());
}

// ---- deterministic runner --------------------------------------------------

function runDeterministic(s) {
  const { cmd, expect = {} } = s.exec;
  if (!Array.isArray(cmd) || cmd.length === 0) {
    return { ok: false, reasons: ["exec.cmd must be a non-empty array"] };
  }
  if (opts.dryRun) {
    return {
      ok: true,
      skipped: true,
      reasons: [`would run: ${cmd.join(" ")}`],
    };
  }
  const res = spawnSync(cmd[0], cmd.slice(1), {
    cwd: REPO_ROOT,
    encoding: "utf8",
    timeout: 60_000,
  });
  const stdout = (res.stdout || "") + (res.stderr || "");
  const reasons = [];
  let ok = true;

  if (typeof expect.exitCode === "number") {
    if (res.status !== expect.exitCode) {
      ok = false;
      reasons.push(`exit ${res.status} != expected ${expect.exitCode}`);
    }
  } else if (res.status !== 0) {
    ok = false;
    reasons.push(`exit ${res.status} (expected 0)`);
  }
  for (const needle of expect.stdoutContains || []) {
    if (!stdout.includes(needle)) {
      ok = false;
      reasons.push(`stdout missing: ${JSON.stringify(needle)}`);
    }
  }
  if (typeof expect.stdoutEquals === "string") {
    if (stdout.trim() !== expect.stdoutEquals.trim()) {
      ok = false;
      reasons.push("stdout did not equal expected");
    }
  }
  if (ok) reasons.push("all assertions passed");
  return { ok, reasons };
}

// ---- judge runner ----------------------------------------------------------

function claudeAvailable() {
  const r = spawnSync("claude", ["--version"], { encoding: "utf8" });
  return r.status === 0;
}

function claudePrint(prompt, appendSystem, cwd = REPO_ROOT) {
  const args = ["-p", "--output-format", "json"];
  if (appendSystem) args.push("--append-system-prompt", appendSystem);
  args.push(prompt);
  const r = spawnSync("claude", args, {
    cwd,
    encoding: "utf8",
    timeout: 300_000,
    maxBuffer: 32 * 1024 * 1024,
  });
  if (r.status !== 0) {
    throw new Error(
      `claude exited ${r.status}: ${(r.stderr || "").slice(0, 400)}`,
    );
  }
  try {
    const obj = JSON.parse(r.stdout);
    return obj.result ?? r.stdout;
  } catch {
    return r.stdout;
  }
}

function extractJson(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const body = fence ? fence[1] : text;
  const start = body.indexOf("{");
  const end = body.lastIndexOf("}");
  if (start < 0 || end < 0) return null;
  try {
    return JSON.parse(body.slice(start, end + 1));
  } catch {
    return null;
  }
}

// Seed a throwaway sandbox dir from a scenario's `sandbox` block and return its
// path. `sandbox.files` is a { relativePath: contents } map written first;
// `sandbox.setup` is an array of shell commands run (joined with &&) in the dir.
// Caller is responsible for removing the returned dir.
function seedSandbox(sandbox) {
  const dir = mkdtempSync(join(tmpdir(), "tron-eval-"));
  for (const [rel, contents] of Object.entries(sandbox.files || {})) {
    const full = join(dir, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, contents);
  }
  if (sandbox.setup?.length) {
    const r = spawnSync("sh", ["-c", sandbox.setup.join(" && ")], {
      cwd: dir,
      encoding: "utf8",
      timeout: 60_000,
    });
    if (r.status !== 0) {
      throw new Error(
        `sandbox setup failed (${r.status}): ${(r.stderr || r.stdout || "").slice(0, 300)}`,
      );
    }
  }
  return dir;
}

function runJudge(s) {
  if (opts.dryRun) {
    const note = s.sandbox ? " (in a seeded sandbox)" : "";
    return {
      ok: true,
      skipped: true,
      reasons: [`would run skill + judge via claude -p${note}`],
    };
  }
  const skill = (s.skills || [])[0];
  const skillPath = join(REPO_ROOT, "skills", skill || "", "SKILL.md");
  if (!skill || !existsSync(skillPath)) {
    return { ok: false, reasons: [`skill SKILL.md not found for "${skill}"`] };
  }
  const skillBody = readFileSync(skillPath, "utf8");

  // Seed a sandbox for scenarios that branch on real repo/filesystem state.
  let runCwd = REPO_ROOT;
  let sandboxDir = null;
  if (s.sandbox) {
    try {
      sandboxDir = seedSandbox(s.sandbox);
      runCwd = sandboxDir;
    } catch (e) {
      return { ok: false, reasons: [e.message] };
    }
  }

  // 1) Run the skill in "describe your plan" mode. Without a sandbox, no side
  // effects at all. With a sandbox, read-only inspection is allowed (the skill
  // must read real state to plan), and the throwaway dir absorbs any stray
  // mutation; only network / pushes are still off-limits.
  const sideEffectRule = sandboxDir
    ? [
        "You are in a throwaway sandbox working tree. You MAY run read-only",
        "inspection (git status, git diff, git diff --staged, git log, reading",
        "files) to ground your plan in the real state. Do NOT push, open PRs, or",
        "contact the network. Describe the mutating actions you would take rather",
        "than relying on them having run.",
      ]
    : [
        "DO NOT execute any side effects (no file writes, no git, no network, no",
        "shell). Instead, describe the exact ordered sequence of concrete actions",
        "and tool calls you would take, and sketch the key output you would produce.",
      ];
  const runSystem = [
    skillBody,
    "",
    "[EVALUATION MODE] You are being evaluated, not asked to act for real.",
    "Follow the skill above to satisfy the user's request.",
    ...sideEffectRule,
  ].join("\n");

  let plan;
  try {
    plan = claudePrint(s.query, runSystem, runCwd);
  } catch (e) {
    return { ok: false, reasons: [`run step failed: ${e.message}`] };
  } finally {
    // Plan captured (or failed); tear the sandbox down before the judge call.
    if (sandboxDir) rmSync(sandboxDir, { recursive: true, force: true });
  }

  // 2) Grade the plan against expected_behavior.
  const judgePrompt = [
    "You are grading whether an assistant's planned response satisfies a set of",
    "expected behaviors for a skill. Be strict: a behavior is met only if the",
    "plan clearly demonstrates it.",
    "",
    `USER REQUEST:\n${s.query}`,
    "",
    `EXPECTED BEHAVIORS (JSON):\n${JSON.stringify(s.expected_behavior, null, 2)}`,
    "",
    `ASSISTANT PLAN:\n${plan}`,
    "",
    'Return ONLY a JSON object: {"pass": boolean, "met": [strings], "missing": [strings], "notes": string}.',
    "Set pass=true only if every expected behavior is met.",
  ].join("\n");

  let verdict;
  try {
    verdict = extractJson(claudePrint(judgePrompt));
  } catch (e) {
    return { ok: false, reasons: [`judge step failed: ${e.message}`] };
  }
  if (!verdict || typeof verdict.pass !== "boolean") {
    return { ok: false, reasons: ["judge returned unparseable verdict"] };
  }
  const reasons = [];
  if (verdict.missing?.length)
    reasons.push(`missing: ${verdict.missing.join("; ")}`);
  if (verdict.notes) reasons.push(verdict.notes);
  if (!reasons.length) reasons.push("all expected behaviors met");
  return { ok: verdict.pass, reasons, verdict };
}

// ---- main ------------------------------------------------------------------

function printHelpAndExit() {
  process.stdout.write(
    [
      "Skill evaluation harness",
      "",
      "Usage: node tools/evaluate/evaluate.mjs [options] [eval-roots...]",
      "",
      "  --judge            also run LLM-judge scenarios (needs `claude`, spends tokens)",
      "  --judge-only       run only LLM-judge scenarios",
      "  --deterministic-only  run only deterministic (exec) scenarios",
      "  --filter <str>     only scenarios whose path or skill contains <str>",
      "  --dry-run          list what would run; make no model/script calls",
      "  --json             emit a JSON summary on stdout",
      "  -h, --help         this help",
      "",
    ].join("\n"),
  );
  process.exit(0);
}

function main() {
  const files = discover();
  const scenarios = files
    .map(loadScenario)
    .filter((s) => {
      if (s.error) return true; // surface JSON errors
      if (!s.skills || s.skills.length === 0) return false; // template / placeholder
      return true;
    })
    .filter(matchesFilter);

  const results = [];
  let failed = 0,
    passed = 0,
    skipped = 0;

  const judgeReady = opts.judge && !opts.dryRun ? claudeAvailable() : true;
  if (opts.judge && !opts.dryRun && !judgeReady) {
    log(
      "⚠ --judge requested but `claude` CLI not available; judge scenarios will be skipped.",
    );
  }

  for (const s of scenarios) {
    if (s.error) {
      results.push({
        rel: relative(REPO_ROOT, s.file),
        mode: "?",
        ok: false,
        reasons: [s.error],
      });
      failed++;
      continue;
    }
    // Manual-only scenarios are interactive/execution specs that judge mode
    // cannot observe reliably (e.g. git-flow: AskUserQuestion + real commit
    // hashes). Skip them in discovery-based runs; they still run if a path is
    // passed explicitly as a positional root, for on-demand experimentation.
    if (s.manual && !opts.roots.length) {
      results.push({
        rel: s.rel,
        mode: s.mode,
        skill: (s.skills || [])[0],
        ok: true,
        skipped: true,
        reasons: [
          "manual-only scenario (interactive/execution eval — see evaluations/README.md)",
        ],
      });
      skipped++;
      if (!opts.json)
        log(
          `○ skip  [manual]  ${s.rel}\n        interactive/execution eval — run by hand`,
        );
      continue;
    }

    const wantDet = !opts.judgeOnly;
    const wantJudge = opts.judge && !opts.deterministicOnly;

    let r;
    if (s.mode === "deterministic") {
      if (!wantDet) {
        skipped++;
        continue;
      }
      r = runDeterministic(s);
    } else {
      if (!wantJudge) {
        skipped++;
        continue;
      }
      if (!judgeReady) {
        skipped++;
        continue;
      }
      r = runJudge(s);
    }

    const row = { rel: s.rel, mode: s.mode, skill: (s.skills || [])[0], ...r };
    results.push(row);
    if (r.skipped) skipped++;
    else if (r.ok) passed++;
    else failed++;

    if (!opts.json) {
      const tag = r.skipped ? "○ skip" : r.ok ? "✓ pass" : "✗ FAIL";
      log(`${tag}  [${s.mode}]  ${s.rel}`);
      if (!r.ok || r.skipped)
        for (const reason of r.reasons) log(`        ${reason}`);
    }
  }

  if (opts.json) {
    process.stdout.write(
      JSON.stringify({ passed, failed, skipped, results }, null, 2) + "\n",
    );
  } else {
    log("");
    log(
      `Summary: ${passed} passed, ${failed} failed, ${skipped} skipped (${scenarios.length} discovered)`,
    );
    if (opts.dryRun) log("(dry run — no scripts or model calls were made)");
    if (!opts.judge && !opts.judgeOnly)
      log("(judge scenarios skipped — pass --judge to run them)");
  }

  process.exit(failed > 0 ? 1 : 0);
}

function log(msg) {
  process.stderr.write(msg + "\n");
}

main();
