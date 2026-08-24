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

FIX="$(mktemp -d "${TMPDIR:-/tmp}/orchestrate-queue-contract.XXXXXX")"
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT

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
NODE

if [ -e "$ROOT/skills/orchestrate-workers" ] || [ -e "$ROOT/skills/orchestrate-epic" ]; then
  fail "legacy competing orchestration skill is still present"
fi

# Execute the exact documented bootstrap from clean Claude and Codex cache installs with root
# variables unset. Keep /usr/bin ahead of Homebrew so the fallback is exercised with macOS tools.
BOOTSTRAP="$FIX/bootstrap.sh"
awk '
  /^[[:space:]]*name=orchestrate-queue[[:space:]]*$/ { grab=1; match($0, /^[[:space:]]*/); ind=RLENGTH }
  grab { print substr($0, ind + 1) }
  grab && /SKILL_DIR="\$\(bash "\$RESOLVER" "\$name"/ { exit }
' "$SKILL" > "$BOOTSTRAP"

mkdir -p "$FIX/bin"
cat > "$FIX/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '[{"id":"d1","status":"working","needsHuman":false,"requiredChecksState":"pending","prNumber":null,"workerWorking":true,"reviewParkedAt":null}]\n'
SH
chmod +x "$FIX/bin/curl"
JQ_DIR="$(dirname "$(command -v jq)")"

PLUGIN_VERSION="$(node -p "require('$ROOT/.claude-plugin/plugin.json').version")"
for harness_root in .claude/plugins/cache .codex/plugins/cache; do
  rm -rf "$FIX/.claude" "$FIX/.codex"
  INSTALL="$FIX/$harness_root/tron/tron-engineer/$PLUGIN_VERSION"
  mkdir -p "$INSTALL/tools/skill" "$INSTALL/skills/orchestrate-queue/scripts"
  cp "$ROOT/tools/skill/resolve-skill-dir.sh" "$INSTALL/tools/skill/resolve-skill-dir.sh"
  cp "$SKILL" "$INSTALL/skills/orchestrate-queue/SKILL.md"
  cp "$MONITOR" "$INSTALL/skills/orchestrate-queue/scripts/monitor-dispatches.sh"
  for shell in /bin/bash /bin/zsh; do
    [ -x "$shell" ] || continue
    resolved="$(env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SKILL_DIR HOME="$FIX" PATH="$FIX/bin:$JQ_DIR:/usr/bin:/bin" "$shell" -c ". '$BOOTSTRAP'; printf '%s' \"\$SKILL_DIR\"")"
    [ "$resolved" = "$INSTALL/skills/orchestrate-queue" ] || fail "$shell could not resolve orchestrate-queue from $harness_root"
    out="$(env TRON_API_URL=http://control.test PATH="$FIX/bin:$JQ_DIR:/usr/bin:/bin" bash "$resolved/scripts/monitor-dispatches.sh" --once d1)"
    printf '%s\n' "$out" | grep -Fq 'd1 status=working' || fail "$shell-resolved monitor did not run from $harness_root"
  done
done

printf 'PASS: orchestrate-queue has one cross-harness control-plane contract.\n'
