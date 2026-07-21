#!/usr/bin/env bash
# Contract + skill regression test for MD-2324 (hardening after CCAL-1777):
# asserts the four worker-hardening guarantees stay written into the canonical
# WORKER_CONTRACT.md and the lifecycle skills that implement them. A doc-content
# test — it reads the real repo files (hermetic, no externals) and fails loudly
# if any guarantee is deleted or the machine-readable contract anchors drift.
#
#   bash tools/lint/test-worker-hardening.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTRACT="$ROOT/WORKER_CONTRACT.md"
SRC_TYPES="$ROOT/skills/jira-source-discovery/reference/source-types.md"
SRC_DISCOVERY="$ROOT/skills/jira-source-discovery/SKILL.md"
START="$ROOT/skills/start-ticket/SKILL.md"
SHIP="$ROOT/skills/ship-ticket/SKILL.md"
CLOSE="$ROOT/skills/close-worktree/SKILL.md"

PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

# has <file> <label> <fixed-string> — assert the file contains the literal string.
has() {
  local file="$1" label="$2" needle="$3"
  [ -f "$file" ] || fail "$label: missing file $file"
  grep -qF -- "$needle" "$file" || fail "$label: expected to find \"$needle\" in ${file#$ROOT/}"
  pass "$label"
}

echo "worker-hardening contract+skill test:"

# --- 1. Unreadable-source blocking (hard gate) -------------------------------
has "$CONTRACT"      "contract: source-hard-gate anchor"        "<!-- contract:source-hard-gate -->"
has "$CONTRACT"      "contract: hard implementation gate"       "hard implementation gate"
has "$CONTRACT"      "contract: every supported authenticated"  "every supported authenticated"
has "$CONTRACT"      "contract: one concise plain-text blocker" "one concise plain-text blocker"
has "$START"         "start-ticket: source is the hard gate"    "hard implementation gate"
has "$SRC_DISCOVERY" "source-discovery: authenticated-path gate" "every supported authenticated retrieval path"

# --- 2. Google Docs retrieval guidance (authenticated gws + JSON model) ------
has "$SRC_TYPES"     "source-types: gws docs get command"       "gws docs documents get"
has "$SRC_TYPES"     "source-types: documentId param"           "documentId"
has "$SRC_TYPES"     "source-types: Docs JSON model extraction"  "body.content"
has "$SRC_TYPES"     "source-types: textRun extraction"          "textRun"
has "$CONTRACT"      "contract: names gws docs path"            "gws docs documents get"

# --- 3. PR-gate worktree retention -------------------------------------------
has "$CONTRACT"      "contract: pr-gate-retention anchor"       "<!-- contract:pr-gate-retention -->"
has "$CONTRACT"      "contract: retained through PR gate"       "retained through the PR gate"
has "$CONTRACT"      "contract: close-worktree human-gated"     "when a human explicitly asks for cleanup"
has "$SHIP"          "ship-ticket: park at PR gate"             "Park at the PR gate"
has "$CLOSE"         "close-worktree: post-merge only"          "post-merge only"

# --- 4. Evidence-backed completion language ----------------------------------
has "$CONTRACT"      "contract: evidence-backed anchor"         "<!-- contract:evidence-backed-claims -->"
has "$CONTRACT"      "contract: claims name their evidence"     "names the command you ran or the artifact"
has "$CONTRACT"      "contract: unavailable != passed"          "report it as unavailable"

echo "worker-hardening contract+skill test: $PASS assertions passed"
