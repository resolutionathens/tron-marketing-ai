#!/usr/bin/env bash
# Regression tests for vale-ini.template: MD-2539 (BlockIgnores parsing) and
# MD-2574 (the AP dateline exemption and both dash tokens, at the end).
#
# MD-2539: BlockIgnores in vale-ini.template must stay a
# single comma-free regex (Vale splits its value on commas), and must still
# ignore both the `::` and `:::` MDC fence variants without swallowing prose
# outside them.
#
# The comma check below is vale-independent and runs unconditionally — it's
# the assertion CI actually exercises, since CI never installs vale. It fails
# on any future edit that reintroduces a comma (e.g. a `{n,m}` quantifier),
# not just on a snapshot of today's string. It's scoped to BlockIgnores only:
# TokenIgnores on the next line legitimately contains a comma (a genuine
# two-pattern list), so the test also asserts the check doesn't false-positive
# there.
#
# Below that, if `vale` is installed locally, a richer check exercises the
# real regex end-to-end against Vale's bundled styles (no `Packages`/`vale
# sync`, so still no network dependency) and confirms both fence variants are
# ignored while outside prose still lints. That part SKIPs cleanly in CI.
#
#   bash skills/prose-lint/scripts/test-vale-ini-template.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
TEMPLATE="$SKILL_DIR/vale-ini.template"

PASS=0
pass() { echo "  ok: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; exit 1; }

[ -f "$TEMPLATE" ] || fail "vale-ini.template not found at $TEMPLATE"

BLOCK_IGNORES="$(grep '^BlockIgnores' "$TEMPLATE" | sed 's/^BlockIgnores = //')"
TOKEN_IGNORES="$(grep '^TokenIgnores' "$TEMPLATE" | sed 's/^TokenIgnores = //')"

[ -n "$BLOCK_IGNORES" ] || fail "no BlockIgnores line found in vale-ini.template"
[ -n "$TOKEN_IGNORES" ] || fail "no TokenIgnores line found in vale-ini.template"

# --- Vale-independent: this is the assertion CI actually runs. ---

case "$BLOCK_IGNORES" in
  *,*) fail "BlockIgnores contains a comma — Vale splits *Ignores values on commas, so this will break with an E201 parse error (the {n,m}-quantifier bug this test guards against): $BLOCK_IGNORES" ;;
esac
pass "BlockIgnores contains no comma"

# Scoping check: the rule above must apply to BlockIgnores only. TokenIgnores
# is a genuine two-pattern list and is expected to contain a comma; if a
# broader "no *Ignores key may contain a comma" check were written instead,
# this would catch it failing on legitimate input.
case "$TOKEN_IGNORES" in
  *,*) pass "TokenIgnores legitimately contains a comma (two-pattern list) — confirms the check above is scoped to BlockIgnores only" ;;
  *) fail "TokenIgnores has no comma — expected it to still be a two-pattern list; if this changed, the scoping assumption behind this test needs a re-check" ;;
esac

if printf '%s' "$BLOCK_IGNORES" | grep -qE '\{[0-9]+,'; then
  fail "BlockIgnores contains a {n,...} quantifier, which reintroduces a comma: $BLOCK_IGNORES"
fi
pass "BlockIgnores contains no {n,...} quantifier"

# --- Vale-dependent: richer end-to-end check, SKIPs cleanly where vale isn't installed (e.g. CI). ---

if ! command -v vale >/dev/null 2>&1; then
  echo "SKIP: vale not installed — skipping the end-to-end vale-ini.template check"
  echo "vale-ini.template BlockIgnores regression: $PASS checks passed (+ 1 skipped)"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/prose-lint-blockignores.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/.vale/styles/config/vocabularies"
ln -s "$SKILL_DIR/styles/Facilitron" "$WORK/.vale/styles/Facilitron"
ln -s "$SKILL_DIR/styles/config/vocabularies/Facilitron" "$WORK/.vale/styles/config/vocabularies/Facilitron"

# Minimal config: exercises the real BlockIgnores/TokenIgnores values against
# the bundled Vale + Facilitron styles only, so no `vale sync` / network call
# is needed to reproduce the E201 parse failure or verify fence behavior.
cat > "$WORK/.vale.ini" <<EOF
StylesPath = .vale/styles
MinAlertLevel = suggestion
Vocab = Facilitron

[*.md]
BasedOnStyles = Vale, Facilitron
Vale.Spelling = NO

BlockIgnores = $BLOCK_IGNORES
TokenIgnores = $TOKEN_IGNORES
EOF

cat > "$WORK/fixture.md" <<'EOF'
This sentence is very very very extremely utilized in order to test wordiness outside a fence.

::card{prop=1}
This markup fence body should be totally skipped no matter how sloppy the writing inside happens to be, obviously.
::

Some more content between the fences that ought to also get linted properly right here.

:::alert{type=warning}
This is the triple-colon fence variant and it too should be skipped entirely, clearly.
:::

Final closing remark outside every fence, meant to trigger a finding down here too.
EOF

OUT="$(cd "$WORK" && vale --output=line fixture.md 2>&1)" || true

if printf '%s\n' "$OUT" | grep -q 'E201'; then
  fail "BlockIgnores/TokenIgnores regex failed to parse (E201)"
fi
pass "vale-ini.template parses under Vale ($(vale --version)) — no E201"

if printf '%s\n' "$OUT" | grep -qE '^fixture\.md:(3|4|5):'; then
  fail "prose inside the ::card fence body (lines 3-5) was linted; expected it to be ignored"
fi
pass "::card{...} ... :: fence body stays ignored"

if printf '%s\n' "$OUT" | grep -qE '^fixture\.md:(9|10|11):'; then
  fail "prose inside the :::alert fence body (lines 9-11) was linted; expected it to be ignored"
fi
pass ":::alert{...} ... ::: fence body stays ignored"

if ! printf '%s\n' "$OUT" | grep -qE '^fixture\.md:1:'; then
  fail "prose outside the fences (line 1) produced no findings; expected the wordiness/hedging hits to survive"
fi
pass "prose outside the fences still produces findings"

# --- MD-2574: the dateline exemption and both dash tokens. ---
#
# Facilitron.EmDash is an error-level rule that must fire on a stray em OR en
# dash but never on the AP press-release dateline, where the dash is correct.
# The exemption lives in TokenIgnores rather than in the rule because RE2 has no
# lookaround. Both dateline variants in the corpus are covered here: the dash
# trailing inside the bold run, and the dash separating city from date.

cat > "$WORK/dateline.md" <<'EOF'
**LOS GATOS, Calif., July 1, 2026 —** For decades districts treated this as routine.

**LOS GATOS, Calif. — February 24, 2026**, Facilitron today announced the framework.

This sentence has a stray em dash — right here.

This sentence has a stray en dash – right here.

**Los Gatos-Saratoga UHSD** had no clear picture of usage.
EOF

DATE_OUT="$(cd "$WORK" && vale --output=line dateline.md 2>&1)" || true

for line in 1 3; do
  if printf '%s\n' "$DATE_OUT" | grep -qE "^dateline\.md:$line:[0-9]+:Facilitron\.EmDash"; then
    fail "EmDash fired on the AP dateline (line $line); TokenIgnores should exempt the bolded run"
  fi
done
pass "both AP dateline variants stay exempt from EmDash"

if ! printf '%s\n' "$DATE_OUT" | grep -qE '^dateline\.md:5:[0-9]+:Facilitron\.EmDash'; then
  fail "EmDash did not fire on a stray em dash (line 5)"
fi
pass "a stray em dash is still caught"

if ! printf '%s\n' "$DATE_OUT" | grep -qE '^dateline\.md:7:[0-9]+:Facilitron\.EmDash'; then
  fail "EmDash did not fire on a stray en dash (line 7) — the en dash token is the MD-2574 gap"
fi
pass "a stray en dash is caught (was unenforced before MD-2574)"

# A TokenIgnores match is invisible to EVERY rule, so the dateline pattern must be
# dateline-shaped, not merely "bold with a year in it". A bold run carrying a year
# but no month name must still lint, or any such phrase becomes a lint-free zone.
cat > "$WORK/fluff.md" <<'EOF'
**Los Gatos-Saratoga UHSD** can unlock and elevate outcomes.

**In 2026 we unlock seamless value** across the district.
EOF

FLUFF_OUT="$(cd "$WORK" && vale --output=line fluff.md 2>&1)" || true
for token in unlock elevate; do
  if ! printf '%s\n' "$FLUFF_OUT" | grep -q "'$token'"; then
    fail "MarketingFluff did not catch '$token' — bare verb tokens are the MD-2574 addition"
  fi
done
pass "bare unlock/elevate are caught, and a yearless bold run is not exempt"

if ! printf '%s\n' "$FLUFF_OUT" | grep -qE '^fluff\.md:3:'; then
  fail "a bold run with a year but no month was exempted; the dateline pattern is too broad and would hide every rule inside it"
fi
pass "bold + year without a month name is NOT dateline-exempt"

# Word boundaries: `elevate` must not fire on `elevators`, which is real
# vocabulary in a facilities-maintenance corpus.
cat > "$WORK/boundary.md" <<'EOF'
Inspect elevators and elevator controls on the published schedule.
EOF

BOUND_OUT="$(cd "$WORK" && vale --output=line boundary.md 2>&1)" || true
if printf '%s\n' "$BOUND_OUT" | grep -q 'MarketingFluff'; then
  fail "MarketingFluff fired on 'elevators' — the fluff tokens must respect word boundaries"
fi
pass "'elevators' does not trip the elevate token"

echo "vale-ini.template BlockIgnores + MD-2574 dateline regression: $PASS checks passed"
