#!/usr/bin/env node
/**
 * Local pre-PR code review CLI (MD-2749) — the client half of Scout's local review.
 *
 * A dispatched worker runs inside the TARGET repo's worktree, not inside tron-os, so
 * `bun run review:local` — a tron-os package script — has nothing to resolve there. The
 * worker's tmux session carries `TRON_DISPATCH_ID` and `TRON_API_URL` but not
 * `TRON_OS_ROOT` (tron-os `lib/tmux.ts`), so it cannot find the OS checkout either. This
 * is the same problem `tools/okf/okf.mjs` solved for OKF queries, and it has the same
 * answer: the worker's channel back to the OS is HTTP over `TRON_API_URL`.
 *
 * What moved here is ONLY the trigger. The reviewer launch, the one fix-and-re-review
 * cycle, the round timeout and the record all stay OS runtime behind these two routes:
 *
 *   POST {TRON_API_URL}/api/dispatches/:id/local-review
 *        { verified: string[] }  → { text?, round?, localReview? }
 *   POST {TRON_API_URL}/api/dispatches/:id/local-review/findings/:findingId/disposition
 *        { disposition, note }   → { localReview? }
 *
 * This file reimplements NO policy. A client that decided "how many rounds do I get"
 * could disagree with the control plane about it, which is exactly the bug that makes a
 * review record unreadable later.
 *
 * Exit codes are the worker's instruction, and match tron-os `scripts/review-local.ts`
 * exactly — the skill branches on them:
 *   0 — review settled. Open the PR.
 *   1 — findings to address. Fix them, record a disposition for each, run again.
 *   2 — could not run at all (no dispatch env, API unreachable). NOT a clean review.
 *
 * Zero dependencies: Node 18+ global fetch.
 */
const DISPOSITIONS = ["fixed", "skipped", "disagreed"];
const DEFAULT_API_URL = "http://127.0.0.1:8787";

const argv = process.argv.slice(2);
const cmd = argv[0];

/** How this CLI was actually invoked, so printed commands are copy-pasteable. */
function selfInvocation() {
  // The server renders `bun run review:disposition …` because it is written for a worker
  // sitting in tron-os. In a consumer repo that command does not exist, so we substitute
  // the invocation the caller really used. process.argv[1] is this script's resolved
  // path — verbose, but correct from any cwd, which is the whole point of this tool.
  return process.env.TRON_REVIEW_CMD || `node ${process.argv[1]}`;
}

/**
 * Rewrite the OS-side text so every command it prints resolves HERE.
 *
 * Deliberately a presentation concern owned by the client: the control plane should not
 * have to know how each harness invokes its own tooling, and the alternative — a worker
 * copying a `bun run` line that silently does nothing in its repo — is the exact failure
 * this ticket exists to remove. If the OS ever renders these itself, drop this.
 */
function localizeCommands(text) {
  if (!text) return text;
  const self = selfInvocation();
  return text
    .replace(/bun run review:disposition/g, `${self} disposition`)
    .replace(/bun run review:local/g, `${self} local`)
    .replace(/`review:disposition`/g, `\`${self} disposition\``)
    .replace(/`review:local`/g, `\`${self} local\``);
}

function usage(code = 0) {
  const self = selfInvocation();
  const out = code === 0 ? console.log : console.error;
  out(
    [
      "Usage:",
      `  ${self} local [--verified <text>]...`,
      `  ${self} disposition --finding <id> --fixed|--skipped|--disagreed --note <text>`,
      "",
      "local        Run ONE local pre-PR review round for this dispatch and print the result.",
      "  --verified <text>   (repeatable) a check you ALREADY ran green on this branch, e.g.",
      '                      --verified "bun run test: 4774 pass, 0 fail". The reviewer is told',
      "                      not to repeat it, so it spends its budget reading code instead.",
      "                      Passed as a CLAIM, not proof.",
      "",
      "disposition  Record what you did about ONE round-one finding.",
      `  --finding <id>      the bracketed id printed under the finding by \`${self} local\`.`,
      `  --<disposition>     one of: ${DISPOSITIONS.map((d) => `--${d}`).join(", ")}`,
      "  --note <text>       REQUIRED — what you changed, or why you did not.",
      "",
      "Record one for EVERY round-one finding, including the ones you disagree with: a reasoned",
      "push-back is a signal about the rule, and a silent fix destroys the round-one/round-two",
      "comparison the second review exists to make.",
      "",
      "The policy is exactly one fix-and-re-review cycle:",
      "  round 1 → fix → record a disposition for EACH → round 2 → open the PR. No third round.",
      "",
      "Env: TRON_DISPATCH_ID (required), TRON_API_URL (default " + DEFAULT_API_URL + ").",
      "Exit: 0 settled · 1 findings to address · 2 could not run at all.",
    ].join("\n"),
  );
  process.exit(code);
}

if (!cmd || cmd === "help" || cmd === "-h" || cmd === "--help") usage(0);

/** Read a repeatable `--name <value>` flag. */
function flagAll(name) {
  const out = [];
  for (let i = 0; i < argv.length; i++) if (argv[i] === `--${name}` && argv[i + 1]) out.push(argv[i + 1]);
  return out;
}
function flag(name) {
  const at = argv.indexOf(`--${name}`);
  return at >= 0 ? argv[at + 1] : undefined;
}

const apiUrl = (flag("api-url") || process.env.TRON_API_URL || DEFAULT_API_URL).replace(/\/+$/, "");
const dispatchId = process.env.TRON_DISPATCH_ID;

if (!dispatchId) {
  console.error(`review ${cmd} must run inside a dispatch — TRON_DISPATCH_ID is not set.`);
  process.exit(2);
}

const base = `${apiUrl}/api/dispatches/${encodeURIComponent(dispatchId)}/local-review`;

/** POST JSON, mapping transport failure onto the caller's chosen exit code. */
async function post(url, body, unreachableExit) {
  try {
    return await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch (e) {
    console.error(`review could not reach the control plane at ${apiUrl}: ${e.message}`);
    if (unreachableExit === 2) {
      console.error("This is NOT a clean review — do not open a PR on the strength of it.");
    }
    process.exit(unreachableExit);
  }
}

async function readJson(res) {
  try {
    return await res.json();
  } catch {
    return {};
  }
}

if (cmd === "local") {
  const verified = flagAll("verified");

  // No client-side timeout: a review launches a real worker and legitimately takes many
  // minutes. The SERVER owns the timeout and records a failed round when it fires, which
  // is the outcome that has to be on the record — a client that gave up early would leave
  // the review running with nobody reading its verdict.
  const res = await post(base, { verified }, 2);
  const body = await readJson(res);

  if (res.status === 409) {
    // Both rounds spent. A normal terminal outcome, not an error.
    console.log(localizeCommands(body.error) ?? "Both local review rounds are spent.");
    process.exit(0);
  }

  if (!res.ok) {
    console.error(`review local failed (${res.status}): ${body.error ?? "unknown error"}`);
    process.exit(2);
  }

  console.log(localizeCommands(body.text) ?? JSON.stringify(body.round, null, 2));

  const round = body.round;
  if (round?.status === "failed") {
    console.error("");
    console.error("The review did NOT run, so nothing was checked. This is recorded as a failed");
    console.error("review, never as a clean one.");
    process.exit(1);
  }

  if (body.localReview?.settled) process.exit(0);
  process.exit(round && round.findings.length > 0 ? 1 : 0);
}

if (cmd === "disposition") {
  const findingId = flag("finding");
  const note = flag("note");
  const chosen = DISPOSITIONS.filter((d) => argv.includes(`--${d}`));

  if (!findingId) {
    console.error("--finding <id> is required. Use the bracketed id printed for the finding.");
    process.exit(2);
  }
  if (chosen.length !== 1) {
    console.error(
      chosen.length === 0
        ? `Pass exactly one of: ${DISPOSITIONS.map((d) => `--${d}`).join(", ")}`
        : `Pass exactly ONE disposition — got ${chosen.map((d) => `--${d}`).join(" and ")}.`,
    );
    process.exit(2);
  }
  if (!note?.trim()) {
    // Refused here as well as server-side: the note IS the evidence, and a `disagreed`
    // with no reason is unreadable later as a claim about the RULE rather than the worker.
    console.error("--note <text> is required — say what you changed, or why you did not.");
    process.exit(2);
  }

  const disposition = chosen[0];
  const res = await post(
    `${base}/findings/${encodeURIComponent(findingId)}/disposition`,
    { disposition, note: note.trim() },
    2,
  );
  const body = await readJson(res);

  if (!res.ok) {
    console.error(`review disposition failed (${res.status}): ${body.error ?? "unknown error"}`);
    process.exit(1);
  }

  console.log(`Recorded ${disposition} for finding ${findingId}.`);
  if (body.localReview?.roundsRemaining) {
    console.log(`When every round-one finding has one, run \`${selfInvocation()} local\` for your final review.`);
  }
  process.exit(0);
}

console.error(`review: unknown subcommand '${cmd}' (try: local, disposition)`);
usage(2);
