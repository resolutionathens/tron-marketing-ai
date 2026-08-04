#!/usr/bin/env node
// Skill evaluation harness. Repository discovery is deterministic and offline.
// Optional model evaluation is limited to one explicitly named scenario and one
// tool-free, low-cost model call whose result is content-addressed and cached.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..");
const MODEL = "claude-haiku-4-5-20251001";
const MODEL_CALL_CAP = 1;
const MODEL_TIMEOUT_MS = 60_000;
const MODEL_MAX_OUTPUT_TOKENS = 1_024;
const MODEL_MAX_OUTPUT_BYTES = 64 * 1024;
const EVALUATOR_VERSION = 2;

const argv = process.argv.slice(2);
const opts = {
  modelScenario: argFlag("--model-eval"),
  cacheDir: argFlag("--cache-dir"),
  claudeBin: process.env.TRON_EVALUATE_CLAUDE_BIN || "claude",
  dryRun: argv.includes("--dry-run"),
  json: argv.includes("--json"),
  filter: argFlag("--filter"),
  roots: [],
};

if (argv.includes("--help") || argv.includes("-h")) printHelpAndExit();
for (const retired of ["--judge", "--judge-only"]) {
  if (argv.includes(retired)) failClosed(`${retired} was removed because discovery-backed model batches are unsafe; use --model-eval <scenario.json>`);
}

function argFlag(name) {
  const indexes = argv.flatMap((arg, index) => (arg === name ? [index] : []));
  if (indexes.length > 1) failClosed(`${name} may be supplied only once`);
  if (!indexes.length) return null;
  const value = argv[indexes[0] + 1];
  if (!value || value.startsWith("-")) failClosed(`${name} requires a value`);
  return value;
}

const valueFlags = new Set(["--filter", "--model-eval", "--cache-dir"]);
const booleanFlags = new Set(["--deterministic-only", "--dry-run", "--json"]);
for (let i = 0; i < argv.length; i++) {
  const arg = argv[i];
  if (valueFlags.has(arg)) {
    i++;
    continue;
  }
  if (booleanFlags.has(arg)) continue;
  if (arg.startsWith("-")) failClosed(`unknown option: ${arg}`);
  opts.roots.push(arg);
}
if (opts.modelScenario && (opts.roots.length || opts.filter)) {
  failClosed("--model-eval accepts exactly one named scenario and cannot be combined with discovery roots or --filter");
}

function failClosed(message) {
  process.stderr.write(`evaluate: ${message}\nModel calls: 0 (hard cap: ${MODEL_CALL_CAP})\n`);
  process.exit(2);
}

function walkJson(path) {
  const out = [];
  if (!existsSync(path)) return out;
  const stat = statSync(path);
  if (stat.isFile()) return path.endsWith(".json") ? [path] : [];
  for (const entry of readdirSync(path)) out.push(...walkJson(join(path, entry)));
  return out;
}

function discoverDeterministic() {
  const files = new Set();
  const roots = opts.roots.length
    ? opts.roots.map(resolveRepoPath)
    : [join(REPO_ROOT, "evaluations")];
  for (const root of roots) for (const file of walkJson(root)) files.add(file);
  if (!opts.roots.length) {
    const skillsDir = join(REPO_ROOT, "skills");
    for (const skill of existsSync(skillsDir) ? readdirSync(skillsDir) : []) {
      for (const file of walkJson(join(skillsDir, skill, "example"))) files.add(file);
    }
  }
  return [...files].sort();
}

function resolveRepoPath(path) {
  return isAbsolute(path) ? path : resolve(REPO_ROOT, path);
}

function loadScenario(file) {
  try {
    const rawText = readFileSync(file, "utf8");
    const raw = JSON.parse(rawText);
    return { file, rawText, rel: relative(REPO_ROOT, file), mode: raw.exec ? "deterministic" : "model", ...raw };
  } catch (error) {
    return { file, rel: relative(REPO_ROOT, file), error: `invalid JSON: ${error.message}` };
  }
}

function matchesFilter(scenario) {
  if (!opts.filter) return true;
  return `${scenario.rel} ${(scenario.skills || []).join(" ")}`.toLowerCase().includes(opts.filter.toLowerCase());
}

function runDeterministic(scenario) {
  const { cmd, expect = {} } = scenario.exec;
  if (!Array.isArray(cmd) || cmd.length === 0) return { ok: false, reasons: ["exec.cmd must be a non-empty array"] };
  if (opts.dryRun) return { ok: true, skipped: true, reasons: [`would run: ${cmd.join(" ")}`] };
  const result = spawnSync(cmd[0], cmd.slice(1), { cwd: REPO_ROOT, encoding: "utf8", timeout: 60_000 });
  const output = (result.stdout || "") + (result.stderr || "");
  const reasons = [];
  let ok = true;
  const expectedExit = typeof expect.exitCode === "number" ? expect.exitCode : 0;
  if (result.status !== expectedExit) {
    ok = false;
    reasons.push(`exit ${result.status} != expected ${expectedExit}`);
  }
  for (const needle of expect.stdoutContains || []) {
    if (!output.includes(needle)) {
      ok = false;
      reasons.push(`stdout missing: ${JSON.stringify(needle)}`);
    }
  }
  if (typeof expect.stdoutEquals === "string" && output.trim() !== expect.stdoutEquals.trim()) {
    ok = false;
    reasons.push("stdout did not equal expected");
  }
  if (ok) reasons.push("all assertions passed");
  return { ok, reasons };
}

function modelInput(scenario) {
  if (!Array.isArray(scenario.skills) || scenario.skills.length !== 1 || !scenario.skills[0]) {
    throw new Error("model scenario must name exactly one skill");
  }
  const skill = scenario.skills[0];
  if (!scenario.query || !Array.isArray(scenario.expected_behavior)) throw new Error("model scenario requires query and expected_behavior");
  const skillPath = join(REPO_ROOT, "skills", skill, "SKILL.md");
  if (!existsSync(skillPath)) throw new Error(`skill SKILL.md not found for ${JSON.stringify(skill)}`);
  const skillBody = readFileSync(skillPath, "utf8");
  const prompt = [
    "Evaluate the supplied skill instructions against this single scenario.",
    "Do not use tools or perform actions. Infer the response the skill directs, then grade every expected behavior.",
    "Return only the requested JSON verdict.",
    "",
    `SKILL INSTRUCTIONS:\n${skillBody}`,
    "",
    `USER REQUEST:\n${scenario.query}`,
    "",
    `EXPECTED BEHAVIORS:\n${JSON.stringify(scenario.expected_behavior, null, 2)}`,
  ].join("\n");
  return { skillBody, prompt };
}

function cacheRoot() {
  if (opts.cacheDir) return resolve(opts.cacheDir);
  if (process.env.XDG_CACHE_HOME) return join(process.env.XDG_CACHE_HOME, "tron", "evaluate");
  return join(homedir(), ".cache", "tron", "evaluate");
}

function modelCacheKey(scenario, skillBody, prompt) {
  return createHash("sha256").update(JSON.stringify({ evaluator: EVALUATOR_VERSION, model: MODEL, maxOutputTokens: MODEL_MAX_OUTPUT_TOKENS, scenario: scenario.rawText, skillBody, prompt })).digest("hex");
}

function parseVerdict(text) {
  let payload = text;
  try {
    const envelope = JSON.parse(text);
    payload = envelope.structured_output ?? envelope.result ?? text;
  } catch {}
  if (typeof payload === "string") {
    const fence = payload.match(/```(?:json)?\s*([\s\S]*?)```/);
    const body = fence ? fence[1] : payload;
    const start = body.indexOf("{");
    const end = body.lastIndexOf("}");
    if (start >= 0 && end >= start) {
      try { payload = JSON.parse(body.slice(start, end + 1)); } catch {}
    }
  }
  return payload && typeof payload.pass === "boolean" ? payload : null;
}

function terminateGroup(child, signal = "SIGTERM") {
  if (!child.pid) return;
  try { process.kill(-child.pid, signal); } catch {
    try { child.kill(signal); } catch {}
  }
}

async function invokeModel(prompt) {
  const schema = JSON.stringify({ type: "object", properties: { pass: { type: "boolean" }, met: { type: "array", items: { type: "string" } }, missing: { type: "array", items: { type: "string" } }, notes: { type: "string" } }, required: ["pass", "met", "missing", "notes"], additionalProperties: false });
  const args = ["-p", "--model", MODEL, "--effort", "low", "--tools", "", "--disable-slash-commands", "--no-session-persistence", "--output-format", "json", "--json-schema", schema, prompt];
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(opts.claudeBin, args, {
      cwd: REPO_ROOT,
      detached: true,
      env: { ...process.env, CLAUDE_CODE_MAX_OUTPUT_TOKENS: String(MODEL_MAX_OUTPUT_TOKENS) },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      process.off("SIGINT", cancelInt);
      process.off("SIGTERM", cancelTerm);
      error ? rejectPromise(error) : resolvePromise(value);
    };
    const cancel = (signal) => {
      terminateGroup(child, "SIGKILL");
      finish(new Error(`model subprocess cancelled by ${signal}`));
      process.exitCode = 130;
    };
    const cancelInt = () => cancel("SIGINT");
    const cancelTerm = () => cancel("SIGTERM");
    process.once("SIGINT", cancelInt);
    process.once("SIGTERM", cancelTerm);
    const timer = setTimeout(() => {
      terminateGroup(child, "SIGKILL");
      finish(new Error(`model subprocess exceeded ${MODEL_TIMEOUT_MS}ms runtime limit`));
    }, MODEL_TIMEOUT_MS);
    child.on("error", (error) => finish(error));
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      if (Buffer.byteLength(stdout) > MODEL_MAX_OUTPUT_BYTES) {
        terminateGroup(child, "SIGKILL");
        finish(new Error(`model output exceeded ${MODEL_MAX_OUTPUT_BYTES} byte limit`));
      }
    });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code, signal) => {
      if (code !== 0) finish(new Error(`claude exited ${code ?? signal}: ${stderr.slice(0, 400)}`));
      else finish(null, stdout);
    });
  });
}

async function runModelScenario(scenario) {
  let input;
  try { input = modelInput(scenario); } catch (error) { return { ok: false, reasons: [error.message] }; }
  const key = modelCacheKey(scenario, input.skillBody, input.prompt);
  const root = cacheRoot();
  const cacheFile = join(root, `${key}.json`);
  if (existsSync(cacheFile)) {
    try {
      const cached = JSON.parse(readFileSync(cacheFile, "utf8"));
      return { ok: cached.verdict.pass, cached: true, modelCalls: 0, reasons: verdictReasons(cached.verdict), verdict: cached.verdict, cacheKey: key };
    } catch {
      return { ok: false, modelCalls: 0, reasons: [`invalid cached result: ${cacheFile}`] };
    }
  }
  if (opts.dryRun) return { ok: true, skipped: true, cached: false, modelCalls: 1, cacheKey: key, reasons: [`would make 1 model call (${MODEL}, tools disabled, ${MODEL_MAX_OUTPUT_TOKENS} output tokens max, ${MODEL_TIMEOUT_MS}ms max)`] };
  let output;
  try { output = await invokeModel(input.prompt); } catch (error) { return { ok: false, modelCalls: 1, reasons: [error.message] }; }
  const verdict = parseVerdict(output);
  if (!verdict) return { ok: false, modelCalls: 1, reasons: ["model returned an unparseable verdict"] };
  mkdirSync(root, { recursive: true });
  const tempFile = join(root, `.${key}.${process.pid}.tmp`);
  writeFileSync(tempFile, JSON.stringify({ cacheVersion: 1, key, model: MODEL, verdict }, null, 2) + "\n", { mode: 0o600 });
  renameSync(tempFile, cacheFile);
  return { ok: verdict.pass, cached: false, modelCalls: 1, reasons: verdictReasons(verdict), verdict, cacheKey: key };
}

function verdictReasons(verdict) {
  const reasons = [];
  if (verdict.missing?.length) reasons.push(`missing: ${verdict.missing.join("; ")}`);
  if (verdict.notes) reasons.push(verdict.notes);
  return reasons.length ? reasons : ["all expected behaviors met"];
}

function printHelpAndExit() {
  process.stdout.write([
    "Skill evaluation harness",
    "",
    "Usage: node tools/evaluate/evaluate.mjs [options] [deterministic-roots...]",
    "",
    "  --model-eval <scenario.json>  evaluate exactly one named scenario with one bounded model call",
    "  --deterministic-only          accepted compatibility alias; deterministic is always the default",
    "  --filter <str>                filter discovered deterministic scenarios",
    "  --cache-dir <path>            override the content-addressed model-result cache",
    "  --dry-run                     preview scripts and exact model-call count without executing",
    "  --json                        emit a JSON summary on stdout",
    "  -h, --help                    this help",
    "",
    "Discovery never runs model scenarios. --judge and --judge-only fail closed.",
  ].join("\n") + "\n");
  process.exit(0);
}

function log(message) { process.stderr.write(message + "\n"); }

async function main() {
  if (opts.modelScenario) {
    const file = resolveRepoPath(opts.modelScenario);
    if (!existsSync(file) || !statSync(file).isFile() || !file.endsWith(".json")) failClosed("--model-eval must name one existing JSON scenario file");
    const scenario = loadScenario(file);
    if (scenario.error) failClosed(scenario.error);
    if (scenario.exec) failClosed("--model-eval requires a model scenario without an exec block");
    let previewCalls = 1;
    try {
      const input = modelInput(scenario);
      previewCalls = existsSync(join(cacheRoot(), `${modelCacheKey(scenario, input.skillBody, input.prompt)}.json`)) ? 0 : 1;
    } catch (error) { failClosed(error.message); }
    log(`Model calls: ${previewCalls} (hard cap: ${MODEL_CALL_CAP}; ${previewCalls === 0 ? "content-addressed cache hit" : `fixed model: ${MODEL}`})`);
    const result = await runModelScenario(scenario);
    const summary = { passed: result.ok && !result.skipped ? 1 : 0, failed: result.ok ? 0 : 1, skipped: result.skipped ? 1 : 0, modelCalls: result.modelCalls, hardModelCallCap: MODEL_CALL_CAP, results: [{ rel: scenario.rel, mode: "model", skill: scenario.skills?.[0], ...result }] };
    if (opts.json) process.stdout.write(JSON.stringify(summary, null, 2) + "\n");
    else {
      log(`${result.skipped ? "○ skip" : result.ok ? "✓ pass" : "✗ FAIL"}  [model]  ${scenario.rel}${result.cached ? " (cached)" : ""}`);
      for (const reason of result.reasons) log(`        ${reason}`);
    }
    if (process.exitCode == null) process.exitCode = result.ok ? 0 : 1;
    return;
  }

  log(`Model calls: 0 (hard cap: ${MODEL_CALL_CAP}; deterministic discovery)`);
  const scenarios = discoverDeterministic().map(loadScenario).filter((scenario) => scenario.error || (scenario.skills?.length && scenario.mode === "deterministic")).filter(matchesFilter);
  const results = [];
  let passed = 0, failed = 0, skipped = 0;
  for (const scenario of scenarios) {
    const result = scenario.error ? { ok: false, reasons: [scenario.error] } : runDeterministic(scenario);
    const row = { rel: scenario.rel, mode: scenario.mode || "?", skill: scenario.skills?.[0], ...result };
    results.push(row);
    if (result.skipped) skipped++; else if (result.ok) passed++; else failed++;
    if (!opts.json) {
      log(`${result.skipped ? "○ skip" : result.ok ? "✓ pass" : "✗ FAIL"}  [${row.mode}]  ${scenario.rel}`);
      if (!result.ok || result.skipped) for (const reason of result.reasons) log(`        ${reason}`);
    }
  }
  const summary = { passed, failed, skipped, modelCalls: 0, hardModelCallCap: MODEL_CALL_CAP, results };
  if (opts.json) process.stdout.write(JSON.stringify(summary, null, 2) + "\n");
  else log(`\nSummary: ${passed} passed, ${failed} failed, ${skipped} skipped (${scenarios.length} deterministic scenarios discovered)`);
  process.exitCode = failed ? 1 : 0;
}

await main();
