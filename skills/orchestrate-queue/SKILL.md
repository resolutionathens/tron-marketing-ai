---
name: orchestrate-queue
model: haiku
effort: low
description: "Drive one or more named Jira tickets from Scout's standing approvals queue through the control plane to parked, CI-green pull requests. Use for 'orchestrate this ticket', 'run these tickets', 'drive the queue', 'work this batch', or coordinating parallel ticket workers across repositories and Claude/Codex harnesses. Requires TRON_API_URL; never approves or merges a pull request."
allowed-tools:
  - Bash
  - Read
  - Skill
scout:
  surface: true
  title: "Orchestrate ticket work"
  blurb: "Sequences one ticket or a batch, launches safe parallel waves, and parks every pull request for human review."
  when: "One or more approved engineering tickets need to run through the same controlled worker loop."
  category: tickets
  effects: [local]
  inputs:
    - key: tickets
      label: "Ticket keys or queue scope"
      type: text
      required: false
      placeholder: "MD-1234, MD-1235, or a repo queue"
---

# Orchestrate the queue

Drive a **work set** of one or more tickets through Scout's control plane. A single ticket is a set
of one; do not branch into a separate single-ticket or epic workflow. This is the only orchestration
entry point. Legacy user-level orchestration commands must be removed or reduced to non-executable
redirects to `tron:orchestrate-queue`.

The worker owns implementation, verification, local review, commit, push, and PR creation. You own
selection, sequencing, launch, observation, and worker guidance. Stop after handing every ready PR
to the human. **Never approve or merge a pull request.**

## Preflight

Require `TRON_API_URL` and a healthy control-plane connection before reading or mutating the queue:

```bash
[ -n "${TRON_API_URL:-}" ] || { echo "tron:orchestrate-queue: TRON_API_URL is required" >&2; exit 1; }
curl -fsS "${TRON_API_URL%/}/health" >/dev/null
```

If this fails, stop and report the missing or unreachable control plane. Do not substitute a local
worker transport. Use the Scout MCP tools for control-plane operations; the bundled monitor below is
the one temporary raw-HTTP exception required to observe today's non-status park fields.

## 1. Build and judge the work set

- With no explicit keys, call `list_approvals` with `dispatchable:true` and any repo scope the
  operator supplied. Include only tickets the operator named or the standing queue scope they named.
- With explicit keys, match them to `list_approvals`. If a key has no card, call `dispatch_ticket` to
  stage it, report that today's runtime requires its own approval-card resolution, and wait for the
  pending card. Never invent an entry skill or bypass the card.
- Call `get_approval` for each selected row. Read the full ticket when its snapshot is stale or when
  the decision, blockers, or paths are incomplete. Do not dispatch from a summary alone.
- Exclude and report decision tickets, umbrella work, unmet decision prerequisites, STOP-tier work,
  already-merged tickets, tickets with open PRs, and tickets already in flight. Do not add substitute
  work to keep the wave full.

Normalize and de-duplicate the keys. Keep this same work-set representation for one key and for N;
epic-child population will become another source for it when the runtime supports that source.

## 2. Derive the execution graph

Build edges from the approval data before launching anything:

1. A `blockedBy` relationship is a directed dependency edge. The blocker must reach `done` before
   its dependent can launch. Re-read the blocker before each later wave because its state may change.
2. Normalize every `affectedPaths` entry relative to the target repo. Two tickets overlap when they
   name the same path, one path is an ancestor of the other, or their declared globs can select the
   same file. Overlap forces serialization even without a dependency edge.
3. Orient an overlap-only edge by explicit operator priority, then queue order, then input order.
   Never let this tie-break reverse a `blockedBy` edge.
4. Tickets with no unresolved dependency and no overlap with a ticket in the same wave may run in
   parallel, up to the operator's wave cap (default **3**).

`affectedPaths` is vague when it is absent, says unknown/TBD, names only a broad repository or
concept, or uses prose that cannot identify file ownership. Post one concise plain-text question
asking for the missing paths or a serial order, then stop for the relayed answer. Do not guess that
two vague tickets are disjoint.

State the graph and first wave before dispatching: dependency edges, overlap edges, skipped/blocked
keys, and why every parallel pair is safe.

## 3. Launch a wave

For every ticket in the chosen wave, call `resolve_approval` with `decision:"approve"` and a
`standingInstruction`. Plan the whole wave first so every parallel worker's instruction can name all
of its peers even when their launches are sequential API calls.

Each `standingInstruction` must include:

- the ticket's dependency and sequencing constraints;
- every other worker in this wave and the exact files or modules each owns;
- an instruction to preserve those ownership boundaries and coordinate changes through the
  orchestrator;
- a pre-park self-check: re-read each acceptance criterion, walk the diff against it, check whether
  tests assert exact values where possible, and check whether every new failure path is exercised.

The note is capped, so be concrete and compact. Record the returned dispatch id beside its ticket.

## 4. Observe, steer, and advance

Use `list_dispatches` for several workers and `get_dispatch_status` for one known worker. Use
`wait_for_dispatch_status` only for a known, imminent status transition; a timeout is normal and is
not a failure.

For persistent observation of park fields, resolve this skill directory and run the bundled monitor:

```bash
name=orchestrate-queue
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/monitor-dispatches.sh)"
bash "$SKILL_DIR/scripts/monitor-dispatches.sh" <dispatch-id> [<dispatch-id> ...]
```

The monitor validates the response, filters to this work set, and emits every tracked-field change
including first park, review re-park, and terminal states. Treat `MONITOR ERROR:` as a failure to
observe, never as a quiet queue.

Send every one-off worker instruction through `relay_dispatch_message`. Its receipt determines
whether delivery was accepted or needs investigation; do not retry a queued or delivered message.
Do not choose a Claude/Codex transport yourself.

When a dispatch fails, report it, hold every downstream dependent, and continue independent work.
When a dispatch reaches `done`, recompute eligibility and launch the next safe wave. Workers start
from the target repo's current default branch, so later serial work must verify that the earlier
change is present rather than recreating its convention.

## 5. Park at the PR gate

A PR is ready to hand to the human when the worker is parked and required checks pass. Report its
ticket, PR URL, local-review state, and required-checks summary. If the worker must act on feedback,
send the concrete instruction with `relay_dispatch_message` and wait for the review re-park.

If a deferred finding belongs to a later ticket in this work set, update that later ticket's
description through `tron:jira-ticket-enricher` before launching it. A PR comment alone is not a
durable handoff to the next worker.

Park and wait for the human after every ready PR is handed off. Human approval remains outside this
skill. Do not perform merge, promotion, deployment, Jira Done, or worktree cleanup on the worker's
behalf.

## Today's runtime boundary (MD-2911)

Keep the loop honest about its current friction; do not build hidden workarounds:

- each ticket still needs its approval card resolved separately;
- the work set and graph live in this session and are lost when the control-plane API restarts;
- epic children cannot populate the work set automatically yet;
- first park and review re-park require the bundled filtered HTTP monitor because they do not cross
  a dispatch status boundary.

Record any additional v1 friction on MD-2911 so the runtime ticket is driven by observed use.
