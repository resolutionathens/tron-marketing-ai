---
name: initiative-report
description: "Roll up the progress of a Marketing Initiative, Theme, Epic, or Campaign — child tickets by status, percent complete, what shipped, what's in flight, blockers, and what's next — into a shareable status summary. Use this skill when a manager wants a status roll-up: 'status of the ADA Compliance initiative', 'how's the FU6 event tracking', 'roll up the Tickets epic', 'progress report for MCR-355', 'what shipped under Brand & Creative', or any initiative/theme status ask. Git-free — reads Jira and writes a summary."
allowed-tools:
  - Bash
  - Read
  - Write
  - Skill
  - WebFetch
---

# /initiative-report — Initiative / theme progress roll-up

Summarize where a Marketing Initiative, Theme, Epic, or Campaign stands. Git-free: reads the board,
writes a status summary for sharing up.

## Resolve the tree
Given a parent key (Initiative/Theme/Epic/Campaign), pull it + its descendants:
```bash
acli jira workitem view <PARENT> --json
# children (Epics under an Initiative, Stories/Tasks under an Epic, Sub-tasks under those):
acli jira workitem search --jql 'parent = <PARENT> OR "Epic Link" = <PARENT> ORDER BY status' --limit 200 --json
```
For a Theme, walk one level down to its Initiatives and summarize each.

## Compute
- **% complete** = Done / total (and a count: `12/20 done, 3 in progress, 5 to do`).
- **Shipped** — recently moved to Done (with dates if available).
- **In flight** — In Progress, with owner.
- **At risk / blocked** — overdue, flagged, or stalled.
- **Unstarted** — To Do, especially unassigned.

## Output
```markdown
# <Initiative/Theme> — status (<date>)
**Progress:** 12/20 done (60%) · 3 in progress · 5 to do
**Shipped recently:** <bullets>
**In flight:** <ticket — owner — note>
**At risk:** <ticket — why>
**Next up:** <the few that should start>
**Ask:** <any decision/resource needed from leadership>
```

## Rules
- Lead with the percent + the one-line health (on track / at risk / blocked).
- Plain prose, no em dashes, exec-readable. Don't editorialize beyond what the tickets show.

Write `/tmp/manager/<slug>-status.md`. Offer `tron:md-to-pdf` for a polished version, or fold into
the manager's `weekly-update`. Summarize health + the single most important ask.
