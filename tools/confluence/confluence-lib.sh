#!/usr/bin/env bash
# confluence-lib.sh — pure, offline-testable Confluence primitives (Phase B).
# Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/confluence/confluence-lib.sh"
#
# Page-ID resolution is the one mechanic shared by tron:confluence, news-item,
# and guide-item, and it was hand-rolled three different ways. This encodes it
# once, entirely OFFLINE: a raw id, a full /pages/<id>/ URL, and a /wiki/x/
# tiny link all resolve with no network call. Anything else fails (rc 1) with
# no output, so a caller never receives a guessed id (MD-3082).

# Decode a /wiki/x/<identifier> tiny-link identifier to its numeric page id.
# The identifier is base64 of the page id's bytes, little-endian, unpadded, in
# Confluence's own alphabet: '-' stands for '/' and '_' for '+'. That is NOT
# base64url (which maps '-'→'+' and '_'→'/'); getting it backwards decodes
# K4A-AgE to the wrong page. Pure bash, so bash 3.2 and BSD/GNU alike.
#   cl_decode_tiny_id MYA5AgE → 4332290097 (rc 0)
#   cl_decode_tiny_id K4A-AgE → 4332683307 (rc 0)
#   cl_decode_tiny_id 'AB!C'  → (nothing)  (rc 1 = not a decodable identifier)
cl_decode_tiny_id() {
  local s="$1" alpha='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
  local i c v acc=0 bits=0 nbytes=0 id=0 pre
  # A page id fits in 7 bytes here (bash arithmetic is signed 64-bit), which is
  # at most 10 characters. 1 or 5 characters cannot encode whole bytes.
  [[ "$s" =~ ^[A-Za-z0-9_-]{2,10}$ ]] || return 1
  (( ${#s} % 4 == 1 )) && return 1
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    pre="${alpha%%"$c"*}"; v=${#pre}     # index of c in the alphabet
    acc=$(( (acc << 6) | v )); bits=$(( bits + 6 ))
    if (( bits >= 8 )); then
      bits=$(( bits - 8 ))
      id=$(( id | (((acc >> bits) & 255) << (8 * nbytes)) ))
      nbytes=$(( nbytes + 1 ))
      acc=$(( acc & ((1 << bits) - 1) ))
    fi
  done
  (( acc == 0 )) || return 1               # non-zero padding bits: not a canonical encoding
  (( nbytes <= 7 && id > 0 )) || return 1
  printf '%s\n' "$id"
}

# Extract a numeric page id from a raw id, a full page URL, or a tiny link — offline.
#   cl_extract_page_id 3851517965                                  → 3851517965  (rc 0)
#   cl_extract_page_id https://….net/wiki/spaces/X/pages/123/Title → 123         (rc 0)
#   cl_extract_page_id https://….net/wiki/x/DYCR5Q                 → 3851517965  (rc 0, decoded offline)
#   cl_extract_page_id https://….net/wiki/x/AB!C                   → (nothing)   (rc 1 = undecodable tiny link)
#   cl_extract_page_id "not a page"                                → (nothing)   (rc 1 = unparseable)
# There is no "needs network" code: an input this cannot resolve offline is an
# error, never a redirect to scrape a digit from.
cl_extract_page_id() {
  local in="$1"
  in="${in%%\?*}"; in="${in%%#*}"          # strip ?query and #fragment
  if [[ "$in" =~ ^[0-9]+$ ]]; then printf '%s\n' "$in"; return 0; fi
  if [[ "$in" =~ /pages/([0-9]+) ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; return 0; fi
  if [[ "$in" =~ /wiki/x/([^/]*)/?$ ]]; then cl_decode_tiny_id "${BASH_REMATCH[1]}"; return; fi
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
