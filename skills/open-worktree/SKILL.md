---
name: open-worktree
model: sonnet
effort: low
description: "Open a git worktree in a new tmux session with vim and a terminal, opening any associated URL in your default browser. Use this skill when the user says 'open worktree', 'open that worktree', 'set up workspace for <branch>', 'open workspace for <ticket>', or wants to start working in a worktree that already exists. Also trigger when the user says 'open it in tmux', 'set up a session for that', or references a worktree path they want to work in. IMPORTANT: Not suitable for dispatched/headless workers — requires interactive tmux+vim session and macOS open command."
allowed-tools:
  - Bash
  - Read
scout:
  surface: developer
  title: "Open worktree in tmux+vim"
  blurb: "Launches an existing worktree in a new tmux session with vim editor and terminal."
  when: "You want to start interactive development in an existing worktree you created earlier."
  category: tickets
  effects: []
  note: "Not for dispatched/headless workers — requires tmux, vim, and macOS open command. Use interactively only."
---

# Open Worktree

Open an existing git worktree in a new tmux session (vim top, terminal bottom), plus any URL in the default browser.

## Important: Not for dispatched workers

This skill **requires interactive terminal access** — it launches tmux+vim and uses `open` (macOS) to open URLs. It is **not compatible with dispatched/headless workers** and should only be invoked interactively by a user at a terminal.

## Fast path — resolve, fix env files, check node_modules

```bash
name=open-worktree
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/open-worktree.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/open-worktree.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/open-worktree.sh" ] || { echo "tron:$name: scripts/open-worktree.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/open-worktree.sh" --branch <name> [--no-switch]
```

Runs `wt switch <branch> --yes` (unless `--no-switch`), copies gitignored `.env*`/`.dev.vars*` from the primary checkout, reports whether `node_modules` is empty.

```json
{"ok":true,"branch":"MD-1801-x","worktreePath":"/…","mainCheckout":"/…","envCopied":[".env.local"],"nodeModulesEmpty":false}
{"ok":false,"branch":"x","error":"worktree-not-found","hint":"create it with tron:start-ticket, or check `wt list`"}
```

If `nodeModulesEmpty` is true, run the project's install before launching dev.

## Set up the tmux session

The session name is the branch sanitized for tmux — the canonical rule is
`wl_session_name_for_branch` in `tools/worktree/worktree-lib.sh` (`.` and `:` are
illegal in tmux session names and map to `-`); close-worktree matches sessions by
the same rule:

```bash
source "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/worktree/worktree-lib.sh"
SESSION="$(wl_session_name_for_branch '<branch-name>')"
tmux new-session -d -s "$SESSION" -c "<worktreePath>"
tmux send-keys -t "$SESSION" 'vim .' Enter
tmux split-window -v -t "$SESSION" -c "<worktreePath>"
```

If a session already exists with that name, reuse it (skip creation).

Open any Jira/PR/docs URL in the default browser:

```bash
open "<url>"    # macOS
```

Then tell the user: `tmux attach -t "$SESSION"` to enter the session.

## Common gotchas

- **Gitignored env files don't follow worktrees** — the script handles this. If running manually, `cp .env*` from the main checkout (first entry in `git worktree list`).
- **Empty `node_modules/`** — the script reports it. If `ls <worktree>/node_modules/ | head -1` is empty, run the project's install command before launching dev.
- **Shell resets to main checkout** in some worktree-integrated environments — make sure you `cd` to the worktree's absolute path.