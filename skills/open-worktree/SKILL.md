---
name: open-worktree
model: sonnet
effort: low
description: "Open a git worktree in a new tmux session with vim and a terminal, opening any associated URL in your default browser. Use this skill when the user says 'open worktree', 'open that worktree', 'set up workspace for <branch>', 'open workspace for <ticket>', or wants to start working in a worktree that already exists. Also trigger when the user says 'open it in tmux', 'set up a session for that', or references a worktree path they want to work in."
allowed-tools:
  - Bash
  - Read
---

# Open Worktree

Open an existing git worktree in a new tmux session with a two-pane layout, and
open any associated URL (ticket, PR, docs) in the user's **default browser**:

```
┌─────────────────────┐
│        vim          │
├─────────────────────┤
│      terminal       │   + any URL opens in your default browser
└─────────────────────┘
```

vim on top, terminal on the bottom. The browser is the user's normal default
browser (`open <url>` on macOS), not a managed pane.

## Fast path (scripted)

Resolve the worktree and fix the two footguns (missing gitignored env files, an
empty `node_modules`) in one deterministic call before setting up tmux:

```bash
# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=open-worktree
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains scripts/open-worktree.sh
# (skips a stale mirror that lacks it; newest version wins, marketplace breaks ties)
[ -e "$SKILL_DIR/scripts/open-worktree.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/open-worktree.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/open-worktree.sh" ] || { echo "tron:$name: can't find scripts/open-worktree.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/open-worktree.sh" --branch <name> [--no-switch]
```

It runs `wt switch <branch> --yes` (unless `--no-switch`), resolves the worktree
path from `git worktree list`, copies the gitignored `.env*`/`.dev.vars*` files
from the primary checkout, and reports whether `node_modules` is empty. One JSON
line on stdout:

```json
{"ok":true,"branch":"MD-1801-x","worktreePath":"/…","mainCheckout":"/…","envCopied":[".env.local"],"nodeModulesEmpty":false}
{"ok":false,"branch":"x","error":"worktree-not-found","hint":"create it with tron:start-ticket, or check `wt list`"}
```

Take `worktreePath` from the result and use it as the `<absolute-path>` in the
tmux steps below. If `nodeModulesEmpty` is true, run the project's install before
launching dev. Smoke it with `bash "$SKILL_DIR/scripts/test-open-worktree.sh"`.

The tmux pane composition below stays manual — surface layout is judgment,
not a fixed sequence (its sibling `start-ticket` keeps tmux setup in prose too).

## Determine the worktree path

The user will either:
- Provide an explicit branch name — use `wt switch <branch>` to switch to it and get the path
- Say they want the current one — use `wt list` to identify it (marked with `@`)
- Have just created one via the tron:start-ticket skill — use that branch name

First, check available worktrees:
```bash
wt list
```

If the user specifies a branch, switch to it to get the correct path. Always pass `--yes` because Claude Code runs in a non-interactive environment and `wt` will prompt for hook approvals otherwise:
```bash
wt switch <branch-name> --yes
```

`wt` will output the worktree path. If you need the absolute path:
```bash
pwd
```

## Set up the tmux session

Run these commands in sequence. Use the branch name (with any `.`/`:` swapped for
`-`, since tmux disallows them in session names) as the session name, and the
worktree's absolute path as `<absolute-path>`:

```bash
SESSION="$(printf '%s' '<branch-name>' | tr '.:' '--')"
```

### 1. Create the session with vim in the first pane

Create a detached session rooted in the worktree, then start vim in it:

```bash
tmux new-session -d -s "$SESSION" -c "<absolute-path>"
tmux send-keys -t "$SESSION" 'vim .' Enter
```

If a session with that name already exists, `new-session` errors — either reuse
it (skip creation) or pick a suffixed name.

### 2. Split a terminal pane below

```bash
tmux split-window -v -t "$SESSION" -c "<absolute-path>"
```

The new bottom pane is a plain shell already `cd`'d into the worktree. It becomes
the active pane after the split, so the user lands in the terminal.

### 3. Open any URL in the default browser

If the user provided a URL (a Jira ticket, PR, or docs page), open it in their
default browser instead of a managed pane:

```bash
open "<url>"          # macOS; use xdg-open on Linux
```

Skip this step when there's no URL to show.

### 4. Attach (the user does this)

The session is detached. Tell the user to attach when ready:

```bash
tmux attach -t "$SESSION"
```

Don't attach from inside the skill — Claude runs non-interactively and attaching
would block. Just leave the session set up and report its name.

## Tell the user

Confirm the session is ready with its name, the layout (vim + terminal), the
`tmux attach -t <name>` command, and the URL you opened (if any). Keep it brief.

## Common gotchas

Worktrees inherit *tracked* files only. Two things that often bite when reopening one:

- **Gitignored env files don't follow worktrees.** `.env`, `.dev.vars`, `.env.local`, etc. live only in the original checkout. If the user reports the dev server returning 500s like "X is required" or "config invalid", check the worktree root and copy any missing env files from the main checkout (found via `git worktree list`, whose first entry is the primary checkout):
  ```bash
  MAIN_CHECKOUT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
  ls -1a "$MAIN_CHECKOUT" | grep -E '^\.(env|dev\.vars)' || true
  # cp each match into the worktree
  ```
- **Empty `node_modules/`.** If `ls <worktree>/node_modules/ | head -1` is empty, the original `wt` post-create hook silently failed. Run the project's install command (`bun install`, `pnpm install`, etc.) before launching dev.

## Quick tip

To see all worktrees and their status at any time:
```bash
wt list
```

To quickly switch between worktrees:
```bash
wt switch <branch-name>
```

The interactive picker (`wt switch` with no args) shows all worktrees with live diff and log previews.
