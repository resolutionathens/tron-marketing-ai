#!/usr/bin/env bash
set -euo pipefail

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/drive-publish-test.XXXXXX")"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/drive-publish.mjs"
PASS=0
cleanup() { trash "$ROOT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
has() { printf '%s' "$1" | rg -q -F -- "$2" || fail "$3: $1"; }

mkdir -p "$ROOT/bin" "$ROOT/tmp"
printf 'Finished content draft\n' > "$ROOT/draft.md"
printf '%%PDF-1.7 finished pdf\n' > "$ROOT/deliverable.pdf"

cat > "$ROOT/bin/gws" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${STUB_AUTH_FAIL:-0}" == 1 ]] && { echo 'OAuth refresh failed: redacted' >&2; exit 1; }
printf '%s\n' "$*" >> "$REQUEST_LOG"
if [[ "$*" == "drive files get "* ]]; then
  [[ "$*" == *'"fileId":"bad-folder"'* ]] && { echo '{"error":{"message":"File not found"}}' >&2; exit 1; }
  printf '%s\n' '{"id":"folder-123","mimeType":"application/vnd.google-apps.folder","trashed":false}'
elif [[ "$*" == "drive files create "* ]]; then
  if [[ "$*" == *'application/vnd.google-apps.document'* ]]; then
    [[ "$(cat "${!#}")" == 'Finished content draft' ]] || { echo 'wrong document content' >&2; exit 8; }
    printf '%s\n' '{"id":"doc-456","mimeType":"application/vnd.google-apps.document","name":"Campaign draft","webViewLink":"https://docs.google.com/document/d/doc-456/edit"}'
  else
    [[ "$(cat "${!#}")" == '%PDF-1.7 finished pdf' ]] || { echo 'wrong uploaded content' >&2; exit 8; }
    printf '%s\n' '{"id":"file-789","mimeType":"application/pdf","name":"deliverable.pdf","webViewLink":"https://drive.google.com/file/d/file-789/view"}'
  fi
elif [[ "$*" == "drive files update "* ]]; then
  [[ "$(cat "${!#}")" == '%PDF-1.7 finished pdf' ]] || { echo 'wrong update content' >&2; exit 8; }
  printf '%s\n' '{"id":"file-9001","mimeType":"application/pdf","name":"revised.pdf","webViewLink":"https://drive.google.com/file/d/file-9001/view"}'
else
  echo 'unexpected gws invocation' >&2
  exit 9
fi
SH
chmod +x "$ROOT/bin/gws"

run_publish() {
  PATH="$ROOT/bin:$PATH" TMPDIR="$ROOT/tmp" REQUEST_LOG="$ROOT/requests.log" node "$SCRIPT" "$@"
}

: > "$ROOT/requests.log"
OUT="$(run_publish create-doc --folder-id folder-123 --name 'Campaign draft' --source-file "$ROOT/draft.md")"
[[ "$OUT" == '{"ok":true,"action":"create-doc","fileId":"doc-456","mimeType":"application/vnd.google-apps.document","name":"Campaign draft","url":"https://docs.google.com/document/d/doc-456/edit"}' ]] || fail "create-doc should return exact metadata: $OUT"
[[ "$(sed -n '1p' "$ROOT/requests.log")" == 'drive files get --params {"fileId":"folder-123","fields":"id,mimeType,trashed","supportsAllDrives":true}' ]] || fail "create-doc should validate the exact folder destination"
CREATE_DOC_REQ="$(sed -n '2p' "$ROOT/requests.log")"
has "$CREATE_DOC_REQ" 'drive files create --params {"fields":"id,mimeType,name,webViewLink","supportsAllDrives":true} --json {"name":"Campaign draft","parents":["folder-123"],"mimeType":"application/vnd.google-apps.document"} --upload ' "create-doc request should contain exact destination metadata"
[[ "$CREATE_DOC_REQ" == *' --upload '*'draft.md' ]] || fail "create-doc upload path should retain the source .md extension: $CREATE_DOC_REQ"
[[ -f "$ROOT/draft.md" ]] || fail "create-doc removed the caller-owned source"
[[ -z "$(find "$ROOT/tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail "create-doc left temporary upload files"
pass "document creation imports the draft into the exact folder and cleans up"

: > "$ROOT/requests.log"
OUT="$(run_publish upload --folder-id folder-123 --name deliverable.pdf --mime-type application/pdf --source-file "$ROOT/deliverable.pdf")"
[[ "$OUT" == '{"ok":true,"action":"upload","fileId":"file-789","mimeType":"application/pdf","name":"deliverable.pdf","url":"https://drive.google.com/file/d/file-789/view"}' ]] || fail "upload should return exact metadata: $OUT"
UPLOAD_REQ="$(sed -n '2p' "$ROOT/requests.log")"
has "$UPLOAD_REQ" 'drive files create --params {"fields":"id,mimeType,name,webViewLink","supportsAllDrives":true} --json {"name":"deliverable.pdf","parents":["folder-123"],"mimeType":"application/pdf"} --upload ' "upload should contain exact folder, name, and MIME type"
[[ -z "$(find "$ROOT/tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail "upload left temporary files"
pass "binary upload targets the exact folder and returns durable metadata"

: > "$ROOT/requests.log"
OUT="$(run_publish update --file-id file-9001 --name revised.pdf --mime-type application/pdf --source-file "$ROOT/deliverable.pdf")"
[[ "$OUT" == '{"ok":true,"action":"update","fileId":"file-9001","mimeType":"application/pdf","name":"revised.pdf","url":"https://drive.google.com/file/d/file-9001/view"}' ]] || fail "update should return exact metadata: $OUT"
[[ "$(wc -l < "$ROOT/requests.log" | tr -d ' ')" == 1 ]] || fail "update must not search by filename or create another file"
UPDATE_REQ="$(sed -n '1p' "$ROOT/requests.log")"
has "$UPDATE_REQ" 'drive files update --params {"fileId":"file-9001","fields":"id,mimeType,name,webViewLink","supportsAllDrives":true} --json {"name":"revised.pdf","mimeType":"application/pdf"} --upload ' "update should target only the explicit file ID"
pass "update requires and targets one explicit file ID"

: > "$ROOT/requests.log"
rc=0
ERR="$(run_publish upload --folder-id bad-folder --name x.pdf --mime-type application/pdf --source-file "$ROOT/deliverable.pdf" 2>&1)" || rc=$?
[[ "$rc" == 1 ]] || fail "invalid folder should exit 1, got $rc"
has "$ERR" 'could not validate Drive folder bad-folder' "invalid folder should be actionable"
[[ "$(wc -l < "$ROOT/requests.log" | tr -d ' ')" == 1 ]] || fail "invalid folder must fail before upload"
[[ -z "$(find "$ROOT/tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail "invalid folder failure left temporary files"
pass "invalid folder fails before upload and cleans up"

: > "$ROOT/requests.log"
rc=0
ERR="$(PATH="$ROOT/bin:$PATH" TMPDIR="$ROOT/tmp" REQUEST_LOG="$ROOT/requests.log" STUB_AUTH_FAIL=1 node "$SCRIPT" upload --folder-id folder-123 --name x.pdf --mime-type application/pdf --source-file "$ROOT/deliverable.pdf" 2>&1)" || rc=$?
[[ "$rc" == 1 ]] || fail "auth failure should exit 1, got $rc"
has "$ERR" 'Google Workspace authentication failed' "auth failure should be actionable"
! printf '%s' "$ERR" | rg -q 'GOOGLE_WORKSPACE_CLI_TOKEN|client_secret|access_token' || fail "auth failure exposed credential material"
[[ -z "$(find "$ROOT/tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail "auth failure left temporary files"
pass "authentication failure is redacted and cleans up"

rc=0
ERR="$(run_publish update --name revised.pdf --mime-type application/pdf --source-file "$ROOT/deliverable.pdf" 2>&1)" || rc=$?
[[ "$rc" == 2 ]] || fail "missing explicit file ID should exit 2, got $rc"
has "$ERR" '--file-id is required for update' "update should require an explicit destination"
pass "update never guesses a destination by filename"

echo "Drive publish tests passed ($PASS checks)."
