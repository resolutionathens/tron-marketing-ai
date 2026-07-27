---
name: open-worktree
model: sonnet
effort: low
description: "Open a git worktree in a new tmux session with vim and a terminal, opening any associated URL in your default browser. Use for 'open worktree', 'set up workspace for <branch>', 'open workspace for <ticket>', or 'open it in tmux' for a worktree that already exists. IMPORTANT: Not suitable for dispatched/headless workers — requires an interactive tmux+vim session and the macOS open command."
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
---

# Open Worktree

Open an existing git worktree in a new tmux session (vim top, terminal bottom), plus any URL in the default browser.

## Important: Not for dispatched workers

This skill **requires interactive terminal access** — it launches tmux+vim and uses `open` (macOS) to open URLs. It is **not compatible with dispatched/headless workers** and should only be invoked interactively by a user at a terminal.

## Fast path — resolve, fix env files, check node_modules

```bash
name=open-worktree
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/open-worktree.sh)"
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