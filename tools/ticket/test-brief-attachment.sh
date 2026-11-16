#!/usr/bin/env bash
# Offline test for brief-attachment.sh: a stub curl records the request and
# answers as Jira does, so nothing reaches the network.
#
#   bash tools/ticket/test-brief-attachment.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/brief-attachment.sh"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 77; }

STUB="$(mktemp -d "${TMPDIR:-/tmp}/brief-stub.XXXXXX")"
trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/curl" <<'SH'
#!/usr/bin/env bash
# Record the arguments and the uploaded file's name as curl saw it (it runs in the upload dir).
printf '%s\n' "$@" > "$BRIEF_STUB_DIR/args"
cat > "$BRIEF_STUB_DIR/stdin"
ls > "$BRIEF_STUB_DIR/cwd-files"
[ "${BRIEF_STUB_FAIL:-}" = 1 ] && exit 22
printf '[{"id":"10042","filename":"%s"}]' "$BRIEF_STUB_NAME"
SH
chmod +x "$STUB/curl"
printf 'brief\n' > "$STUB/draft.md"
run() { PATH="$STUB:$PATH" BRIEF_STUB_DIR="$STUB" ATLASSIAN_EMAIL="${E-a@b.c}" JIRA_API_TOKEN="${T-tok}" bash "$SH" "$@"; }

echo "brief-attachment:"
OUT="$(BRIEF_STUB_NAME=MD-7-engineering.md run upload MD-7 "$STUB/draft.md")"
[[ "$(jq -c . <<<"$OUT")" == '{"key":"MD-7","id":"10042","filename":"MD-7-engineering.md"}' ]] || fail "prints the attachment (got: $OUT)"
grep -qx 'https://facilitron.atlassian.net/rest/api/3/issue/MD-7/attachments' "$STUB/args" || fail "posts to the issue's attachments"
grep -qx 'X-Atlassian-Token: no-check' "$STUB/args" || fail "sends the XSRF header Jira needs"
grep -qx 'file=@MD-7-engineering.md;type=text/markdown' "$STUB/args" || fail "uploads under the brief's exact name"
grep -qx 'MD-7-engineering.md' "$STUB/cwd-files" || fail "the renamed copy exists when curl runs"
grep -q 'tok' "$STUB/args" && fail "the token must not be in curl's arguments"
grep -qx 'user = "a@b.c:tok"' "$STUB/stdin" || fail "credentials reach curl on stdin"
pass "uploads any local file as <KEY>-engineering.md"

rc=0; BRIEF_STUB_NAME=other.md run upload MD-7 "$STUB/draft.md" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 4 ]] || fail "a reply without the brief exits 4 (got: $rc)"
rc=0; BRIEF_STUB_FAIL=1 run upload MD-7 "$STUB/draft.md" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 4 ]] || fail "a failed upload exits 4 (got: $rc)"
rc=0; E='' run upload MD-7 "$STUB/draft.md" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 3 ]] || fail "missing credentials exit 3 (got: $rc)"
for args in "upload md-7 $STUB/draft.md" "upload MD-7 $STUB/none.md" "upload MD-7" "send MD-7 $STUB/draft.md"; do
  rc=0; run $args >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 2 ]] || fail "bad arguments ($args) exit 2 (got: $rc)"
done
: > "$STUB/empty.md"
rc=0; run upload MD-7 "$STUB/empty.md" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "an empty brief exits 2 (got: $rc)"
pass "fails plainly on a bad key, file, credentials, upload or reply"

echo "brief-attachment: $PASS checks passed"
