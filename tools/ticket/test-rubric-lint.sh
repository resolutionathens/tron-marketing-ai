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

# Intent is an optional, one-sentence outcome marker. It parses through the
# canonical marker primitive but never participates in the verdict ladder.
INTENT='Intent: District staff can identify the correct enrollment workflow without support'
[[ "$(rb_marker_value "$INTENT" Intent)" == "District staff can identify the correct enrollment workflow without support" ]] \
  || fail "rb_marker_value Intent"
rb_marker_present "$INTENT" Intent || fail "Intent should be present"
pass "Intent parses as a machine-readable outcome marker"

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

# rubric-version 5 (MD-3405): engineering is a pilot type, graded against
# pilot-template.md for its stage (rb_verdict's third argument, default created).
# The ladder keeps its four steps.
PILOT_HEAD='Done: Swap the BAS logo across the footer
Intent: Visitors recognise the current BAS brand across the site
Type: engineering
Deliverable type: pr
Stakeholder: Ian Kennedy
Engineer: Ian Kennedy
Context: https://x.y/brief
Decision: 2026-07-20; Ian signs off'
PILOT_BODY='PR: [add PR]   Test Branch: [add link]   Branch: [add name]

## 1. Problem
As a visitor, I need the current logo so that I recognise the brand.
Today: the footer shows the legacy mark.

## 2. Scope
In scope: the footer
Out of scope: the header

## 3. Pages & Roles
| Page / entry point (path) | Roles that see or do this | Roles explicitly excluded |
|---|---|---|
| every page | visitors | none |

## 4. Pre-conditions & Test Data
- Settings, flags or org config: none

## 5. Acceptance Criteria
Same numbers as the header.

**AC1** The footer shows the new logo

**AC2** The old logo file is gone

## 6. Design, Links & Decisions
| Date | Decision or open question | Owner | Status |
|---|---|---|---|
| 2026-07-20 | Keep the footer layout | Ian | Decided |

## 7. Change log
| Date | Change | Added / Removed / Changed | Requested by | ACs affected |
|---|---|---|---|---|'
# A fenced pilot ticket: <header lines> then the sections.
pilot() { printf '```text\n%s\n```\n\n%s\n' "$1" "$PILOT_BODY"; }
ENG_ACS='Acceptance criteria:
- AC1 The footer shows the new logo on every page
- AC2 The old logo file is no longer in the bundle'
HIGHT="$(pilot "$PILOT_HEAD
Repo: marketing-pages
Affected paths: components/Footer.vue
$ENG_ACS")"
for st in created ready kickoff review; do
  [[ "$(rb_verdict "$HIGHT" 0 "$st")" == "high: actionable" ]] \
    || fail "full pilot engineering ticket → high at $st (got: $(rb_verdict "$HIGHT" 0 "$st"))"
done

# The spine without a Stakeholder → low; with one but no section 1 → medium.
MEDT='Done: Swap the logo
Type: engineering
Deliverable type: pr
Context: https://x.y/brief'
[[ "$(rb_verdict "$MEDT")" == "low: needs enrichment" ]] \
  || fail "pilot spine without Stakeholder → low (got: $(rb_verdict "$MEDT"))"
[[ "$(rb_missing "$MEDT")" == *"spine:Stakeholder"* ]] || fail "missing Stakeholder is a spine gap"
[[ "$(rb_verdict "$(pilot "$PILOT_HEAD")" 0 created)" == "high: actionable" ]] \
  || fail "a created ticket needs no Repo, paths or criteria yet"
[[ "$(rb_verdict "$PILOT_HEAD")" == "medium: routable but thin" ]] \
  || fail "no section 1 → medium"
[[ "$(rb_missing "$PILOT_HEAD")" == *"section:section 1. Problem"* ]] || fail "section 1 named when missing"

# Intent is required from created in the pilot template (no longer advisory).
NOINTENT="$(printf '%s\n' "$HIGHT" | grep -v '^Intent:')"
[[ "$(rb_verdict "$NOINTENT")" == "medium: routable but thin" ]] || fail "a pilot ticket without Intent → medium"
[[ "$(rb_missing "$NOINTENT")" == *"section:Intent"* ]] || fail "missing Intent is named"
[[ "$(rb_verdict "${HIGHT/Intent: Visitors recognise the current BAS brand across the site/Intent: TBD}")" == "medium: routable but thin" ]] \
  || fail "a placeholder Intent is no Intent"

# Without a Repo marker, a valid summary PREFIX still stands in at kickoff.
NOREPO="$(printf '%s\n' "$HIGHT" | grep -v '^Repo:')"
[[ "$(rb_verdict "$NOREPO" 0 kickoff)" == "medium: routable but thin" ]] \
  || fail "no Repo, no prefix → medium at kickoff"
[[ "$(rb_verdict "$NOREPO" 1 kickoff)" == "high: actionable" ]] \
  || fail "no Repo marker but prefix_ok=1 → high at kickoff"
[[ "$(rb_verdict "$NOREPO" 0 ready)" == "high: actionable" ]] \
  || fail "Repo isn't required before kickoff"
pass "verdict ladder: none → low → medium → high, PREFIX satisfies Repo"
pass "pilot engineering tickets require Stakeholder and Intent from created"

# --- acceptance criteria must describe reviewable change properties ----------
COMMAND_GATE='Acceptance criteria:
- bun run docs:check exits 0
- bun run docs:check passes
- bun run docs:check passes.
- bun run docs:check succeeds
- the suite passes
- CI is green'
[[ "$(rb_command_gate_criteria "$COMMAND_GATE")" == *"bun run docs:check exits 0"* ]] \
  || fail "command exit-code criterion should be flagged"
[[ "$(rb_command_gate_criteria "$COMMAND_GATE")" == *"bun run docs:check passes"* ]] \
  || fail "command-pass criterion should be flagged"
[[ "$(rb_command_gate_criteria "$COMMAND_GATE")" == *"bun run docs:check succeeds"* ]] \
  || fail "command-success criterion should be flagged"
[[ "$(rb_command_gate_criteria "$COMMAND_GATE")" == *"the suite passes"* ]] \
  || fail "suite-pass criterion should be flagged"
[[ "$(rb_command_gate_criteria "$COMMAND_GATE")" == *"CI is green"* ]] \
  || fail "CI-green criterion should be flagged"
[[ "$(rb_acceptance_criteria_valid "$COMMAND_GATE")" != 0 ]] \
  || fail "command-only acceptance criteria should be invalid"

COMMAND_NEAR_MISS='Acceptance criteria:
- The command reports a stale pointer when the sync file is older than the manifest'
[[ -z "$(rb_command_gate_criteria "$COMMAND_NEAR_MISS")" ]] \
  || fail "observable command behaviour must not be flagged"
rb_acceptance_criteria_valid "$COMMAND_NEAR_MISS" \
  || fail "observable command behaviour should be valid"

UPPERCASE_GATE='ACCEPTANCE CRITERIA:
- bun run docs:check exits 0'
[[ "$(rb_command_gate_criteria "$UPPERCASE_GATE")" == *"bun run docs:check exits 0"* ]] \
  || fail "uppercase acceptance-criteria header should still flag a command gate"
[[ "$(rb_acceptance_criteria_valid "$UPPERCASE_GATE")" != 0 ]] \
  || fail "uppercase command-only acceptance criteria should be invalid"
pass "command-result acceptance criteria are invalid; observable command behaviour is valid"

# --- acceptance criteria name something checkable (SR-6176) ------------------
# Baton drafted "Done: shouldn't all staging pages be https?" and an acceptance
# criterion ending in the same question. A question, or a criterion that checks
# nothing, keeps the ticket below high: actionable. Since rubric-version 5 the
# engineering base is a pilot ticket (unfenced, so the criteria appended below
# are still its header's); the rule holds at every stage.
CHECKABLE_BASE='## 1. Problem
As a staff member, I need Favorites over https so that the browser trusts it.

Done: The Favorites page loads over https on staging
Intent: Staff reach Favorites without a browser warning
Type: engineering
Deliverable type: bugfix
Stakeholder: Ian Kennedy
Context: https://facilitron.atlassian.net/browse/SR-6176
Decision: 2026-11-16; Ian decided and signs off
Repo: Facilitron/facilitron
Affected paths: /favorites
Acceptance criteria:'
for ac in \
  'On /, click Favorites: shouldn’t all staging pages be https?' \
  "AC1 On /, click Favorites: shouldn't all staging pages be https?" \
  'Is the page https' \
  'Can we add a map' \
  'Why does Escape close the whole panel' \
  'It works' \
  'On /, click Favorites: as expected' \
  'None yet: the reviewer decides the expected result'; do
  T="$CHECKABLE_BASE
- $ac"
  [[ -n "$(rb_uncheckable_criteria "$T")" ]] || fail "uncheckable criterion should be flagged: $ac"
  [[ "$(rb_verdict "$T")" == "medium: routable but thin" ]] \
    || fail "uncheckable criterion should hold the verdict at medium: $ac (got: $(rb_verdict "$T"))"
done
[[ "$(rb_uncheckable_criteria "$CHECKABLE_BASE
- Is the page https")" == question$'\t'"Is the page https" ]] \
  || fail "a verb-first question is reported as a question"
[[ "$(rb_uncheckable_criteria "$CHECKABLE_BASE
- It works")" == vague$'\t'"It works" ]] \
  || fail "a criterion that checks nothing is reported as vague"
for ac in \
  'On /favorites: the address bar shows https://facilities.staging.facilitron.com/favorites' \
  'On /, “Old” is replaced by “Need help?”' \
  'On /, “Old” is replaced by “Help: Need help?”' \
  'The button reads "Need help?"' \
  'Does nothing when the menu is open no longer happens: the Search dialog opens' \
  'Should open the Search dialog when Search is tapped'; do
  T="$CHECKABLE_BASE
- $ac"
  [[ -z "$(rb_uncheckable_criteria "$T")" ]] || fail "checkable criterion must not be flagged: $ac"
  [[ "$(rb_verdict "$T")" == "high: actionable" ]] || fail "checkable criterion should lint high: $ac"
done
# A command gate is reported once, as a gate.
[[ -z "$(rb_uncheckable_criteria "$CHECKABLE_BASE
- the suite passes")" ]] || fail "a command gate is not also reported as uncheckable"
# A Done that asks is no Done; an Intent that asks is no Intent.
QDONE="$(printf '%s\n' "$CHECKABLE_BASE" | sed 's/^Done: .*/Done: shouldn’t all staging pages be https?/')
- On /favorites: the page loads over https"
[[ "$(rb_verdict "$QDONE")" == "none: needs human direction" ]] || fail "a question as Done needs human direction"
QJSON="$(printf '%s\n' "$QDONE" | sed 's/^Intent: .*/Intent: is it https?/' | bash "$CLI")"
# A pilot ticket requires Intent, so a question there is a section gap (rubric-version 5).
[[ "$(jq -r '.missing.section | join(",")' <<< "$QJSON")" == *Intent* ]] || fail "a question as Intent is reported missing"
[[ "$(jq -r '.issues | join("\n")' <<< "$QJSON")" == *"Done is a question: shouldn’t all staging pages be https?."* ]] \
  || fail "lint names the question in Done"
[[ "$(jq -r '.issues | join("\n")' <<< "$QJSON")" == *"Intent is a question: is it https?."* ]] \
  || fail "lint names the question in Intent"
# An Intent that asks keeps an otherwise complete ticket below high.
QINTENT="Intent: is it https?
$CHECKABLE_BASE
- On /favorites: the page loads over https"
[[ "$(rb_verdict "$QINTENT")" == "medium: routable but thin" ]] || fail "a question as Intent keeps the ticket below high"
[[ "$(rb_verdict "$(printf '%s\n' "$QINTENT" | sed 's/^Intent: .*/Intent: Visitors reach Favorites over https/')")" == "high: actionable" ]] \
  || fail "the same ticket with a stated Intent lints high"
# A quoted value ending in a question mark is copy, not a question.
[[ "$(rb_verdict "$(printf '%s\n' "$CHECKABLE_BASE" | sed 's/^Done: .*/Done: The button reads “Need help?”/')
- On /, “Old” is replaced by “Need help?”")" == "high: actionable" ]] || fail "a Done quoting copy with a question mark is a statement"
[[ "$(rb_verdict "$(printf '%s\n' "$CHECKABLE_BASE" | sed 's/^Done: .*/Done: The button reads "Need help?"/')
- The button reads "Need help?"")" == "high: actionable" ]] || fail "straight-quoted copy with a question mark is a statement"
QLINT="$(printf '%s\n' "$CHECKABLE_BASE
- It works
- Is the page https" | bash "$CLI")"
[[ "$(jq -r '.verdict' <<< "$QLINT")" == "medium: routable but thin" ]] || fail "lint verdict holds at medium"
[[ "$(jq -r '.issues[0]' <<< "$QLINT")" == "Acceptance criterion names no outcome anyone can check: It works. Name one thing a person or a browser test can check pass or fail (an address, a text, an element's state, a response)." ]] \
  || fail "lint explains a vague criterion"
[[ "$(jq -r '.issues[1]' <<< "$QLINT")" == "Acceptance criterion is a question, not something to check: Is the page https. Keep the question for the reviewer, and state here one outcome a person or a browser test can check pass or fail." ]] \
  || fail "lint explains a question criterion"
pass "a question or an uncheckable criterion keeps a ticket below high; quoted copy and statements pass"

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

# --- rubric-version 4: research tickets and several repos (MD-3262) ------------
# Since rubric-version 5 a research ticket is a pilot ticket, graded at kickoff here
# (the first stage that requires Repo and Affected paths).
RESEARCH="$(pilot 'Done: A write-up comparing Flue and Pi Durable, with a recommendation
Type: engineering
Deliverable type: research
Stakeholder: Ian Kennedy
Engineer: Ian Kennedy
Context: https://facilitron.atlassian.net/wiki/x/FgD9BgE
Decision: Ian signs off
Intent: The team knows which framework the coordinator keeps
Repo: tron-coordinator, tron-coordinator-do
Acceptance criteria:
- AC1 the write-up compares crash recovery, streaming and approvals
- AC2 it recommends one framework')"
rb_deliverable_type_valid "$RESEARCH" engineering || fail "research is an engineering deliverable type"
rb_is_research "$RESEARCH" || fail "rb_is_research on a research ticket"
rb_is_research "${RESEARCH/research/pr}" && fail "rb_is_research is false for a pr ticket"
[[ "$(rb_verdict "$RESEARCH" 0 kickoff)" == "high: actionable" ]] || fail "research ticket without Affected paths should lint high (got: $(rb_verdict "$RESEARCH" 0 kickoff))"
[[ "$(rb_verdict "${RESEARCH/research/pr}" 0 kickoff)" == "medium: routable but thin" ]] || fail "a pr ticket still needs Affected paths"
[[ "$(rb_verdict "${RESEARCH/Repo: tron-coordinator, tron-coordinator-do/Repo: TBD}" 0 kickoff)" == "medium: routable but thin" ]] || fail "research still needs a Repo"
rb_is_research "${RESEARCH/research/  Research  }" || fail "research is case- and space-insensitive"
rb_is_research "${RESEARCH/Type: engineering/Type: design}" && fail "research is engineering only"
NOREPO="$(printf '%s\n' "$RESEARCH" | grep -v '^Repo:')"
[[ "$(rb_verdict "$NOREPO" 1 kickoff)" == "high: actionable" ]] || fail "a valid PREFIX satisfies Repo for research too"
pass "research: engineering deliverable with no Affected paths, still needs Repo"

repo() { rb_repo_valid "Repo: $1"; }
repo 'marketing-pages' || fail "one repo key"
repo 'tron-coordinator, tron-coordinator-do' || fail "comma-separated repos"
repo 'resolutionathens/tron-os,Facilitron/facilitron-ui' || fail "owner/repo entries"
repo 'marketing-pages (footer only)' || fail "a note after the key is allowed"
repo 'marketing-pages, TBD' && fail "a placeholder entry is invalid"
repo 'marketing-pages,' && fail "an empty entry is invalid"
repo 'see the epic!' && fail "free text is not a repo"
repo 'TBD' && fail "a placeholder Repo is invalid"
repo '*' && fail "a glob character is text, not a file pattern"
repo 'marketing-pages (footer, header), tron-os' || fail "a comma inside a note doesn't split an entry"
repo $'\tmarketing-pages ,  tron-os  ' || fail "surrounding whitespace is ignored"
repo 'marketing-pages — footer' && fail "free text after a key is invalid (put notes in parentheses)"
pass "Repo: one repo key or several, each validated"

# A PREFIX stands in for a missing Repo, not for a malformed one (MD-3268).
[[ "$(rb_verdict "${RESEARCH/Repo: tron-coordinator, tron-coordinator-do/Repo: marketing-pages, TBD}" 1 kickoff)" == "medium: routable but thin" ]] \
  || fail "a PREFIX doesn't excuse an invalid entry in an explicit Repo list"
[[ "$(rb_verdict "${RESEARCH/Repo: tron-coordinator, tron-coordinator-do/Repo: marketing-pages — footer}" 1 kickoff)" == "medium: routable but thin" ]] \
  || fail "a PREFIX doesn't excuse free text in Repo"
[[ "$(rb_verdict "${RESEARCH/Repo: tron-coordinator, tron-coordinator-do/Repo: TBD}" 1 kickoff)" == "high: actionable" ]] \
  || fail "a PREFIX still satisfies a placeholder Repo"
[[ "$(rb_verdict "$RESEARCH" 1 kickoff)" == "high: actionable" ]] || fail "a PREFIX with a valid Repo list stays high"
pass "PREFIX satisfies a missing Repo, but an explicit Repo is still validated"

# --- CLI (--file / stdin, JSON) ---------------------------------------------
command -v jq >/dev/null || { echo "  (skipping CLI JSON checks — jq not on PATH)"; echo "rubric smoke: $PASS checks passed"; exit 0; }

TMP="$(mktemp "${TMPDIR:-/tmp}/rubric-hi.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$HIGHT" > "$TMP"
OUT="$(bash "$CLI" --file "$TMP" --stage kickoff)"
[[ "$(jq -r '.verdict' <<<"$OUT")" == "high: actionable" ]] || fail "CLI --file verdict"
[[ "$(jq -r '.type' <<<"$OUT")" == engineering ]] || fail "CLI --file type"
[[ "$(jq -r '.missing.spine|length' <<<"$OUT")" == 0 ]] || fail "CLI --file no spine gaps"
[[ "$(jq -r '[.template, .stage, .source] | join(",")' <<<"$OUT")" == "pilot,kickoff,file" ]] \
  || fail "CLI reports the pilot template, the stage and the source"
pass "CLI --file emits JSON with verdict/type/missing"

GATE_TICKET="${HIGHT/The footer shows the new logo on every page/bun run docs:check exits 0}"
GATE_OUT="$(printf '%s\n' "$GATE_TICKET" | bash "$CLI" --summary 'TRON-PLUGIN: swap logo')"
[[ "$(jq -r '.verdict' <<<"$GATE_OUT")" == "medium: routable but thin" ]] \
  || fail "command-result criterion should prevent a high verdict"
[[ "$(jq -r '.issues[0]' <<<"$GATE_OUT")" == *"State the verification in the description instead"* ]] \
  || fail "command-result criterion should give the author a remediation message"
pass "CLI reports command-result criteria and blocks a high verdict"

# stdin + summary prefix satisfying Repo
OUT2="$(printf '%s\n' "$NOREPO" | bash "$CLI" --summary 'TRON-PLUGIN: swap the logo' --stage kickoff)"
[[ "$(jq -r '.prefix_ok' <<<"$OUT2")" == true ]] || fail "CLI prefix_ok detection"
[[ "$(jq -r '.verdict' <<<"$OUT2")" == "high: actionable" ]] || fail "CLI prefix satisfies Repo"
pass "CLI stdin + --summary PREFIX satisfies Repo requirement"

# recognized prefix + an invalid second repo → Repo gap still reported (MD-3268)
BADREPO="${RESEARCH/Repo: tron-coordinator, tron-coordinator-do/Repo: marketing-pages, TBD}"
OUT_BR="$(printf '%s\n' "$BADREPO" | bash "$CLI" --summary 'PAGES: Port interfaces' --stage kickoff)"
[[ "$(jq -r '.prefix_ok' <<<"$OUT_BR")" == true ]] || fail "CLI prefix_ok for PAGES:"
[[ "$(jq -r '.verdict' <<<"$OUT_BR")" == "medium: routable but thin" ]] || fail "CLI: PREFIX + invalid Repo entry is not high"
[[ "$(jq -r '.missing.section | index("Repo")' <<<"$OUT_BR")" != "null" ]] || fail "CLI reports the invalid Repo as a section gap"
pass "CLI --summary PREFIX does not hide an invalid Repo entry"

# An empty Repo entry is caught through the CLI under the system bash 3.2, where
# rb_missing's `local IFS='|'` once made the `|` in the empty-entry regex literal (MD-3268).
for ENTRY in 'tron-os,' ',tron-os' 'tron-os,,marketing-pages'; do
  OUT_EE="$(printf '%s\n' "${RESEARCH/Repo: tron-coordinator, tron-coordinator-do/Repo: $ENTRY}" | /bin/bash "$CLI" --stage kickoff)"
  [[ "$(jq -r '.missing.section | index("Repo")' <<<"$OUT_EE")" != "null" ]] \
    || fail "CLI (/bin/bash): 'Repo: $ENTRY' reports a Repo gap"
done
pass "CLI under /bin/bash rejects empty Repo entries"

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

# --- pilot template: every pilot type at every stage (MD-3405) ---------------
# product, engineering, bug, data and spike are graded against pilot-template.md
# for their Jira stage. Each case builds a complete ticket for the type and stage
# (high), then takes away what that stage first requires, and checks that the
# lint names it.
# Does rb_missing name <line> exactly? (A grep -q on the pipe could SIGPIPE under pipefail.)
missing_has() { [ -n "$(rb_missing "$1" 0 "$2" | grep -xF -- "$3")" ]; }
drop_section() {   # $1 = text, $2 = section number: the text without that section
  printf '%s\n' "$1" | awk -v n="$2" '
    /^###?[[:space:]]*[0-9]\./ { h = $0; sub(/^#+[[:space:]]*/, "", h); skip = (substr(h, 1, 1) == n) }
    !skip { print }'
}
pilot_ticket() {   # $1 = type, $2 = stage
  local repo=""
  # A product ticket names no Repo or paths until the engineer's kickoff.
  if [ "$1" != product ] || [ "$(rb_stage_index "$2")" -ge 2 ]; then
    repo='Repo: marketing-pages
Affected paths: components/Footer.vue'
  fi
  pilot "${PILOT_HEAD/Type: engineering/Type: $1}
$repo
$ENG_ACS"
}
for type in product engineering bug data spike; do
  for st in created ready kickoff review; do
    T="$(pilot_ticket "$type" "$st")"
    [[ "$(rb_verdict "$T" 0 "$st")" == "high: actionable" ]] \
      || fail "complete $type ticket at $st → high (got: $(rb_verdict "$T" 0 "$st"); missing: $(rb_missing "$T" 0 "$st" | paste -sd, -))"
    case "$st" in
      created) T2="$(printf '%s\n' "$T" | grep -v '^Stakeholder:')"; want=spine:Stakeholder; v="low: needs enrichment" ;;
      ready)   T2="${T/Engineer: Ian Kennedy/Engineer: not yet assigned}"; want=section:Engineer; v="medium: routable but thin" ;;
      *)       T2="$(printf '%s\n' "$T" | grep -v '^Affected paths:')"; want="section:Affected paths"; v="medium: routable but thin" ;;
    esac
    [[ "$(rb_verdict "$T2" 0 "$st")" == "$v" ]] || fail "$type at $st without ${want#*:} → $v (got: $(rb_verdict "$T2" 0 "$st"))"
    missing_has "$T2" "$st" "$want" || fail "$type at $st names $want"
    # What the next stage requires isn't asked for yet.
    [ "$st" = created ] && { [[ "$(rb_verdict "${T/Engineer: Ian Kennedy/Engineer: not yet assigned}" 0 created)" == "high: actionable" ]] \
      || fail "$type: Engineer may be not yet assigned while created"; }
  done
done
pass "each pilot type at each stage: complete → high, the stage's first requirement named when missing"

# Sections by type: each type needs its own sections from ready on, and only those.
for pair in "product 4" "engineering 4" "bug 3" "data 2" "spike 6"; do
  type="${pair% *}"; n="${pair#* }"
  T="$(drop_section "$(pilot_ticket "$type" ready)" "$n")"
  [[ "$(rb_verdict "$T" 0 created)" == "high: actionable" ]] || fail "$type without section $n is fine while created"
  [[ "$(rb_verdict "$T" 0 ready)" == "medium: routable but thin" ]] || fail "$type needs section $n from ready"
  missing_has "$T" ready "section:section $n. $(rb_pilot_section_name "$n")" || fail "$type names section $n"
done
for pair in "bug 2" "bug 6" "data 3" "data 4" "data 6" "spike 3" "spike 4"; do
  type="${pair% *}"; n="${pair#* }"
  T="$(drop_section "$(pilot_ticket "$type" kickoff)" "$n")"
  [[ "$(rb_verdict "$T" 0 kickoff)" == "high: actionable" ]] || fail "$type doesn't need section $n (got: $(rb_missing "$T" 0 kickoff | paste -sd, -))"
done
# A spike has a deliverable instead of criteria: no section 5 and no header ACs.
SPIKE="$(drop_section "$(pilot_ticket spike kickoff)" 5 | sed '/^Acceptance criteria:/d; /^- AC[0-9]/d')"
[[ "$(rb_verdict "$SPIKE" 0 kickoff)" == "high: actionable" ]] || fail "a spike needs no acceptance criteria"
[[ "$(rb_verdict "$(drop_section "$(pilot_ticket engineering ready)" 7)" 0 review)" == "high: actionable" ]] \
  || fail "section 7 isn't checked (Baton doesn't either)"
pass "sections by type: bug 1 3 4 5, data 1 2 5, spike 1 2 6, the rest 1 to 6"

# From ready on: no Open decisions, two or more numbered criteria, and the same AC numbers in the header and section 5.
OPEN="${HIGHT/| Ian | Decided |/| Ian | Open |}"
[[ "$(rb_verdict "$OPEN" 0 created)" == "high: actionable" ]] || fail "an Open decision is fine while created"
[[ "$(rb_verdict "$OPEN" 0 ready)" == "medium: routable but thin" ]] || fail "an Open decision at ready → medium"
[[ "$(rb_missing "$OPEN" 0 ready)" == *'problem:Open decision at ready: "Keep the footer layout" (owner: Ian)'* ]] || fail "the Open decision is named"
ONE_AC="$(printf '%s\n' "$HIGHT" | grep -v '^- AC2 ')"
[[ "$(rb_verdict "$ONE_AC" 0 created)" == "high: actionable" ]] || fail "criteria aren't counted while created"
missing_has "$ONE_AC" ready 'section:Acceptance criteria' || fail "one criterion isn't enough from ready"
UNNUMBERED="${HIGHT/- AC1 /- }"; UNNUMBERED="${UNNUMBERED/- AC2 /- }"
missing_has "$UNNUMBERED" ready 'section:Acceptance criteria' || fail "criteria must be numbered AC1, AC2"
MISMATCH="$(printf '%s\n' "$HIGHT" | grep -v '^\*\*AC2\*\*')"
[[ "$(rb_missing "$MISMATCH" 0 ready)" == *"problem:Header ACs (AC1,AC2) don't match section 5 (AC1)"* ]] || fail "AC numbers must match section 5"
[[ "$(rb_verdict "$MISMATCH" 0 created)" == "high: actionable" ]] || fail "AC numbers aren't compared while created"
pass "from ready: Open decisions, unnumbered or single criteria and mismatched AC numbers hold a ticket at medium"

# A product ticket says what and why: no Repo or paths before kickoff, and code is a warning.
PROD="$(pilot_ticket product kickoff)"
[[ "$(rb_verdict "$PROD" 0 ready)" == "medium: routable but thin" ]] || fail "a product ticket with Repo at ready → medium"
[[ "$(rb_missing "$PROD" 0 ready)" == *"problem:Repo is the engineer's to fill at kickoff, not in a product ticket."* ]] || fail "product Repo named"
[[ "$(rb_verdict "$PROD" 0 kickoff)" == "high: actionable" ]] || fail "a product ticket takes Repo at kickoff"
CODE="$(pilot_ticket product created | sed 's/^Today: the footer shows the legacy mark\./Today: Footer.vue calls renderLogo()./')"
[[ "$(rb_verdict "$CODE" 0 created)" == "high: actionable" ]] || fail "a code warning doesn't lower the verdict"
[[ "$(rb_missing "$CODE" 0 created)" == *'warning:section 1 names code ("Footer.vue")'* ]] || fail "code in a product section is a warning"
[[ "$(rb_missing "$(pilot_ticket engineering created | sed 's/^Today: .*/Today: Footer.vue calls renderLogo()./')" 0 created)" != *warning:* ]] \
  || fail "an engineering ticket may name code"
pass "product tickets: Repo and paths are problems before kickoff, code in a section is a warning"

# #130's rule on fenced pilot criteria, at every stage.
for st in created ready kickoff review; do
  Q="${HIGHT/- AC2 The old logo file is no longer in the bundle/- AC2 Shouldn’t the old logo be gone?}"
  [[ "$(rb_verdict "$Q" 0 "$st")" == "medium: routable but thin" ]] || fail "a question criterion holds a pilot ticket at medium at $st"
  V="${HIGHT/- AC2 The old logo file is no longer in the bundle/- AC2 It works}"
  [[ "$(rb_verdict "$V" 0 "$st")" == "medium: routable but thin" ]] || fail "a vague criterion holds a pilot ticket at medium at $st"
done
QOUT="$(printf '%s\n' "$Q" | bash "$CLI" --stage ready)"
[[ "$(jq -r '.issues[0]' <<<"$QOUT")" == "Acceptance criterion is a question, not something to check: AC2 Shouldn’t the old logo be gone?. Keep the question for the reviewer, and state here one outcome a person or a browser test can check pass or fail." ]] \
  || fail "lint explains a pilot question criterion (got: $(jq -r '.issues[0]' <<<"$QOUT"))"
pass "a question or vague pilot criterion holds the ticket at medium at every stage"

# Stages from Jira statuses (pilot-template.md, "Stages").
for pair in "Backlog=created" "To Do=created" "Ready to Develop=ready" "In Progress=kickoff" \
            "In Development=kickoff" "Dev Review=review" "In Review=review" "QA=review" "Done=review" "Triage=created"; do
  [[ "$(rb_stage_for_status "${pair%=*}")" == "${pair#*=}" ]] || fail "status ${pair%=*} → ${pair#*=} (got: $(rb_stage_for_status "${pair%=*}"))"
done
[[ "$(printf '%s\n' "$OPEN" | bash "$CLI" --status 'Ready to Develop' | jq -r '[.stage, .verdict] | join(",")')" == "ready,medium: routable but thin" ]] \
  || fail "CLI --status maps to a stage"
rc=0; printf '%s\n' "$OPEN" | bash "$CLI" --stage soon >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "an unknown --stage exits 2 (got: $rc)"
DESIGN_OUT="$(printf 'Done: X\nType: design\nDeliverable type: figma\nContext: https://x.y\n' | bash "$CLI" --stage ready)"
[[ "$(jq -r '[.template, (.stage|tostring)] | join(",")' <<<"$DESIGN_OUT")" == "rubric,null" ]] || fail "design keeps the marker rubric, with no stage"
pass "Jira statuses map to stages; --stage and --status choose one; design has none"

# --key: the description, or the newest <KEY>-engineering.md attachment when there is one.
STUB="$(mktemp -d "${TMPDIR:-/tmp}/rubric-stub.XXXXXX")"
trap 'rm -rf "$TMP" "$STUB"' EXIT
cat > "$STUB/acli" <<'SH'
#!/usr/bin/env bash
cat "$RUBRIC_STUB_JSON"
SH
cat > "$STUB/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RUBRIC_STUB_DIR/curl.log"
case "$*" in *content/22*) cat "$RUBRIC_STUB_DIR/new.md" ;; *) cat "$RUBRIC_STUB_DIR/old.md" ;; esac
SH
chmod +x "$STUB/acli" "$STUB/curl"
printf '%s\n' "$HIGHT" > "$STUB/new.md"
printf 'Make the banner pop\n' > "$STUB/old.md"
jq -n '{fields: {summary: "UI: swap logo", status: {name: "In Progress"}, description: null, attachment: [
  {id: "11", filename: "MD-9-engineering.md", created: "2026-11-01T10:00:00.000+0000", content: "https://x.atlassian.net/rest/api/3/attachment/content/11"},
  {id: "22", filename: "MD-9-engineering.md", created: "2026-11-02T10:00:00.000+0000", content: "https://x.atlassian.net/rest/api/3/attachment/content/22"},
  {id: "33", filename: "notes.md", created: "2026-11-03T10:00:00.000+0000", content: "https://x.atlassian.net/rest/api/3/attachment/content/33"}]}}' > "$STUB/brief.json"
KOUT="$(PATH="$STUB:$PATH" RUBRIC_STUB_JSON="$STUB/brief.json" RUBRIC_STUB_DIR="$STUB" ATLASSIAN_EMAIL=a@b.c JIRA_API_TOKEN=t bash "$CLI" --key MD-9)"
[[ "$(jq -r '[.verdict, .stage, .source] | join(",")' <<<"$KOUT")" == "high: actionable,kickoff,attachment:MD-9-engineering.md" ]] \
  || fail "--key reads the newest brief at the status's stage (got: $(jq -c . <<<"$KOUT"))"
grep -q 'content/22' "$STUB/curl.log" || fail "--key downloads the newest brief"
rc=0; PATH="$STUB:$PATH" RUBRIC_STUB_JSON="$STUB/brief.json" RUBRIC_STUB_DIR="$STUB" ATLASSIAN_EMAIL='' JIRA_API_TOKEN='' bash "$CLI" --key MD-9 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 4 ]] || fail "a brief without credentials exits 4 rather than grading the description (got: $rc)"
pass "--key grades the newest <KEY>-engineering.md brief at the Jira status's stage"

# --- ADF round-trip (the contract that ties create-ticket to the --key path) -
# create-ticket writes the marker block as a fenced code block precisely so it
# survives md-to-adf (ordinary lines collapse to a space-joined paragraph and
# bare URLs split off their Key:). Guard on node + the converter being present.
# md-to-adf lazy-installs markdown-to-adf on first run; the test never lets it (MD-3398:
# no network from Layer 1). Without the installed dependency this check is skipped and
# the whole test reports SKIP (exit 77) once the other checks have run.
ADF="$HERE/../md-to-adf/md-to-adf.mjs"
ADF_SKIPPED=""
if [ ! -d "$HERE/../md-to-adf/node_modules/markdown-to-adf" ]; then
  ADF_SKIPPED="tools/md-to-adf/node_modules/markdown-to-adf is not installed (run: cd tools/md-to-adf && npm ci)"
elif ! node -e 0 >/dev/null 2>&1 || [ ! -f "$ADF" ]; then
  ADF_SKIPPED="node or md-to-adf.mjs unavailable"
fi
if [ -z "$ADF_SKIPPED" ]; then
  RT="$(mktemp "${TMPDIR:-/tmp}/rubric-rt.XXXXXX")"
  trap 'rm -rf "$TMP" "$STUB" "$RT"' EXIT
  # A product ticket's whole pilot brief is its description (pilot-template.md,
  # "Where it lives"), so it must survive md-to-adf and come back through --key
  # with its fenced header, ## sections and table rows.
  pilot_ticket product ready | sed 's#^Context: .*#Context: https://figma.com/file/abc?node-id=1:2#' > "$RT"
  node "$ADF" < "$RT" 2>/dev/null \
    | jq '{fields: {summary: "Swap the logo", status: {name: "Ready to Develop"}, description: ., attachment: []}}' > "$STUB/desc.json"
  EXTRACT="$(jq -r '[.fields.description | .. | objects | select(.type=="text") | .text] | join("\n")' "$STUB/desc.json")"
  printf '%s\n' "$EXTRACT" | grep -qE '^Context: https://figma\.com/file/abc' \
    || fail "ADF round-trip: Context URL should stay on its marker line"
  printf '%s\n' "$EXTRACT" | grep -qE '^Intent: Visitors recognise the current BAS brand' \
    || fail "ADF round-trip: Intent should stay on its marker line"
  ROUT="$(PATH="$STUB:$PATH" RUBRIC_STUB_JSON="$STUB/desc.json" bash "$CLI" --key MD-8)"
  [[ "$(jq -r '[.verdict, .stage, .source] | join(",")' <<<"$ROUT")" == "high: actionable,ready,description" ]] \
    || fail "ADF round-trip: a pilot description should lint high at ready (got: $(jq -c . <<<"$ROUT"))"
  OPEN_RT="$(sed 's/| Ian | Decided |/| Ian | Open |/' "$RT")"
  printf '%s\n' "$OPEN_RT" | node "$ADF" 2>/dev/null \
    | jq '{fields: {summary: "Swap the logo", status: {name: "Ready to Develop"}, description: ., attachment: []}}' > "$STUB/desc.json"
  ROUT="$(PATH="$STUB:$PATH" RUBRIC_STUB_JSON="$STUB/desc.json" bash "$CLI" --key MD-8)"
  [[ "$(jq -r '.issues | join("\n")' <<<"$ROUT")" == *'Open decision at ready: "Keep the footer layout"'* ]] \
    || fail "ADF round-trip: section 6's table survives, so an Open decision is found"
  pass "ADF round-trip: a pilot description survives md-to-adf and --key grades it at its stage"
fi

echo "rubric smoke: $PASS checks passed"
if [ -n "$ADF_SKIPPED" ]; then
  echo "SKIP: ADF round-trip check — $ADF_SKIPPED"
  exit 77
fi
