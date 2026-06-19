#!/usr/bin/env bash
# content-lib.sh — pure, offline-testable primitives shared by the marketing-pages
# content pipelines (tron:toolkit-item, news-item, guide-item). Sourced, not run:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/content/content-lib.sh"
#
# These encode the deterministic backbone all three repeat by hand: the
# marketing-pages preflight guard, slug derivation, the facilitron.com→relative
# link rewrite (the #1 build-breaking step), internal-path validation against
# pages/, and the next-free guide card index. The judgment — writing the copy,
# choosing components, trimming the PDF — stays in each skill.

# True (rc 0) if <repo> (default cwd) is a marketing-pages checkout. Worktrees
# match too — they share the origin remote.
ct_is_marketing_pages() {
  local repo="${1:-$(pwd)}" url
  url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  [[ "$url" == *marketing-pages* ]]
}

# Slugify a title into a content slug: lowercase, non-alnum → hyphen, collapse
# repeats, trim edge hyphens. No length cap (content slugs are long & full-text).
#   ct_slug "How to Prepare a Preventive Maintenance Plan"
#     → how-to-prepare-a-preventive-maintenance-plan
ct_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//'
}

# Rewrite absolute facilitron.com URLs to site-relative paths on stdin→stdout.
# Only the marketing domain is touched — external URLs (and the bare homepage
# with no path) pass through unchanged.
#   [Works](https://www.facilitron.com/product/works) → [Works](/product/works)
ct_rewrite_links() {
  sed -E 's#https?://(www\.)?facilitron\.com(/[A-Za-z0-9._~%/?#=&+-]*)#\2#g'
}

# Echo the pages/*.vue file that serves an internal route, or return 1.
# Resolves <path> against <repo>/pages as foo.vue, foo/index.vue, or the nearest
# [...slug].vue catch-all — the same resolution Nuxt uses.
ct_resolve_page() {
  local p="$1" repo="${2:-$(pwd)}" base
  base="$repo/pages"; p="${p#/}"; p="${p%/}"
  [[ -f "$base/$p.vue" ]] && { printf '%s\n' "$base/$p.vue"; return 0; }
  [[ -f "$base/$p/index.vue" ]] && { printf '%s\n' "$base/$p/index.vue"; return 0; }
  local probe="$p"
  while :; do
    [[ -f "$base/$probe/[...slug].vue" ]] && { printf '%s\n' "$base/$probe/[...slug].vue"; return 0; }
    [[ "$probe" == */* ]] || break
    probe="${probe%/*}"
  done
  [[ -f "$base/[...slug].vue" ]] && { printf '%s\n' "$base/[...slug].vue"; return 0; }
  return 1
}

# Given existing filenames on stdin, echo the next free zero-padded 2-digit index
# for <prefix>[-]NN<suffix>. Used for guide cards (guide-04.webp → 05).
ct_next_index() {
  local prefix="$1" suffix="$2" max=0 n line
  local suf_re="${suffix//./\\.}"
  while IFS= read -r line; do
    if [[ "$line" =~ ${prefix}-?0*([0-9]+)${suf_re} ]]; then
      n="${BASH_REMATCH[1]}"; (( n > max )) && max=$n
    fi
  done
  printf '%02d' $((max + 1))
}
