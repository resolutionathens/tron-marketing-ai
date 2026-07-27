---
name: weekly-update
model: sonnet
effort: medium
fallback:
  cost: low
  skip_when: "Use tron:weekly-update only for composing a full weekly email. If user just needs their activity list without the email template, run the fetch script directly."
  stage_skips:
    - stage: "Step 3 — Ask three soft questions"
      skip_when: "User says 'no blockers' or provides the soft sections directly"
    - stage: "GitHub activity"
      skip_when: "GitHub is unavailable or user is Jira-only"
description: "Generate your weekly status update for your manager (and template owner) by pulling recent activity from Jira — and GitHub when it's available — asking 3 quick questions for the soft sections (blockers, decisions, cross-team), composing it into the team's 6-section template as a plain-text email body, and copying it to the clipboard via pbcopy. Use this skill whenever the user asks for their 'weekly update', 'weekly status', 'weekly report', 'standup report', 'manager report', 'update email', or mentions their weekly reporting deadline. Also trigger when the user says 'wrap up the week', 'what did I ship this week', or asks for a recap they can paste into an email. Recipient, template owner, and deadline are configurable per user (env vars, defaulting to the Kristina / Tuesday 9am PST ritual) — see Step 0. Works Jira-only for people without git/GitHub. Default window is 'since last Monday'; if the user says 'two-week' / 'biweekly' / 'past two weeks' / '2 weeks', widen accordingly."
allowed-tools:
  - Bash
  - AskUserQuestion
  - Read
  - Skill
scout:
  surface: true
  title: "Write my weekly update"
  blurb: "Pulls your week's activity from Jira, asks three quick questions, and copies a ready-to-send status email to your clipboard."
  when: "It's Monday and the weekly update is due Tuesday morning."
  category: tickets
  effects: [local]
  inputs:
    - key: window
      label: "Time window"
      type: text
      required: false
      placeholder: "since last Monday (default)"
---

# Weekly Update Generator

Produces a plain-text email body in the team's 6-section template, copied to clipboard via `pbcopy`. Works Jira-only (GitHub optional). Never auto-sends.

Jira auth is `acli`'s own per-user OAuth session, not a brokered token — see
[tools/jira/broker-status.md](../../tools/jira/broker-status.md) for why.

## Step 0 — Load recipient config

Recipient, template owner, and deadline come from env vars (same `~/.env` convention other
skills use — see [README.md](../../README.md) "Environment Variables"), defaulting to Ian's
current Kristina / Tuesday ritual so existing users see no change:

```bash
if [[ -z "${WEEKLY_UPDATE_RECIPIENT:-}" && -f "$HOME/.env" ]]; then
  set -a; source "$HOME/.env"; set +a
fi
RECIPIENT="${WEEKLY_UPDATE_RECIPIENT:-Kristina}"
MANAGER="${WEEKLY_UPDATE_MANAGER:-Dave}"
DEADLINE="${WEEKLY_UPDATE_DEADLINE:-Tuesday 9am PST / 12pm EST}"
```

`RECIPIENT` is also the template owner (whose 6-section format this is). Use `RECIPIENT` and
`MANAGER` in the Step 4 greeting, and `DEADLINE` anywhere the deadline is mentioned back to the
user. A user with no `~/.env` and no exports gets the same Kristina/Dave/Tuesday defaults as
today — this step changes nothing for them.

## Step 1 — Fetch the week's activity (scripted)

```bash
name=weekly-update
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/weekly-activity.sh)"
bash "$SKILL_DIR/scripts/weekly-activity.sh" fetch          # last Monday → now
bash "$SKILL_DIR/scripts/weekly-activity.sh" fetch --weeks 2   # biweekly
```

Returns:
```
WINDOW_START=2026-05-04
GITHUB: included
DONE: KEY — summary [status; labels]
IN FLIGHT: KEY — summary [status; labels; epic: KEY]
PRS MERGED: ...
PRS OPEN: ...
```

Relay the window to the user. If GitHub is skipped, say so. If the script exits non-zero on Jira, surface the auth error and stop.

## Step 2 — Categorize

| Bucket | → Section | Rule |
|--------|-----------|------|
| **Shipped** | §1 Quick Update, §6 Wins | DONE + merged PRs |
| **In flight** | §2 Key Priorities | IN FLIGHT + open PRs. **Pick at most 3.** |
| **Idle/dropped** | Discard | Noise |

## Step 3 — Ask three soft questions (one AskUserQuestion call)

1. **Roadblocks/Risks** — "Anything blocking you or at risk?"
2. **Items for Review/Decision** — "Anything needing team input?"
3. **Cross-Team Dependencies** — "Anything impacting other teams?"

Provide 2-3 plausible options from the data + "Other." If the user said "none," skip.

## Step 4 — Compose the email

```
Hey <RECIPIENT> and <MANAGER>,

1. Quick Update
- <1–2 bullets, high level — what moved forward>

2. Key Priorities (This Week)
- <priority 1>
- <priority 2>
- <priority 3>

3. Roadblocks / Risks
- <answer or "None this week">

4. Items for Review / Decision
- <answer or "None this week">

5. Cross-Team Dependencies
- <answer or "None this week">

6. Wins / Notable Progress
- <2–4 bullets from Shipped, optional — omit if nothing notable>
```

### Formatting rules (non-negotiable)

- **Plain text only** — no markdown, no `*bold*`, no backticks. Parentheses are fine.
- **No em dashes** (Facilitron voice). Use commas, colons, or split the sentence.
- **No Jira keys, no PR numbers, no commit hashes.** Translate to plain English: "Shipped MD-1733" → "Shipped the news page redesign."
- **~25 words per bullet max.** Roll up related work — name the theme, not each ticket.
- **Greeting is "Hey `<RECIPIENT>` and `<MANAGER>`,"** using the values loaded in Step 0. No subject line, no sign-off.
- **Section 6 optional.** Omit if nothing notable.
- **Look up Jira keys mentioned in user answers** before composing — write from the substance, not the key.

## Step 5 — Copy to clipboard

Write the composed body to a file, then copy from it:

```bash
cat > /tmp/weekly-update-body.txt <<'BODY'
<the composed email body>
BODY
if command -v pbcopy >/dev/null 2>&1; then
  pbcopy < /tmp/weekly-update-body.txt
fi
```

Print the full body for user review. If `pbcopy` succeeded, tell them: "On your clipboard. Paste into a new email." If `pbcopy` is unavailable (e.g. not on macOS), print the body and say it could not be copied — the user copies it from the terminal.

## Edge cases

| Situation | Action |
|-----------|--------|
| Empty window (no DONE, no IN FLIGHT) | Ask user before writing — may have done non-tracked work |
| `acli` not authenticated | Surface error, stop |
| GitHub absent (Jira-only) | Compose from Jira, note PRs not included |
| Cross-project work | `currentUser()` JQL spans all projects — good |
| Two-week mode (after PTO) | Make gap visible in §1: "Returned from PTO; ..." |

## Anti-patterns

❌ List every ticket — roll up. ❌ Write narrative — bullets only. ❌ Invent activity — say so and ask. ❌ Auto-send — `pbcopy` only. ❌ Reorder the template's sections. ❌ Use markdown or em dashes in output.