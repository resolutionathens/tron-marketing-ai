# TESTING.md — testing the `tron` plugin

This repo **is a Claude Code plugin**, not an app — so "testing" means verifying the
instruction layer behaves as written: skills route correctly, delegate correctly, and the
deterministic scripts they shell out to keep working. There is nothing to build or serve.

There are three layers to test, cheapest first:

1. **Deterministic scripts** — the `scripts/<name>.sh` backbones, via their `test-<name>.sh` siblings.
2. **Audit delegation smoke** — the 5 thin orchestrators reach their runner agent.
3. **Skill evaluations** — the [`evaluations/`](evaluations/) scenarios plus the co-located
   `skills/<name>/example/` golden runs, executed by the [`tools/evaluate/`](tools/evaluate/README.md)
   harness (deterministic offline; LLM-judge with `--judge`).

---

## 1. Deterministic scripts (`scripts/<name>.sh` + `test-<name>.sh`)

Mechanical flows live in `skills/<name>/scripts/<name>.sh` and the SKILL.md's "Fast path"
runs them rather than re-deriving the steps in prose (see [CLAUDE.md](CLAUDE.md) → Deterministic
scripts). **The script is the source of truth**, so it gets a test.

Every script has a `test-<name>.sh` sibling. Run it after editing the script:

```bash
bash skills/site-audit/scripts/test-site-audit.sh
bash skills/optimize-images/scripts/test-optimize-images.sh
```

Run every script test at once:

```bash
for t in skills/*/scripts/test-*.sh; do
  echo "=== $t ==="
  bash "$t" || echo "FAILED: $t"
done
```

The shared `tools/` have their own smoke tests — run them after touching shared tooling:

```bash
bash tools/content/test-content.sh    # repo guard, slug, link rewrite, internal-path checks
bash tools/evaluate/test-evaluate.sh  # the evaluation harness itself (offline)
```

These tests cover the script **in isolation** — they do not exercise the full skill flow.
Each test script's header should describe how to run the full skill manually as an integration
spec. The skill-level behavior is covered by the evaluations in layer 3.

---

## 2. Audit-skill delegation smoke (the delegate → runner chain)

The five audit skills — `a11y-scan`, `link-check`, `prose-lint`, `site-audit`,
`optimize-images` — are thin orchestrators (`haiku`): the SKILL.md resolves the target and
hands off to a matching `agents/*-runner.md` that carries whatever model the work needs (see
[CLAUDE.md](CLAUDE.md) → Runner-agent delegation). The thing most likely to break is the
**delegation chain**: a skill that runs the tool itself instead of delegating is a regression,
even if the output looks right.

A lightweight smoke verifies the chain end to end without depending on the heavy tools being
installed:

| Skill             | Must delegate to         | Smoke query                                           |
| ----------------- | ------------------------ | ----------------------------------------------------- |
| `a11y-scan`       | `a11y-scan-runner`       | "a11y scan https://www.facilitron.com"                |
| `link-check`      | `lychee-link-runner`     | "check for broken links in README.md"                 |
| `prose-lint`      | `vale-prose-runner`      | "run vale on content/"                                |
| `site-audit`      | `unlighthouse-runner`    | "run lighthouse across the /resources/guides section" |
| `optimize-images` | `optimize-images-runner` | "compress the PNGs in ./assets"                       |

For each row, issue the smoke query and confirm:

1. The **right skill triggers** (routing).
2. The skill **spawns the matching runner agent via the Task tool** — it does **not** run
   pa11y/lychee/vale/unlighthouse/pngquant in the main session.
3. The runner returns a report (or a clean "tool not installed" message with the install
   hint), and the skill **relays** it rather than re-doing the work.

A static check that every audit skill still names its runner:

```bash
for s in a11y-scan link-check prose-lint site-audit optimize-images; do
  grep -ql 'runner' "skills/$s/SKILL.md" && echo "OK  $s names a runner" \
    || echo "BAD $s does not mention a runner"
done
```

If a skill stops delegating, fix the SKILL.md so it hands off — and keep the skill's declared
model (`haiku`) and its delegation note in sync, per CLAUDE.md.

---

## 3. Skill evaluations (across model tiers)

The [`evaluations/`](evaluations/) directory holds one JSON scenario per file, grouped by
skill family (`audit-skills/`, `content-pipeline/`, `drafting/`, `seo/`, `jira-ops/`,
`git-flow/`), and each skill can carry a
co-located golden run in `skills/<name>/example/`. Each scenario pairs a realistic `query`
with the `expected_behavior` to observe. See [evaluations/README.md](evaluations/README.md)
for the format.

**There is an executable runner — [`tools/evaluate/`](tools/evaluate/README.md).** It
discovers every scenario, runs deterministic ones offline (the `exec`-block examples that
exercise a skill's script), and grades judge scenarios by loading the `SKILL.md` under test,
asking `claude -p` for the plan it would follow, then scoring that plan against
`expected_behavior` with a second `claude -p` call.

```bash
node tools/evaluate/evaluate.mjs            # deterministic only — offline, free, CI-safe
node tools/evaluate/evaluate.mjs --judge    # + LLM-judge — needs `claude`, spends tokens
node tools/evaluate/evaluate.mjs --dry-run  # list what would run, make no calls
```

You can still run any scenario by hand: install the plugin as a directory marketplace
(`/plugin marketplace add /path/to/tron-marketing-ai`), issue the `query`, and check the
result against `expected_behavior`.

The harness validates JSON as it loads; to check parsing independently:

```bash
for f in $(find evaluations skills/*/example -name '*.json'); do
  python3 -m json.tool "$f" >/dev/null && echo "OK $f" || echo "BAD $f"
done
```

### Testing across Haiku / Sonnet / Opus

The plugin deliberately routes each skill to the cheapest tier that does the job (see
[CLAUDE.md](CLAUDE.md) → Model + effort routing). The frontmatter `model` is the _intended_
tier, but a skill can be exercised under a different model in two ways worth testing:

- The **main session model** the user is running affects orchestration-layer judgment
  (grouping, target resolution, when to ask vs proceed).
- A **runner agent or subagent** carries its own model for the heavy work (e.g.
  `vale-prose-runner` is `sonnet` for prose judgment; the news-item pipeline pushes the
  Confluence transform to a `sonnet` subagent and image fan-out to `haiku`).

So test a skill under the tiers it actually runs at, and watch for the tier-sensitive
behaviors below.

| Tier               | Skills (intended)                                                | What to verify holds at this tier                                                                                                                           |
| ------------------ | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `haiku` / low      | the 5 audit skills, `jira`, `confluence`, `preview-page/url`     | Pure orchestration only — resolve the target, delegate, relay. It must **not** start doing the heavy work itself or add judgment the runner owns.           |
| `sonnet` / low–med | git flows, board ops, SEO, video, social, `figma-to-imagekit`    | Light judgment is correct: commit grouping is atomic, PR title/body are conventional, drafting is on-voice. No over-splitting, no hallucinated steps.       |
| `opus` / high      | `news-item`, `guide-item`, `toolkit-item`, `case-study`, `grill` | Long-form quality dominates: component selection, column balancing, link verification, and the served-HTML correctness gate are all exercised, not skipped. |

**Behaviors that differ by tier — check these explicitly:**

- **Judgment depth.** Higher tiers make finer calls (which component, which images pair with
  which paragraph, when to split a commit). Lower tiers should _defer_ that judgment to a
  subagent or to the user, not guess. An orchestration-only skill that starts making content
  judgments at `haiku` is a routing bug.
- **Delegation discipline.** Cheap skills must still delegate. Confirm a `haiku` audit skill
  spawns its runner rather than economizing by inlining the tool run.
- **Following long checklists.** The Opus content skills carry multi-stage workflows (intake →
  images → write → verify → clean up). On a weaker model, confirm no stage silently drops —
  especially the repo guard, link verification, and the served-HTML check.
- **Voice rules.** Copy-producing skills must keep the Facilitron no-em-dash rule regardless
  of tier (see [CLAUDE.md](CLAUDE.md) → Conventions when authoring copy-producing skills).

When a change makes a skill's behavior model-sensitive, run its evals under each tier it can
run at and note any divergence in the PR.

---

## What to run when

| You changed…                        | Run                                                                              |
| ----------------------------------- | -------------------------------------------------------------------------------- |
| A `scripts/<name>.sh`               | its `test-<name>.sh` (layer 1)                                                   |
| Anything under `tools/`             | the matching `tools/*/test-*.sh` (layer 1)                                       |
| An audit skill's SKILL.md           | the delegation smoke for that skill (layer 2)                                    |
| Any skill's description or workflow | that skill's evals in `evaluations/`, across its tiers (layer 3)                 |
| A model/effort tier in frontmatter  | re-run the skill's evals at the new tier; confirm CLAUDE.md routing still agrees |
