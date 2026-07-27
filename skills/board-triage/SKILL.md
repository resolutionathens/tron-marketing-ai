---
name: board-triage
model: sonnet
effort: medium
description: "Review a Jira marketing board (default MCR) and surface what needs attention — new/unassigned tickets, stale or blocked items, missing priorities or due dates, and ownership gaps — with suggested assignments and priorities grouped by Marketing Theme. Use this skill when a manager wants to run the board: 'triage the MCR board', 'what needs attention on the board', 'morning board review', 'who should pick these up', 'what's stale', or any standup/board-grooming ask. Git-free — reads Jira and proposes changes; it applies assignments/transitions only on your confirmation."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
  - Skill
scout:
  surface: true
  title: "Triage the board"
  blurb: "Reviews the marketing board for stale, unassigned, or blocked tickets and suggests what to do with each."
  when: "Start of the week, or the board feels out of control."
  category: tickets
  effects: [jira]
  inputs: []
---

# /board-triage — Marketing board triage

Give a manager a fast, prioritized read of the board and a proposed set of grooming actions. Lineage:
the orchestrator's `jira-morning-suggest`. Git-free: it reads and proposes; it writes to Jira only
after you confirm.

Auth is `acli`'s own per-user OAuth session, not a brokered token — see
[tools/jira/broker-status.md](../../tools/jira/broker-status.md) for why.

## Scope

Default board: **MCR** (the marketing master board). Hierarchy: Marketing Theme → Initiative →
Campaign/Epic/Story/Task/Sub-task.

## Fast path (scripted)

The mechanical pull (search, per-key enrichment, bucket math) is one script — it emits the five
lenses below as pre-digested JSON, so you never read raw per-ticket JSON:

```bash
name=board-triage
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/board-triage.sh)"
bash "$SKILL_DIR/scripts/board-triage.sh" fetch                    # MCR, --limit 500, 14-day staleness
bash "$SKILL_DIR/scripts/board-triage.sh" fetch --project ABC --stale-days 7
```

Output is one JSON object: `{project, total, truncated, unassigned, stale, missing_metadata,
blocked, wip_load}` — each bucket a list of `{key, summary, status, assignee, priority, duedate,
updated, parent, parent_summary}`. If `truncated` is true the board is larger than `--limit`;
paginate or raise the limit. The raw enriched array is saved to `/tmp/manager/triage-enriched.json`
for any follow-up query. If the script exits non-zero on Jira, surface the auth error and stop.

## Manual fallback (if script unavailable)

`acli jira workitem search` only returns a fixed set of fields and **rejects `--fields updated`,
`duedate`, or `parent`** — so the bare search can't compute the stale / overdue / orphaned lenses.
Pull the candidate keys with search, then **enrich each with `view`** (where those fields resolve):

```bash
mkdir -p /tmp/manager

# 1. Candidate set (keys + the fields search does return). Raise the limit / paginate — MCR has
#    more than 200 non-Done items, and --limit 200 silently truncates.
acli jira workitem search --jql 'project = MCR AND statusCategory != Done ORDER BY updated ASC' \
  --limit 500 --json | jq -r '.[].key' > /tmp/manager/triage-keys.txt

# 2. Enrich: updated, duedate, and parent only exist on the full item view.
while read k; do
  acli jira workitem view "$k" --fields '*all' --json
done < /tmp/manager/triage-keys.txt | jq -s '.'
```

Enrichment is what powers lenses 2–3 below; without it, only Unassigned, WIP-load, and status are
computable. If the board is large, enrich just the actionable slice (To Do / In Progress) first.

## Triage lenses

1. **Unassigned + actionable** — To Do / In Progress with no assignee.
2. **Stale** — In Progress not updated in >N days (default 14), or To Do that's overdue.
3. **Missing metadata** — no priority, no due date, or orphaned (no parent Initiative/Theme).
4. **Blocked / at-risk** — flagged blockers, or due soon with no progress.
5. **WIP load** — who's carrying how much In Progress (over-allocation).

## Output

Grouped by Marketing Theme, then a proposed-actions list:

```
THEME: Events & Conferences
  ⚠ MCR-310 FU6 Event Projections — In Progress 21d, no update → ping owner / re-scope
  ○ MCR-318 Logo Filler Pages — unassigned, event in <2wk → assign (suggest: designer)
PROPOSED ACTIONS
  - assign MCR-318 → <name>; set priority High
  - nudge MCR-310 owner for status
```

For unassigned tickets, suggest a **role** (not a person) inferred from the ticket type:
asset/Figma/swag/collateral work → **designer**; copy, page content, or resources items →
**content**; keyword, meta, or ranking work → **seo**; build/deploy/navigation/code changes →
**dev**. Leave the specific assignee to the user — they know the team's load and roster. Use
**AskUserQuestion** to batch the decisions. Apply approved assignments/priorities/transitions via
`acli` and notes via `tron:jira-comment` — **only after confirmation**. Never mass-transition
without a yes.

End with: counts (unassigned / stale / blocked), the top 3 things needing a human, and what you
applied (if anything).
