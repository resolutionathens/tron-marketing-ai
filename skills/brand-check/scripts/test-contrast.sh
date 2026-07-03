#!/usr/bin/env bash
# Hermetic test for contrast.sh — known WCAG ratios, hex-format handling, and
# argument validation. No network, no deps beyond bash + awk.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/contrast.sh"

fail=0
contains()    { if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok  : $1"; else echo "FAIL: $1 — missing '$2'"; fail=1; fi; }
expect_exit() { if [ "$2" = "$3" ]; then echo "ok  : $1 (exit $3)"; else echo "FAIL: $1 (want exit $2, got $3)"; fail=1; fi; }

run() { set +e; out="$(bash "$SCRIPT" "$@" 2>&1)"; code=$?; set -e; }

# Black on white — the canonical maximum, exactly 21:1
run '#000000' '#ffffff'
expect_exit "black/white exits 0"            0 "$code"
contains    "black/white ratio is 21.00"     "21.00:1" "$out"
contains    "black/white passes 4.5:1"       "AA normal text (4.5:1): PASS" "$out"
contains    "black/white passes 3:1"         "AA large text / UI (3:1): PASS" "$out"

# Order-independent (lighter/darker swapped)
run '#ffffff' '#000000'
contains    "white/black same ratio (order-independent)" "21.00:1" "$out"

# Same color — minimum, exactly 1:1, fails both
run '#ffffff' '#ffffff'
contains    "white/white ratio is 1.00"      "1.00:1" "$out"
contains    "white/white fails 4.5:1"        "AA normal text (4.5:1): FAIL" "$out"
contains    "white/white fails 3:1"          "AA large text / UI (3:1): FAIL" "$out"

# WebAIM's classic compliant gray: #767676 on white = 4.54:1 (just passes AA)
run '#767676' '#ffffff'
contains    "#767676/white is 4.54:1"        "4.54:1" "$out"
contains    "#767676/white passes 4.5:1"     "AA normal text (4.5:1): PASS" "$out"

# One shade lighter: #777777 on white = 4.48:1 (fails 4.5, passes 3)
run '#777777' '#ffffff'
contains    "#777/white is 4.48:1"           "4.48:1" "$out"
contains    "#777/white fails 4.5:1"         "AA normal text (4.5:1): FAIL" "$out"
contains    "#777/white passes 3:1"          "AA large text / UI (3:1): PASS" "$out"

# Pure red on white = 4.00:1 (large-text/UI only)
run '#ff0000' '#ffffff'
contains    "red/white is 4.00:1"            "4.00:1" "$out"
contains    "red/white fails 4.5:1"          "AA normal text (4.5:1): FAIL" "$out"
contains    "red/white passes 3:1"           "AA large text / UI (3:1): PASS" "$out"

# Shorthand #RGB and missing '#' both accepted
run '000' 'fff'
expect_exit "shorthand no-# exits 0"         0 "$code"
contains    "shorthand #RGB expands (21.00)" "21.00:1" "$out"
run '#F00' '#FFF'
contains    "shorthand red matches long form" "4.00:1" "$out"

# Bad input → exit 2
run '#12345' '#ffffff'
expect_exit "5-digit hex rejected"           2 "$code"
run '#gggggg' '#ffffff'
expect_exit "non-hex chars rejected"         2 "$code"
run '#ffffff'
expect_exit "missing arg rejected"           2 "$code"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
