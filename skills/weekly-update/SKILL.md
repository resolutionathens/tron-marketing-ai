---
name: weekly-update
model: sonnet
effort: medium
description: "Generate your weekly status update for Kristina (and your manager) by pulling recent activity from Jira — and GitHub when it's available — asking 3 quick questions for the soft sections (blockers, decisions, cross-team), composing it into Kristina's 6-section template as a plain-text email body, and copying it to the clipboard via pbcopy so you can paste it into a new email. Use this skill whenever the user asks for their 'weekly update', 'weekly status', 'weekly report', 'standup report', 'Kristina report', 'report for Dave', 'update email', or mentions Kristina's Tuesday 9am PST / 12pm EST deadline. Also trigger when the user says 'wrap up the week', 'what did I ship this week', or asks for a recap they can paste into an email. Works Jira-only for people without git/GitHub. Default window is 'since last Monday'; if the user says 'two-week' / 'biweekly' / 'past two weeks' / '2 weeks', widen accordingly."
allowed-tools:
  - Bash
  - AskUserQuestion
  - Read
  - Skill
---

# Weekly Update Generator

This skill produces a weekly status update for Kristina (and the user's manager) in the exact 6-section template Kristina expects. The output is a **plain-text email body** (no markdown, no Slack asterisks), copied to the clipboard via `pbcopy`. The user pastes it into a new email and sends it themselves — the skill never sends.

The skill's value is removing the busywork: pulling the user's tickets (and PRs, when GitHub is set up), grouping them into "moved forward" vs "priorities", and asking just enough about the soft sections (blockers, decisions, cross-team) to fill in what the data can't tell us. Kristina's instruction is "keep it high level" — terse bullets, no narrative.

**Works Jira-only.** The fetch script treats GitHub as optional: anyone with `acli` (Jira) can run this. If `gh` is missing or unauthenticated, the PR buckets are skipped with the reason stated and the report is composed from Jira alone. `acli` is the only hard dependency.

## When to run

Trigger phrases: "weekly update", "weekly status", "Kristina report", "update for Dave", "standup report", "what did I ship this week", "weekly recap", "wrap up the week". Also trigger when the user mentions Tuesday 9am PST or the Kristina deadline reminder.

## Workflow

Follow this sequence. Each step is short — don't pad.

### Step 1 — Fetch the week's activity (scripted)

The window math + Jira/GitHub pulls are mechanical and deterministic, so they live in a bundled script. Run it rather than re-deriving the JQL and date math by hand:

```bash
# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=weekly-update
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains the script
[ -e "$SKILL_DIR/scripts/weekly-activity.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/weekly-activity.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/weekly-activity.sh" ] || { echo "tron:$name: can't find scripts/weekly-activity.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/weekly-activity.sh" fetch          # default: last Monday → now
# bash "$SKILL_DIR/scripts/weekly-activity.sh" fetch --weeks 2   # biweekly / "past two weeks"
```

| Want                                      | Command                                       |
| ----------------------------------------- | --------------------------------------------- |
| Default weekly window (since last Monday) | `weekly-activity.sh fetch`                    |
| Biweekly window                           | `weekly-activity.sh fetch --weeks 2`          |
| Override the start date                   | `weekly-activity.sh fetch --start YYYY-MM-DD` |
| Different GitHub org                      | `weekly-activity.sh fetch --owner <ORG>`      |
| Force Jira-only                           | `weekly-activity.sh fetch --no-github`        |

The script computes the Monday-anchored window (default 1 week back; `--weeks 2` for biweekly), runs the two authoritative Jira queries (`updated >= START` for in-flight + `status changed TO ('Done','Closed','Resolved') DURING` for shipped), and — only if `gh` is installed and authenticated — the merged + open PR pulls. It prints compact, pre-digested buckets you compose from:

```
WINDOW_START=2026-05-04  (1 week)
GITHUB: included            # or: skipped — gh not installed (Jira-only mode) / not authenticated / --no-github

DONE (transitioned to done in window):       # → §1, §6
- KEY — summary [status; labels]
IN FLIGHT (In Progress / To Do, updated in window):   # → §2
- KEY — summary [status; labels; epic: KEY]
PRS MERGED in window:        # → §1, §6 (or "(github skipped …)")
PRS OPEN:                    # → §2 (or "(github skipped …)")
```

The first line tells you the window — relay it to the user in one short sentence so they can correct it (e.g., "Pulling activity since 2026-05-04."). If `GITHUB:` is anything but `included`, **say so** ("GitHub skipped — composing from Jira only") so the user knows PRs aren't reflected; don't fabricate PR activity. If the script exits non-zero on the Jira pull, surface the `acli jira auth` remedy it prints and stop — don't invent tickets. Smoke the offline surface (window math, the Jira-only degradation, the usage contract) with `bash "$SKILL_DIR/scripts/test-weekly-activity.sh"`.

### Step 2 — Categorize the data

Sort the buckets into three categories that map to template sections:

| Category           | Maps to                  | Selection rule                                                                |
| ------------------ | ------------------------ | ----------------------------------------------------------------------------- |
| **Shipped**        | §1 Quick Update, §6 Wins | The DONE bucket (transitioned to a done state in-window) + merged PRs.        |
| **In flight**      | §2 Key Priorities        | The IN FLIGHT bucket + open PRs that are still relevant going into next week. |
| **Idle / dropped** | (discard)                | Noise; anything not genuinely this week or next.                              |

The DONE bucket already reflects the authoritative "status changed TO done DURING window" query, so use it for §1/§6 as-is — don't re-query or second-guess it.

For §2 Key Priorities, **pick at most 3** even if more are in flight. Kristina caps it at "top 1–3 priorities". Choose by recency of activity and apparent stakes — newest In Progress with active commits or labels like `priority`/`blocker` outrank stale ones. If unsure, pick the ones with the most recent updates.

### Step 3 — Ask the user the three soft questions

These can't be derived from data. Ask them as a single `AskUserQuestion` call (three questions in one batch) — never one at a time, it wastes a round trip:

1. **Roadblocks / Risks** — "Anything blocking you or at risk? Be specific about what's needed and from who."
2. **Items for Review / Decision** — "Anything that needs team input, alignment, or approval? Include context + recommended direction."
3. **Cross-Team Dependencies** — "Anything impacting or needed from other teams? Call out names/teams."

Provide 2–3 plausible options based on what you saw in the data **plus** an "Other" path. Examples:

- Roadblocks: "None this week", "Waiting on review for an open PR", "Blocked on design feedback from <person>"
- Decisions: "None this week", names of tickets that look like they need a call
- Cross-Team: "None this week", any tickets/PRs that @-mention other teams or carry cross-team labels

**Categorization overlap — the most common confusion:** "Waiting on another team for an asset" can fit both §3 Roadblocks and §5 Cross-Team. They're not the same — Roadblocks is what's _at risk_ (won't ship without it), Cross-Team is _who owes what_ (the audit trail of asks). The same item can legitimately land in both — that's fine, not duplication:

- Asset has a deadline that puts shipping at risk → Roadblock primary, optionally mirror in Cross-Team.
- Routine ask, no deadline pressure → Cross-Team only.
- User picks one but the other seems load-bearing → ask: "should this also go under §5 Cross-Team so the design team sees the ask?" Don't silently file it in both.

If the user said up front "no blockers, no decisions, no cross-team this week", skip the questions and write "None this week" for each. Otherwise always ask — these make the report useful to the team.

### Step 4 — Compose the plain-text email body

Use this exact structure. Headings match Kristina's template verbatim — don't rename them.

```
Hey Kristina and Dave,

1. Quick Update
- <1–2 bullets max — what moved forward since last week, high level>

2. Key Priorities (This Week)
- <priority 1>
- <priority 2>
- <priority 3>

3. Roadblocks / Risks
- <user's answer, or "None this week">

4. Items for Review / Decision
- <user's answer, or "None this week">

5. Cross-Team Dependencies
- <user's answer, or "None this week">

6. Wins / Notable Progress
- <2–4 bullets pulled from Shipped — keep to genuinely notable items>
```

Notes on formatting and voice:

- **Plain text only — no markdown.** This goes into an email body that doesn't render markdown. No `*bold*`, `**bold**`, or `` `backticks` `` (they show up literally). For file paths / ticket-ish things, write them bare or in quotes. Parentheses are fine.
- **No em dashes** in the produced copy (Facilitron voice). Use a comma, a colon, or split the sentence.
- **Greeting is fixed: "Hey Kristina and Dave,"** with a blank line after, then "1. Quick Update". If the user is not Ian, swap "Dave" for their own manager's name (ask if unsure who the second recipient is). No sign-off — the email client appends the signature.
- **Don't include a subject line in the clipboard.** Body only — the user types a subject themselves.
- Section 6 is optional per Kristina's template. If there are no genuinely notable wins, omit the whole §6 — don't fake-fill it.
- Each bullet is one short sentence. No paragraphs. No filler ("This week I worked on...").
- **Hard cap: ~25 words per bullet.** If a bullet runs long, trim modifiers ("the news article and index templates" → "news templates") or split it — but §1 itself is capped at 1–2 bullets total, so usually roll up tighter.
- **No Jira keys, no PR numbers, no commit hashes in the output.** Kristina doesn't have GitHub access, and neither she nor the manager wants to chase ticket links. Translate each item from "what's in the tracker" to "what got built/shipped/written" — the deliverable, in plain English. _Bad:_ "Shipped MD-1733 (PR #699)." _Good:_ "Shipped the news article and index page redesign, now using the same branded hero style as the toolkit pages."
- **Roll-up rule** (one bullet covering many tickets): name the theme + the count + a parenthetical of concrete deliverables. _Bad:_ "Toolkit content drop, CCAL-1462/1473/1475/1476/1477." _Good:_ "Toolkit content drop: 4 new resources (a maintenance-schedule template, a grounds-maintenance checklist, an asset-lifecycle template, and an SOP for preventive maintenance) plus a cluster article on the top benefits of facility management software."
- **For "ship to prod" priorities, name the page/feature, not the PR.** _Bad:_ "Land PR #699 to master + staging/prod." _Good:_ "Push the news page redesign to production."
- **For roadblocks, describe the constraint, not the ticket.** _Bad:_ "Static deploy issues blocked by MD-1715, MD-1713." _Good:_ "Our static deploy setup keeps blocking work that needs real server responses, same root cause we've flagged twice before. Both items are on hold pending an architectural call about moving to server-rendered hosting."
- "High level" means roll up related work. With 10+ tickets in a category, name the _theme_, not each item.
- Don't say "in progress" or "ongoing" in §1 — only completed work belongs there. In-progress goes in §2.
- **If a soft-section answer names a Jira KEY** (e.g. "blocked by MD-1715"), look it up with `acli jira workitem view <KEY> --json` before composing the bullet — but write the bullet from the summary's _substance_, not the key. The lookup sharpens your framing; the key stays out of the output.

### Step 5 — Copy to clipboard and show the user

Pipe the composed text to `pbcopy`:

```bash
printf '%s' "$REPORT" | pbcopy
```

(Use `printf '%s'`, not `echo` — `echo` adds a trailing newline and may interpret backslashes.)

Then print the full body back to the user for review. Tell them: "On your clipboard. Paste into a new email to Kristina + your manager." If GitHub was skipped, remind them the report is Jira-only so they can add any PR-only work by hand.

## Edge cases

- **Empty window**: If the DONE and IN FLIGHT buckets are both empty (and GitHub too), ask the user before writing anything. They may have done non-tracked work (research, meetings) that belongs in §1. Don't write a report claiming nothing happened.
- **acli not authenticated**: The script exits non-zero and prints `acli jira auth`. Surface that and stop — don't fake the data.
- **GitHub absent (Jira-only user)**: Expected and supported. The `GITHUB:` line will say why it was skipped. Compose from Jira, and tell the user PRs aren't included so they can add anything PR-only.
- **Cross-project Jira work**: The `assignee = currentUser()` JQL spans all projects (MD, CCAL, MCR) by default — good. Don't restrict to one project.
- **Recurring priorities**: If MEMORY.md records a standing priority (e.g. WCAG audit, April 2026 deadline), you may mention it in §2 even if nothing moved this week — but only if it's genuinely top priority. Don't pad.
- **Two-week mode after time off**: For `--weeks 2` because the user was out, make the gap visible in §1 ("Returned from PTO; ..."). Ask if unsure whether to call it out.

## Anti-patterns

- **Don't list every ticket.** Roll up. A reader scanning their inbox should learn the shape of the week in 15 seconds.
- **Don't write narrative prose.** Bullets only.
- **Don't invent activity.** If Jira (and GitHub) are quiet, say so and ask the user. Hallucinated "made progress on X" bullets are worse than an honest light week. Never fabricate PRs when GitHub was skipped.
- **Don't auto-send.** `pbcopy` is the contract — clipboard for the user to paste, not a direct send via `gws` or anything else.
- **Don't reorder Kristina's sections.** They're numbered; she scans top-to-bottom across the team.
- **Don't use markdown or em dashes anywhere in the output.** Both render as literal characters / off-voice in the email.
