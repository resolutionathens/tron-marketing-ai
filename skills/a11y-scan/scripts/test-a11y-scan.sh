#!/usr/bin/env bash
# Offline smoke test for a11y-scan.sh — verifies the assembled command uses the CORRECT
# binary/flags per mode and generates the right pa11y-ci config, WITHOUT downloading
# axe/pa11y-ci or hitting the network (A11Y_DRY_RUN short-circuits before npx runs).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/a11y-scan.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/a11y-cleanup-smoke.XXXXXX")"
mkdir -p "$ROOT/tmp"
trap 'rm -rf "$ROOT"' EXIT
export TMPDIR="$ROOT/tmp"
export A11Y_DRY_RUN=1

fail=0
check() { # <desc> <expected-substr> <actual>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    echo "ok  : $1"
  else
    echo "FAIL: $1"; echo "      expected to contain: $2"; echo "      got: $3"; fail=1
  fi
}
reject() { # <desc> <forbidden-substr> <actual>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    echo "FAIL: $1 (should NOT contain: $2)"; echo "      got: $3"; fail=1
  else
    echo "ok  : $1"
  fi
}
expect_rc2() { # <desc> <args…> — must exit 2 (bad arguments)
  local desc="$1"; shift
  local rc=0
  bash "$SCRIPT" "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then echo "ok  : $desc"; else echo "FAIL: $desc (rc=$rc, want 2)"; fail=1; fi
}

# 1. URL mode (default) — single URL goes to axe with the WCAG 2.1 AA tag set.
out="$(bash "$SCRIPT" https://www.facilitron.com/pricing 2>/dev/null)"
check   "url: uses @axe-core/cli"                 "npx -y @axe-core/cli" "$out"
check   "url: target URL passed"                  "https://www.facilitron.com/pricing" "$out"
check   "url: WCAG 2.1 AA tag set"                "--tags wcag2a,wcag2aa,wcag21a,wcag21aa" "$out"
check   "url: saves JSON results"                 "--save a11y-results.json" "$out"
reject  "url: no pa11y-ci for a single URL"       "pa11y-ci" "$out"

# 1b. Single URL + --pa11y — pa11y-ci spot check via generated config (never bare flags).
out="$(bash "$SCRIPT" https://www.facilitron.com/pricing --pa11y 2>/dev/null)"
check   "pa11y: uses pa11y-ci"                    "npx -y pa11y-ci" "$out"
check   "pa11y: runs from a generated config"     "--config" "$out"
check   "pa11y: config lists the URL"             '"https://www.facilitron.com/pricing"' "$out"

# 2. Many URLs — pa11y-ci with a generated pa11yci.json carrying the defaults + URL list.
out="$(bash "$SCRIPT" https://www.facilitron.com/a https://www.facilitron.com/b 2>/dev/null)"
check   "urls: uses pa11y-ci"                     "npx -y pa11y-ci" "$out"
check   "urls: JSON output"                       "--json" "$out"
check   "urls: config has WCAG2AA default"        '"standard": "WCAG2AA"' "$out"
check   "urls: config has timeout 30000"          '"timeout": 30000' "$out"
check   "urls: config has wait 1500"              '"wait": 1500' "$out"
check   "urls: config has --no-sandbox"           '"--no-sandbox"' "$out"
check   "urls: config lists first URL"            '"https://www.facilitron.com/a",' "$out"
check   "urls: config lists second URL"           '"https://www.facilitron.com/b"' "$out"
reject  "urls: not the sitemap flag"              "--sitemap" "$out"

# 3. Sitemap mode — explicit flag, plus find/replace pass-through.
out="$(bash "$SCRIPT" https://www.facilitron.com/sm.xml --sitemap --sitemap-find 'https://www.facilitron.com' --sitemap-replace 'http://localhost:3000' 2>/dev/null)"
check   "sitemap: uses pa11y-ci --sitemap"        "--sitemap https://www.facilitron.com/sm.xml" "$out"
check   "sitemap: --sitemap-find passed"          "--sitemap-find https://www.facilitron.com" "$out"
check   "sitemap: --sitemap-replace passed"       "--sitemap-replace http://localhost:3000" "$out"
check   "sitemap: config still ships defaults"    '"standard": "WCAG2AA"' "$out"
reject  "sitemap: config has no urls list"        '"urls"' "$out"

# 3b. Auto-detect: a target ending in sitemap.xml selects sitemap mode without the flag.
out="$(bash "$SCRIPT" https://www.facilitron.com/sitemap.xml 2>/dev/null)"
check   "auto-sitemap: pa11y-ci --sitemap chosen" "--sitemap https://www.facilitron.com/sitemap.xml" "$out"
reject  "auto-sitemap: not axe"                   "@axe-core/cli" "$out"

# 3c. Custom standard reaches the config.
out="$(bash "$SCRIPT" https://www.facilitron.com/a --pa11y --standard WCAG2AAA 2>/dev/null)"
check   "standard: custom value in config"        '"standard": "WCAG2AAA"' "$out"

# 4. Bad arguments → exit 2.
expect_rc2 "bad-args: no arguments"
expect_rc2 "bad-args: not a URL"                  "not-a-url"
expect_rc2 "bad-args: unknown flag"               https://www.facilitron.com --frobnicate
expect_rc2 "bad-args: --standard without value"   https://www.facilitron.com --standard
expect_rc2 "bad-args: sitemap with two URLs"      https://a.example/sitemap.xml https://b.example/x --sitemap

if [[ -z "$(command ls -A "$TMPDIR")" ]]; then echo "ok  : cleanup: dry-run leaves isolated TMPDIR empty"; else echo "FAIL: cleanup left: $(command ls -A "$TMPDIR")"; fail=1; fi

# A real scanner result stays just long enough for the runner to read it; the runner owns
# successful-result cleanup. Scanner failures must clean their own workspace.
mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/npx" <<'EOF'
#!/usr/bin/env bash
if [[ "${A11Y_FAKE:-}" == fail ]]; then exit 1; fi
dir=""; save=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) dir="$2"; shift 2; continue ;;
    --save) save="$2"; shift 2; continue ;;
  esac
  shift
done
mkdir -p "$dir"; printf '[]' > "$dir/$save"
EOF
chmod +x "$ROOT/bin/npx"
unset A11Y_DRY_RUN
out="$(PATH="$ROOT/bin:$PATH" bash "$SCRIPT" https://www.facilitron.com/ok 2>/dev/null)"
[[ -s "$out" ]] && rm -rf "$(dirname "$out")" || { echo "FAIL: success did not provide a result for runner cleanup"; fail=1; }
rc=0; A11Y_FAKE=fail PATH="$ROOT/bin:$PATH" bash "$SCRIPT" https://www.facilitron.com/fail >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 && -z "$(command ls -A "$TMPDIR")" ]] && echo "ok  : cleanup: success handoff and scanner failure both leave no scratch" || { echo "FAIL: scanner failure cleanup"; fail=1; }
rg -q 'trap .*dirname.*RESULTS' "$HERE/../../../agents/a11y-scan-runner.md" \
  && echo "ok  : cleanup: runner owns successful result-directory removal" \
  || { echo "FAIL: runner cleanup contract missing"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
