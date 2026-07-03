---
name: initiative-report
model: sonnet
effort: medium
description: "Roll up the progress of a Marketing Initiative, Theme, Epic, or Campaign — child tickets by status, percent complete, what shipped, what's in flight, blockers, and what's next — into a shareable status summary. Use this skill when a manager wants a status roll-up: 'status of the ADA Compliance initiative', 'how's the FU6 event tracking', 'roll up the Tickets epic', 'progress report for MCR-355', 'what shipped under Brand & Creative', or any initiative/theme status ask. Git-free — reads Jira and writes a summary."
allowed-tools:
  - Bash
  - Read
  - Write
  - Skill
---

# /initiative-report — Initiative / theme progress roll-up

Summarize where a Marketing Initiative, Theme, Epic, or Campaign stands. Git-free: reads the board,
writes a status summary for sharing up.

## Resolve the tree

Given a parent key (Initiative/Theme/Epic/Campaign), pull it **plus every descendant** — not just
direct children. `parent = <PARENT>` is **single-level**: on MCR an Initiative's real subtree is
Initiative → Epic → Task → Sub-task (often 100+ items), so a one-level query computes % complete on
the wrong denominator. Do **not** use `"Epic Link" = <PARENT>` — MCR's marketing hierarchy is
`parent`-based and Epic Link adds zero rows.

### Fast path (scripted)

The mechanical walk (csv helper, breadth-first frontier loop, JQL assembly, status pull) is one
script — it returns the parent, every descendant with status fields, and pre-computed counts:

```bash
name=initiative-report
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/initiative-report.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/initiative-report.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/initiative-report.sh" ] || { echo "tron:$name: scripts/initiative-report.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/initiative-report.sh" fetch <PARENT-KEY>
```

Output is one JSON object: `{parent, counts: {total, done, in_progress, to_do}, descendants,
truncated}`. If `truncated` is true, some level returned exactly `--limit` rows (default 200) —
re-run with a higher `--limit` and note the board is larger than one page. The full descendant
detail is also saved to `/tmp/manager/<PARENT>-descendants.json`. For a Theme the same walk applies
(its Initiatives are just the first level down); optionally summarize per-Initiative as well as
the rollup.

### Manual fallback (if script unavailable)

```bash
acli jira workitem view <PARENT> --json   # the parent itself

# BFS every level of descendants (jq is fine — this runs on your machine, not a sandbox).
# csv() squeezes runs of spaces/newlines into single commas and trims the ends, so jq's
# newline-separated output becomes a valid JQL list (no leading/empty element).
csv() { tr -s ' \n' ',' | sed 's/^,//;s/,$//'; }
frontier="<PARENT>"; all=""
while [ -n "$frontier" ]; do
  list=$(printf '%s' "$frontier" | csv)
  kids=$(acli jira workitem search --jql "parent in ($list)" --limit 200 --json | jq -r '.[].key')
  [ -z "$kids" ] && break
  all="$all $kids"; frontier="$kids"
done
# $all = every descendant key. Pull their statuses to compute % complete over the FULL set:
keys=$(printf '%s' "$all" | csv)
acli jira workitem search --jql "key in ($keys)" \
  --fields key,summary,status,assignee,duedate,updated --limit 1000 --json
```

If any level hits the 200 cap, paginate (`--limit`/offset) and note the board is larger than one
page.

## Compute

- **% complete** = Done / total over **every descendant** gathered above (not just direct children),
  with a count: `35/118 done, 12 in progress, 71 to do`. State the denominator so the number is auditable.
- **Shipped** — recently moved to Done (with dates if available).
- **In flight** — In Progress, with owner.
- **At risk / blocked** — overdue, flagged, or stalled.
- **Unstarted** — To Do, especially unassigned.

## Output

```markdown
# <Initiative/Theme> — status (<date>)

**Progress:** 12/20 done (60%) · 3 in progress · 5 to do
**Shipped recently:** <bullets>
**In flight:** <ticket · owner · note>
**At risk:** <ticket · why>
**Next up:** <the few that should start>
**Ask:** <any decision/resource needed from leadership>
```

## Rules

- Lead with the percent + the one-line health (on track / at risk / blocked).
- Plain prose, no em dashes, exec-readable. Don't editorialize beyond what the tickets show.

Write the summary:

```bash
mkdir -p /tmp/manager
# then write /tmp/manager/<slug>-status.md
```

Offer `tron:md-to-pdf` for a polished version, or fold into the manager's `weekly-update`.
Summarize health + the single most important ask.
