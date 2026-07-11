#!/usr/bin/env bash
# Fetch a Confluence page's storage body + download the image attachments it
# actually references.
#
# NOTE: prefer `acli` for the page BODY where you can (it's already authenticated,
# no email/token needed). This script uses the REST gateway because the image
# ATTACHMENT download (the /wiki/download/ 401 gotcha) still requires basic auth +
# the api.atlassian.com gateway, which acli doesn't expose.
#
# Auth (MD-1995): the page-body fetch and attachment *listing* both hit
# facilitron.atlassian.net, which the org-secret broker (secrets.facilitron.work,
# MD-1994) proxies 1:1 at /jira/* — so those two calls try the broker first via a
# short-lived Cloudflare Access token, with no local token/email needed. Falls
# back automatically to direct Basic auth (JIRA_API_TOKEN/ATLASSIAN_EMAIL) if the
# broker is unreachable or a caller overrides CONFLUENCE_BASE to a non-Facilitron
# site. The attachment *download* leg still hits api.atlassian.com, a host the
# broker doesn't proxy yet (blocked on MD-2011) — it always uses direct auth.
# See tools/jira/broker-status.md for the full picture.
#
# Handles the two auth gotchas that waste time otherwise:
#   1. ~/.env (1Password-generated) holds JIRA_API_TOKEN but isn't auto-sourced.
#   2. The /wiki/download/ servlet 401s with an API token — you must go through
#      the api.atlassian.com gateway route and follow the redirect to media.
#
# Usage:  fetch-confluence.sh <page-id-or-tiny-link> <output-dir>
# Output: <output-dir>/page.json         (raw v2 page response)
#         <output-dir>/body.html         (storage-format body, for conversion)
#         <output-dir>/raw/<filename>    (each referenced attachment, original name)
#         prints the resolved page title and the ordered list of referenced images

set -euo pipefail

INPUT="${1:?Usage: fetch-confluence.sh <page-id-or-tiny-link> <output-dir>}"
OUTDIR="${2:?Usage: fetch-confluence.sh <page-id-or-tiny-link> <output-dir>}"
# Defaults target Facilitron's Atlassian instance (this is an internal tool);
# override CONFLUENCE_CLOUD_ID / CONFLUENCE_BASE for a different site.
CLOUD_ID="${CONFLUENCE_CLOUD_ID:-91c1b48f-c272-40fb-9c7f-cc5f23bb74d7}"
BASE="${CONFLUENCE_BASE:-https://facilitron.atlassian.net/wiki}"
BASE_HOST="${BASE#*://}"; BASE_HOST="${BASE_HOST%%/*}"

# Broker (org-shared, no local credential needed) — only valid for the default
# Facilitron host; only covers /wiki paths under facilitron.atlassian.net.
BROKER_APP="${CONFLUENCE_BROKER_APP:-https://secrets.facilitron.work}"
BROKER_JIRA_BASE="${CONFLUENCE_BROKER_BASE:-https://secrets.facilitron.work/jira}"

broker_token() {
  [[ "$BASE_HOST" == "facilitron.atlassian.net" ]] || return 1
  if [[ -n "${CONFLUENCE_ACCESS_TOKEN:-}" ]]; then echo "$CONFLUENCE_ACCESS_TOKEN"; return 0; fi
  command -v cloudflared >/dev/null 2>&1 || return 1
  cloudflared access token --app="$BROKER_APP" 2>/dev/null
}
BROKER_TOKEN="$(broker_token || true)"

# Direct Basic-auth fallback (JIRA_API_TOKEN/ATLASSIAN_EMAIL) — resolved lazily,
# only when actually needed (broker unavailable, or the attachment-download leg
# below which the broker never covers), so a working broker path never touches
# ~/.env at all.
NETRC=""
ensure_direct_creds() {
  [[ -n "$NETRC" ]] && return 0
  if [[ -z "${JIRA_API_TOKEN:-}" && -f "$HOME/.env" ]]; then
    set -a; source "$HOME/.env"; set +a
  fi
  : "${JIRA_API_TOKEN:?JIRA_API_TOKEN not set and not found in ~/.env}"

  # Atlassian account email for basic auth — from env (ATLASSIAN_EMAIL, e.g. in
  # ~/.env) or the local git identity as a fallback. The git fallback is a
  # footgun in repos whose git email isn't the Atlassian account (you'd 401 with
  # no clue why), so warn loudly when we fall back rather than failing silently.
  local email
  if [[ -n "${ATLASSIAN_EMAIL:-}" ]]; then
    email="$ATLASSIAN_EMAIL"
  else
    email="$(git config user.email 2>/dev/null || true)"
    [[ -n "$email" ]] && echo "NOTE: ATLASSIAN_EMAIL unset — using git email '$email' for Confluence auth. If that isn't your Atlassian account email, export ATLASSIAN_EMAIL or you'll get a 401." >&2
  fi
  : "${email:?Set ATLASSIAN_EMAIL to your Atlassian account email (in ~/.env or the environment)}"

  # Hand the credentials to curl via a temp netrc instead of -u, so the API token
  # never appears in the process list (ps/top) while these requests run. The file
  # is mode 600 and removed on exit.
  NETRC="$(mktemp)"
  chmod 600 "$NETRC"
  trap 'rm -f "$NETRC"' EXIT
  printf 'machine %s login %s password %s\nmachine api.atlassian.com login %s password %s\n' \
    "$BASE_HOST" "$email" "$JIRA_API_TOKEN" "$email" "$JIRA_API_TOKEN" > "$NETRC"
}

# GET a /wiki path, broker-first with automatic direct-auth fallback. `path`
# must start with "/" and is relative to $BASE (i.e. already under /wiki).
cf_get() { # <path> <outfile>
  local path="$1" out="$2" code
  if [[ -n "$BROKER_TOKEN" ]]; then
    code="$(curl -s -o "$out" -w '%{http_code}' -H "CF-Access-Token: $BROKER_TOKEN" "$BROKER_JIRA_BASE/wiki$path" || echo 000)"
    if [[ "$code" == 2* ]]; then return 0; fi
    echo "NOTE: broker request for $path returned HTTP $code — falling back to direct Basic auth." >&2
  fi
  ensure_direct_creds
  curl -s --netrc-file "$NETRC" "$BASE$path" -o "$out"
}

mkdir -p "$OUTDIR/raw"

# 2. Resolve to a numeric page ID. confluence-lib resolves raw ids and full
#    /pages/<id>/ URLs offline; only a /wiki/x/ tiny link needs the redirect.
# shellcheck source=/dev/null
source "$(dirname "$0")/confluence-lib.sh"
if ! PAGE_ID="$(cl_extract_page_id "$INPUT")"; then
  PAGE_ID="$(curl -sIL "$INPUT" | grep -i '^location:' | tail -1 | grep -oE '[0-9]+' | tail -1)"
fi
: "${PAGE_ID:?Could not resolve a page ID from: $INPUT}"

# 3. Fetch the storage-format body (broker-first, see cf_get above).
cf_get "/api/v2/pages/$PAGE_ID?body-format=storage" "$OUTDIR/page.json"
python3 -c "
import json,sys
d=json.load(open('$OUTDIR/page.json'))
if 'body' not in d:
    sys.exit('Page fetch failed: '+json.dumps(d)[:300])
open('$OUTDIR/body.html','w').write(d['body']['storage']['value'])
print('TITLE:', d['title'])
"

# 4. List attachments, then download only the ones the body actually references
#    (Confluence pages routinely carry extra unused uploads).
cf_get "/api/v2/pages/$PAGE_ID/attachments?limit=100" "$OUTDIR/attachments.json"

python3 - "$OUTDIR" <<'PY'
import json, re, sys
outdir = sys.argv[1]
body = open(f"{outdir}/body.html").read()
# Referenced filenames, in document order, de-duplicated.
referenced = []
for m in re.finditer(r'<ri:attachment ri:filename="([^"]+)"', body):
    name = m.group(1)
    if name not in referenced:
        referenced.append(name)
atts = {a['title']: a for a in json.load(open(f"{outdir}/attachments.json"))['results']}
print("REFERENCED IMAGES (document order):")
for i, name in enumerate(referenced, 1):
    status = "" if name in atts else "  [!! not found as attachment]"
    print(f"  {i:2}. {name}{status}")
unused = sorted(set(atts) - set(referenced))
if unused:
    print("UNUSED ATTACHMENTS (skipped):")
    for name in unused:
        print(f"      {name}")
# Emit the download list for the bash loop below.
with open(f"{outdir}/_dl.tsv", "w") as f:
    for name in referenced:
        if name in atts:
            f.write(f"{name}\t{atts[name]['downloadLink']}\n")
PY

# 5. Download each referenced attachment via the gateway route. This hits
#    api.atlassian.com, a host the broker doesn't proxy yet (MD-2011), so it
#    always uses direct Basic auth regardless of how steps 3-4 went. Only
#    required when there's actually something to download.
#    --location-trusted is required: the gateway 302s to api.media.atlassian.com
#    and curl drops credentials on a cross-host redirect without it.
if [[ -s "$OUTDIR/_dl.tsv" ]]; then ensure_direct_creds; fi
while IFS=$'\t' read -r name link; do
  curl -s -L --location-trusted --netrc-file "$NETRC" \
    "https://api.atlassian.com/ex/confluence/$CLOUD_ID/wiki$link" \
    -o "$OUTDIR/raw/$name"
done < "$OUTDIR/_dl.tsv"
rm -f "$OUTDIR/_dl.tsv"

echo "DONE. Body: $OUTDIR/body.html  |  Images: $OUTDIR/raw/"
