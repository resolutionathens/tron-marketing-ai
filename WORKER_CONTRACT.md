# The dispatched-worker contract

This document is the single source of truth for what it means to run as a **dispatched worker**
in this repo — a non-interactive subagent the Tron control plane (tron-os) launches into a
worktree to execute a ticket. Today that contract exists only as folklore spread across kickoff
prompts, `TESTING.md`, `tools/broker/README.md`, and individual `SKILL.md` files. This page
consolidates it. It is cross-linked from tron-os's `CLAUDE.md` so either repo's reader lands
here.

If you're a worker reading this mid-task: skim it once at dispatch, then treat it as the
authority when a skill's behavior and this contract disagree with your instinct about what an
interactive user would do.

## Contents

- [What a dispatched worker is](#what-a-dispatched-worker-is)
- [Environment variables you get](#environment-variables-you-get)
- [The PR-gate autonomy model](#the-pr-gate-autonomy-model)
- [Tools and skills unavailable to you](#tools-and-skills-unavailable-to-you)
- [The broker: on-demand credential minting](#the-broker-on-demand-credential-minting)
- [Detecting and testing dispatch mode](#detecting-and-testing-dispatch-mode)
- [Open gaps](#open-gaps)

## What a dispatched worker is

You run inside the **target repo's worktree** (`marketing-pages`, `facilitron-ui`,
`tron-marketing-ai`, etc.) — never inside tron-os itself. You cannot import tron-os internals
(`lib/okf-client.ts`, `lib/triage.ts`, …) or read its files off disk. Your only channel back to
the control plane that dispatched you is HTTP, over `TRON_API_URL`. Everything else — Jira,
Confluence, ImageKit, Figma, CircleCI — is reached the same way a human contributor reaches it:
via `acli`, the broker, or a directly-held token, per skill.

You are expected to run **non-interactively end to end**: no terminal prompts, no menu
selections, no waiting on a human mid-task. Input you need is either front-loaded into your
kickoff prompt/env, or fetched on demand over `TRON_API_URL` (see `tron:okf-query` below).

## Environment variables you get

Set by tron-os's dispatcher (`lib/tmux.ts`) into every worker's environment:

| Var | What it is | Example |
| --- | --- | --- |
| `TRON_DISPATCH_ID` | Unique ID for this dispatch run | `2026-07-11T18-52-39Z-md-2088` |
| `TRON_API_URL` | Base URL of the control-plane API that dispatched you | `http://127.0.0.1:8787` |

A skill (or you, mid-task) can detect dispatch mode by checking `TRON_DISPATCH_ID`:

```bash
if [ -n "${TRON_DISPATCH_ID:-}" ]; then
  # running under dispatch — use TRON_API_URL, never prompt
else
  # running interactively in Claude Code
fi
```

`TRON_API_URL` is the primary channel for pulling org knowledge mid-task
(`tron:okf-query` → `tools/okf/okf.mjs`, `GET /api/okf/select` / `POST /api/okf/load`). If it's
unset — some dispatches don't pass it — the OKF CLI falls back to the org-secret broker's
`/knowledge/*` surface directly (MD-2066; see [broker section](#the-broker-on-demand-credential-minting)
below). Only if neither `TRON_API_URL` nor the broker is reachable should a skill degrade to
whatever playbooks you were front-loaded with at kickoff, rather than blocking.

Jira/Confluence access does **not** go through `TRON_API_URL`. `acli`-based skills (`jira`,
`jira-comment`, `enrich-jira-ticket`, `jira-source-discovery`, `jira-ticket-enricher`, `board-triage`, `start-ticket`, `weekly-update`) use
`acli`'s own per-user OAuth session; Confluence page/attachment fetches go through the broker's
`/jira/*` surface. See [`tools/jira/broker-status.md`](tools/jira/broker-status.md) for why
`acli` stays off the broker.

## The PR-gate autonomy model

A dispatched worker's git-lifecycle autonomy stops at the PR, not before it and not after it:

- **Up to and including opening the PR is yours to do autonomously**, per the kickoff prompt's
  instructions — commit, push, open the PR, post the retro comment. Don't stop to ask
  "should I commit / open the PR?" — that's the job, not a checkpoint.
- **The PR itself is the review gate.** Once it's open and the control plane is notified, you
  stop and wait for a human to approve. Do not merge, do not promote past it, do not go looking
  for more work.
- **Production promotion is explicitly human-gated, always** — `skills/git-pushtoprod/SKILL.md`
  states it directly: *"production deploy is high-risk. The script is the mechanics; the
  decision to run it stays with the human/PR gate — don't invoke autonomously."* Never run
  `tron:git-pushtoprod` (or `tron:git-dev` in repos that don't use it) as part of a dispatched
  run unless the kickoff prompt explicitly authorizes that stage.
- Scout (tron-os's desktop app) enforces a parallel version of this at the skill level: a skill
  whose `scout:` frontmatter declares the `publish` effect is what routes a Scout-initiated run
  through the git lifecycle (branch → PR → parked at the gate); every other effect stops for
  review with **no PR** at all. Tiers are enforced server-side — a locked Scout instance 403s
  `developer`-tier runs regardless of what you ask for.

In short: **autonomous through the PR, human-gated at and beyond it.** This is the same shape
whether you were dispatched by the Tron control plane directly or via a Scout run.

## Tools and skills unavailable to you

- **`AskUserQuestion` (and any interactive prompt/select) is not callable under dispatch.**
  Many skills declare it in `allowed-tools` for their interactive path, but a skill must not
  actually invoke it when `TRON_DISPATCH_ID` is set — any input it needs must already be in the
  kickoff prompt/env, or fetched via `tron:okf-query`. This is also a known **testing** gap:
  `evaluations/README.md` and `tools/evaluate/README.md` mark `git-commit`/`git-pr` evals
  `"manual": true` specifically because "headless `claude -p` cannot invoke `AskUserQuestion`" —
  those skills' interactive confirmation step is skipped, not evaluated, under headless runs.
- **`tron:open-worktree` is not for dispatched workers.** It launches a tmux+vim session and
  shells out to macOS `open` to open a browser tab — both require an interactive terminal a
  worker doesn't have. Its `SKILL.md` says so explicitly and is the template to follow if you
  add another interactive-only skill.
- **Don't open URLs in a browser.** `tron:start-ticket` calls this out directly: don't `open` the
  ticket URL, and that applies to dispatched/non-interactive workers same as the
  `tron:ship-ticket` orchestrator.
- **`tron:ship-ticket`'s per-stage confirmation gates assume a human is present** to answer them.
  As a dispatched worker you're normally driven by the individual lifecycle skills
  (`start-ticket` → `git-commit` → `git-pr`) per your kickoff prompt, not by `ship-ticket`,
  precisely because its stage-advance prompts have nowhere to go under dispatch.

## The broker: on-demand credential minting

The **org-secret broker** (`secrets.facilitron.work`, documented in full at
[`tools/broker/README.md`](tools/broker/README.md)) exists because org-shared API credentials
copied onto every dispatched worker's environment are a liability — they leak, they rotate out
of sync, and they outlive the worker that had them. Instead of a worker holding a long-lived
`IMAGEKIT_PRIVATE_KEY` or Figma token, most broker-backed tools mint access on demand:

1. One-time SSO: `cloudflared access login https://secrets.facilitron.work` (cached, auto-refreshed).
2. Per request: `cloudflared access token --app=https://secrets.facilitron.work`, sent as the
   `CF-Access-Token` header to `https://secrets.facilitron.work/<service>/<path>`, which mirrors
   the real upstream API 1:1.

Proxied surfaces today: `/imagekit/*`, `/figma/*`, `/circleci/*`, `/jira/*` (Confluence page
body/listing only — attachment downloads still use `JIRA_API_TOKEN`/`ATLASSIAN_EMAIL` directly,
tracked in MD-2011), and `/knowledge/*` (OKF, fallback-only per MD-2066).

Most tools are **broker-first, direct-API fallback** (`imagekit.mjs`, `fetch-confluence.sh`):
try the broker, and on any connectivity/TLS failure or missing token, fall back to the direct
API with a locally-held credential. `okf.mjs` is the **inverse**: `TRON_API_URL` is primary
(that's your normal channel back to the OS), and the broker's `/knowledge/*` surface is only the
fallback for the rare dispatch that has no `TRON_API_URL` at all.

A known intermittent TLS handshake failure to the broker affects some workers — see
[tron-os's broker known-issues playbook](https://github.com/Facilitron/tron-os/blob/3086c8402611369e59af12cbbcf5e5de2f00ded0/knowledge/playbooks/org-secret-broker.md#known-issues).
The fallback path exists precisely so that failure doesn't dead-end a run. Skills run
identically under the experimental pi harness.

## Detecting and testing dispatch mode

See [`TESTING.md` § 4](TESTING.md#4-testing-under-workerdispatch-mode-non-interactive) for the
full mock-server pattern and non-interactive behavior checklist
(`tools/okf/test-okf.sh` is the worked example). The short version, restated as a contract for
anyone writing or editing a skill:

1. **No prompts.** Never call `AskUserQuestion`, show a `.` select, or otherwise pause for input
   once `TRON_DISPATCH_ID` is set.
2. **API-first, then fall back, then fail clearly.** Call `TRON_API_URL` (or the broker, per the
   tool's documented fallback order) if available; if neither path is reachable, exit with a
   clear error rather than hanging or guessing.
3. **No side effects on failure.** A failed API call reports the error and stops cleanly — it
   does not retry indefinitely or leave partial state behind.
4. **Deterministic output.** Same inputs → same output, regardless of interactive vs. dispatch
   mode.

## Open gaps

- There is no formal, machine-readable field (e.g. a `scout:` key like `dispatchable: false`) to
  mark a skill as excluded from worker dispatch. `tron:open-worktree` is excluded only by prose
  in its `description` and a dedicated SKILL.md section. If you're adding another
  interactive-only skill, follow that same prose pattern until a formal field exists — and file a
  follow-up ticket if you hit this gap in a way that blocks you.
- `git-commit`/`git-pr` evals are marked manual rather than truly exercised under headless mode,
  because their `AskUserQuestion` confirmation step can't run there (see above). Their
  non-interactive dispatch behavior is contractually specified by this document and by kickoff
  prompts, not by an automated eval — treat that gap as real until it's closed.
