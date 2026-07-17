#!/usr/bin/env bash
# Offline test for build.ts's parse stage (--emit-md — no pandoc/xelatex needed).
# Feeds fixture Nuxt-Content markdown through the front-matter split, ::faq
# expansion, ::checklist-group conversion, CRLF normalization, and table-heavy
# detection, then asserts the cleaned intermediate markdown.
#
# Requires bun (build.ts is a bun script). If bun is missing, skips loudly.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if ! command -v bun >/dev/null 2>&1; then
  echo "SKIP: bun not found on PATH — test-build.sh needs bun to run build.ts (install: https://bun.sh)"
  exit 0
fi

# build.ts imports yaml from this skill's isolated package manifest. Provision it
# here so the parse-layer test works from a fresh checkout, not just a reused one.
if [ ! -d "$HERE/node_modules/yaml" ]; then
  (cd "$HERE" && bun install --frozen-lockfile >/dev/null)
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"

fail=0
contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok  : $1"; else echo "FAIL: $1 — missing '$2'"; fail=1; fi; }
not_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "FAIL: $1 — unexpectedly contains '$2'"; fail=1; else echo "ok  : $1"; fi; }

# ---------------------------------------------------------------------------
# Fixture 1: front matter + ::faq + ::checklist-group
# ---------------------------------------------------------------------------
cat > "$TMP/fixture.md" <<'EOF'
---
title: Gym Rental Guide
description: ignore me
---

Intro paragraph.

::faq
---
title: Common questions
faqItems:
  - question: How do I rent a gym?
    answer: Submit a request through Facilitron.
  - question: What does it cost?
    answer: Rates vary by district.
---
::

::checklist-group
- Confirm insurance
- [ ] Already a checkbox
- Book the date
::

Closing paragraph.
EOF

bun "$HERE/build.ts" "$TMP/fixture.md" --out "$OUT" --emit-md >/dev/null
md="$(cat "$OUT/fixture.md")"

contains     "front matter: title becomes the H1"          "# Gym Rental Guide" "$md"
not_contains "front matter: yaml block stripped"           "description: ignore me" "$md"
not_contains "front matter: no --- delimiter survives"     $'---\ntitle:' "$md"
contains     "logo: prepended image ref"                   "facilitron-logo.png){ width=160px }" "$md"
contains     "faq: section heading from yaml title"        "## Common questions" "$md"
contains     "faq: question becomes H3"                    "### How do I rent a gym?" "$md"
contains     "faq: answer becomes paragraph"               "Submit a request through Facilitron." "$md"
contains     "faq: second item expanded"                   "### What does it cost?" "$md"
not_contains "faq: MDC block markers removed"              "::faq" "$md"
contains     "checklist: bullet converted to checkbox"     "- [ ] Confirm insurance" "$md"
contains     "checklist: existing checkbox untouched"      "- [ ] Already a checkbox" "$md"
contains     "checklist: later bullet converted too"       "- [ ] Book the date" "$md"
not_contains "checklist: group wrapper removed"            "::checklist-group" "$md"
contains     "body: prose kept"                            "Closing paragraph." "$md"
[ ! -e "$OUT/fixture.pdf" ] && echo "ok  : --emit-md skips the pdf render" || { echo "FAIL: pdf was rendered despite --emit-md"; fail=1; }

# ---------------------------------------------------------------------------
# Fixture 2: no front matter → filename is the title; CRLF input
# ---------------------------------------------------------------------------
printf 'Plain body line one.\r\n\r\n::checklist-group\r\n- windows item\r\n::\r\n' > "$TMP/crlf-doc.md"
bun "$HERE/build.ts" "$TMP/crlf-doc.md" --out "$OUT" --emit-md >/dev/null
md2="$(cat "$OUT/crlf-doc.md")"
contains "no front matter: slug used as title"      "# crlf-doc" "$md2"
contains "crlf: checklist still parsed"             "- [ ] windows item" "$md2"
if grep -q $'\r' "$OUT/crlf-doc.md"; then echo "FAIL: CRLF survived normalization"; fail=1; else echo "ok  : crlf: normalized to LF"; fi

# ---------------------------------------------------------------------------
# Fixture 3: table-heavy detection warns and points at the working sed command
# ---------------------------------------------------------------------------
cat > "$TMP/tables.md" <<'EOF'
| A | B | C | D | E |
|---|---|---|---|---|
| 1 | 2 | 3 | 4 | 5 |
EOF
warn="$(bun "$HERE/build.ts" "$TMP/tables.md" --out "$OUT" --emit-md 2>&1 >/dev/null)"
contains     "table-heavy: warns on a 5-col table"     "5-column table" "$warn"
contains     "table-heavy: hint uses the sed command"  's|@@SKILLDIR@@|' "$warn"
contains     "table-heavy: cites the real section"     'Two paths — default to LaTeX' "$warn"
not_contains "table-heavy: no broken cp hint"          "cp " "$warn"

# Fixture 4: light table (2 cols, 1 table) → no warning
cat > "$TMP/light.md" <<'EOF'
| A | B |
|---|---|
| 1 | 2 |
EOF
warn2="$(bun "$HERE/build.ts" "$TMP/light.md" --out "$OUT" --emit-md 2>&1 >/dev/null)"
not_contains "table detection: light table stays quiet" "Heads up" "$warn2"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
