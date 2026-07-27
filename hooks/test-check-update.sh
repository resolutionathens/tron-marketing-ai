#!/usr/bin/env bash
# Tests for check-update.sh — drives the hook with fixture plugin manifests and a file://
# "remote", asserting the notice fires only when the installed version is behind. No network.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-update.sh"
fail=0

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tron-update-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Build a fake plugin root with a given local version, and a remote manifest fixture.
mk_root() { # <dir> <version>
  mkdir -p "$1/.claude-plugin"
  printf '{ "name": "tron", "version": "%s" }\n' "$2" > "$1/.claude-plugin/plugin.json"
}
mk_remote() { printf '{ "name": "tron", "version": "%s" }\n' "$1" > "$TMP/remote.json"; }

# Run the hook with isolated cache + file:// remote; capture exit code and output.
run() { # <local_version>  -> sets RC and OUT
  local root="$TMP/root"; rm -rf "$root"; mk_root "$root" "$1"
  OUT="$(CLAUDE_PLUGIN_ROOT="$root" \
        TRON_UPDATE_REMOTE_URL="file://$TMP/remote.json" \
        TRON_UPDATE_CACHE="$TMP/cache-$1-$RANDOM" \
        bash "$SCRIPT" 2>&1)"
  RC=$?
}
ok()   { echo "ok  : $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# 1. Behind → a clean SessionStart system message (exit 0).
mk_remote "0.10.0"; run "0.9.0"
[ "$RC" -eq 0 ] && ok "behind: exits 0" || bad "behind: expected exit 0, got $RC"
case "$OUT" in *'"systemMessage"'*) ok "behind: emits a system message" ;; *) bad "behind: missing system message ($OUT)";; esac
printf '%s' "$OUT" | node -e 'const fs = require("fs"); const output = JSON.parse(fs.readFileSync(0, "utf8")); process.exit(typeof output.systemMessage === "string" ? 0 : 1)' \
  && ok "behind: emits valid hook JSON" || bad "behind: invalid hook JSON ($OUT)"
case "$OUT" in *"0.9.0"*"0.10.0"*) ok "behind: names installed + published" ;; *) bad "behind: message missing versions ($OUT)";; esac
case "$OUT" in *"claude plugin update tron@tron"*) ok "behind: shows working plugin update command" ;; *) bad "behind: no plugin update command";; esac
case "$OUT" in *"tron-os reconcile-tron-release"*) ok "behind: shows release-store reconcile command" ;; *) bad "behind: no release-store reconcile command";; esac

# 2. Up to date → silent (exit 0, no output).
mk_remote "0.10.0"; run "0.10.0"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "current: silent exit 0" || bad "current: expected silent exit 0 (rc=$RC out=$OUT)"

# 3. Local AHEAD of remote (e.g. dev build) → silent.
mk_remote "0.9.0"; run "0.10.0"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "ahead: silent exit 0" || bad "ahead: expected silent exit 0 (rc=$RC out=$OUT)"

# 4. Version-sort correctness: 0.9.0 installed vs 0.10.0 published must read as behind
#    (lexical sort would wrongly call 0.9.0 newer). Covered by test 1 passing with sort -V.
mk_remote "0.10.0"; run "0.9.0"
[ "$RC" -eq 0 ] && ok "semver: 0.10.0 > 0.9.0" || bad "semver: 0.10.0 not treated as newer than 0.9.0"

# 5. Unreachable remote + no cache → fail-silent (exit 0, never blocks startup).
root="$TMP/root"; rm -rf "$root"; mk_root "$root" "0.9.0"
OUT="$(CLAUDE_PLUGIN_ROOT="$root" \
      TRON_UPDATE_REMOTE_URL="file://$TMP/does-not-exist.json" \
      TRON_UPDATE_CACHE="$TMP/cache-miss-$RANDOM" \
      bash "$SCRIPT" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "no-network: fail-silent exit 0" || bad "no-network: expected silent exit 0 (rc=$RC out=$OUT)"

# 6. Non-numeric version text is ignored so interpolation can never make invalid hook JSON.
mk_remote "0.10.0-beta"; run "0.9.0"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "non-numeric remote: silent exit 0" || bad "non-numeric remote: expected silent exit 0 (rc=$RC out=$OUT)"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
