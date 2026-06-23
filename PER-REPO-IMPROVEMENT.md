# Per-repo improvements (tron-marketing-ai plugin)

Plugin-side improvements surfaced while making the OS (`tron-os`) per-repo-convention aware.
Each repo the OS drives has its own branch + promotion conventions; the OS now classifies
them by data (see "Convention matrix" below), but a few rough edges live in the **plugin's
git/worktree skills**, not the OS, so they're recorded here for a future ticket.

> Scope note: items the OS could fix itself were fixed in `tron-os` (cross-referenced below),
> NOT recorded here. This file is only for changes that belong in the **plugin**.

_Last updated: 2026-06-23 (from the self-maintenance reviewer's "4 rules + 5 fixes" plan)._

> **Status (2026-06-23): all four plugin improvements below are SHIPPED.** Items 1–4 are
> implemented in `git-dev.sh` / `git-promote.sh` / `ticket-lib.sh` / `start-ticket.sh` and
> covered by the smoke tests (`test-git-dev.sh`, `test-start-ticket.sh`). Plugin version bumped
> to 0.14.0. The "Open question" at the bottom remains deferred by the owner.

---

## Convention matrix (the source of the per-repo differences)

| Repo | Default branch | Promotion model | Lifecycle the worker should run | Pkg mgr / deploy |
|---|---|---|---|---|
| `tron-os` | `main` | **direct** (ship via `v*` tag) | commit → PR → merge. NO git-dev / preview-url / pushtoprod. | bun · Tauri/R2 updater |
| `tron-marketing-ai` | `master` | **direct** (+ version bump) | commit → PR → merge. NO git-dev / preview-url / pushtoprod. Bump `.claude-plugin/plugin.json`. | bun · marketplace |
| `marketing-pages` | `master` | **full** master→staging→production | commit → git-dev → preview-url → PR → (approve) → pushtoprod | npm (+ stray `bun.lock`) · CircleCI→S3/CloudFront |
| `marketing-dynamic-landing-pages` | `master` | **full** master→staging→production | same as marketing-pages | CircleCI→S3/CloudFront |
| `facilitron-ui` | `master` | **dev-only** (published npm lib; release downstream) | commit → git-dev (land on `dev`) → PR → (approve) → merge. NO pushtoprod — packaging/release (master + `npm publish`) is done downstream by a human. | npm · `@facilitron/facilitron-ui` |

This is encoded in `tron-os` as two derived predicates over `promotionBranches`:
`usesPromotionFlow` (is there a dev gate? → git-dev/preview-url) and `promotesToProd`
(is there a `production` env? → git-pushtoprod).

### Already fixed in `tron-os` (do NOT duplicate in the plugin)

- **Dispatch lifecycle branches on the repo's promotion model.** The worker kickoff
  (`orchestrator/dispatch.ts`) and the approve-PR relay (`control-plane/api/server.ts`) no
  longer hard-code the marketing-pages CI lifecycle. They skip git-dev / preview-url for
  direct repos and git-pushtoprod for direct + dev-only repos. _(This is the image's
  "Dispatch lifecycle: branch on repo role" item — its real files were in tron-os.)_
- **`facilitron-ui` promotion model** set to `promotionBranches: ["dev"]` in the OS registry,
  so its dispatches complete (they no longer wait forever on a non-existent `production`
  branch) and never attempt git-pushtoprod.
- **Ticketless worktree node_modules** — `tron-os`'s own ticketless bootstrap
  (`lib/worktree.ts`) now symlinks the main checkout's `node_modules` (root **and** nested
  workspaces like `control-plane/web/node_modules`) into a fresh worktree. The plugin's
  ticketed `tron:start-ticket` path still needs the equivalent — see item 2 below.
- **`tron-os` `.gitignore`** now ignores a *symlinked* `node_modules` (the pattern lost its
  trailing slash). The plugin repos don't symlink into themselves, so no change needed there.

---

## Plugin improvements to make

### 1. ✅ `tron:git-dev` (and the promote path): accept an explicit `--worktree <abs-path>`; derive branch + dirty-check from it, not `pwd`

**Where:** `skills/git-dev/scripts/git-dev.sh` (and, by extension, `tools/git/git-promote.sh`).

**Problem.** `git-dev.sh` derives BOTH the feature branch and the clean/dirty check from the
current directory:

```sh
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"   # line 28 — from pwd's git
…
if [[ -n "$(gp_dirty "$(pwd)")" ]]; then emit_err "dirty-working-tree"; fi   # line 34 — pwd
```

Under the worktree-integrated shell, `pwd` is reset to the **main checkout** after every
Bash call. So from a wt shell the script reads the main checkout's branch (often `master` →
`on-protected-branch`) or the main checkout's stray files (→ `dirty-working-tree`), even when
the actual worktree is on a clean feature branch. The script is effectively unusable from a
wt-integrated shell whenever the main checkout is dirty.

**Fix.** Add a `--worktree <abs-path>` flag (falling back to `pwd` when absent) and run all
worktree-scoped git through `git -C "$WORKTREE"` — branch detection (`git -C "$WT" branch
--show-current`) and the dirty check (`gp_dirty "$WT"`). The merge target side already
resolves the main checkout via `--git-common-dir`, so only the *source/worktree* side needs
this. `git-commit` / `git-pr` are SKILL.md-only (no bundled script) but their instructions
should likewise prefer `git -C <worktree>` and never assume `pwd` persists between Bash calls.
(`tron-os` can then pass the worktree path it already knows deterministically.)

### 2. ✅ `tron:start-ticket` worktree hook: symlink nested `node_modules`, not just the root

**Where:** `skills/start-ticket/scripts/start-ticket.sh` (the post-`worktree add` step) — and
whatever `wt`/hook it relies on for dependency linking.

**Problem.** Fresh ticket worktrees can't install private packages (`@facilitron/*` 404 on the
public registry), so deps must be symlinked from the main checkout. The current path only
handles (or skips) the **root** `node_modules`. Repos with nested workspaces — e.g.
`control-plane/web/node_modules` in tron-os, or any monorepo-ish layout — are left without
their nested deps, which floods the worker with LSP errors and test failures.

**Fix.** After `git worktree add`, symlink **every** `node_modules` the main checkout has
(root + nested), at the same relative path in the worktree. Drive it by scanning for
`package.json` one or two levels deep (skip dotdirs; never descend into `node_modules`), or by
a per-repo config list. Best-effort + non-fatal (a link failure must not strand setup).
Reference implementation already shipped on the OS side: `tron-os` `lib/worktree.ts`
(`nodeModuleRelPaths` + `linkNodeModules`, bounded depth 3) — mirror its behavior here for the
ticketed path.

### 3. ✅ `git-promote.sh`: also auto-resolve `bun.lock` conflicts (not only `package*.json`)

**Where:** `tools/git/git-promote.sh` (the conflict-classification loop, ~lines 54–69).

**Problem.** The promote script treats only `package.json` / `package-lock.json` as
dependency files owned by the long-lived branch (→ `--ours`); **any other** conflict aborts
the merge. `marketing-pages` now carries a `bun.lock` **alongside** `package-lock.json`, so a
promotion that touches deps can conflict on `bun.lock` and abort — even though it's the same
"long-lived branch owns its lockfile" rule.

**Fix.** Add `bun.lock` (and `bun.lockb`) to the set that resolves to `--ours`:

```sh
case "$f" in
  package.json|package-lock.json|bun.lock|bun.lockb) resolved+="…" ;;
  *) other+="…" ;;
esac
```

…and include them in the `checkout --ours` / `add` lines. Keep it list-driven so a repo that
uses yarn/pnpm can extend it later.

### 4. ✅ (Minor) Friendlier message when git-dev is run on a no-dev-branch repo

**Where:** `skills/git-dev/scripts/git-dev.sh` (`gp_merge_into` → `error:checkout-dev`).

The OS now never *calls* git-dev for direct or release-only repos, so this is no longer a hot
path. But if a human runs `tron:git-dev` by hand in `tron-os` / `tron-marketing-ai` (no `dev`
branch), `gp_merge_into` fails with the opaque `error:checkout-dev`. A one-line guard ("this
repo has no `dev` branch — it ships straight to its default branch; use tron:git-pr") would
save confusion. Low priority.

---

## Open question (deferred by the owner)

- **`facilitron-ui` release automation.** For now its lifecycle finishes at `dev`; packaging +
  the versioned `npm publish` (from `master`) is handled downstream by a human. If/when that
  release is automated, revisit `promotionBranches` (and whether a `tron:publish-lib` skill is
  warranted) so the OS can own it end-to-end. _(Owner decision, 2026-06-23: "just dev, no
  promoting, investigate later.")_
