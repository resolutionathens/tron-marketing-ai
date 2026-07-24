#!/usr/bin/env bash
# Smoke for rubric-lib.sh + rubric-lint.sh — the deterministic backbone of
# tron:ticket-lint and the rubric it shares with tron:create-ticket and SCOUT
# triage. Everything here is offline: marker parsing, placeholder detection,
# type normalization, the verdict ladder, and the --file/stdin CLI path.
#
#   bash tools/ticket/test-rubric-lint.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/rubric-lib.sh"
CLI="$HERE/rubric-lint.sh"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

# shellcheck source=/dev/null
source "$LIB"

echo "rubric smoke:"

# --- marker value + presence -------------------------------------------------
TXT='Done: Ship the BAS logo swap
Type: engineering
Context: https://figma.com/file/abc?node-id=1:2
Decision: TBD'

[[ "$(rb_marker_value "$TXT" Done)" == "Ship the BAS logo swap" ]] || fail "rb_marker_value Done"
[[ "$(rb_marker_value "$TXT" Context)" == "https://figma.com/file/abc?node-id=1:2" ]] \
  || fail "rb_marker_value keeps URL colon (got: $(rb_marker_value "$TXT" Context))"
[[ "$(rb_marker_value "$TXT" Missing)" == "" ]] || fail "rb_marker_value absent → empty"
pass "rb_marker_value extracts value, preserves URL colons, empty when absent"

rb_marker_present "$TXT" Done    || fail "Done should be present"
rb_marker_present "$TXT" Decision && fail "Decision=TBD should read as absent"
rb_marker_present "$TXT" Type    || fail "Type should be present"
pass "rb_marker_present treats TBD/placeholder as absent"

# case-insensitive key + <bracketed> placeholder
CI='done: lower key still counts
type: <engineering | design | content | campaign-asset | cms>'
rb_marker_present "$CI" Done || fail "case-insensitive Done key"
rb_marker_present "$CI" Type && fail "<bracketed> template stub should read as absent"
pass "keys match case-insensitively; <bracketed> stubs read as absent"

# --- value realness ----------------------------------------------------------
for bad in "" "  " "TBD" "todo" "???" "-" "n/a" "NA" "<figma url>"; do
  rb_value_is_real "$bad" && fail "rb_value_is_real should reject '$bad'"
done
for good in "news" "https://x.y" "a real answer"; do
  rb_value_is_real "$good" || fail "rb_value_is_real should accept '$good'"
done
pass "rb_value_is_real rejects blanks/placeholders, accepts real values"

# --- type normalization ------------------------------------------------------
[[ "$(rb_type 'Type: Engineering')" == engineering ]] || fail "Type: Engineering → engineering"
[[ "$(rb_type 'Type: content')"     == content ]]     || fail "Type: content → content"
[[ "$(rb_type 'Type: design work')" == design ]]      || fail "Type: 'design work' → design"
[[ "$(rb_type 'Type: campaign-asset')" == campaign-asset ]] \
  || fail "Type: campaign-asset → campaign-asset"
[[ "$(rb_type 'Type: cms edit')" == cms ]] || fail "Type: 'cms edit' → cms"
[[ "$(rb_type 'Type: marketing')"   == "" ]]          || fail "unknown type → empty"
pass "rb_type normalizes every rubric work type, empty for unknown"

# --- deliverable values + shared locator vocabulary --------------------------
[[ "$(rb_deliverable_types campaign-asset)" == "image|pdf|print|merch|collateral" ]] \
  || fail "campaign-asset deliverable values drifted"
[[ "$(rb_deliverable_types cms)" == "page-edit|bugfix|content-update" ]] \
  || fail "cms deliverable values drifted"
[[ "$(rb_resolvable_locator_markers)" == "Figma|Draft|Edit URL|Verify URL" ]] \
  || fail "resolvable locator marker set drifted"
[[ "$(rb_placement_context_markers)" == "Campaign|Lands|Destination" ]] \
  || fail "placement context marker set drifted"
pass "deliverables and locator classes are explicit and deterministic"

# --- verdict ladder ----------------------------------------------------------
[[ "$(rb_verdict 'random prose with no markers')" == "none: needs human direction" ]] \
  || fail "no markers → none"

# Done + Deliverable type present, but Type/Context missing → low
LOWT='Done: X
Deliverable type: pr'
[[ "$(rb_verdict "$LOWT")" == "low: needs enrichment" ]] \
  || fail "spine gap → low (got: $(rb_verdict "$LOWT"))"

# Full spine, engineering, but no section markers → medium
MEDT='Done: Swap the logo
Type: engineering
Deliverable type: pr
Context: https://x.y/brief'
[[ "$(rb_verdict "$MEDT")" == "medium: routable but thin" ]] \
  || fail "spine only → medium (got: $(rb_verdict "$MEDT"))"

# Full engineering ticket with all section markers → high
HIGHT='Done: Swap the BAS logo across the footer
Type: engineering
Deliverable type: pr
Context: https://x.y/brief
Decision: 2026-07-20; Ian signs off
Repo: marketing-pages
Affected paths: components/Footer.vue
Acceptance criteria:
- new logo renders in the footer'
[[ "$(rb_verdict "$HIGHT")" == "high: actionable" ]] \
  || fail "full engineering ticket → high (got: $(rb_verdict "$HIGHT"))"

# Same ticket WITHOUT Repo marker but WITH a valid summary PREFIX → still high
NOREPO='Done: Swap the BAS logo
Type: engineering
Deliverable type: pr
Context: https://x.y/brief
Affected paths: components/Footer.vue
Acceptance criteria:
- renders'
[[ "$(rb_verdict "$NOREPO" 0)" == "medium: routable but thin" ]] \
  || fail "no Repo, no prefix → medium"
[[ "$(rb_verdict "$NOREPO" 1)" == "high: actionable" ]] \
  || fail "no Repo marker but prefix_ok=1 → high"
pass "verdict ladder: none → low → medium → high, PREFIX satisfies Repo"

# --- full content + design ticket → high ------------------------------------
CONT='Done: Publish the HVAC maintenance guide
Type: content
Deliverable type: guide
Context: https://docs.google.com/document/d/xyz
Destination: guide
Format: article
SEO target: preventive maintenance plan
Draft: https://docs.google.com/document/d/xyz'
[[ "$(rb_verdict "$CONT")" == "high: actionable" ]] || fail "full content ticket → high"

DES='Done: Design the ticketing product illustration
Type: design
Deliverable type: figma
Context: https://figma.com/file/abc
Figma: https://figma.com/file/abc?node-id=1:2
Format: 1200x630 PNG
Brand refs: tron- palette
Lands: /product/ticketing hero'
[[ "$(rb_verdict "$DES")" == "high: actionable" ]] || fail "full design ticket → high"
pass "full content and design tickets → high"

# --- full campaign asset ticket → high; missing campaign → medium ------------
CAMPAIGN='Done: Produce the pillow design for the welcome kit
Type: campaign-asset
Deliverable type: print
Context: https://facilitron.atlassian.net/browse/MCR-394
Campaign: FU6 Welcome Kit > Pillows (MCR-393)
Asset: Pillow Design
Format: print-ready PDF
Lands: campaign production folder'
[[ "$(rb_verdict "$CAMPAIGN")" == "high: actionable" ]] \
  || fail "full campaign-asset ticket → high (got: $(rb_verdict "$CAMPAIGN"))"

CAMPAIGN_NO_LOCATOR='Done: Produce the pillow design for the welcome kit
Type: campaign-asset
Deliverable type: print
Context: https://facilitron.atlassian.net/browse/MCR-394
Asset: Pillow Design
Format: print-ready PDF
Lands: campaign production folder'
[[ "$(rb_verdict "$CAMPAIGN_NO_LOCATOR")" == "medium: routable but thin" ]] \
  || fail "campaign-asset without Campaign hierarchy → medium"
[[ "$(rb_missing "$CAMPAIGN_NO_LOCATOR")" == *"section:Campaign"* ]] \
  || fail "campaign-asset without hierarchy flags Campaign"
pass "campaign-asset requires its campaign locator and other section markers"

CAMPAIGN_BAD_DELIVERABLE="${CAMPAIGN/Deliverable type: print/Deliverable type: zzz-not-real}"
[[ "$(rb_verdict "$CAMPAIGN_BAD_DELIVERABLE")" == "none: needs human direction" ]] \
  || fail "invalid campaign-asset deliverable → none"
[[ "$(rb_missing "$CAMPAIGN_BAD_DELIVERABLE")" == *"spine:Deliverable type"* ]] \
  || fail "invalid deliverable is reported as a spine gap"
rb_deliverable_type_valid "$CAMPAIGN" campaign-asset \
  || fail "valid campaign-asset deliverable rejected"
rb_deliverable_type_valid "$CAMPAIGN_BAD_DELIVERABLE" campaign-asset \
  && fail "invalid campaign-asset deliverable accepted"
pass "Deliverable type must match the selected Type's value table"

# --- hosted CMS edit requires edit + verify locations ------------------------
CMS='Done: Fix the Stewardship Awards page layout
Type: cms
Deliverable type: bugfix
Context: https://facilitron.atlassian.net/browse/MCR-414
CMS: HubSpot
Edit URL: https://app.hubspot.com/pages/46442771/editor/216811382540/content
Verify URL: https://info.facilitron.com/stewardship-awards-2026?hs_preview=eQbTwLgt-216811382540'
[[ "$(rb_verdict "$CMS")" == "high: actionable" ]] \
  || fail "full cms ticket → high (got: $(rb_verdict "$CMS"))"

CMS_NO_VERIFY='Done: Fix the Stewardship Awards page layout
Type: cms
Deliverable type: bugfix
Context: https://facilitron.atlassian.net/browse/MCR-414
CMS: HubSpot
Edit URL: https://app.hubspot.com/pages/46442771/editor/216811382540/content'
[[ "$(rb_verdict "$CMS_NO_VERIFY")" == "medium: routable but thin" ]] \
  || fail "cms ticket without Verify URL → medium"
[[ "$(rb_missing "$CMS_NO_VERIFY")" == *"section:Verify URL"* ]] \
  || fail "cms ticket without public verification flags Verify URL"
pass "cms work requires separately openable edit and verification locations"

# --- CLI (--file / stdin, JSON) ---------------------------------------------
command -v jq >/dev/null || { echo "  (skipping CLI JSON checks — jq not on PATH)"; echo "rubric smoke: $PASS checks passed"; exit 0; }

TMP="$(mktemp "${TMPDIR:-/tmp}/rubric-hi.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$HIGHT" > "$TMP"
OUT="$(bash "$CLI" --file "$TMP")"
[[ "$(jq -r '.verdict' <<<"$OUT")" == "high: actionable" ]] || fail "CLI --file verdict"
[[ "$(jq -r '.type' <<<"$OUT")" == engineering ]] || fail "CLI --file type"
[[ "$(jq -r '.missing.spine|length' <<<"$OUT")" == 0 ]] || fail "CLI --file no spine gaps"
pass "CLI --file emits JSON with verdict/type/missing"

# stdin + summary prefix satisfying Repo
OUT2="$(printf '%s\n' "$NOREPO" | bash "$CLI" --summary 'TRON-PLUGIN: swap the logo')"
[[ "$(jq -r '.prefix_ok' <<<"$OUT2")" == true ]] || fail "CLI prefix_ok detection"
[[ "$(jq -r '.verdict' <<<"$OUT2")" == "high: actionable" ]] || fail "CLI prefix satisfies Repo"
pass "CLI stdin + --summary PREFIX satisfies Repo requirement"

# a thin, real-world title-only ticket → none, with concrete gaps listed
OUT3="$(printf 'Make the banner pop\n' | bash "$CLI")"
[[ "$(jq -r '.verdict' <<<"$OUT3")" == "none: needs human direction" ]] || fail "thin ticket → none"
[[ "$(jq -r '.missing.spine | index("Done")' <<<"$OUT3")" != "null" ]] || fail "thin ticket flags missing Done"
pass "thin title-only ticket → none, missing Done flagged"

# --- CLI arg handling (deterministic failures) ------------------------------
rc=0; bash "$CLI" --key >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "--key with no value should exit 2 (got: $rc)"
rc=0; bash "$CLI" --summary >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "--summary with no value should exit 2 (got: $rc)"
rc=0; bash "$CLI" --key MD-1 --file /tmp/x >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "--key + --file should exit 2 (mutually exclusive) (got: $rc)"
rc=0; bash "$CLI" --bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown arg should exit 2 (got: $rc)"
pass "CLI arg handling: missing values, --key/--file exclusivity, unknown args exit 2"

# --- ADF round-trip (the contract that ties create-ticket to the --key path) -
# create-ticket writes the marker block as a fenced code block precisely so it
# survives md-to-adf (ordinary lines collapse to a space-joined paragraph and
# bare URLs split off their Key:). Guard on node + the converter being present.
ADF="$HERE/../md-to-adf/md-to-adf.mjs"
if command -v node >/dev/null && [ -f "$ADF" ]; then
  RT="$(mktemp "${TMPDIR:-/tmp}/rubric-rt.XXXXXX")"
  trap 'rm -f "$TMP" "$RT"' EXIT
  cat > "$RT" <<'MD'
# Swap the BAS logo across the footer

```
Done: Replace the legacy BAS logo in the footer sitewide
Type: engineering
Deliverable type: pr
Context: https://figma.com/file/abc?node-id=1:2
Decision: 2026-07-20; Ian signs off
Repo: marketing-pages
Affected paths: components/Footer.vue
Acceptance criteria:
- new logo renders in the footer sitewide
- old asset removed
```

## Context

Rebrand rollout. See the [Figma frame](https://figma.com/file/abc?node-id=1:2).
MD
  EXTRACT="$(node "$ADF" < "$RT" 2>/dev/null \
    | jq -r '[.. | objects | select(.type=="text") | .text] | join("\n")')"
  V="$(printf '%s' "$EXTRACT" | bash "$CLI" --summary 'TRON-PLUGIN: swap logo' | jq -r '.verdict')"
  [[ "$V" == "high: actionable" ]] \
    || fail "ADF round-trip: fenced marker block should lint high (got: $V)"
  printf '%s\n' "$EXTRACT" | grep -qE '^Context: https://figma\.com/file/abc' \
    || fail "ADF round-trip: Context URL should stay on its marker line"
  pass "ADF round-trip: fenced marker block survives md-to-adf → lints high"
else
  echo "  (skipping ADF round-trip check — node or md-to-adf.mjs unavailable)"
fi

echo "rubric smoke: $PASS checks passed"
