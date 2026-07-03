#!/usr/bin/env bash
# Hermetic test for seo-audit.sh — parses local fixture HTML via --html-file,
# no network. Asserts the one-line JSON extraction (robots meta, canonical,
# title, meta description, H1s, img-alt coverage) and the 0/1/2 exit contract.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/seo-audit.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not found — seo-audit.sh requires it"; exit 0; }

fail=0
contains()    { if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok  : $1"; else echo "FAIL: $1 — missing '$2'"; fail=1; fi; }
not_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "FAIL: $1 — unexpectedly contains '$2'"; fail=1; else echo "ok  : $1"; fi; }
expect_exit() { if [ "$2" = "$3" ]; then echo "ok  : $1 (exit $3)"; else echo "FAIL: $1 (want exit $2, got $3)"; fail=1; fi; }

# ---------------------------------------------------------------------------
# Fixture: a realistic marketing page head + body
# ---------------------------------------------------------------------------
cat > "$TMP/page.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <title>  District Facility
    Rentals — Facilitron  </title>
  <meta name="description" content="Rent school facilities online with Facilitron.">
  <meta name="robots" content="noindex, follow">
  <link rel="canonical" href="https://www.facilitron.com/rentals">
</head>
<body>
  <h1>Rent <em>district</em> facilities</h1>
  <img src="/hero.png" alt="A school gym set up for an event">
  <img src="/spacer.gif" alt="">
  <img src="/logo.svg">
  <h2>Not an H1</h2>
</body>
</html>
EOF

set +e
json="$(bash "$SCRIPT" --html-file "$TMP/page.html" "https://example.com/rentals" 2>"$TMP/stderr.log")"; code=$?
set -e
expect_exit "fixture parse exits 0"            0 "$code"
[ "$(printf '%s\n' "$json" | wc -l)" -eq 1 ] && echo "ok  : stdout is one JSON line" || { echo "FAIL: stdout not a single line"; fail=1; }
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$json" && echo "ok  : stdout is valid JSON" || { echo "FAIL: invalid JSON"; fail=1; }

contains "url passed through"                  '"url":"https://example.com/rentals"' "$json"
contains "title extracted + whitespace-normalized" '"title":"District Facility Rentals — Facilitron"' "$json"
contains "title length computed"               '"title_length":38' "$json"
contains "meta description extracted"          '"meta_description":"Rent school facilities online with Facilitron."' "$json"
contains "meta description length"             '"meta_description_length":46' "$json"
contains "robots meta extracted"               '"robots_meta":"noindex, follow"' "$json"
contains "canonical extracted"                 '"canonical":"https://www.facilitron.com/rentals"' "$json"
contains "h1 text (nested tags flattened)"     '"h1s":["Rent district facilities"]' "$json"
contains "h1 count is 1 (h2 not counted)"      '"h1_count":1' "$json"
contains "img total counts all 3"              '"img_total":3' "$json"
contains "img alt: empty alt not counted"      '"img_with_alt":1' "$json"
contains "img alt coverage ratio"              '"img_alt_coverage":0.33' "$json"
contains "no fetch → status null"              '"status":null' "$json"
narration="$(cat "$TMP/stderr.log")"
contains "narration on stderr, not stdout"     "parsing local file" "$narration"
not_contains "stdout free of narration"        "parsing local file" "$json"

# ---------------------------------------------------------------------------
# Fixture: bare page — nothing to extract, still valid JSON with empty fields
# ---------------------------------------------------------------------------
printf '<html><body><p>hi</p></body></html>' > "$TMP/bare.html"
json2="$(bash "$SCRIPT" --html-file "$TMP/bare.html" 2>/dev/null)"
contains "bare page: title null"               '"title":null' "$json2"
contains "bare page: canonical null"           '"canonical":null' "$json2"
contains "bare page: robots null"              '"robots_meta":null' "$json2"
contains "bare page: h1_count 0"               '"h1_count":0' "$json2"
contains "bare page: alt coverage null (no imgs)" '"img_alt_coverage":null' "$json2"

# ---------------------------------------------------------------------------
# Exit contract
# ---------------------------------------------------------------------------
set +e
bash "$SCRIPT" >/dev/null 2>&1; code=$?
set -e
expect_exit "no args → usage (2)"              2 "$code"
set +e
bash "$SCRIPT" --html-file "$TMP/nope.html" >/dev/null 2>&1; code=$?
set -e
expect_exit "unreadable file → 1"              1 "$code"
set +e
bash "$SCRIPT" url1 url2 >/dev/null 2>&1; code=$?
set -e
expect_exit "two positional urls → usage (2)"  2 "$code"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
