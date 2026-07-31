#!/usr/bin/env bash
# Enforce the runner-agent delegation contract for the five audit skills.
#
# The skill is a thin orchestrator and must stay on `haiku`; the mechanical run
# belongs to its matching agents/*-runner.md, which carries whatever model the
# work needs. Two regressions this catches:
#
#   1. The skill stops naming its runner (it starts running pa11y/lychee/vale/
#      unlighthouse/pngquant in the main session instead of delegating).
#   2. The skill's declared model drifts off `haiku` — an orchestration-only
#      skill on `sonnet` is a routing bug, which is what was wrong with
#      a11y-scan before it was corrected.
#
# The skill → runner pairs below ARE the contract; a new audit skill is added
# here deliberately, not discovered.
#
#   bash tools/lint/check-audit-delegation.sh [repo-root]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

# <skill>:<runner agent>[,<runner agent>…] — a skill may delegate to more than
# one runner, as prose-lint does: vale-prose-runner carries the mechanical Vale
# pass, facilitron-voice-judge carries the brand-voice pass (MD-2574). Every
# runner listed is checked, so inlining either pass back into the skill fails.
PAIRS="a11y-scan:a11y-scan-runner
link-check:lychee-link-runner
prose-lint:vale-prose-runner,facilitron-voice-judge
site-audit:unlighthouse-runner
optimize-images:optimize-images-runner"

fail=0
checked=0

# frontmatter_field <file> <field> — echo the value from the leading `---` block.
frontmatter_field() {
  awk -v field="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && index($0, field ":") == 1 {
      value = substr($0, length(field) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$1"
}

while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  skill="${pair%%:*}"
  runners="${pair##*:}"
  checked=$((checked + 1))
  skill_doc="skills/$skill/SKILL.md"

  if [ ! -f "$skill_doc" ]; then
    echo "FAIL $skill: missing $skill_doc" >&2
    fail=1
    continue
  fi

  model="$(frontmatter_field "$skill_doc" model)"
  if [ "$model" != "haiku" ]; then
    echo "FAIL $skill: $skill_doc declares model \"$model\", must be \"haiku\" — the runner agent carries the model the work needs, the orchestrator stays cheap" >&2
    fail=1
  fi

  # Split the comma-separated runner list without arrays, so this stays portable
  # to the bash 3.2 that ships with macOS.
  while [ -n "$runners" ]; do
    runner="${runners%%,*}"
    case "$runners" in
      *,*) runners="${runners#*,}" ;;
      *) runners="" ;;
    esac
    agent_doc="agents/$runner.md"

    if ! grep -qF -- "$runner" "$skill_doc"; then
      echo "FAIL $skill: $skill_doc no longer names its runner \"$runner\" — a skill that runs the tool itself instead of delegating is a regression" >&2
      fail=1
    fi

    if [ ! -f "$agent_doc" ]; then
      echo "FAIL $skill: missing runner agent $agent_doc" >&2
      fail=1
      continue
    fi

    agent_name="$(frontmatter_field "$agent_doc" name)"
    if [ "$agent_name" != "$runner" ]; then
      echo "FAIL $skill: $agent_doc declares name \"$agent_name\", must be \"$runner\" so the skill's handoff resolves" >&2
      fail=1
    fi
  done
done <<EOF
$PAIRS
EOF

if [ "$fail" -ne 0 ]; then
  echo "check-audit-delegation: FAILED (audit skills must stay haiku and delegate to their runner agent)" >&2
  exit 1
fi

echo "check-audit-delegation: OK (checked $checked audit skills)"
