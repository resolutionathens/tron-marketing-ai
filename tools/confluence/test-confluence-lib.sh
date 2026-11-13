#!/usr/bin/env bash
# Direct unit test for confluence-lib.sh's pure functions. Fully offline — the
# lib is sourced, not executed. Pins the two contracts the rest of the toolchain
# leans on:
#   • cl_extract_page_id's return-code map: 0 = resolved id (raw, /pages/<id>/,
#     or a /wiki/x/ tiny link decoded offline), 1 = anything else, with NO
#     output. There is no "needs network" code any more (MD-3082): a redirect
#     scrape returned a digit from the identifier itself (MYA5AgE → 5), so an
#     unresolvable input must fail rather than hand back a guessed id.
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

# --- rc 0: /wiki/x/ tiny link decoded offline (MD-3082) ----------------------
# Known-good fixtures, confirmed against the live pages (CCAL-2228/CCAL-2229).
# MYA5AgE decodes the same under either alphabet; K4A-AgE carries a '-', so it
# is the fixture that pins Confluence's mapping ('-'→'/', '_'→'+') over
# base64url's ('-'→'+', '_'→'/'). The redirect scrape returned 5 and 4.
# Run with curl off PATH so any network attempt would fail the case.
offline() { PATH=/nonexistent idrc "$1"; }
for case in \
  'https://facilitron.atlassian.net/wiki/x/MYA5AgE|4332290097' \
  'https://facilitron.atlassian.net/wiki/x/K4A-AgE|4332683307' \
  'https://facilitron.atlassian.net/wiki/x/DYCR5Q|3851517965' \
  'http://facilitron.atlassian.net/wiki/x/K4A-AgE/|4332683307' \
  'https://facilitron.atlassian.net/wiki/x/MYA5AgE?atlOrigin=abc#top|4332290097'; do
  url="${case%|*}"; want="${case##*|}"
  out="$(offline "$url")"
  [[ "$out" == "$want|0" ]] || fail "tiny link should decode to $want|0 (got $out for $url)"
done
pass "tiny link → page id decoded offline, rc 0 (incl. the '-' alphabet fixture)"

# cl_decode_tiny_id directly: the '_' half of the alphabet, and base64url's
# mapping must NOT be what is used (K4A+AgE is the base64url reading of K4A-AgE).
[[ "$(cl_decode_tiny_id 'AB_-')" == 12525312 ]] || fail "'_'→'+' / '-'→'/' mapping wrong: $(cl_decode_tiny_id 'AB_-' || true)"
[[ "$(cl_decode_tiny_id K4A-AgE)" != 4332617771 ]] || fail "K4A-AgE decoded with the base64url mapping"
pass "cl_decode_tiny_id uses Confluence's alphabet ('-'→'/', '_'→'+'), not base64url"

# --- rc 1: undecodable tiny link → no id, never a scraped digit --------------
for bad in \
  'https://facilitron.atlassian.net/wiki/x/' \
  'https://facilitron.atlassian.net/wiki/x/AB!C5' \
  'https://facilitron.atlassian.net/wiki/x/ABCDE' \
  'https://facilitron.atlassian.net/wiki/x/MYA5AgF' \
  'https://facilitron.atlassian.net/wiki/x/AAAA' \
  'https://facilitron.atlassian.net/wiki/x/ABCDEFGHIJKLMNOP' \
  'https://facilitron.atlassian.net/l/cp/abcd1234' \
  'https://example.com/some/other/page5'; do
  out="$(offline "$bad")"
  [[ "$out" == '|1' ]] || fail "undecodable link should be empty|rc1 (got $out for $bad)"
done
pass "undecodable tiny link / unknown URL → empty output, rc 1 (no guessed id)"

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
