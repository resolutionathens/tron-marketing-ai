#!/usr/bin/env bash
# Direct unit test for confluence-lib.sh's pure functions. Fully offline — the
# lib is sourced, not executed. Pins the two contracts the rest of the toolchain
# leans on:
#   • cl_extract_page_id's return-code map: 0 = resolved id (raw or /pages/<id>/),
#     2 = a URL we CAN'T read offline (tiny link → caller must follow a redirect),
#     1 = unparseable garbage. The rc=2 tiny-link contract is load-bearing:
#     fetch-confluence.sh keys its "curl -sIL redirect" branch off exactly rc≠0.
#   • cl_referenced_images: doc-order, de-duplicated <ri:attachment> filenames.
#
#   bash tools/confluence/test-confluence-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/confluence-lib.sh"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

echo "confluence-lib unit test"

# shellcheck source=/dev/null
source "$LIB"

# id + rc helper: runs the fn, captures both stdout and rc
idrc() { local out rc=0; out="$(cl_extract_page_id "$1")" || rc=$?; printf '%s|%s' "$out" "$rc"; }

# --- rc 0: raw numeric id passes through -------------------------------------
[[ "$(idrc 3851517965)" == '3851517965|0' ]] || fail "raw id: $(idrc 3851517965)"
[[ "$(idrc 42)" == '42|0' ]] || fail "short raw id: $(idrc 42)"
pass "raw numeric id → same id, rc 0"

# --- rc 0: full /pages/<id>/ URL, offline ------------------------------------
[[ "$(idrc 'https://facilitron.atlassian.net/wiki/spaces/K/pages/123/Some+Title')" == '123|0' ]] \
  || fail "full URL: $(idrc 'https://facilitron.atlassian.net/wiki/spaces/K/pages/123/Some+Title')"
# ?query and #fragment are stripped before matching
[[ "$(idrc 'https://x.atlassian.net/wiki/spaces/X/pages/777/T?focusedCommentId=9#c9')" == '777|0' ]] \
  || fail "query/fragment strip: $(idrc 'https://x.atlassian.net/wiki/spaces/X/pages/777/T?focusedCommentId=9#c9')"
# /pages/<id> with no trailing title/slash still resolves (first numeric group)
[[ "$(idrc 'https://x.atlassian.net/wiki/spaces/X/pages/999')" == '999|0' ]] \
  || fail "pages id no-title: $(idrc 'https://x.atlassian.net/wiki/spaces/X/pages/999')"
pass "full /pages/<id>/ URL → extracted id, rc 0 (query/fragment stripped)"

# --- rc 2: tiny link (a URL we can't parse offline → needs a redirect) --------
for tiny in \
  'https://facilitron.atlassian.net/wiki/x/DYCR5Q' \
  'http://facilitron.atlassian.net/wiki/x/AbC123' \
  'https://facilitron.atlassian.net/l/cp/abcd1234'; do
  out="$(idrc "$tiny")"
  [[ "$out" == '|2' ]] || fail "tiny link should be empty|rc2 (got $out for $tiny)"
done
pass "tiny/short link → empty output, rc 2 (needs network redirect)"

# --- rc 1: unparseable non-URL garbage ---------------------------------------
for junk in 'just some text' 'MD-1234' '' 'not/a/url'; do
  out="$(idrc "$junk")"
  [[ "$out" == '|1' ]] || fail "garbage should be empty|rc1 (got $out for '$junk')"
done
pass "non-URL garbage → empty output, rc 1 (unparseable)"

# --- cl_referenced_images: doc-order, de-duplicated --------------------------
BODY='<p><ac:image><ri:attachment ri:filename="hero.png" /></ac:image></p>
<p><ac:image><ri:attachment ri:filename="diagram.svg" /></ac:image></p>
<p>reuse <ac:image><ri:attachment ri:filename="hero.png" /></ac:image></p>
<p><ac:image><ri:attachment ri:filename="chart-3.png" ri:version-at-save="2" /></ac:image></p>'
OUT="$(cl_referenced_images <<<"$BODY")"
EXPECT=$'hero.png\ndiagram.svg\nchart-3.png'
[[ "$OUT" == "$EXPECT" ]] || fail "referenced-images order/dedup wrong: got [$OUT]"
pass "cl_referenced_images → doc-order, de-duplicated, extra attrs ignored"

# attachment-free body → empty output (grep's no-match rc is an internal detail;
# what callers rely on is the empty list, which is what the images subcommand emits)
OUT="$(printf '<p>no images here</p>' | cl_referenced_images || true)"
[[ -z "$OUT" ]] || fail "no-attachment body should yield empty (got: $OUT)"
pass "cl_referenced_images on attachment-free body → empty list"

echo ""
echo "✅ confluence-lib unit test PASSED ($PASS checks)"
