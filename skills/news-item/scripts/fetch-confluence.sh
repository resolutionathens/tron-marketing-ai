#!/usr/bin/env bash
# Fetch a Confluence page's storage body + download the image attachments it
# actually references.
#
# NOTE: prefer `acli` for the page BODY where you can (it's already authenticated,
# no email/token needed). This script uses the REST gateway because the image
# ATTACHMENT download (the /wiki/download/ 401 gotcha) still requires basic auth +
# the api.atlassian.com gateway, which acli doesn't expose.
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

# 1. Make sure the token is available — ~/.env is not sourced into every shell.
if [[ -z "${JIRA_API_TOKEN:-}" && -f "$HOME/.env" ]]; then
  set -a; source "$HOME/.env"; set +a
fi
: "${JIRA_API_TOKEN:?JIRA_API_TOKEN not set and not found in ~/.env}"

# Atlassian account email for basic auth — from env (ATLASSIAN_EMAIL, e.g. in ~/.env)
# or the local git identity as a fallback.
EMAIL="${ATLASSIAN_EMAIL:-$(git config user.email 2>/dev/null || true)}"
: "${EMAIL:?Set ATLASSIAN_EMAIL to your Atlassian account email (in ~/.env or the environment)}"

# Hand the credentials to curl via a temp netrc instead of -u, so the API token
# never appears in the process list (ps/top) while these requests run. The file
# is mode 600 and removed on exit.
BASE_HOST="${BASE#*://}"; BASE_HOST="${BASE_HOST%%/*}"
NETRC="$(mktemp)"
chmod 600 "$NETRC"
trap 'rm -f "$NETRC"' EXIT
printf 'machine %s login %s password %s\nmachine api.atlassian.com login %s password %s\n' \
  "$BASE_HOST" "$EMAIL" "$JIRA_API_TOKEN" "$EMAIL" "$JIRA_API_TOKEN" > "$NETRC"

mkdir -p "$OUTDIR/raw"

# 2. Resolve a tiny link (/wiki/x/XXXXX) to a numeric page ID if needed.
if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  PAGE_ID="$INPUT"
else
  PAGE_ID=$(curl -sIL "$INPUT" | grep -i '^location:' | tail -1 | grep -oE '[0-9]+' | tail -1)
fi
: "${PAGE_ID:?Could not resolve a page ID from: $INPUT}"

# 3. Fetch the storage-format body. The v2 pages API works with basic auth.
curl -s --netrc-file "$NETRC" \
  "$BASE/api/v2/pages/$PAGE_ID?body-format=storage" -o "$OUTDIR/page.json"
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
curl -s --netrc-file "$NETRC" \
  "$BASE/api/v2/pages/$PAGE_ID/attachments?limit=100" -o "$OUTDIR/attachments.json"

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

# 5. Download each referenced attachment via the gateway route.
#    --location-trusted is required: the gateway 302s to api.media.atlassian.com
#    and curl drops credentials on a cross-host redirect without it.
while IFS=$'\t' read -r name link; do
  curl -s -L --location-trusted --netrc-file "$NETRC" \
    "https://api.atlassian.com/ex/confluence/$CLOUD_ID/wiki$link" \
    -o "$OUTDIR/raw/$name"
done < "$OUTDIR/_dl.tsv"
rm -f "$OUTDIR/_dl.tsv"

echo "DONE. Body: $OUTDIR/body.html  |  Images: $OUTDIR/raw/"
