#!/usr/bin/env bash
# content-lib.sh — pure, offline-testable primitives shared by the marketing-pages
# content pipelines (tron:toolkit-item, news-item, guide-item). Sourced, not run:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/content/content-lib.sh"
#
# These encode the deterministic backbone all three repeat by hand: the
# marketing-pages preflight guard, slug derivation, the facilitron.com→relative
# link rewrite (the #1 build-breaking step), internal-path validation against
# pages/, the next-free guide card index, and reading the consuming repo's
# content profile. The judgment — writing the copy, choosing components,
# trimming the PDF — stays in each skill.

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

# Echo the *.vue file that serves an internal route, or return 1.
# Resolves <path> against <repo>/app/pages (Nuxt 4 srcDir layout) or, if that
# directory doesn't exist, <repo>/pages (pre-migration layout) as foo.vue,
# foo/index.vue, or the nearest [...slug].vue catch-all — the same resolution
# Nuxt uses.
ct_resolve_page() {
  local p="$1" repo="${2:-$(pwd)}" base
  base="$repo/app/pages"; [[ -d "$base" ]] || base="$repo/pages"
  p="${p#/}"; p="${p%/}"
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

# --- repo content profile -----------------------------------------------------
# The consuming repo declares its own paths, collection schema, components, and
# CDN folders in `.tron/content-profile.json` (version 1). The plugin reads that
# file instead of hardcoding one repo's layout. This is descriptive only — the
# write guard is still ct_is_marketing_pages, which deliberately does NOT consult
# the profile (a file inside the repo cannot vouch for the repo).

CT_PROFILE_REL=".tron/content-profile.json"

# Echo the profile path for <repo> (default cwd), or return 1 if absent.
ct_profile_path() {
  local repo="${1:-$(pwd)}" root
  root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")"
  [[ -f "$root/$CT_PROFILE_REL" ]] || return 1
  printf '%s\n' "$root/$CT_PROFILE_REL"
}

# Echo the profile JSON for <repo>, or return 1 (caller reports what it needed).
# Rejects a profile whose `version` this plugin doesn't speak rather than
# silently reading fields that may have moved.
ct_profile_read() {
  local repo="${1:-$(pwd)}" path v
  path="$(ct_profile_path "$repo")" || return 1
  v="$(jq -r '.version // empty' "$path" 2>/dev/null)" || return 1
  [[ "$v" == "1" ]] || return 1
  cat "$path"
}

# Template expansion ({slug}/{name}/{NN}) lives in content.sh's profile_expand, which
# walks the whole JSON blob with jq rather than one string at a time.

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
