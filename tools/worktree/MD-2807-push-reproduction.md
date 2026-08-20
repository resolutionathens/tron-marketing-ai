# MD-2807 push-snippet reproduction

This reproduction was run before changing either push snippet.

From the linked worktree `/tmp/md-2807-worktree-repro.3DI78R/feature-two`, with the
primary checkout plus `feature-one` and `feature-two` worktrees present, I ran the
then-current snippet:

```bash
cd /tmp/md-2807-worktree-repro.3DI78R/feature-two
MAIN_WD="$(git rev-parse --git-dir | xargs dirname)"
WORKTREE="$(git worktree list --porcelain | grep -v "^bare:" | awk '{print $1}' | grep -v "^$MAIN_WD\\$" | head -1)" || WORKTREE="$MAIN_WD"
printf 'cwd=%s\\ngit_dir=%s\\nMAIN_WD=%s\\nWORKTREE=%s\\n' "$PWD" "$(git rev-parse --git-dir)" "$MAIN_WD" "$WORKTREE"
git -C "$WORKTREE" rev-parse --abbrev-ref HEAD
```

Observed output:

```text
cwd=/tmp/md-2807-worktree-repro.3DI78R/feature-two
git_dir=/private/tmp/md-2807-worktree-repro.3DI78R/main/.git/worktrees/feature-two
MAIN_WD=/private/tmp/md-2807-worktree-repro.3DI78R/main/.git/worktrees
WORKTREE=worktree
fatal: cannot change to 'worktree': No such file or directory
```

The porcelain parser selected the literal first field, `worktree`, rather than the
path that follows it.
