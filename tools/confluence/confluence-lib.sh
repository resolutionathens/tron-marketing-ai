#!/usr/bin/env bash
# confluence-lib.sh — pure, offline-testable Confluence primitives (Phase B).
# Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/confluence/confluence-lib.sh"
#
# Page-ID resolution is the one mechanic shared by tron:confluence, news-item,
# and guide-item, and it was hand-rolled three different ways. This encodes it
# once: a full /pages/<id>/ URL or a raw id resolves OFFLINE (no network); only
# a /wiki/x/ tiny link needs a redirect follow, which the caller does.

# Extract a numeric page id from a raw id or a full page URL — offline.
#   cl_extract_page_id 3851517965                                  → 3851517965  (rc 0)
#   cl_extract_page_id https://….net/wiki/spaces/X/pages/123/Title → 123         (rc 0)
#   cl_extract_page_id https://….net/wiki/x/DYCR5Q                 → (nothing)   (rc 2 = needs network)
#   cl_extract_page_id "not a page"                                → (nothing)   (rc 1 = unparseable)
cl_extract_page_id() {
  local in="$1"
  in="${in%%\?*}"; in="${in%%#*}"          # strip ?query and #fragment
  if [[ "$in" =~ ^[0-9]+$ ]]; then printf '%s\n' "$in"; return 0; fi
  if [[ "$in" =~ /pages/([0-9]+) ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; return 0; fi
  [[ "$in" =~ ^https?:// ]] && return 2     # a URL we can't read offline → tiny link, needs a redirect follow
  return 1
}

# List the attachment filenames a storage-format body references, in document
# order, de-duplicated. Pure regex over the XML — the same set fetch-confluence.sh
# downloads. Reads the body on stdin, prints one filename per line.
cl_referenced_images() {
  grep -oE '<ri:attachment ri:filename="[^"]+"' \
    | sed -E 's/.*ri:filename="([^"]+)".*/\1/' \
    | awk '!seen[$0]++'
}
