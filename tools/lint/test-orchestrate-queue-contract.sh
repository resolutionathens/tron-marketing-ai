#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ROOT/skills/orchestrate-queue/SKILL.md"
MONITOR="$ROOT/skills/orchestrate-queue/scripts/monitor-dispatches.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_text() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || fail "$file does not contain required contract text: $needle"
}

test -f "$SKILL" || fail "orchestrate-queue skill is missing"
test -x "$MONITOR" || fail "orchestrate-queue monitor is missing or not executable"

require_text 'name: orchestrate-queue' "$SKILL"
require_text 'surface: true' "$SKILL"
require_text 'TRON_API_URL' "$SKILL"
require_text 'list_approvals' "$SKILL"
require_text 'resolve_approval' "$SKILL"
require_text 'blockedBy' "$SKILL"
require_text 'affectedPaths' "$SKILL"
require_text 'standingInstruction' "$SKILL"
require_text 'relay_dispatch_message' "$SKILL"

if grep -Fq 'send-keys' "$SKILL"; then
  fail "orchestrate-queue contains a competing raw worker transport"
fi
if grep -Eq 'approve_pr|gh[[:space:]]+pr[[:space:]]+merge|git[[:space:]]+merge' "$SKILL"; then
  fail "orchestrate-queue can approve or merge a pull request"
fi
for repo_specific in 'knowledge/log.md' 'OKF_SOURCE_CONCEPTS' 'api:tmux' 'pkill'; do
  if grep -Fq "$repo_specific" "$SKILL"; then
    fail "orchestrate-queue leaked tron-os-specific guidance: $repo_specific"
  fi
done

node - "$ROOT/packages/package-map.json" <<'NODE'
const fs = require("fs");
const map = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (!map.packages.engineer.skills.includes("orchestrate-queue")) {
  throw new Error("engineer package does not include orchestrate-queue");
}
if (!map.ownership.engineer.includes("orchestrate-queue")) {
  throw new Error("engineer does not own orchestrate-queue");
}
NODE

require_text 'tron:orchestrate-queue' "$ROOT/README.md"

node - "$ROOT/.claude-plugin/plugin.json" "$ROOT/.codex-plugin/plugin.json" <<'NODE'
const fs = require("fs");
const [claudePath, codexPath] = process.argv.slice(2);
const claude = JSON.parse(fs.readFileSync(claudePath, "utf8"));
const codex = JSON.parse(fs.readFileSync(codexPath, "utf8"));
if (claude.version !== codex.version) throw new Error("Claude/Codex plugin versions differ");
const parts = claude.version.split(".").map(Number);
if (parts.length !== 3 || parts.some(Number.isNaN) || parts[0] < 0 || (parts[0] === 0 && parts[1] < 49)) {
  throw new Error(`new orchestrate-queue capability requires version 0.49.0 or newer, got ${claude.version}`);
}
NODE

if [ -e "$ROOT/skills/orchestrate-workers" ] || [ -e "$ROOT/skills/orchestrate-epic" ]; then
  fail "legacy competing orchestration skill is still present"
fi

printf 'PASS: orchestrate-queue has one cross-harness control-plane contract.\n'
