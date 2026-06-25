# `evaluate` — the skill evaluation harness

An executable runner for the skill evaluations. It discovers every scenario,
runs it, and exits non-zero if any executed scenario fails. There are two kinds
of scenario and the harness picks the mode per file:

| Mode              | Trigger                          | What it does                                                                                                                                                                                     | Cost                          |
| ----------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------- |
| **deterministic** | the scenario has an `exec` block | Runs the command and asserts exit code / stdout. Offline, repeatable, CI-safe.                                                                                                                   | none                          |
| **judge**         | the scenario has no `exec` block | Loads the `SKILL.md` under test, asks `claude -p` to describe the actions it _would_ take (no side effects), then asks a second `claude -p` call to grade that plan against `expected_behavior`. | spends tokens; needs `claude` |

## Where scenarios live

- `evaluations/**/*.json` — the central scenario library (audit-skills, content-pipeline, git-flow).
- `skills/<name>/example/*.json` — co-located **golden example runs** that travel with the skill and evolve with it. Generative skills get a judge example; script-backed skills get a deterministic one.

Both are discovered automatically. `evaluations/template.json` and any file with an empty `skills` array are ignored.

## Running

```bash
# Deterministic scenarios only (default — offline, no model calls):
node tools/evaluate/evaluate.mjs

# Add the LLM-judge scenarios (needs the `claude` CLI; spends tokens):
node tools/evaluate/evaluate.mjs --judge

# Only the judge scenarios, only one skill:
node tools/evaluate/evaluate.mjs --judge-only --filter onesheet

# See what would run without making a single call:
node tools/evaluate/evaluate.mjs --dry-run

# Machine-readable summary:
node tools/evaluate/evaluate.mjs --json
```

Flags: `--judge`, `--judge-only`, `--deterministic-only`, `--filter <str>`, `--dry-run`, `--json`, `--help`. Extra positional arguments are treated as eval roots (files or directories), overriding the default discovery.

CI should run the default (deterministic) target — it is fast and free. The `--judge` pass is for local quality checks and pre-release sweeps, since it spends tokens and is non-deterministic by nature.

## Scenario format

Judge scenario (the best-practices format):

```json
{
  "skills": ["onesheet"],
  "mode": "judge",
  "query": "Make a one-pager sell sheet for our new district-admin dashboard.",
  "files": [],
  "expected_behavior": [
    "Asks for the load-bearing facts via AskUserQuestion before drafting",
    "Produces copy with no em dashes (Facilitron voice)",
    "Uses `> TODO:` placeholders instead of fabricating numbers",
    "Stays git-free and hands off to the publisher"
  ]
}
```

Deterministic scenario (adds an `exec` block):

```json
{
  "skills": ["gh"],
  "mode": "deterministic",
  "query": "Show the gh skill's scripted fast-path commands.",
  "files": [],
  "exec": {
    "cmd": ["bash", "skills/gh/scripts/gh.sh", "help"],
    "expect": {
      "exitCode": 0,
      "stdoutContains": [
        "gh-view-pr",
        "gh-list-issues",
        "gh-merge-pr",
        "gh-comment"
      ]
    }
  },
  "expected_behavior": ["help lists all four subcommands and exits 0"]
}
```

`exec.cmd` is an argv array run from the repo root. `exec.expect` supports `exitCode` (defaults to 0), `stdoutContains` (array of substrings; stderr is included), and `stdoutEquals` (exact, trimmed). The `mode` field is advisory — the presence of `exec` is what selects the deterministic runner.

### Optional fields

- **`sandbox`** — for judge scenarios that branch on real repo/filesystem state. Before the run step the harness seeds a throwaway temp dir (which becomes the skill's cwd) and tears it down after the plan is captured. `sandbox.files` is a `{ relativePath: contents }` map written first; `sandbox.setup` is an array of shell commands run (joined with `&&`) in the dir. In a sandbox the skill is allowed read-only inspection (so it can ground its plan in the seeded state); the throwaway dir absorbs any stray mutation, and network/pushes stay off-limits.
- **`manual`** — set `true` to mark a scenario as an interactive/execution spec that judge mode cannot observe reliably (see the boundary below). The harness **skips** it in discovery-based runs (reported as `○ skip [manual]`), so it never shows up as a flaky red. It still runs if you pass its path explicitly as a positional root, for on-demand experimentation.

## What judge mode can and can't observe

Judge mode grades the **plan** the skill produces — it runs the skill in a "describe the actions you would take, do not execute" mode, then grades that description. This is reliable when the skill's deliverable _is_ the plan/reasoning:

- ✅ **content** (news-item, guide-item, …), **audit** (delegation to the runner agent), **brainstorm** (stage discipline) — all judged reliably.

It is **not** reliable for skills whose value is in execution and real-state grounding:

- ⚠️ **git-flow** (git-commit, git-pr) — headless `claude -p` cannot invoke `AskUserQuestion`, "do not execute" means there are no real commit hashes / push results to grade, and whether the model bothers to inspect real state is nondeterministic run to run.

So the git-flow scenarios are marked `"manual": true`: they stay in the suite as documentation and as interactive run scripts (with a `sandbox` to seed a realistic tree), but the harness does not auto-judge them. Their mechanics are covered by the deterministic `scripts/*/test-*.sh` tests instead. Grading git-flow automatically would require an **execution mode** (actually run the skill in the sandbox with headless auto-execute permissions and grade the real artifacts) — a worthwhile future addition, not built yet.

## Adding a golden example to a skill

1. Decide the mode: if the skill has a `scripts/<name>.sh`, prefer a deterministic example that exercises it; otherwise write a judge example.
2. Drop the JSON in `skills/<name>/example/run.json` (a second deterministic case can be `run-script.json`).
3. `node tools/evaluate/evaluate.mjs --filter <name> --dry-run` to confirm discovery, then run it for real.

## Testing the harness itself

```bash
bash tools/evaluate/test-evaluate.sh
```

Offline smoke: pass/fail deterministic fixtures, `--dry-run` safety, JSON output, and the real repo deterministic scenarios. No model calls.
