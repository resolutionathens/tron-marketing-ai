---
name: jira-comment
model: sonnet
effort: medium
description: Add a short, plain-language progress or summary comment to a Jira ticket using the `acli` CLI, in a voice that's succinct, non-technical, prose (no bullets), and free of em dashes. Use this skill whenever the user says "comment on the ticket", "add a Jira comment", "leave a note on CCAL-XXXX", "note what we did on the ticket", "drop a comment on MD-1234", "update the ticket", or otherwise wants to post a quick status, progress, or summary comment to a Jira issue. Trigger even when the user doesn't explicitly say "Jira"; phrases like "comment on it" in a context where a Jira key or active ticket is in play count.
allowed-tools:
  - Bash
  - AskUserQuestion
scout:
  surface: true
  title: "Post a ticket update"
  blurb: "Writes a short, plain-language progress note on a ticket — in your voice, not robot voice."
  when: "A ticket needs a status note and you don't want to write it."
  category: tickets
  effects: [jira]
  inputs:
    - key: ticket
      label: "Ticket"
      type: text
      required: true
      placeholder: "e.g. MCR-1801"
    - key: comment
      label: "Comment"
      type: textarea
      required: true
---

# Jira Comment

Post a short, plain-language comment to a Jira ticket via `acli`. Auth is `acli`'s
own per-user OAuth session, not a brokered token — see
[tools/jira/broker-status.md](../../tools/jira/broker-status.md) for why. The point of this skill is **voice**: most LLM-written comments are too long, too technical, or have AI tells (em dashes, bullet lists, conventional-commit prefixes leaking into prose). This skill is here to keep comments sounding like a human teammate dropping a quick note.

## When to use

Anytime the user wants a comment on a ticket — typically after some work has landed (commit, merge to dev, PR, deploy) and they want to keep the ticket conversation up to date for non-technical stakeholders who read it (PMs, designers, requesters like the person who filed the ticket).

## Step 1: Find the ticket key

Try in this order, stop as soon as you have one:

1. The user named a key (e.g. "comment on CCAL-1906").
2. The current branch matches `^[A-Z]+-\d+`. Grab the leading `<KEY>` segment: `git rev-parse --abbrev-ref HEAD | grep -oE '^[A-Z]+-[0-9]+'`.
3. Ask the user.

If you're inside a worktree, the branch name is still the source of truth — no special handling needed.

## Step 2: Draft the comment in the right voice

The voice rules below are the heart of the skill. Each one is here for a reason; understanding the reason helps you handle edge cases.

**Succinct.** Two to four sentences is the sweet spot. One sentence is fine for trivial updates. If the comment is creeping toward a paragraph, you're probably explaining too much — the ticket already has the title, description, and PR link; the comment just connects the dots.

**Plain-language, not too technical.** The ticket reader may be a designer, PM, or the person who originally filed the request — not necessarily an engineer. Translate code concepts into outcomes: not "added a `backgroundImageMode` prop with `'repeat'` and `'cover'` enum values", but "the background image can either tile as a repeating pattern or fill the whole section as a cover image." Framework names, prop names, file paths, conventional-commit prefixes, and TypeScript jargon don't belong in the comment body. Save those for the PR.

**Prose, not bullets.** Bullets feel like a status report or a chunked AI response. Two or three sentences in a row reads like a person talking. If you genuinely have a list of unrelated items, that's usually a sign you have more than one comment to write — or that the items belong in the PR description.

**No em dashes**, and scan the draft for them before posting. The rule, the reasons, and the substitutions are in [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).

**Mention where it stands if there's a useful next step.** If the work is on dev, in a PR, or live on production, end with a short pointer ("Live on dev now for review, PR #709." or "Shipped to production."). Skip this if the ticket itself already implies where things are or if the comment is purely informational with no follow-up.

**First-person plural is fine.** "We updated…", "I added…" — both read naturally. Pick whatever feels right; the user is talking to their own team.

See [voice examples and anti-patterns](reference/voice-examples.md) for the detailed example and review checklist.

## Step 3: Post the comment

If the user explicitly told you what to comment about ("comment that we shipped X"), draft it and post directly — they've authorized the action and don't want a preview round-trip.

If the user asked for "a comment" without specifics, or you're not sure what's worth highlighting, draft it and show them first. Comments are shared state (other people on the ticket see them), so when in doubt, confirm.

Use `acli` with a single-quoted body. The body is plain text — Jira will render newlines as paragraph breaks but won't parse markdown:

```bash
acli jira workitem comment create --key <KEY> --body '<comment text>'
```

If the body contains a single quote, swap the outer quoting to double quotes and escape any inner double quotes, or use a HEREDOC pattern via `--from-file`. ADF JSON is overkill for short prose comments — `--body` is the right tool here.
