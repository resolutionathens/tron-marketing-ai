---
name: board-scaffold
model: sonnet
effort: low
description: "Scaffold a repeatable set of Jira sub-tasks under a parent ticket from a template — most notably the standard Facilitron creative production chain (Design → Design Approval → Order Logistics → Ordered → Delivered) used across swag and event collateral, but also custom checklists. Use this skill when a manager/designer wants to set up a ticket's sub-tasks: 'scaffold the sub-tasks for this swag item', 'set up the production chain under MCR-305', 'add the standard design→deliver steps', 'break this down into sub-tasks', or when creating a new merch/collateral item that needs the usual lifecycle. Git-free (Jira writes) — always previews and confirms before creating anything."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
  - Skill
---

# /board-scaffold — Templated sub-task scaffolding

Create the repeatable sub-task chains the marketing board uses over and over (the swag/collateral
Design→Deliver lifecycle and friends), so a manager doesn't hand-create the same five sub-tasks for
every hat, tee, and banner. Git-free (it writes Jira issues) — **previews and confirms first**, never
bulk-creates silently.

## Templates
| Template | Sub-tasks |
|---|---|
| **creative-production** (default for swag/collateral) | Design · Design Approval · Order Logistics · Final Approval · Ordered · Delivered |
| **print-collateral** | Design · Design Approval · Print Proof · Printed · Delivered |
| **web-page** | Content · Design · Build · SEO review · QA · Publish |
| **custom** | you provide the list |

The board already follows the creative-production pattern — the **live MCR chain is six steps**: the
swag tickets carry a **Final Approval** gate between Order Logistics and Ordered (verified on the
Totebag and Pins chains), so the default reproduces all six. Before scaffolding, glance at a recent
sibling chain (`acli jira workitem view <SIBLING> --json`) and match it: board naming is inconsistent
in practice ("Order Pins" vs "Totes Ordered", "Totebag Design" vs "Sticker Design"). Default to the
clean `<Item> <Step>` convention, but if the surrounding tickets use a different label, follow them.

## Flow
1. **Resolve the parent:** `acli jira workitem view <PARENT> --json` — confirm project, item name,
   issue type (sub-tasks attach to a Story/Task/Epic per the project config).
2. **Pick the template** (default creative-production) and the item label (e.g. "Beach Towel").
3. **Preview** the exact sub-tasks to be created (titles, parent, assignee, any due dates) and get a
   single confirmation via **AskUserQuestion**.
4. **Create** on confirmation:
```bash
acli jira workitem create --project MCR --type Sub-task --parent <PARENT> \
  --summary "<Item> Design" [--assignee <id>] [--json]
# ...one per template step
```
5. **Report** the created keys as a checklist; offer to set the parent's links/priority.

## Rules
- Never create without the explicit preview-and-confirm step. Creating Jira issues is outward-facing.
- Match the project's real issue-type + field config (Sub-task requires a parent; check it exists).
- Keep naming consistent with the board's convention (`<Item> <Step>`).

End with the list of created sub-task keys and the parent they hang under.
