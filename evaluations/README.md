# Evaluations — `tron` plugin skills

These evaluations test that the right skill **triggers** and produces the right
**observable behavior** for a realistic user request. They follow the [Skill authoring
best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
("build evaluations first") and exist because the skill `description` is the only signal
the router sees — an eval is how you confirm a query actually routes where you expect and
the skill then does what its SKILL.md promises.

There is an executable runner — [`tools/evaluate/`](../tools/evaluate/README.md). It discovers
every scenario here (plus the co-located golden examples in `skills/<name>/example/`) and runs
it in one of two modes: **deterministic** scenarios (those with an `exec` block) run a command
and assert its output offline; **judge** scenarios load the `SKILL.md` under test, ask `claude -p`
to describe the actions it would take, then grade that plan against `expected_behavior`.

```bash
node tools/evaluate/evaluate.mjs            # deterministic only (offline, default)
node tools/evaluate/evaluate.mjs --judge    # + LLM-judge (needs `claude`, spends tokens)
```

You can still run any scenario by hand — read the `query`, issue it to Claude Code, and check
the result against `expected_behavior` (see "How to run (manual)" below). See
[TESTING.md](../TESTING.md) for the broader testing strategy (multi-model verification, the
`scripts/<name>.sh` + `test-<name>.sh` pattern, and the audit smoke test).

## Layout

```
evaluations/
├── README.md              this file
├── template.json          the canonical empty template — copy it to add a new eval
├── audit-skills/          the 5 thin orchestrators that delegate to a runner agent
├── content-pipeline/      the marketing-pages content writers (news, guide, toolkit)
├── drafting/              git-free copy drafters (social, spotlight, email)
├── seo/                   the SEO family (audit, keyword research, on-page spec)
├── jira-ops/              Jira read/report skills (comment, triage, roll-up, weekly update)
└── git-flow/              the deterministic git lifecycle skills
```

One JSON file per scenario. Group by skill family; name the file
`<skill-name>-<scenario>.json` (e.g. `a11y-scan-url.json`, `news-item-with-images.json`).

## Format

Each eval is a single JSON object:

```json
{
  "skills": ["<skill-name>"],
  "query": "<realistic user request that should trigger this skill>",
  "files": ["<input files, [] if none>"],
  "expected_behavior": [
    "<observable action 1>",
    "<observable action 2>",
    "<observable action 3>"
  ]
}
```

| Field               | Meaning                                                                                           |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| `skills`            | The skill(s) the query should route to. Usually one.                                              |
| `query`             | A realistic user request, phrased the way a user actually would — this is the routing signal.     |
| `files`             | Input files the scenario assumes are present (e.g. a dropped-in `featuredimg.png`). `[]` if none. |
| `expected_behavior` | Observable actions to check, in rough order. **Three or more per eval.**                          |

**Write `expected_behavior` as things you can observe**, not internal reasoning. Good:
"Delegates the run to the a11y-scan-runner subagent via the Task tool." Bad: "Understands
that it should scan accessibility."

For the **audit skills**, the single most important observable is the **delegation chain**:
the skill must hand off to its matching `agents/*-runner.md` (a11y-scan → `a11y-scan-runner`,
link-check → `lychee-link-runner`, prose-lint → `vale-prose-runner`, site-audit →
`unlighthouse-runner`, optimize-images → `optimize-images-runner`) rather than running the
tool itself. Every audit eval asserts this.

## How to run (executable)

The [`tools/evaluate/`](../tools/evaluate/README.md) harness runs scenarios for you and exits
non-zero on any failure:

```bash
node tools/evaluate/evaluate.mjs                       # all deterministic scenarios
node tools/evaluate/evaluate.mjs --judge               # also the LLM-judge scenarios
node tools/evaluate/evaluate.mjs --judge-only --filter news-item   # one skill, judge only
node tools/evaluate/evaluate.mjs --dry-run             # show what would run, no calls
```

CI should run the default (deterministic) target — fast and free. Use `--judge` locally and
before a release, since it spends tokens and is non-deterministic.

**Note on git-flow:** the `git-flow/` scenarios are marked `"manual": true` and the harness
skips them in auto runs. Judge mode grades a _plan_, but git-flow's value is in execution and
real-state grounding — headless mode can't invoke `AskUserQuestion`, has no real commit hashes
to grade, and inconsistently inspects state. They remain here as interactive run scripts (with a
`sandbox` block that seeds a realistic tree); their mechanics are covered by the deterministic
`scripts/*/test-*.sh` tests. See [tools/evaluate/README.md](../tools/evaluate/README.md) →
"What judge mode can and can't observe".

## How to run (manual)

1. Install the plugin locally as a directory marketplace so edits apply without a push:
   `/plugin marketplace add /path/to/tron-marketing-ai`.
2. Pick an eval file and read its `query` and `files`.
3. Stage any `files` the scenario assumes (or run it in a checkout that already has them —
   the content-pipeline evals expect the `marketing-pages` repo).
4. Issue the `query` to Claude Code.
5. Check the result against `expected_behavior`. Note any item that did not happen and
   whether it was a routing miss (wrong skill) or a behavior miss (right skill, wrong steps).

A scenario **passes** when the right skill triggers and every `expected_behavior` item is
observable. Re-run across model tiers per [TESTING.md](../TESTING.md) when a skill's behavior
is model-sensitive.

## Adding an eval

Copy `template.json`, fill in all four fields, and drop it in the right family dir. Read the
target skill's SKILL.md first so the `query` and `expected_behavior` reflect what the skill
actually does. Keep at least three eval files per priority skill family. Validate that every
file still parses:

```bash
for f in $(find evaluations -name '*.json'); do
  python3 -m json.tool "$f" >/dev/null && echo "OK $f" || echo "BAD $f"
done
```
