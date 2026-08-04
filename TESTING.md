# TESTING.md — testing the `tron` plugin

This repo **is a Claude Code plugin**, not an app — so "testing" means verifying the
instruction layer behaves as written: skills route correctly, delegate correctly, and the
deterministic scripts they shell out to keep working. There is nothing to build or serve.

There are three layers to test, cheapest first:

1. **Deterministic scripts** — the `scripts/<name>.sh` backbones, via their `test-<name>.sh` siblings.
2. **Audit delegation smoke** — the 5 thin orchestrators reach their runner agent.
3. **Skill evaluations** — the [`evaluations/`](evaluations/) scenarios plus the co-located
   `skills/<name>/example/` golden runs, executed by the [`tools/evaluate/`](tools/evaluate/README.md)
   harness (deterministic offline by default; one explicitly named, human-authorized model scenario when needed).

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
bash tools/lint/run-layer1-tests.sh   # every test-*.sh under skills/ and tools/
```

This is the suite `tron:git-pr` runs locally before it pushes or creates a PR. The equivalent
hand-rolled loop is:

```bash
for t in $(find skills tools -name 'test-*.sh' -not -path '*/node_modules/*' | sort); do
  echo "=== $t ==="
  bash "$t" || echo "FAILED: $t"
done
```

The release smoke test also statically guards the release workflow's provenance check. It must verify
the downloaded artifact files listed in `release-manifest.json` with `gh attestation verify`; tag-level
`gh release verify` checks a different attestation subject and would falsely fail after publication.

### Layer-1 pre-PR gate (macOS / Apple Silicon)

`tron:git-pr` runs the whole layer-1 suite via `run-layer1-tests.sh` on the developer's
Mac before any branch push or PR creation. Layer 1 deliberately does not run in GitHub
Actions: the plugin only ships to Apple-Silicon macOS, so testing on the development host
provides the real `/bin/bash` 3.2 and BSD-coreutils runtime without a billed hosted macOS
job. That runtime catches the two bug classes an Ubuntu runner masks:

- **bash-3.2 empty-array expansion** (`"${arr[@]}"` under `set -u` throws on bash < 4.4).
  The CCAL-2091/CCAL-2092 regressions only reproduce under the 3.2 that macOS ships.
- **BSD vs GNU coreutils divergence.** `base64` needs stdin/`-i` (not a positional file)
  on BSD; `stat` uses `-f '%Lp'` not `-c '%a'`. Write test helpers to work on both.

So when you add a `test-*.sh`, keep it portable across BSD/GNU or `command -v`-guard the
divergent tool and SKIP. A test that quietly assumes GNU flags will fail the local pre-PR gate.

The shared `tools/` have their own smoke tests — run them after touching shared tooling:

```bash
bash tools/content/test-content.sh    # repo guard, slug, link rewrite, internal-path checks
bash tools/evaluate/test-evaluate.sh  # the evaluation harness itself (offline)
```

These tests cover the script **in isolation** — they do not exercise the full skill flow.
Each test script's header should describe how to run the full skill manually as an integration
spec. The skill-level behavior is covered by the evaluations in layer 3.

### Instruction-only engineering workflows

`test-driven-development`, `debugging-and-error-recovery`, `code-review-and-quality`, and
`security-and-hardening` intentionally have no deterministic scripts: they guide judgment within a
repository's existing test, browser, CI, and lifecycle tooling. Verify them by checking all of the
following after an edit:

```bash
bash tools/lint/check-scout-frontmatter.sh
bash tools/lint/check-plugin-package.sh
bash tools/package/test-build-packages.sh
```

Then run a focused evaluation or manual scenario against the skill's trigger language. Confirm it
discovers repository-specific commands rather than assuming a stack, reports evidence rather than
claiming success, stays report-only, and preserves dispatched-worker approval gates for risky changes.

### Fast-path SKILL_DIR resolver lint (pre-PR enforced)

A scripted skill's SKILL.md (or, for the runner-delegated audit skills, the matching
`agents/*-runner.md`) resolves the bundled script's absolute path with the
`CLAUDE_SKILL_DIR` → `CLAUDE_PLUGIN_ROOT` → cache/marketplace `SKILL_DIR` fallback described
in [CLAUDE.md](CLAUDE.md) → Path resolution. Losing that fallback breaks the skill under the
headless worker, where `$CLAUDE_SKILL_DIR` isn't always exported — it happened once already
(trimmed from 16 skills, restored in PR #29). `tools/lint/check-fastpath-resolvers.sh` checks
every `skills/*/scripts/*.sh` against the doc that resolves it and fails if the fallback is
missing; it runs as part of the local Layer-1 gate before each PR.

```bash
bash tools/lint/check-fastpath-resolvers.sh       # lint the real repo
bash tools/lint/test-check-fastpath-resolvers.sh  # the lint's own smoke test
```

### Progressive-disclosure structure lint

A long reference doc is read partially, so its scope has to be visible in the opening lines. The
lint owns the threshold and the reason; it fails with the offending path and its line count:

```bash
bash tools/lint/check-reference-contents.sh       # lint the real repo
bash tools/lint/test-check-reference-contents.sh  # the lint's own smoke test
```

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

The static half of that chain is linted, so it does not need checking by hand:

```bash
bash tools/lint/check-audit-delegation.sh       # lint the real repo
bash tools/lint/test-check-audit-delegation.sh  # the lint's own smoke test
```

If a skill stops delegating, fix the SKILL.md so it hands off.

---

## 3. Skill evaluations (across model tiers)

The [`evaluations/`](evaluations/) directory holds one JSON scenario per file, grouped by
skill family (`audit-skills/`, `content-pipeline/`, `drafting/`, `seo/`, `jira-ops/`,
`git-flow/`), and each skill can carry a
co-located golden run in `skills/<name>/example/`. Each scenario pairs a realistic `query`
with the `expected_behavior` to observe. See [evaluations/README.md](evaluations/README.md)
for the format.

**There is an executable runner — [`tools/evaluate/`](tools/evaluate/README.md).** It
discovers and runs deterministic scenarios offline (the `exec`-block examples that exercise a
skill's script). Discovery never runs model scenarios. A human can explicitly name one scenario
for a bounded, cached model evaluation when deterministic assertions cannot express the behavior.

```bash
node tools/evaluate/evaluate.mjs            # deterministic only: offline, free, CI/worker-safe
node tools/evaluate/evaluate.mjs --dry-run  # list commands and report zero model calls
node tools/evaluate/evaluate.mjs --model-eval evaluations/drafting/onesheet-product.json --dry-run
```

Workers must use the deterministic path. Do not run model evaluation autonomously. The optional
`--model-eval` path accepts exactly one file, previews zero or one call, disables tools, enforces
token/runtime limits, and caches unchanged inputs. `--judge` and `--judge-only` fail closed.

You can still run any scenario by hand: install the plugin as a directory marketplace
(`/plugin marketplace add /path/to/tron-marketing-ai`), issue the `query`, and check the
result against `expected_behavior`.

The harness validates JSON as it loads, and a lint parses every scenario and golden run without
running the harness (nothing else covers them in CI):

```bash
bash tools/lint/check-evaluation-json.sh       # lint the real repo
bash tools/lint/test-check-evaluation-json.sh  # the lint's own smoke test
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
| `haiku` / low      | the 5 audit skills, `jira`, `confluence`                         | Pure orchestration only — resolve the target, delegate, relay. It must **not** start doing the heavy work itself or add judgment the runner owns.           |
| `sonnet` / low–med | git flows, board ops, SEO, video, social, `figma-to-imagekit`, engineering-quality workflows | Light judgment is correct: commit grouping is atomic, PR title/body are conventional, debugging preserves evidence, reviews identify material risks, and security gates defer risky changes. |
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

## 4. Testing under worker/dispatch mode (non-interactive)

Skills are designed to run in two environments: **Claude Code's interactive terminal** (the user
invokes `/skillname` in the IDE or web UI) and **headless worker mode** (the Tron control plane
dispatches skills as non-interactive subagents). Testing dispatch-mode behavior is essential for
skills that call out to the control-plane API, use environment variables set by the dispatcher,
or need to handle non-interactive constraints (no `AskUserQuestion`, no menu prompts, no
awaiting user input).

### Environment setup for dispatch mode

When the Tron control plane dispatches a skill, it sets two key environment variables:

- **`TRON_DISPATCH_ID`** — a unique ID for this dispatch run (e.g., `2026-07-11T18-52-39Z-md-2088`)
- **`TRON_API_URL`** — base URL for the control-plane API (e.g., `http://127.0.0.1:8787`)

A skill can detect dispatch mode by checking whether `TRON_DISPATCH_ID` is set:

```bash
if [ -n "${TRON_DISPATCH_ID:-}" ]; then
  # Running under dispatch — use TRON_API_URL and avoid interactive prompts
else
  # Running interactively in Claude Code
fi
```

### Mocking the control-plane API

To test dispatch mode locally without a real control plane, stand up a stub HTTP server
that implements the control-plane surface. The `tools/okf/test-okf.sh` provides a complete
example: it creates a minimal Node.js HTTP server on localhost, exports `TRON_API_URL`, and
asserts the tool's behavior against it.

**Minimal mock pattern:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Create a temporary directory for server state
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Stand up a minimal stub server
cat > "$TMP/server.mjs" <<'EOF'
import { createServer } from "node:http";
const srv = createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  if (req.method === "GET" && u.pathname === "/api/example") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }
  res.writeHead(404);
  res.end("{}");
});
srv.listen(0, "127.0.0.1", () => { process.stdout.write(String(srv.address().port) + "\n"); });
EOF

# Start server and capture its port
node "$TMP/server.mjs" > "$TMP/port" &
SERVER_PID=$!
sleep 0.2
PORT="$(cat "$TMP/port")"

# Run the skill under simulated dispatch
export TRON_DISPATCH_ID="test-dispatch-$(date +%s)"
export TRON_API_URL="http://127.0.0.1:$PORT"

# Invoke the skill and assert behavior
# (Skill should use TRON_API_URL for API calls, not prompt the user)

kill "$SERVER_PID" 2>/dev/null || true
```

### Non-interactive behavior checklist

When testing under dispatch mode, verify the following:

1. **No prompts:** The skill must not call `AskUserQuestion`, show `.` selects, or pause for user input.
   Any user input should be resolved at dispatch time and injected via environment variables or
   command-line args.

2. **API fallback:** If the skill needs data (e.g., from Jira, Confluence, or the OKF), it should:
   - Call the control-plane API (`TRON_API_URL/api/…`) if `TRON_API_URL` is set
   - Fall back to interactive prompt or direct API auth if running interactively
   - Exit with a clear error if neither path is available

3. **No side-effects on API failure:** If an API call fails (network error, 404, 500), the skill
   should report the error and stop cleanly, not hang or retry indefinitely.

4. **Deterministic output:** The skill should produce the same output for the same inputs,
   regardless of execution mode. This is especially important for skills that make decisions
   based on API responses — mock those responses consistently in tests.

### Integration testing a skill under dispatch

To test a full skill flow under simulated dispatch:

1. **Set environment variables** (`TRON_DISPATCH_ID`, `TRON_API_URL`, plus any
   skill-specific secrets like tokens)
2. **Run the skill** (directly or via the agent that invokes it)
3. **Mock the control-plane API** with a stub server (use the `test-okf.sh` pattern above)
4. **Assert behavior** — check exit codes, output content, and confirm no interactive
   prompts were triggered

**Example:** Testing `okf-query` under dispatch:

```bash
# Set up mock control-plane API (see tools/okf/test-okf.sh for the full server)
export TRON_DISPATCH_ID="test-dispatch"
export TRON_API_URL="http://127.0.0.1:5555"  # stub server

# Invoke the skill
node tools/okf/okf.mjs select --type Policy

# Assert expected output (OKF manifest filtered by type, no user prompts)
```

---

## What to run when

| You changed…                        | Run                                                                              |
| ----------------------------------- | -------------------------------------------------------------------------------- |
| A `scripts/<name>.sh`               | its `test-<name>.sh` (layer 1)                                                   |
| Anything under `tools/`             | the matching `tools/*/test-*.sh` (layer 1)                                       |
| An audit skill's SKILL.md           | the delegation smoke for that skill (layer 2)                                    |
| Any skill's description or workflow | that skill's evals in `evaluations/`, across its tiers (layer 3)                 |
| A model/effort tier in frontmatter  | re-run the skill's evals at the new tier; confirm CLAUDE.md routing still agrees |
