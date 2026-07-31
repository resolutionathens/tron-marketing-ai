#!/usr/bin/env bash
# Offline smoke test for site-audit.sh — verifies the assembled command uses the
# CORRECT binary/flags and scopes the crawl, WITHOUT downloading Chromium or hitting the
# network (UNLH_DRY_RUN short-circuits before npx runs).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/site-audit.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/site-audit-cleanup-smoke.XXXXXX")"
mkdir -p "$ROOT/tmp"
trap 'rm -rf "$ROOT"' EXIT
export TMPDIR="$ROOT/tmp"
export UNLH_DRY_RUN=1

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

# 1. SECTION scope (default) — regex-anchored --include-urls, full origin --site.
out="$(bash "$SCRIPT" https://www.facilitron.com/resources/guides 2>/dev/null)"
check   "section: uses unlighthouse-ci binary"     "npx -y unlighthouse-ci" "$out"
check   "section: --site is the origin"            "--site https://www.facilitron.com" "$out"
check   "section: --include-urls anchored on path" "--include-urls ^/resources/guides" "$out"
reject  "section: never the fake --urls-pattern"   "--urls-pattern" "$out"
reject  "section: never bare 'unlighthouse '"      "ci unlighthouse " "$out"

# 2. SINGLE PAGE — crawler disabled via --urls (exact path), no --include-urls.
out="$(bash "$SCRIPT" https://www.facilitron.com/resources/guides/foo --page 2>/dev/null)"
check   "page: --urls pins the exact path"         "--urls /resources/guides/foo" "$out"
reject  "page: no --include-urls in page mode"     "--include-urls" "$out"

# 2b. SINGLE PAGE on a bare origin — must default the path to "/" (never emit --urls "").
out="$(bash "$SCRIPT" https://www.facilitron.com --page 2>/dev/null)"
check   "page+bare-origin: defaults --urls to /"   "--urls /" "$out"

# 3. FULL — explicit opt-in, origin only, no scoping flags.
out="$(bash "$SCRIPT" https://www.facilitron.com/resources/guides --full 2>/dev/null)"
check   "full: --site origin"                      "--site https://www.facilitron.com" "$out"
reject  "full: no --include-urls when --full"      "--include-urls" "$out"

# 4. Bare origin (no path) naturally means full site.
out="$(bash "$SCRIPT" https://www.facilitron.com 2>/dev/null)"
reject  "bare-origin: no scoping flag"             "--include-urls" "$out"

# 5. Pass-throughs.
out="$(bash "$SCRIPT" https://www.facilitron.com/resources --samples 3 --desktop --throttle 2>/dev/null)"
check   "passthrough: --samples 3"                 "--samples 3" "$out"
check   "passthrough: --desktop"                   "--desktop" "$out"
check   "passthrough: --throttle"                  "--throttle" "$out"

# 5b. Regex metachars in the section path are escaped (no over-matching / invalid regex).
out="$(bash "$SCRIPT" https://www.facilitron.com/pricing.html 2>/dev/null)"
check   "regex-escape: dot is escaped"             "--include-urls ^/pricing\\.html" "$out"
out="$(bash "$SCRIPT" https://www.facilitron.com/c++ 2>/dev/null)"
check   "regex-escape: plus is escaped"            "--include-urls ^/c\\+\\+" "$out"

# 6. Always headless reporter + temp output path.
check   "always: csvExpanded reporter"             "--reporter csvExpanded" "$out"
check   "always: --build-static"                   "--build-static" "$out"
if [[ -z "$(command ls -A "$TMPDIR")" ]]; then echo "ok  : cleanup: dry-run leaves isolated TMPDIR empty"; else echo "FAIL: cleanup left: $(command ls -A "$TMPDIR")"; fail=1; fi

mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/npx" <<'EOF'
#!/usr/bin/env bash
[[ "${UNLH_FAKE:-}" == fail ]] && exit 1
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output-path ]]; then mkdir -p "$2"; printf 'url,performance\n' > "$2/ci-result.csv"; shift 2; continue; fi
  shift
done
EOF
chmod +x "$ROOT/bin/npx"
unset UNLH_DRY_RUN
out="$(PATH="$ROOT/bin:$PATH" bash "$SCRIPT" https://www.facilitron.com/ok 2>/dev/null)"
[[ -s "$out" ]] && rm -rf "$(dirname "$out")" || { echo "FAIL: success did not provide a CSV for runner cleanup"; fail=1; }
rc=0; UNLH_FAKE=fail PATH="$ROOT/bin:$PATH" bash "$SCRIPT" https://www.facilitron.com/fail >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 && -z "$(command ls -A "$TMPDIR")" ]] && echo "ok  : cleanup: success handoff and audit failure both leave no scratch" || { echo "FAIL: audit failure cleanup"; fail=1; }
rg -q 'trap .*dirname.*CSV' "$HERE/../../../agents/unlighthouse-runner.md" \
  && echo "ok  : cleanup: runner owns successful result-directory removal" \
  || { echo "FAIL: runner cleanup contract missing"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
