---
name: jira-comment
model: sonnet
effort: medium
description: Add a short, plain-language progress or summary comment to a Jira ticket using the `acli` CLI, in a voice that's succinct, non-technical, prose (no bullets), and free of em dashes. Use this skill whenever the user says "comment on the ticket", "add a Jira comment", "leave a note on CCAL-XXXX", "note what we did on the ticket", "drop a comment on MD-1234", "update the ticket", or otherwise wants to post a quick status, progress, or summary comment to a Jira issue. Trigger even when the user doesn't explicitly say "Jira"; phrases like "comment on it" in a context where a Jira key or active ticket is in play count.
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Jira Comment

Post a short, plain-language comment to a Jira ticket via `acli`. The point of this skill is **voice**: most LLM-written comments are too long, too technical, or have AI tells (em dashes, bullet lists, conventional-commit prefixes leaking into prose). This skill is here to keep comments sounding like a human teammate dropping a quick note.

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

**No em dashes.** They're an AI tell and they make casual writing feel formal. Use a period, a comma, parentheses, or the word "and"/"but"/"so" instead. This is one of the more common rules to slip on — actively scan your draft for them before posting.

**Mention where it stands if there's a useful next step.** If the work is on dev, in a PR, or live on production, end with a short pointer ("Live on dev now for review, PR #709." or "Shipped to production."). Skip this if the ticket itself already implies where things are or if the comment is purely informational with no follow-up.

**First-person plural is fine.** "We updated…", "I added…" — both read naturally. Pick whatever feels right; the user is talking to their own team.

### Example

After shipping a backward-compatible component change with options for variation:

> Updated the product hero so the background image can either tile as a repeating pattern (the current behavior) or fill the whole section as a cover image, both over a chosen background color. The tile size is now adjustable too, giving more ways to vary heroes between sections. All existing heroes are unaffected since the new options are opt-in. Live on dev now for review, PR #709.

Notice: prose, no bullets, no em dashes, no `backgroundImageMode` or other code-y names, and a clear status pointer at the end.

## Step 3: Post the comment

If the user explicitly told you what to comment about ("comment that we shipped X"), draft it and post directly — they've authorized the action and don't want a preview round-trip.

If the user asked for "a comment" without specifics, or you're not sure what's worth highlighting, draft it and show them first. Comments are shared state (other people on the ticket see them), so when in doubt, confirm.

Use `acli` with a single-quoted body. The body is plain text — Jira will render newlines as paragraph breaks but won't parse markdown:

```bash
acli jira workitem comment create --key <KEY> --body '<comment text>'
```

If the body contains a single quote, swap the outer quoting to double quotes and escape any inner double quotes, or use a HEREDOC pattern via `--from-file`. ADF JSON is overkill for short prose comments — `--body` is the right tool here.

## Anti-patterns

- **Echoing the commit message.** The ticket already links to the PR; the comment shouldn't read like `feat(hero): add cover mode...`. Strip the prefix and rewrite in prose.
- **Listing every change as bullets.** If you find yourself writing `- did X` `- did Y`, collapse them into a sentence: "We did X and Y."
- **Em dashes anywhere.** Even one. Scan before posting.
- **Restating the ticket.** If the ticket is "Add cover mode to hero," don't comment "Added cover mode to the hero." Tell them what's *new* since they filed it — that it's working, where to see it, anything they should know.
- **Multi-paragraph essays.** If the update genuinely needs that much explanation, it probably wants a meeting or a Confluence page, not a Jira comment.
