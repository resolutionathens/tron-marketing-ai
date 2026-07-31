#!/usr/bin/env bash
# Smoke for check-audit-delegation.sh: a correct fixture passes, and each of the
# regressions the lint exists to stop makes it fail with a message naming the
# offending skill — a model drifted off haiku, a dropped runner handoff, a
# missing runner agent, and a runner whose declared name no longer matches.
# A skill may contract several runners (prose-lint has two since MD-2574), so
# dropping either one is covered too.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-audit-delegation.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/audit-delegation-lint.XXXXXX")"
LOG="$(mktemp "${TMPDIR:-/tmp}/audit-delegation-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'trash "$FIXTURE" "$LOG"' EXIT

PAIRS="a11y-scan:a11y-scan-runner
link-check:lychee-link-runner
prose-lint:vale-prose-runner,facilitron-voice-judge
site-audit:unlighthouse-runner
optimize-images:optimize-images-runner"

# write_skill <skill> <runner[,runner…]> <model> — a minimally valid audit-skill doc.
write_skill() {
  mkdir -p "$FIXTURE/skills/$1"
  cat >"$FIXTURE/skills/$1/SKILL.md" <<EOF
---
name: $1
model: $3
effort: low
---

Hand the mechanical run to the \`$2\` agent.
EOF
}

# write_agent <runner> <declared-name>
write_agent() {
  mkdir -p "$FIXTURE/agents"
  cat >"$FIXTURE/agents/$1.md" <<EOF
---
name: $2
model: sonnet
---

Runner body.
EOF
}

reset_fixture() {
  [ ! -e "$FIXTURE/skills" ] || trash "$FIXTURE/skills"
  [ ! -e "$FIXTURE/agents" ] || trash "$FIXTURE/agents"
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    write_skill "${pair%%:*}" "${pair##*:}" haiku
    # A skill may contract more than one runner; each needs its own agent doc.
    runners="${pair##*:}"
    while [ -n "$runners" ]; do
      runner="${runners%%,*}"
      case "$runners" in
        *,*) runners="${runners#*,}" ;;
        *) runners="" ;;
      esac
      write_agent "$runner" "$runner"
    done
  done <<EOF
$PAIRS
EOF
}

# expect_fail <needle> <label>
expect_fail() {
  if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
    fail "$2: lint should have failed"
  fi
  rg -q -- "$1" "$LOG" || { cat "$LOG" >&2; fail "$2: failure should report \"$1\""; }
  rg -q 'check-audit-delegation: FAILED' "$LOG" || fail "$2: failure should identify the lint"
  pass "$2"
}

bash "$SCRIPT" "$REPO_ROOT" >"$LOG" 2>&1 || { cat "$LOG" >&2; fail "should pass on the real repo"; }
rg -q 'check-audit-delegation: OK \(checked 5 audit skills\)' "$LOG" \
  || { cat "$LOG" >&2; fail "should report all 5 contracted audit skills as checked"; }
pass "passes on the real repo with all 5 contracted audit skills checked"

reset_fixture
bash "$SCRIPT" "$FIXTURE" >/dev/null || fail "should pass on a correct fixture"
pass "passes on a correct fixture"

reset_fixture
write_skill prose-lint vale-prose-runner,facilitron-voice-judge sonnet
expect_fail 'FAIL prose-lint: .*declares model "sonnet", must be "haiku"' "rejects an audit skill promoted off haiku"

# MD-2574: prose-lint contracts two runners. Dropping either one must fail, or a
# pass could be silently inlined back into the haiku orchestrator.
reset_fixture
write_skill prose-lint vale-prose-runner haiku
expect_fail 'FAIL prose-lint: .*no longer names its runner "facilitron-voice-judge"' "rejects a multi-runner skill that dropped its second runner"

reset_fixture
write_skill prose-lint facilitron-voice-judge haiku
expect_fail 'FAIL prose-lint: .*no longer names its runner "vale-prose-runner"' "rejects a multi-runner skill that dropped its first runner"

reset_fixture
mkdir -p "$FIXTURE/skills/link-check"
cat >"$FIXTURE/skills/link-check/SKILL.md" <<'EOF'
---
name: link-check
model: haiku
effort: low
---

Run lychee here in the main session.
EOF
expect_fail 'FAIL link-check: .*no longer names its runner "lychee-link-runner"' "rejects a skill that stopped delegating"

reset_fixture
trash "$FIXTURE/agents/unlighthouse-runner.md"
expect_fail 'FAIL site-audit: missing runner agent agents/unlighthouse-runner\.md' "rejects a missing runner agent"

reset_fixture
write_agent a11y-scan-runner some-other-runner
expect_fail 'FAIL a11y-scan: .*declares name "some-other-runner"' "rejects a runner whose declared name drifted"

reset_fixture
trash "$FIXTURE/skills/optimize-images"
expect_fail 'FAIL optimize-images: missing skills/optimize-images/SKILL\.md' "rejects a contracted audit skill that disappeared"

echo "check-audit-delegation smoke: $PASS assertions passed"
