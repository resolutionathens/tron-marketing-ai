---
name: open-worktree
model: sonnet
effort: low
description: "Open a git worktree in a new cmux workspace with browser, vim, and terminal. Use this skill when the user says 'open worktree', 'open that worktree', 'set up workspace for <branch>', 'open workspace for <ticket>', or wants to start working in a worktree that already exists. Also trigger when the user says 'open it in cmux', 'set up cmux for that', or references a worktree path they want to work in."
allowed-tools:
  - Bash
  - Read
---

# Open Worktree

Open an existing git worktree in a new cmux workspace with a three-pane layout:

```
┌──────────┬──────────┐
│          │   vim    │
│ browser  ├──────────┤
│          │ terminal │
└──────────┴──────────┘
```

Browser on the left, vim top-right, terminal bottom-right.

## Fast path (scripted)

Resolve the worktree and fix the two footguns (missing gitignored env files, an
empty `node_modules`) in one deterministic call before touching cmux:

```bash
bash $CLAUDE_SKILL_DIR/scripts/open-worktree.sh --branch <name> [--no-switch]
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
cmux steps below. If `nodeModulesEmpty` is true, run the project's install before
launching dev. Smoke it with `bash $CLAUDE_SKILL_DIR/scripts/test-open-worktree.sh`.

The cmux three-pane composition below stays manual — surface layout is judgment,
not a fixed sequence (its sibling `start-ticket` keeps cmux setup in prose too).

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

## Set up the cmux workspace

Run these commands in sequence — each step depends on the previous one's output.

### 1. Create the workspace

```bash
cmux new-workspace
```

This returns a line like `OK <uuid>`. You don't need the UUID — use `cmux --json list-workspaces` to find the new workspace ref (it'll be the highest-numbered one).

### 2. Rename the workspace

Use the branch/ticket name so it's easy to identify:

```bash
cmux rename-workspace --workspace <ref> "<branch-name>"
```

### 3. Add the browser pane on the left first

The workspace starts with one terminal pane. Add the browser to its left before splitting the right side — this ensures the split only affects the right pane:

```bash
cmux --json new-pane --type browser --direction left --workspace <ref> [--url <url>]
```

If the user provided a URL (e.g., a Jira ticket, PR, or docs page), pass it with `--url` so the browser opens there directly.

### 4. Send cd + vim to the right pane (top)

The original terminal pane is now the right side. Send vim to it:

```bash
cmux send --workspace <ref> "cd <absolute-path> && vim ."
cmux send-key --workspace <ref> Enter
```

Note: the `send` command without `--surface` targets the focused surface, which is still the original terminal pane.

### 5. Split the right pane down for the terminal (bottom)

```bash
cmux --json new-split down --workspace <ref>
```

This returns JSON with the new `surface_ref`. Send cd to that surface so it's ready in the worktree directory:

```bash
cmux send --workspace <ref> --surface <new-surface-ref> "cd <absolute-path>"
cmux send-key --workspace <ref> --surface <new-surface-ref> Enter
```

### 6. Focus the terminal pane

Focus the bottom-right pane (the terminal) so the user lands there. Use the pane ref returned from step 5:

```bash
cmux focus-pane --pane <terminal-pane-ref> --workspace <ref>
```

## Tell the user

Confirm the workspace is ready with the workspace name and the layout. Keep it brief.

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
