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

# Run the hook with isolated cache + file:// remote; capture exit code and stderr.
run() { # <local_version>  -> sets RC and ERR
  local root="$TMP/root"; rm -rf "$root"; mk_root "$root" "$1"
  ERR="$(CLAUDE_PLUGIN_ROOT="$root" \
        TRON_UPDATE_REMOTE_URL="file://$TMP/remote.json" \
        TRON_UPDATE_CACHE="$TMP/cache-$1-$RANDOM" \
        bash "$SCRIPT" 2>&1 >/dev/null)"
  RC=$?
}
ok()   { echo "ok  : $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# 1. Behind → notice (exit 2, message names both versions + the update command).
mk_remote "0.10.0"; run "0.9.0"
[ "$RC" -eq 2 ] && ok "behind: exits 2" || bad "behind: expected exit 2, got $RC"
case "$ERR" in *"0.9.0"*"0.10.0"*) ok "behind: names installed + published" ;; *) bad "behind: message missing versions ($ERR)";; esac
case "$ERR" in *"/plugin marketplace update tron"*) ok "behind: shows update command" ;; *) bad "behind: no update command";; esac

# 2. Up to date → silent (exit 0, no output).
mk_remote "0.10.0"; run "0.10.0"
[ "$RC" -eq 0 ] && [ -z "$ERR" ] && ok "current: silent exit 0" || bad "current: expected silent exit 0 (rc=$RC err=$ERR)"

# 3. Local AHEAD of remote (e.g. dev build) → silent.
mk_remote "0.9.0"; run "0.10.0"
[ "$RC" -eq 0 ] && [ -z "$ERR" ] && ok "ahead: silent exit 0" || bad "ahead: expected silent exit 0 (rc=$RC err=$ERR)"

# 4. Version-sort correctness: 0.9.0 installed vs 0.10.0 published must read as behind
#    (lexical sort would wrongly call 0.9.0 newer). Covered by test 1 passing with sort -V.
mk_remote "0.10.0"; run "0.9.0"
[ "$RC" -eq 2 ] && ok "semver: 0.10.0 > 0.9.0" || bad "semver: 0.10.0 not treated as newer than 0.9.0"

# 5. Unreachable remote + no cache → fail-silent (exit 0, never blocks startup).
root="$TMP/root"; rm -rf "$root"; mk_root "$root" "0.9.0"
ERR="$(CLAUDE_PLUGIN_ROOT="$root" \
      TRON_UPDATE_REMOTE_URL="file://$TMP/does-not-exist.json" \
      TRON_UPDATE_CACHE="$TMP/cache-miss-$RANDOM" \
      bash "$SCRIPT" 2>&1 >/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$ERR" ] && ok "no-network: fail-silent exit 0" || bad "no-network: expected silent exit 0 (rc=$RC err=$ERR)"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
