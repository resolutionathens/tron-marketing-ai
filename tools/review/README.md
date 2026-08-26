# `tools/review` — local pre-PR code review CLI

The client half of Scout's local code review (MD-2749). It lets a dispatched worker **in any repo**
trigger its own pre-PR review and record what it did about each finding.

## Why this exists

MD-2745 moved code review off GitHub and onto the machine, **before** the PR exists, and gave the
worker a self-trigger: `bun run review:local`. That is a **tron-os package script**. A dispatched
worker's cwd is the *target* repo's worktree, and its session carries `TRON_DISPATCH_ID` and
`TRON_API_URL` but not `TRON_OS_ROOT` — so outside a tron-os worktree there was nothing to resolve
and the self-trigger silently was not there.

This is the same problem [`tools/okf`](../okf/README.md) solved for OKF queries, with the same
answer: the worker's channel back to the OS is HTTP over `TRON_API_URL`.

**Only the trigger and final-remediation callback live here.** The reviewer launch, the three-round remediation cycle, the round
timeout and the record are OS runtime in tron-os (`lib/local-review.ts`) and stay there. This client
reimplements no policy — one that decided "how many rounds do I get" could disagree with the control
plane about it.

## Usage

```bash
REVIEW="${CLAUDE_PLUGIN_ROOT}/tools/review/review.mjs"

# Run one review round. --verified is repeatable; it is a CLAIM, not proof.
node "$REVIEW" local --verified "bun run test: 4774 pass, 0 fail"

# Record what you did about ONE round-one or round-two finding. Required for EVERY finding.
node "$REVIEW" disposition --finding f1 --fixed --note "narrowed the guard"

# After a non-passing final round, record repair and proof for every target.
node "$REVIEW" remediation --target finding:f3 --repair "narrowed the guard" --verification "bash tools/review/test-review.sh: passed"

# Only for a terminal failed review with no repair targets, record its reason and proof.
node "$REVIEW" recovery --failed-review-reason "review artifact was invalid with no repair target" --verification "bash tools/review/test-review.sh: passed"
```

`tron:git-pr` Step 1c resolves it via `tools/skill/resolve-plugin-root.sh` and drives both commands.

## Exit codes are the contract

They match tron-os `scripts/review-local.ts` exactly, because the skill branches on them:

| Code | Meaning | What the worker does |
| --- | --- | --- |
| `0` | Review settled | Open the PR |
| `1` | Findings to address | In rounds 1 and 2, fix, record a disposition for each, then run the next round |
| `2` | Could not run at all | **Not** a clean review — say so; never open a PR on its strength |

A `409` (all rounds spent) is a normal terminal outcome and exits `0`, not an error. A round the
server records as `failed` exits `1` — a review that did not run is never reported as clean.

The live control plane permits at most three rounds. A passing round settles review immediately.
After a non-passing third round, fix every actionable finding and unmet criterion, verify the
affected behavior, and record each repair plus its verification with `remediation` before PR
registration. There is no fourth round.

If the terminal review failed without any finding or unmet criterion, the live gate instead requires
its failure reason and verification through `recovery` before PR registration. Do not use recovery
when a final-review target exists.

## Localized commands

The control plane renders `bun run review:disposition …` in its output, because it is written for a
worker sitting in tron-os. This client rewrites those to the invocation you actually used, so the
line a worker copies resolves in its own repo. Set `TRON_REVIEW_CMD` to present a different wrapper
(e.g. `tron-review`) instead of a raw `node <path>`.

If the OS ever renders these itself, delete `localizeCommands` — it is a presentation concern owned
by the client, not a permanent part of the protocol.

## Env

- `TRON_DISPATCH_ID` — **required**; absent means "not under dispatch" and exits `2`.
- `TRON_API_URL` — control-plane base URL. Default `http://127.0.0.1:8787`; `--api-url` overrides.
- `TRON_REVIEW_CMD` — optional display override for printed commands.

## Tests

```bash
bash tools/review/test-review.sh
```

Hermetic: a stub control plane on `127.0.0.1:0`, no network and no dispatch required. It runs in the
Layer-1 suite automatically (`run-layer1-tests.sh` discovers every `test-*.sh` under `tools/`).
