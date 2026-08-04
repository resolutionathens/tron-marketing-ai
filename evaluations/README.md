# Evaluations — `tron` plugin skills

These evaluations test that the right skill **triggers** and produces the right
**observable behavior** for a realistic user request. They follow the [Skill authoring
best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
("build evaluations first") and exist because the skill `description` is the only signal
the router sees — an eval is how you confirm a query actually routes where you expect and
the skill then does what its SKILL.md promises.

There is an executable runner — [`tools/evaluate/`](../tools/evaluate/README.md). It discovers
every scenario here (plus the co-located golden examples in `skills/<name>/example/`) and runs
deterministic scenarios (those with an `exec` block) offline. Scenarios without `exec` are manual
specifications unless a human explicitly names one for the bounded model path.

```bash
node tools/evaluate/evaluate.mjs                                # deterministic only, zero model calls
node tools/evaluate/evaluate.mjs --model-eval <scenario.json>   # one explicit, bounded model evaluation
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
node tools/evaluate/evaluate.mjs                       # all deterministic scenarios, offline
node tools/evaluate/evaluate.mjs --filter news-item    # matching deterministic scenarios only
node tools/evaluate/evaluate.mjs --dry-run             # show commands and zero model calls
node tools/evaluate/evaluate.mjs --model-eval evaluations/drafting/onesheet-product.json --dry-run
```

CI and autonomous workers must run the default deterministic target. Optional model evaluation
requires one explicitly named file and human authorization. It uses zero calls on a content-addressed
cache hit and otherwise one tool-free, low-token Haiku call. Discovery can never expand that request.
The retired `--judge` and `--judge-only` batch flags fail closed.

**Note on git-flow:** the `git-flow/` scenarios are marked `"manual": true` because their value is
in execution and real-state grounding. They remain interactive specifications with sandbox setup;
their mechanics are covered by deterministic `scripts/*/test-*.sh` tests. Discovery ignores every
scenario without an `exec` block, whether or not it is marked manual.

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
