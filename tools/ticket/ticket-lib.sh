#!/usr/bin/env bash
# ticket-lib.sh — pure, offline-testable primitives for tron:start-ticket
# (Phase B). Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/ticket/ticket-lib.sh"
#
# These encode the two mechanics that are easy to get subtly wrong by hand:
# (1) detecting Jira-vs-GitHub from the many ref shapes, and (2) carrying the
# gitignored env/secret files into a fresh worktree (skip it and the dev server
# 500s on every request). The interactive judgment — reading the ticket, the
# branch slug wording, the tmux/worker/dev-server offers — stays in the skill.

# Classify a ticket ref. Echoes a single line:
#   jira <KEY>                e.g. "jira MD-1234"
#   gh <N> <owner/repo>       explicit repo (from owner/repo#N or a GH URL)
#   gh <N>                    current-repo issue (from #N) — caller resolves slug
#   ambiguous                 a bare number with no '#': can't tell Jira from GH
# Returns 0 on a confident classification, 1 on ambiguous/unparseable.
tl_detect_ref() {
  local ref="$1"
  # Jira URL: …/browse/<KEY>
  if [[ "$ref" =~ /browse/([A-Z][A-Z0-9]+-[0-9]+) ]]; then
    echo "jira ${BASH_REMATCH[1]}"; return 0
  fi
  # GitHub issue URL: github.com/<owner>/<repo>/issues/<N>
  if [[ "$ref" =~ github\.com/([^/]+/[^/]+)/issues/([0-9]+) ]]; then
    echo "gh ${BASH_REMATCH[2]} ${BASH_REMATCH[1]}"; return 0
  fi
  # owner/repo#N
  if [[ "$ref" =~ ^([^/[:space:]]+/[^#[:space:]]+)#([0-9]+)$ ]]; then
    echo "gh ${BASH_REMATCH[2]} ${BASH_REMATCH[1]}"; return 0
  fi
  # Bare Jira key: PROJ-1234
  if [[ "$ref" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
    echo "jira $ref"; return 0
  fi
  # #N (current repo)
  if [[ "$ref" =~ ^#([0-9]+)$ ]]; then
    echo "gh ${BASH_REMATCH[1]}"; return 0
  fi
  # A bare number could be either — caller must disambiguate.
  echo "ambiguous"; return 1
}

# Slugify free text into a branch-safe slug: lowercase, non-alnum → hyphen,
# collapse repeats, trim to ~50 chars on a word boundary, strip edge hyphens.
tl_slugify() {
  local s
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//')"
  if [[ ${#s} -gt 50 ]]; then
    s="${s:0:50}"; s="${s%-*}"   # don't cut mid-word
  fi
  printf '%s\n' "$s"
}

# Build the conventional branch name for a classified ref.
#   tl_branch_name jira MD-1234 "Add BAS logo" → MD-1234-add-bas-logo
#   tl_branch_name gh   42      "Improve UX"    → issue-42-improve-ux
# The `issue-` prefix keeps GH branches from looking like a Jira key downstream.
tl_branch_name() {
  local type="$1" id="$2" slug; slug="$(tl_slugify "$3")"
  case "$type" in
    jira) printf '%s-%s\n' "$id" "$slug" ;;
    gh)   printf 'issue-%s-%s\n' "$id" "$slug" ;;
    *) return 1 ;;
  esac
}

# Copy gitignored env/secret files from a source checkout into a worktree root.
# `wt switch -c` does NOT carry these (they're gitignored), and without them the
# dev server boots but every request 500s ("X is required"). Copies the
# conventional secret-file set that EXISTS in <src> and is NOT already in <dst>.
# Echoes each copied filename (one per line). Filesystem-only — no git/network.
tl_copy_env_files() {
  local src="$1" dst="$2" name
  [[ -d "$src" && -d "$dst" ]] || return 0
  shopt -s nullglob dotglob
  local candidates=("$src"/.env "$src"/.env.* "$src"/.dev.vars "$src"/.dev.vars.*)
  for f in "${candidates[@]}"; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    [[ -e "$dst/$name" ]] && continue   # don't clobber an existing file
    if cp "$f" "$dst/$name" 2>/dev/null; then printf '%s\n' "$name"; fi
  done
  shopt -u nullglob dotglob
}

# Symlink EVERY node_modules the source checkout has (root + nested workspaces)
# into a fresh worktree at the same relative path. Fresh ticket worktrees can't
# install private packages (@facilitron/* 404 on the public registry), so deps
# must be linked from the main checkout — and a root-only link strands nested
# workspaces (e.g. control-plane/web/node_modules), flooding the worker with LSP
# errors and test failures. Scans for node_modules up to 3 levels deep, skipping
# any nested inside another node_modules. Best-effort: a link failure is skipped,
# never fatal. Echoes each linked relative path (one per line). Mirrors tron-os
# lib/worktree.ts (nodeModuleRelPaths + linkNodeModules, bounded depth 3).
tl_link_node_modules() {
  local src="$1" dst="$2" nm rel target
  [[ -d "$src" && -d "$dst" ]] || return 0
  while IFS= read -r nm; do
    [[ -z "$nm" ]] && continue
    rel="${nm#"$src"/}"
    target="$dst/$rel"
    [[ -e "$target" || -L "$target" ]] && continue   # don't clobber existing deps
    mkdir -p "$(dirname "$target")" 2>/dev/null || continue
    if ln -s "$nm" "$target" 2>/dev/null; then printf '%s\n' "$rel"; fi
    # -prune stops find from descending INTO each node_modules it matches, so we
    # never walk a huge dependency tree (and never reach a nested node_modules).
  done < <(find "$src" -maxdepth 3 -type d -name node_modules -prune -print 2>/dev/null)
}
